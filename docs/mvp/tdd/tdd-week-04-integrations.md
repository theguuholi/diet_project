# TDD — Week 04: External Integrations

**Version:** 1.0
**Date:** 2026-04-08
**Phase:** 4 — External Integrations
**Reference:** [Concept Doc](../concept_docs/week-04.md)

---

## 1. Overview

Connects NutriBot to the fitness and health ecosystem: Strava for automatic workout sync (also acting as a hub for Garmin, Apple Watch, and Whoop), and FreeStyle Libre for continuous glucose monitoring (CGM) correlated with meals. All integrations use OAuth2, store tokens in the DB with automatic refresh, and process events asynchronously via Oban.

---

## 2. System Architecture

```
OAuth2 Flows (user-initiated)
  ├── /integrations/strava    → Strava OAuth2 (Assent)
  └── /integrations/freestyle → LibreView OAuth2 (Assent)

Inbound Webhooks
  ├── POST /webhooks/strava   → validate → enqueue ProcessStravaActivityJob
  └── (LibreView: polling via Oban Cron, no push webhook)

Oban Workers
  ├── ProcessStravaActivityJob   — activity → ActivityLog
  ├── RefreshStravaTokenJob      — token expiry management
  ├── ImportGlucoseHistoryJob    — initial 14-day CGM import
  └── PollGlucoseReadingsJob     — every 15 min (Oban Cron)

LiveView
  └── GlucoseDashboardLive      — CGM chart + meal markers
```

---

## 3. Contexts & Responsibilities

| Context | Module | Additions |
|---|---|---|
| `Integrations` | `DietProject.Integrations` | `StravaToken`, `LibreViewToken`, `GlucoseReading` |
| `Tracking` (extended) | — | `ActivityLog` extended with `source`, HR fields |
| `Tracking` (extended) | — | `Profile` extended with `tdee_source`, dynamic TDEE |

---

## 4. Data Models

### 4.1 Strava

```elixir
# strava_tokens
%StravaToken{
  id: uuid,
  user_id: uuid,
  access_token: string,    # encrypted at rest
  refresh_token: string,   # encrypted at rest
  expires_at: datetime,
  athlete_id: integer,     # Strava athlete ID
  scope: string            # "activity:read_all"
}

# activity_logs (extended from Week 02)
%ActivityLog{
  ...existing fields...,
  source: enum,            # :manual | :strava
  strava_activity_id: integer,  # null for manual entries
  avg_heart_rate: integer,
  max_heart_rate: integer,
  calories_source: enum    # :met_estimate | :strava_computed | :device
}
```

### 4.2 FreeStyle Libre

```elixir
# libre_view_tokens
%LibreViewToken{
  id: uuid,
  user_id: uuid,
  access_token: string,    # encrypted at rest
  refresh_token: string,   # encrypted at rest
  expires_at: datetime,
  patient_id: string       # LibreView patient identifier
}

# glucose_readings
%GlucoseReading{
  id: uuid,
  user_id: uuid,
  measured_at: datetime,
  glucose_mmol: float,     # mmol/L (primary unit)
  glucose_mgdl: float,     # mg/dL (derived: mmol × 18.0182)
  trend_arrow: enum,       # :rapid_rise | :rise | :flat | :fall | :rapid_fall
  device_type: string      # "FreeStyle Libre 2" etc.
}
```

---

## 5. Strava OAuth2 Flow

```
1. User visits /integrations/strava
2. SessionController redirects to Strava authorization URL
   (scope: "activity:read_all", redirect_uri: /integrations/strava/callback)
3. User approves → Strava redirects to /integrations/strava/callback?code={code}
4. Exchange code for access_token + refresh_token via Strava API
5. Persist StravaToken (encrypt tokens before storing)
6. Subscribe to Strava webhook for this athlete_id
7. Redirect to dashboard with success flash
```

### 5.1 Token Refresh

```elixir
def get_valid_token(user_id) do
  token = Repo.get_by!(StravaToken, user_id: user_id)

  if DateTime.before?(token.expires_at, DateTime.add(DateTime.utc_now(), 300)) do
    # Refresh when within 5 minutes of expiry
    {:ok, new_token} = StravaClient.refresh_token(token.refresh_token)
    update_token(token, new_token)
  else
    {:ok, token}
  end
end
```

---

## 6. Strava Webhook

### 6.1 Challenge Verification (one-time setup)

```
GET /webhooks/strava?hub.challenge={challenge}&hub.verify_token={our_secret}
→ respond: {"hub.challenge": "{challenge}"}
```

`STRAVA_WEBHOOK_VERIFY_TOKEN` stored in environment.

### 6.2 Event Payload

```json
{
  "object_type": "activity",
  "aspect_type": "create",
  "object_id": 1234567890,
  "owner_id": 9876543,
  "updates": {}
}
```

### 6.3 Webhook Handler

```elixir
def handle_webhook(conn, %{"object_type" => "activity", "aspect_type" => "create",
                            "object_id" => activity_id, "owner_id" => athlete_id}) do
  user = Integrations.find_user_by_strava_athlete(athlete_id)
  Oban.insert(ProcessStravaActivityJob.new(%{user_id: user.id, activity_id: activity_id}))
  send_resp(conn, 200, "")
end
```

---

## 7. Strava Activity Processing

### 7.1 ProcessStravaActivityJob

```
Input: %{user_id: uuid, activity_id: integer}
Steps:
  1. Fetch full activity from Strava API GET /activities/{id}
  2. Check if strava_activity_id already exists in ActivityLog (dedup)
  3. Map Strava payload → ActivityLog attrs (see 7.2)
  4. Persist ActivityLog
  5. Update daily MacroLog (add burned calories)
  6. Broadcast PubSub "user:{id}:exercise_logged"
  7. Send WhatsApp notification
Retries: 3
```

### 7.2 Strava → ActivityLog Mapping

```elixir
def map_strava_activity(strava_activity, user) do
  %{
    user_id:             user.id,
    exercise_id:         find_exercise(strava_activity["type"]),
    date:                Date.from_iso8601!(strava_activity["start_date_local"]),
    duration_minutes:    div(strava_activity["moving_time"], 60),
    calories_burned:     strava_activity["calories"] || estimate_calories(strava_activity, user),
    calories_source:     calories_source(strava_activity),
    source:              :strava,
    strava_activity_id:  strava_activity["id"],
    avg_heart_rate:      strava_activity["average_heartrate"],
    max_heart_rate:      strava_activity["max_heartrate"]
  }
end

defp calories_source(%{"calories" => c}) when not is_nil(c), do: :device
defp calories_source(_), do: :met_estimate
```

### 7.3 Strava Type → Exercise Mapping

| Strava Type | Exercise Name |
|---|---|
| `Run` | running |
| `Ride` | cycling |
| `Swim` | swimming |
| `Walk` | walking |
| `WeightTraining` | weight_training |
| `Yoga` | yoga |
| `HIIT` | hiit |
| `Hike` | hiking |
| `Soccer` | football |
| `Basketball` | basketball |
| _(unknown)_ | general_exercise (MET: 4.0) |

---

## 8. Dynamic TDEE

```elixir
def compute_dynamic_tdee(user_id) do
  days_with_data = Tracking.activity_days_in_range(user_id, days: 7)

  if length(days_with_data) >= 5 do
    avg_burned = Tracking.avg_daily_calories_burned(user_id, days: 7)
    profile    = Accounts.get_profile(user_id)
    dynamic    = profile.bmr + avg_burned
    {:ok, :dynamic, Float.round(dynamic, 0)}
  else
    {:ok, :static, profile.tdee}
  end
end

# Run after every ProcessStravaActivityJob success
# Update Profile.tdee + Profile.tdee_source if changed by > 50 kcal
```

---

## 9. FreeStyle Libre OAuth2 Flow

```
1. User visits /integrations/freestyle-libre
2. Redirect to LibreView authorization URL
3. User approves → callback with authorization code
4. Exchange code → access_token + refresh_token + patient_id
5. Persist LibreViewToken (encrypted)
6. Enqueue ImportGlucoseHistoryJob (last 14 days)
7. Redirect to dashboard
```

### 9.1 Initial Import (ImportGlucoseHistoryJob)

```
Input: %{user_id: uuid}
Steps:
  1. Fetch 14 days of readings from LibreView API
  2. Bulk insert into glucose_readings (ignore conflicts on measured_at)
  3. Mark token as `history_imported: true`
```

### 9.2 Polling (PollGlucoseReadingsJob — Oban Cron: "*/15 * * * *")

```
For each user with active LibreViewToken:
  1. Refresh token if needed
  2. Fetch readings since last_polled_at
  3. Upsert new readings into glucose_readings
  4. Update token.last_polled_at
  5. Check for high post-meal spikes → send WhatsApp alert if needed
```

---

## 10. Glucose-Meal Correlation

### 10.1 Correlation Query

```elixir
def correlate_meal(meal) do
  window_start = DateTime.add(meal.logged_at, -15, :minute)
  window_end   = DateTime.add(meal.logged_at, 120, :minute)

  readings = Repo.all(
    from g in GlucoseReading,
    where: g.user_id == ^meal.user_id
      and g.measured_at >= ^window_start
      and g.measured_at <= ^window_end,
    order_by: g.measured_at
  )

  peak = Enum.max_by(readings, & &1.glucose_mmol, fn -> nil end)
  %{readings: readings, peak_mmol: peak && peak.glucose_mmol}
end
```

### 10.2 Spike Alert Threshold

```
Threshold: post-meal peak > 10.0 mmol/L (180 mg/dL)
Alert: "📈 High glucose after your last meal: {peak} mmol/L.
        Consider lower-GI options next time."
Alert cooldown: 1 per meal (tracked via NotificationLog)
```

### 10.3 GL Classification (Coloring)

| Range (mmol/L) | Color | Label |
|---|---|---|
| < 7.8 | Green | Normal |
| 7.8 – 10.0 | Yellow | Elevated |
| > 10.0 | Red | High |

---

## 11. LiveView — Glucose Dashboard

```elixir
defmodule DietProjectWeb.GlucoseDashboardLive do
  # Mount: load last 24h of glucose readings + meals
  def mount(_params, _session, socket) do
    readings = Integrations.glucose_readings(user_id, hours: 24)
    meals    = Nutrition.meals_for_day(user_id, Date.utc_today())

    socket
    |> assign(readings: readings, meals: meals)
    |> push_event("init_glucose_chart", %{
         readings: format_readings(readings),
         meal_markers: format_meal_markers(meals)
       })
  end

  # Subscribe to real-time glucose updates
  def handle_info({:new_glucose_reading, reading}, socket) do
    push_event(socket, "append_glucose_reading", %{reading: format_reading(reading)})
  end
end
```

Chart.js hook renders a time-series line chart with meal event markers overlaid as vertical annotations.

---

## 12. Token Encryption

All OAuth tokens stored encrypted at rest using `Cloak.Ecto`:

```elixir
# mix.exs: {:cloak_ecto, "~> 1.2"}
field :access_token,  Cloak.Ecto.Binary
field :refresh_token, Cloak.Ecto.Binary
```

Encryption key stored in `CLOAK_KEY` environment variable — never in code or DB.

---

## 13. Security Requirements

- OAuth tokens encrypted at rest (Cloak.Ecto)
- Strava webhook validates `X-Hub-Signature` on every request
- Glucose data **never logged** in application logs (Logger level checks)
- All Integrations queries are scoped by `user_id` — no global queries
- LibreView API uses HTTPS only; reject any non-TLS response
- Token refresh failures revoke the integration and notify the user

---

## 14. Testing Strategy

| Feature | Approach |
|---|---|
| Strava OAuth2 flow | Integration test with mocked Strava API responses |
| Webhook challenge verification | `Plug.Test` with valid/invalid challenge params |
| ProcessStravaActivityJob | `Oban.Testing.perform_job/2`, Mox for Strava API |
| Activity type mapping | Unit test — all Strava types mapped correctly |
| Dynamic TDEE computation | Unit test with fixture ActivityLog data |
| Token refresh logic | Unit test — expired vs. valid token paths |
| ImportGlucoseHistoryJob | `Oban.Testing.perform_job/2`, Mox for LibreView API |
| Glucose correlation | DB integration test with seeded readings + meals |
| Spike alert | Unit test — values above/below threshold |
| Glucose LiveView chart | `Phoenix.LiveViewTest` — verify chart events pushed |
| Token encryption | Unit test — round-trip encrypt/decrypt |
| Cross-user isolation | Test that queries with different user_id return empty |

---

## 15. Database Indexes

```sql
-- Strava dedup
CREATE UNIQUE INDEX activity_logs_strava_id ON activity_logs (strava_activity_id)
  WHERE strava_activity_id IS NOT NULL;

-- Strava athlete lookup
CREATE UNIQUE INDEX strava_tokens_athlete ON strava_tokens (athlete_id);

-- Glucose time-range queries
CREATE INDEX glucose_readings_user_measured ON glucose_readings (user_id, measured_at DESC);

-- Glucose dedup on insert
CREATE UNIQUE INDEX glucose_readings_user_time ON glucose_readings (user_id, measured_at);

-- LibreView token per user
CREATE UNIQUE INDEX libre_tokens_user ON libre_view_tokens (user_id);
```

---

## 16. Error Handling

| Scenario | Behavior |
|---|---|
| Strava token expired (webhook) | Attempt refresh; if fails, mark token inactive, notify user |
| Strava API rate limit (429) | Oban retry with 60s backoff |
| Duplicate Strava activity | Skip insert (unique index constraint); log warning |
| LibreView API unavailable | Retry up to 3x; if fails, skip poll cycle, try next interval |
| Glucose reading outside plausible range (< 1 or > 30 mmol/L) | Discard + log; do not persist |
| Dynamic TDEE < BMR | Cap at BMR + 200 kcal; log anomaly |
| Missing patient_id in LibreView token | Revoke integration; prompt user to reconnect |

---

## 17. Production Checklist

- [ ] OAuth tokens encrypted at rest (`CLOAK_KEY` set in Gigalixir)
- [ ] Strava webhook signature validation enabled
- [ ] `STRAVA_WEBHOOK_VERIFY_TOKEN` set and rotated
- [ ] Glucose data excluded from all logging statements
- [ ] LibreView polling cron verified in staging
- [ ] Token refresh tested for both Strava and LibreView
- [ ] Cross-user isolation verified for all Integrations queries
- [ ] All external API calls over HTTPS with SSL verification enabled
