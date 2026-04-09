# Week 03 — Advanced AI

**Phase:** 3
**Period:** Weeks 15–20 of the original roadmap

---

## Goal

Transform the bot from a command-driven tool into a truly intelligent assistant: context-aware conversations, glycemic load evaluation, and habit learning with personalized weekly insights.

---

## Features

### 3.1 — Conversational Assistant
User can ask free-form questions ("what can I eat for dinner to hit my protein goal?"). Claude responds with full awareness of the user's profile, daily progress, and conversation history.

| Task | Priority |
|---|---|
| Context builder: inject profile + daily summary into prompt | P1 |
| Intent detection: meal log vs. question vs. command | P1 |
| Food suggestions based on remaining macro balance | P2 |
| Conversation history in context (last 10 messages) | P2 |

**Key implementation details:**
- `Bot.ContextBuilder` assembles the system prompt per request: profile, macro targets, today's summary, last 3 meals
- `Bot.IntentDetector` classifies messages into: `:log_meal`, `:ask_question`, `:command`, `:correction`
- Conversation history stored in DB, trimmed to last 10 messages, expires after 24h of inactivity
- Keep context under ~2,000 tokens to control API cost

### 3.2 — Glycemic Index Evaluation
For each logged meal, the system estimates glycemic index (GI) and glycemic load (GL). Alerts user when GL is high.

| Task | Priority |
|---|---|
| Food GI database (TACO + USDA) seeded | P2 |
| Glycemic load calculation per meal | P2 |
| High-GL alert via WhatsApp (GL ≥ 20) | P3 |

**Key implementation details:**
- `GL = (GI × carbs_g) / 100` — summed per meal
- GL classification: Low < 10 / Medium 10–19 / High ≥ 20
- TACO database seeded from `priv/repo/seeds/taco.csv` (free from UNICAMP)
- Stored in `MacroLog`: `glycemic_index`, `glycemic_load` columns

### 3.3 — Habit Learning & Pattern Detection
System learns the user's most frequent foods and detects behavioral patterns. Delivers a personalized weekly insight via WhatsApp.

| Task | Priority |
|---|---|
| `food_frequencies` table per user | P3 |
| Frequent food suggestions during meal logging | P3 |
| Weekly insight: detected pattern sent via WhatsApp | P3 |

**Key implementation details:**
- `food_frequencies`: `user_id`, `food_name`, `count`, `last_logged_at` — updated on every meal log
- Pattern queries: skipped meals (0 `Meal` records before noon), calorie spikes (> 20% over goal), top 5 foods
- Claude generates the insight text from raw pattern data — factual, not judgmental
- Fires alongside `WeeklyReportJob` every Sunday

---

## Prompt Engineering Guidelines

- Store all prompts as module constants in `lib/diet_project/ai/prompts/` — not inline strings
- Tag each prompt with `@version` for future A/B testing
- Use claude-haiku for intent detection (cheaper), claude-sonnet for food analysis and conversation
- Log token usage per request in `ai_request_logs` for cost tracking
- Test prompts against a curated set of 20+ real Brazilian meal descriptions

---

## Dependencies

- Week 01: `AI.ClaudeClient`, `Nutrition.daily_summary/2`
- Week 02: `food_frequencies` updated in `ProcessTextMeal` / `ProcessImageMeal` jobs
