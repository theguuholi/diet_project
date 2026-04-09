# Week 04 — External Integrations

**Phase:** 4
**Period:** Weeks 21–28 of the original roadmap

---

## Goal

Connect NutriBot to the fitness and health ecosystem: Strava for automatic workout sync, wearables (Garmin, Apple Watch, Whoop) via Strava as a hub, and FreeStyle Libre for continuous glucose monitoring correlated with meals.

---

## Features

### 4.1 — Strava Integration
Automatic sync of completed workouts from Strava. Activities appear in NutriBot and update the daily caloric balance.

| Task | Priority |
|---|---|
| OAuth2 with Strava (Assent) | P2 |
| Strava webhook: activity completed → Oban Job | P2 |
| Activity type → calorie mapping (all Strava types) | P2 |

**Key implementation details:**
- `Integrations.StravaToken`: `user_id`, `access_token`, `refresh_token`, `expires_at`
- Webhook endpoint validates the Strava challenge, then enqueues `ProcessStravaActivityJob`
- Prefer Strava's own `calories` field (uses HR data) over MET estimate when available
- `ActivityLog` extended with `source: :strava` to prevent double-counting manual + synced entries
- Handle Strava `update` and `delete` webhook events

### 4.2 — Garmin / Apple Health / Whoop
Sync wearable data (HR, active calories) via Strava as a central hub — no separate OAuth needed.

| Task | Priority |
|---|---|
| Process Strava payload with HR and active calorie data | P2 |
| Dynamic TDEE based on rolling 7-day wearable data | P3 |

**Key implementation details:**
- `ActivityLog` extended: `avg_heart_rate`, `max_heart_rate`, `calories_source` (`:device`, `:strava_computed`, `:met_estimate`)
- Dynamic TDEE = rolling 7-day average of actual calorie expenditure from device data
- Falls back to static TDEE if no wearable data for > 3 consecutive days
- TDEE changes only affect today onward — past `MacroLog` records are never modified

### 4.3 — FreeStyle Libre (CGM) Integration
Import continuous glucose data from FreeStyle Libre via LibreView API. Visualize the glucose response to each meal.

| Task | Priority |
|---|---|
| LibreView API OAuth2 integration | P3 |
| `GlucoseReading` model and historical data import | P3 |
| Meal → glucose spike correlation in LiveView | P3 |

**Key implementation details:**
- `Integrations.GlucoseReading`: `user_id`, `measured_at`, `glucose_mmol`, `glucose_mgdl`, `trend_arrow`
- Historical import on first connection (last 14 days); poll every 15 minutes via Oban cron
- Correlation window: glucose readings from 15 min before the meal to 2 hours after
- LiveView chart: continuous glucose line with meal markers overlaid
- Color coding: green < 7.8 mmol/L / yellow 7.8–10 / red > 10 mmol/L (post-meal peak)
- WhatsApp alert when post-meal spike > 10 mmol/L
- Glucose data is sensitive health data — **never log it or expose it in error messages**

---

## Production Launch Checklist

Before going live, verify:

- [ ] All OAuth2 tokens refresh automatically (Strava, LibreView)
- [ ] Strava webhook verified with production token
- [ ] `SECRET_KEY_BASE` set via Gigalixir env vars (never in code)
- [ ] Database connection pool sized correctly (`pool_size: 10`)
- [ ] SSL enforced on all external API calls
- [ ] AppSignal/Sentry alerts configured: error rate > 1%, queue depth > 50, latency > 5s
- [ ] Database backups enabled and restore tested
- [ ] Rate limiting on WhatsApp webhook endpoint
- [ ] No cross-user data leakage (all queries parameterized by `user_id`)

---

## Environment Variables Required

```
STRAVA_CLIENT_ID
STRAVA_CLIENT_SECRET
LIBRE_VIEW_CLIENT_ID
LIBRE_VIEW_CLIENT_SECRET
```

---

## Dependencies

- Week 01: `ActivityLog`, Claude API client, Oban
- Week 02: MET values table, `Tracking` context
- Week 03: Glycemic data to enrich glucose-meal correlation view
