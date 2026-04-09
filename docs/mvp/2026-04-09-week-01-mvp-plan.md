# Week 01 MVP — Implementation Plan

**Date:** 2026-04-09
**Branch:** `feature/week-01-mvp`
**Reference:** [TDD](./tdd/tdd-week-01-mvp.md) · [Concept Doc](./concept_docs/week-01.md)

---

## Context

The project has a working authentication foundation (phx.gen.auth, User schema, session management) but zero business logic. This plan implements all 7 MVP features from the Week 01 TDD using strict TDD: every test is written before its implementation. The outcome is the full NutriBot core loop: WhatsApp onboarding → AI meal logging → real-time LiveView dashboard → subscription gating.

---

## TDD Rule

For every task: **write the failing test first → implement minimum code → verify green → refactor**.
Never write implementation code without a test file open.

---

## Baseline Fix (before Task 1)

The current test suite requires `lazy_html` as a LiveView test dependency. Add it to `mix.exs` before starting:

```elixir
{:lazy_html, ">= 0.0.0", only: :test},
```

Run `mix deps.get && mix test` to confirm all 128 tests pass before proceeding.

---

## Tasks

### Task 1 — Dependencies & Mox scaffolding

**Goal:** Add all missing libraries and define all Mox mocks so every subsequent task can compile.

**Files to modify/create:**

| File | Change |
|---|---|
| `mix.exs` | Add `oban ~> 2.18`, `req ~> 0.5`, `mox ~> 1.0 (test only)`, `ex_aws ~> 2.5`, `ex_aws_s3 ~> 2.5` |
| `config/config.exs` | Add Oban config with queues: `meals: 10, media: 5, audio: 5` |
| `config/test.exs` | Set `Oban.Testing` plugin; set AI/R2/WhatsApp adapters to Mox mocks |
| `lib/diet_project/application.ex` | Add `{Oban, Application.fetch_env!(:diet_project, Oban)}` to supervision tree |
| `test/support/mocks.ex` | Define 4 Mox mocks (see below) |
| `test/test_helper.exs` | Add `Mox.defmock` calls |

**Mox mocks to define in `test/support/mocks.ex`:**
```elixir
Mox.defmock(DietProject.AI.ClaudeClientMock,       for: DietProject.AI.ClaudeClientBehaviour)
Mox.defmock(DietProject.AI.WhisperClientMock,      for: DietProject.AI.WhisperClientBehaviour)
Mox.defmock(DietProject.Integrations.R2ClientMock, for: DietProject.Integrations.R2ClientBehaviour)
Mox.defmock(DietProject.Integrations.WhatsAppClientMock, for: DietProject.Integrations.WhatsAppClientBehaviour)
```

**Verify:** `mix deps.get && mix test` — all tests pass.

---

### Task 2 — Extend User with phone field

**Goal:** Every NutriBot user is identified by their WhatsApp phone number (E.164 format).

**Files to create/modify:**

| File | Change |
|---|---|
| `priv/repo/migrations/TIMESTAMP_add_phone_to_users.exs` | `add :phone, :string`; unique index on `users(phone)` |
| `lib/diet_project/accounts/user.ex` | Add `field :phone, :string`; validate E.164 format |
| `lib/diet_project/accounts.ex` | Add `get_user_by_phone/1`; accept phone in `register_user/1` |
| `test/support/fixtures/accounts_fixtures.ex` | Add phone to `valid_user_attributes/1` |

**Test file:** `test/diet_project/accounts_test.exs`

**Verify:** `mix test test/diet_project/accounts_test.exs`

---

### Task 3 — Profile & Goals schemas + BMR/TDEE calculations

**Goal:** Collect user body data during onboarding and calculate caloric targets.

**Files to create:**

| File | Purpose |
|---|---|
| `priv/repo/migrations/TIMESTAMP_create_profiles.exs` | `profiles` table (user_id FK, weight_kg, height_cm, body_fat_pct, activity_level enum, goal enum, bmr, tdee) |
| `priv/repo/migrations/TIMESTAMP_create_goals.exs` | `goals` table (user_id FK, calories, protein_g, carbs_g, fat_g) |
| `lib/diet_project/accounts/profile.ex` | `Profile` schema — `@moduledoc`, `@type t`, `@typedoc` per field, changeset |
| `lib/diet_project/accounts/goals.ex` | `Goals` schema — `@moduledoc`, `@type t`, changeset |
| `lib/diet_project/accounts.ex` | Add: `calculate_bmr/2`, `calculate_tdee/2`, `default_macro_targets/2`, `create_profile/2`, `get_profile/1`, `update_profile/3`, `create_goals/2`, `get_goals/1` |
| `test/support/fixtures/accounts_fixtures.ex` | Add `profile_fixture/1`, `goals_fixture/1` |

**Key algorithms (from TDD §5):**
```elixir
# BMR (Katch-McArdle)
lean_mass = weight_kg * (1 - body_fat_pct / 100)
bmr = 370 + 21.6 * lean_mass

# TDEE multipliers
%{sedentary: 1.2, light: 1.375, moderate: 1.55, very_active: 1.725, extra_active: 1.9}

# Macro split by goal (% of calories)
%{lose: %{protein: 35, carbs: 35, fat: 30}, ...}
```

**Doctest requirement:** `calculate_bmr/2` and `calculate_tdee/2` must have doctests.

**Test file:** `test/diet_project/accounts_test.exs`

---

### Task 4 — Nutrition context (Meal, FoodItem, MacroLog)

**Goal:** Persist meal events, parsed food items, and daily macro aggregates.

**Files to create:**

| File | Purpose |
|---|---|
| `priv/repo/migrations/TIMESTAMP_create_meals.exs` | `meals` table; index on `(user_id, logged_at)` |
| `priv/repo/migrations/TIMESTAMP_create_food_items.exs` | `food_items` table |
| `priv/repo/migrations/TIMESTAMP_create_macro_logs.exs` | `macro_logs` table; unique index on `(user_id, date)` |
| `lib/diet_project/nutrition/meal.ex` | Schema with `@moduledoc`, `@type t`, `@typedoc` per field |
| `lib/diet_project/nutrition/food_item.ex` | Schema |
| `lib/diet_project/nutrition/macro_log.ex` | Schema |
| `lib/diet_project/nutrition.ex` | Context — see public API below |
| `test/support/fixtures/nutrition_fixtures.ex` | `meal_fixture/1`, `food_item_fixture/1`, `macro_log_fixture/1` |

**Public API for `DietProject.Nutrition`:**

| Function | Spec | Purpose |
|---|---|---|
| `create_meal/2` | `(user_id, attrs) :: {:ok, Meal.t()} \| {:error, changeset}` | Insert meal + food items in transaction |
| `update_macro_log/2` | `(user_id, date) :: {:ok, MacroLog.t()}` | Upsert daily macro aggregate |
| `daily_summary/2` | `(user_id, date) :: map()` | Returns `%{calories, protein_g, carbs_g, fat_g}` (zeroed if no data) |
| `meal_count_today/1` | `(user_id) :: non_neg_integer()` | Count today's meals (for feature gate) |
| `list_meals/2` | `(user_id, opts) :: [Meal.t()]` | Paginated meal list for dashboard |
| `broadcast_meal_logged/2` | `(user_id, meal) :: :ok` | PubSub broadcast to `"user:{id}:meal_logged"` |

**Test file:** `test/diet_project/nutrition_test.exs`

---

### Task 5 — Bot context (ConversationState + FSM)

**Goal:** Persist onboarding state and drive the 7-step FSM for each WhatsApp user.

**Files to create:**

| File | Purpose |
|---|---|
| `priv/repo/migrations/TIMESTAMP_create_conversation_states.exs` | `conversation_states` table (user_id unique FK, state enum, context jsonb) |
| `lib/diet_project/bot/conversation_state.ex` | Schema; states: `:idle \| :collecting_name \| :collecting_weight \| :collecting_height \| :collecting_body_fat \| :collecting_goal \| :collecting_activity \| :awaiting_confirmation` |
| `lib/diet_project/bot.ex` | Context — see public API below |

**Public API for `DietProject.Bot`:**

| Function | Purpose |
|---|---|
| `get_or_create_state/1` | Fetch or create `:idle` state for user |
| `advance_state/2` | FSM transition; returns `{:ok, next_state, response_text}` |
| `set_awaiting_confirmation/2` | Store parsed food data in state context map |
| `format_macro_reply/2` | Format macro totals as WhatsApp message string |
| `format_daily_balance/3` | Format daily progress vs goal as WhatsApp message |

**FSM transitions (from TDD §8):**
```
:idle → any message → :collecting_name
:collecting_name → name reply → :collecting_weight
:collecting_weight → weight → :collecting_height
:collecting_height → height → :collecting_body_fat
:collecting_body_fat → % → :collecting_goal
:collecting_goal → goal selection → :collecting_activity
:collecting_activity → level → calculate BMR/TDEE → persist → :idle
```

**Test file:** `test/diet_project/bot_test.exs` — must cover all FSM transitions.

---

### Task 6 — AI context (Claude client)

**Goal:** Wrap the Claude API for text food extraction and image vision analysis.

**Files to create:**

| File | Purpose |
|---|---|
| `lib/diet_project/ai/claude_client_behaviour.ex` | `@callback extract_meal/1` and `@callback analyze_image/1` |
| `lib/diet_project/ai/claude_client.ex` | `Req` HTTP implementation; reads `CLAUDE_API_KEY` from env |
| `lib/diet_project/ai/prompts/food_extraction.ex` | `build/1` — versioned food extraction prompt |
| `lib/diet_project/ai/prompts/vision.ex` | `build/1` — versioned vision prompt |
| `lib/diet_project/ai.ex` | Public API; delegates to `Application.get_env(:diet_project, :claude_client)` |

**Tests use `ClaudeClientMock` — never hit the real API.**

**Test file:** `test/diet_project/ai/claude_client_test.exs`

---

### Task 7 — AI context (Whisper client)

**Goal:** Wrap the OpenAI Whisper API for audio transcription.

**Files to create:**

| File | Purpose |
|---|---|
| `lib/diet_project/ai/whisper_client_behaviour.ex` | `@callback transcribe/1` |
| `lib/diet_project/ai/whisper_client.ex` | `Req` POST to OpenAI audio endpoint |

Extend `lib/diet_project/ai.ex` with `transcribe/1` delegating to configured adapter.

**Test file:** `test/diet_project/ai/whisper_client_test.exs`

---

### Task 8 — Integrations (R2 + WhatsApp media)

**Goal:** Upload media to Cloudflare R2 and download media from WhatsApp.

**Files to create:**

| File | Purpose |
|---|---|
| `lib/diet_project/integrations/r2_client_behaviour.ex` | `@callback upload/3` |
| `lib/diet_project/integrations/r2_client.ex` | ExAws S3 upload to R2; returns `{:ok, url}` |
| `lib/diet_project/integrations/whatsapp_client_behaviour.ex` | `@callback send_message/2`, `@callback download_media/1` |
| `lib/diet_project/integrations/whatsapp_client.ex` | `Req` calls to WhatsApp Business API |
| `lib/diet_project/integrations.ex` | Public API delegating to configured adapters |

**Test file:** `test/diet_project/integrations_test.exs`

---

### Task 9 — Oban workers + BotController

**Goal:** Process all three message types asynchronously; respond to WhatsApp webhook in < 2s.

**Files to create:**

| File | Worker steps |
|---|---|
| `lib/diet_project/workers/process_text_meal.ex` | Feature gate → `AI.extract_meal` → `Nutrition.create_meal` → `Nutrition.update_macro_log` → PubSub → WhatsApp reply |
| `lib/diet_project/workers/process_image_meal.ex` | R2 upload → Claude vision → set confirmation state → on confirm: persist + notify |
| `lib/diet_project/workers/transcribe_audio.ex` | R2 upload → Whisper → enqueue `ProcessTextMeal` |
| `lib/diet_project_web/controllers/bot_controller.ex` | Verify webhook signature → route by type → enqueue worker → respond `200 ""` |

**Worker tests use `Oban.Testing.perform_job/2`.**

**Test files:** `test/diet_project/workers/process_text_meal_test.exs`, etc.

---

### Task 10 — Billing context (Plans, Subscriptions, Feature Gate)

**Goal:** Gate heavy features behind a subscription; handle Stripe webhooks.

**Files to create:**

| File | Purpose |
|---|---|
| `priv/repo/migrations/TIMESTAMP_create_plans.exs` | `plans` table (name, price_cents, interval enum) |
| `priv/repo/migrations/TIMESTAMP_create_subscriptions.exs` | `subscriptions` table; index on `(user_id, status)` |
| `lib/diet_project/billing/plan.ex` | Schema |
| `lib/diet_project/billing/subscription.ex` | Schema; status: `:trialing \| :active \| :canceled \| :past_due` |
| `lib/diet_project/billing.ex` | `subscriber?/1`, `create_subscription/2`, `update_subscription_status/2`, `handle_stripe_webhook/1` |
| `lib/diet_project_web/controllers/billing_controller.ex` | POST `/webhooks/stripe`; verify Stripe signature |
| `test/support/fixtures/billing_fixtures.ex` | `plan_fixture/0`, `subscription_fixture/1` |

**Test file:** `test/diet_project/billing_test.exs`

---

### Task 11 — Magic Link Auth (Dashboard Login)

**Goal:** Let WhatsApp users log in to the web dashboard without a password.

**Files to create/modify:**

| File | Purpose |
|---|---|
| `priv/repo/migrations/TIMESTAMP_create_magic_tokens.exs` | `magic_tokens` table; unique index on `token_hash` |
| `lib/diet_project/accounts/magic_token.ex` | Schema; `build/1` generates raw token + SHA-256 hash; `verify/1` checks expiry |
| `lib/diet_project/accounts.ex` | Add `generate_magic_link_token/1`, `verify_magic_link_token/1` |
| `lib/diet_project_web/controllers/user_session_controller.ex` | Add `magic_link/2` action |

**Test file:** extend `test/diet_project/accounts_test.exs`

---

### Task 12 — LiveView Dashboard

**Goal:** Real-time macro tracking dashboard; updates instantly when meals are logged via WhatsApp.

**Files to create:**

| File | Purpose |
|---|---|
| `lib/diet_project_web/live/dashboard_live/index.ex` | Mount, PubSub subscribe (`connected?` guard), assigns |
| `lib/diet_project_web/live/dashboard_live/index.html.heex` | Mobile-first semantic layout |
| `lib/diet_project_web/live/dashboard_live/macro_summary_component.ex` | LiveComponent — calories/protein/carbs/fat with progress bars |
| `lib/diet_project_web/live/dashboard_live/macro_summary_component.html.heex` | Template |
| `lib/diet_project_web/live/dashboard_live/meal_list_component.ex` | Stream-based meal list |
| `lib/diet_project_web/live/dashboard_live/meal_list_component.html.heex` | Template |
| `lib/diet_project_web/live/dashboard_live/weekly_chart_component.ex` | `phx-hook="WeeklyChart"` |
| `assets/js/hooks/WeeklyChart/index.js` | Chart.js or canvas-based chart |
| `assets/js/hooks.js` | Register `WeeklyChart` |

**Test file:** `test/diet_project_web/live/dashboard_live_test.exs`

**PubSub test pattern:**
```elixir
Phoenix.PubSub.broadcast(DietProject.PubSub, "user:#{user_id}:meal_logged", {:meal_logged, meal})
assert has_element?(view, "#macro-summary", "1,200 kcal")
```

---

### Task 13 — Router updates

**File:** `lib/diet_project_web/router.ex`

**Changes:**
```elixir
# Bot + Stripe webhooks (no CSRF)
scope "/webhooks", DietProjectWeb do
  pipe_through :api
  post "/whatsapp", BotController, :webhook
  post "/stripe",   BillingController, :webhook
end

# Magic link login
scope "/auth", DietProjectWeb do
  pipe_through :browser
  get "/:token", UserSessionController, :magic_link
end

# Dashboard — add inside :require_authenticated_user live_session
live "/dashboard", DashboardLive.Index, :index
```

---

## Migrations Summary

| # | Migration | Table | Purpose |
|---|---|---|---|
| 1 | `add_phone_to_users` | `users` | WhatsApp phone number |
| 2 | `create_profiles` | `profiles` | BMR/TDEE source data |
| 3 | `create_goals` | `goals` | Daily macro targets |
| 4 | `create_conversation_states` | `conversation_states` | Bot FSM state |
| 5 | `create_meals` | `meals` | Meal log events |
| 6 | `create_food_items` | `food_items` | Parsed food per meal |
| 7 | `create_macro_logs` | `macro_logs` | Daily macro aggregates |
| 8 | `create_magic_tokens` | `magic_tokens` | Dashboard login tokens |
| 9 | `create_plans` | `plans` | Subscription tiers |
| 10 | `create_subscriptions` | `subscriptions` | User subscription state |

---

## Verification Checklist (after every task)

```bash
mix credo --strict    # no issues
mix test              # all green
mix test --cover      # ≥ 97% coverage
mix dialyzer          # no new warnings
mix precommit         # full gate — must pass before commit
```

**End-to-end smoke test (after all 13 tasks):**
1. POST `/webhooks/whatsapp` with text message → Oban job enqueues → `ProcessTextMeal` runs → meal persisted → dashboard macro updates via PubSub
2. Free user POSTs 4th meal → feature gate fires → WhatsApp reply with upgrade CTA
3. User sends `/login` → magic token generated → link clicked → session created → `/dashboard` renders correct macros
