# Week 02 — Advanced Tracking

**Phase:** 2
**Period:** Weeks 9–14 of the original roadmap

---

## Goal

Expand beyond nutrition into full lifestyle tracking: exercise, hydration, body measurements, fasting, reminders, recipes, and automated weekly reports.

---

## Features

### 2.1 — Exercise Tracking
User logs physical activities via WhatsApp or dashboard. System calculates calories burned using MET values and updates the daily caloric balance.

| Task | Priority |
|---|---|
| Tracking context: `Exercise`, `ActivityLog` | P1 |
| MET values table for calorie expenditure | P1 |
| Exercise recognition from free text via Claude | P1 |
| Integration into daily caloric balance | P1 |

### 2.2 — Water Intake Control
User logs glasses of water via WhatsApp. Bot tracks the daily total and sends alerts when below the goal.

| Task | Priority |
|---|---|
| `WaterLog` model and context | P1 |
| Registration and query commands via WhatsApp | P1 |
| Configurable daily goal (default: 3L) | P2 |

### 2.3 — Body Measurements
User logs weight, circumferences, and body fat %. Evolution charts in the web dashboard.

| Task | Priority |
|---|---|
| `BodyMeasurement` model (weight, waist, hips, arms, etc.) | P1 |
| Weight evolution chart in LiveView | P1 |
| Body composition analysis via photo (Claude API) | P2 |

### 2.4 — Fasting Timer
User starts and ends fasting via WhatsApp. Bot shows elapsed time and notifies when the goal is reached.

| Task | Priority |
|---|---|
| `FastingSession` model with start/end timestamps | P2 |
| Commands: `/fast start`, `/fast end`, `/fast status` | P2 |
| Auto-notification when fasting goal is reached | P2 |

### 2.5 — Custom Reminders
User configures reminders in natural language ("remind me to drink water every day at 10am, 2pm, and 6pm"). Oban Cron fires notifications on schedule.

| Task | Priority |
|---|---|
| `Reminder` model with cron expression | P1 |
| Natural language time parser via Claude | P1 |
| Oban Cron job: `SendReminder` | P1 |
| Reminder management via WhatsApp (list, delete) | P2 |

### 2.6 — Recipe Management
User saves custom recipes with ingredients and portions. System auto-calculates macros when a saved recipe is mentioned in a meal log.

| Task | Priority |
|---|---|
| `Recipe` and `RecipeIngredient` schemas | P2 |
| Recipe CRUD in web dashboard | P2 |
| Recipe recognition when logging a meal | P2 |

### 2.7 — Reports & History
Weekly and monthly reports automatically sent via WhatsApp. Dashboard with macro, calorie, and weight evolution charts.

| Task | Priority |
|---|---|
| Oban Job: `WeeklyReportJob` (fires every Sunday) | P1 |
| LiveView charts: weekly macros, monthly weight | P1 |
| CSV history export | P3 |

---

## Key Architectural Rules

- `Tracking` context is the single owner of exercise, water, body, and fasting data
- Oban cron jobs drive all scheduled notifications and reports — no manual triggers
- `BodyMeasurement` records are **immutable snapshots** — always insert, never update
- MET values seeded from `priv/repo/seeds/met_values.exs` — not hardcoded in logic

---

## Dependencies

- Week 01 complete: Accounts context, Nutrition context, Oban configured, Claude API client
