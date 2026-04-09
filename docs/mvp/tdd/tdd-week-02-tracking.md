# TDD — Week 02: Advanced Tracking

**Version:** 1.0
**Date:** 2026-04-08
**Phase:** 2 — Advanced Tracking
**Reference:** [Concept Doc](../concept_docs/week-02.md)

---

## 1. Overview

Extends NutriBot beyond nutrition into full lifestyle tracking. The `Tracking` context owns exercise, water, body measurements, and fasting data. All scheduled jobs (reminders, reports, water alerts) run via Oban Cron. The `Nutrition` context is extended to include exercise calories in the daily balance.

---

## 2. System Architecture

```
WhatsApp Message
        │
        ▼
Bot.IntentDetector
  ├── :log_exercise    → ProcessExerciseJob (Oban)
  ├── :log_water       → Tracking.log_water/2 (sync, lightweight)
  ├── :log_body        → Tracking.log_measurement/2 (sync)
  ├── :fasting_command → Tracking.handle_fast/2
  ├── :set_reminder    → ProcessReminderJob (Oban, Claude parse)
  └── :log_meal        → (Week 01 pipeline)

Oban Cron Jobs
  ├── SendReminderWorker    — fires per reminder schedule
  ├── WaterAlertWorker      — daily at 18:00 per user timezone
  └── WeeklyReportWorker    — every Sunday at 20:00
```

---

## 3. Contexts & Responsibilities

| Context | Additions |
|---|---|
| `Tracking` | `Exercise`, `ActivityLog`, `WaterLog`, `BodyMeasurement`, `FastingSession` |
| `Notifications` | `Reminder`, `NotificationLog` |
| `Nutrition` (extended) | `daily_summary/2` includes exercise calories burned |

---

## 4. Data Models

### 4.1 Tracking

```elixir
# exercises (static reference table, seeded from MET values)
%Exercise{
  id: uuid,
  name: string,           # "running", "cycling", "weight_training"
  met_value: float,
  category: enum          # :cardio | :strength | :flexibility | :sports
}

# activity_logs
%ActivityLog{
  id: uuid,
  user_id: uuid,
  exercise_id: uuid,
  date: date,
  duration_minutes: integer,
  calories_burned: float,
  source: enum,           # :manual | :strava (future)
  notes: string
}

# water_logs
%WaterLog{
  id: uuid,
  user_id: uuid,
  date: date,
  amount_ml: integer      # 1 glass = 250ml default
}

# body_measurements (immutable snapshots — never update)
%BodyMeasurement{
  id: uuid,
  user_id: uuid,
  measured_at: datetime,
  weight_kg: float,
  body_fat_pct: float,
  waist_cm: float,
  hips_cm: float,
  chest_cm: float,
  arm_cm: float,
  notes: string
}

# fasting_sessions
%FastingSession{
  id: uuid,
  user_id: uuid,
  started_at: datetime,
  ended_at: datetime,     # null while active
  goal_hours: float,      # e.g. 16.0 for 16:8
  completed: boolean
}
```

### 4.2 Notifications

```elixir
# reminders
%Reminder{
  id: uuid,
  user_id: uuid,
  message: string,        # "Time to drink water!"
  cron_expr: string,      # "0 10 * * *" (daily at 10:00)
  timezone: string,       # "America/Sao_Paulo"
  active: boolean
}

# notification_logs
%NotificationLog{
  id: uuid,
  user_id: uuid,
  reminder_id: uuid,      # nullable (for system alerts)
  sent_at: datetime,
  channel: enum,          # :whatsapp
  status: enum            # :sent | :failed
}
```

---

## 5. Key Algorithms

### 5.1 Calorie Expenditure (MET)

```elixir
# calories = MET × weight_kg × duration_hours
def calculate_calories_burned(met_value, weight_kg, duration_minutes) do
  duration_hours = duration_minutes / 60
  Float.round(met_value * weight_kg * duration_hours, 1)
end
```

### 5.2 Daily Balance (Extended)

```elixir
def daily_summary(user_id, date) do
  goals      = Accounts.get_goals(user_id)
  consumed   = Nutrition.macro_log(user_id, date)
  burned     = Tracking.exercise_calories(user_id, date)
  water      = Tracking.water_total_ml(user_id, date)

  %{
    goal_calories:     goals.calories,
    consumed_calories: consumed.calories,
    burned_calories:   burned,
    net_calories:      consumed.calories - burned,
    remaining:         goals.calories - consumed.calories + burned,
    protein_g:         consumed.protein_g,
    carbs_g:           consumed.carbs_g,
    fat_g:             consumed.fat_g,
    water_ml:          water,
    water_goal_ml:     goals.water_ml || 3000
  }
end
```

### 5.3 Fasting Status

```elixir
def fasting_status(user_id) do
  case Tracking.active_fast(user_id) do
    nil -> {:no_active_fast}
    session ->
      elapsed_hours = DateTime.diff(DateTime.utc_now(), session.started_at, :second) / 3600
      pct = Float.round(elapsed_hours / session.goal_hours * 100, 1)
      {:active, %{elapsed_hours: elapsed_hours, goal_hours: session.goal_hours, pct: pct}}
  end
end
```

---

## 6. MET Values Seed (Selected)

```elixir
# priv/repo/seeds/met_values.exs
[
  %{name: "running",          met: 9.8,  category: :cardio},
  %{name: "cycling",          met: 7.5,  category: :cardio},
  %{name: "swimming",         met: 6.0,  category: :cardio},
  %{name: "walking",          met: 3.5,  category: :cardio},
  %{name: "weight_training",  met: 3.5,  category: :strength},
  %{name: "hiit",             met: 8.0,  category: :cardio},
  %{name: "yoga",             met: 2.5,  category: :flexibility},
  %{name: "football",         met: 7.0,  category: :sports},
  %{name: "basketball",       met: 6.5,  category: :sports},
  %{name: "dancing",          met: 4.8,  category: :cardio}
]
```

---

## 7. Claude API Contract — Exercise Parsing

**Prompt:**
```
Extract exercise data from this message. Return JSON only.
Message: "{user_message}"

Schema: {
  "activity": string,       // normalized activity name
  "duration_minutes": number,
  "intensity": "low" | "moderate" | "high"
}
```

**Expected output:**
```json
{"activity": "running", "duration_minutes": 30, "intensity": "moderate"}
```

Post-processing: match `activity` against `exercises.name` via `ILIKE`. If no match, use the closest MET category default.

---

## 8. Claude API Contract — Reminder Parsing

**Prompt:**
```
Extract reminder schedule from this message. Return JSON only.
Message: "{user_message}"
User timezone: "{timezone}"

Schema: [{
  "message": string,
  "times": ["HH:MM"],
  "days": "daily" | ["mon","tue","wed","thu","fri","sat","sun"],
  "cron_expr": string
}]
```

**Expected output:**
```json
[
  {"message": "Drink water!", "times": ["10:00"], "days": "daily", "cron_expr": "0 10 * * *"},
  {"message": "Drink water!", "times": ["14:00"], "days": "daily", "cron_expr": "0 14 * * *"},
  {"message": "Drink water!", "times": ["18:00"], "days": "daily", "cron_expr": "0 18 * * *"}
]
```

---

## 9. Oban Workers

### 9.1 ProcessExerciseJob

```
Input:  %{user_id: uuid, message: string}
Steps:
  1. Call AI.ClaudeClient.parse_exercise(message)
  2. Match activity name against exercises table
  3. Load user weight from Profile
  4. Calculate calories_burned
  5. Persist ActivityLog
  6. Broadcast PubSub "user:{id}:exercise_logged"
  7. Send WhatsApp reply with calories burned
```

### 9.2 SendReminderWorker

```
Input:  %{reminder_id: uuid}
Steps:
  1. Load Reminder (skip if inactive)
  2. Send WhatsApp message to user
  3. Persist NotificationLog
  4. Re-enqueue next occurrence based on cron_expr + timezone
```

### 9.3 WaterAlertWorker (Oban Cron: "0 18 * * *")

```
Steps (per active user):
  1. Load water_goal_ml from Goals (default 3000)
  2. Sum WaterLog.amount_ml for today
  3. If total < goal * 0.5:
     → Send alert: "You've only had {total}ml today. Goal: {goal}ml. Keep it up!"
  4. Persist NotificationLog
```

### 9.4 WeeklyReportWorker (Oban Cron: "0 20 * * 0")

```
Steps (per active subscriber):
  1. Aggregate MacroLog for last 7 days
  2. Compute: avg_calories, total_protein, best_day, worst_day, trend vs. previous week
  3. Call Claude to generate a 2-sentence motivational summary
  4. Send WhatsApp report
  5. Persist NotificationLog
```

---

## 10. LiveView — Weight Chart

```elixir
# Mount: load last 90 days of BodyMeasurement
defp load_weight_history(user_id) do
  Tracking.list_measurements(user_id, days: 90)
  |> Enum.map(&{&1.measured_at, &1.weight_kg})
end

# Push to Chart.js hook via push_event
push_event(socket, "update_chart", %{
  labels: dates,
  data: weights
})
```

Chart.js hook (`phx-hook="LineChart"`) renders a line chart with weight on Y-axis and date on X-axis.

---

## 11. Recipe Matching Algorithm

```
1. User logs: "I ate my omelet"
2. Extract meal intent via Claude → candidate: "omelet"
3. Query: SELECT * FROM recipes WHERE user_id = ? AND name ILIKE '%omelet%'
4. If match found with similarity > 0.8 (pg_trgm):
   → Use recipe macros directly (sum ingredients / servings)
5. If no match:
   → Fall back to Claude food analysis
```

---

## 12. Weekly Report Format

```
📊 Your Weekly Summary

Avg. daily calories: 1,820 / 2,000 kcal
Total protein: 756g (108g/day avg)
Best day: Wednesday (on target ✅)
Worst day: Saturday (+420 kcal over goal)

vs. last week: -3% calories ↓ (good trend!)

Keep it up — you're making steady progress! 💪
```

---

## 13. Testing Strategy

| Feature | Approach |
|---|---|
| MET calorie calculation | Pure function tests — no mocks |
| Exercise parsing | Mox `AI.ClaudeClientBehaviour` |
| Reminder parsing | Mox `AI.ClaudeClientBehaviour` |
| Fasting status | Pure function tests with fixed timestamps |
| WaterAlertWorker | `Oban.Testing.perform_job/2`, mock WhatsApp send |
| WeeklyReportWorker | `Oban.Testing.perform_job/2`, assert notification logged |
| Weight chart LiveView | `Phoenix.LiveViewTest`, verify event pushed |
| Recipe matching | DB integration test with seeded recipes |

---

## 14. Database Indexes

```sql
-- Exercise lookups
CREATE INDEX activity_logs_user_date ON activity_logs (user_id, date);

-- Water daily sum
CREATE INDEX water_logs_user_date ON water_logs (user_id, date);

-- Body measurement history
CREATE INDEX body_measurements_user_measured ON body_measurements (user_id, measured_at DESC);

-- Active fasting session
CREATE INDEX fasting_sessions_user_active ON fasting_sessions (user_id) WHERE ended_at IS NULL;

-- Active reminders
CREATE INDEX reminders_user_active ON reminders (user_id) WHERE active = true;

-- Recipe name search (fuzzy)
CREATE INDEX recipes_name_trgm ON recipes USING gin (name gin_trgm_ops);
```

---

## 15. Error Handling

| Scenario | Behavior |
|---|---|
| Exercise not recognized | Reply: "I couldn't identify that exercise. Try: 'I ran for 30 minutes'" |
| No MET match | Use generic MET = 4.0 (moderate activity); notify user of estimate |
| Fasting already active | Reply: "You already have an active fast. Use `/fast status` to check." |
| Reminder cron parse failure | Reply with error, ask user to rephrase |
| WeeklyReport Claude failure | Send report without the motivational summary; log error |
| Water alert send failure | Log to NotificationLog with status `:failed`; do not retry |
