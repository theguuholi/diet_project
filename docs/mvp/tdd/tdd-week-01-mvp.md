# TDD — Week 01: MVP

**Version:** 1.0
**Date:** 2026-04-08
**Phase:** 1 — MVP
**Reference:** [Concept Doc](../concept_docs/week-01.md)

---

## 1. Overview

The MVP delivers the full NutriBot core loop: WhatsApp onboarding, AI-powered meal logging (text, photo, audio), a real-time LiveView dashboard, and a subscription system. All heavy processing is async via Oban. The WhatsApp webhook must always respond in < 2s.

---

## 2. System Architecture

```
WhatsApp Cloud API
        │
        ▼
BotController (Phoenix)
  └── responds 200 immediately
  └── enqueues Oban Job
        │
        ▼
Oban Workers
  ├── ProcessTextMeal
  ├── ProcessImageMeal
  └── TranscribeAudio
        │
        ├──► AI Context (Claude API / Whisper API)
        ├──► Integrations.R2Client (Cloudflare R2)
        ├──► Nutrition Context (Meal, FoodItem, MacroLog)
        └──► Bot Context (sends reply via WhatsApp API)

Phoenix LiveView (Dashboard)
  └── subscribes to PubSub "user:{id}:meal_logged"
  └── real-time macro updates
```

---

## 3. Contexts & Responsibilities

| Context | Module | Responsibility |
|---|---|---|
| `Accounts` | `DietProject.Accounts` | Users, profiles, goals, BMR/TDEE |
| `Nutrition` | `DietProject.Nutrition` | Meals, food items, macro logs |
| `Bot` | `DietProject.Bot` | FSM, intent, WhatsApp message formatting |
| `AI` | `DietProject.AI` | Claude API and Whisper API wrappers |
| `Integrations` | `DietProject.Integrations` | R2 uploads, WhatsApp media download |
| `Billing` | `DietProject.Billing` | Plans, subscriptions, invoices |

---

## 4. Data Models

### 4.1 Accounts

```elixir
# users
%User{
  id: uuid,
  phone: string,          # WhatsApp phone number (unique)
  name: string,
  inserted_at: datetime
}

# profiles
%Profile{
  id: uuid,
  user_id: uuid,
  weight_kg: float,
  height_cm: float,
  body_fat_pct: float,
  activity_level: enum,   # :sedentary | :light | :moderate | :very_active | :extra_active
  goal: enum,             # :lose | :maintain | :gain
  bmr: float,
  tdee: float
}

# goals (macro targets)
%Goals{
  id: uuid,
  user_id: uuid,
  calories: integer,
  protein_g: integer,
  carbs_g: integer,
  fat_g: integer
}
```

### 4.2 Nutrition

```elixir
# meals
%Meal{
  id: uuid,
  user_id: uuid,
  logged_at: datetime,
  input_type: enum,       # :text | :photo | :audio
  raw_input: string,      # original user message or R2 URL
  confirmed: boolean      # used for photo confirmation flow
}

# food_items
%FoodItem{
  id: uuid,
  meal_id: uuid,
  name: string,
  quantity: float,
  unit: string,
  calories: float,
  protein_g: float,
  carbs_g: float,
  fat_g: float
}

# macro_logs (daily aggregate per user)
%MacroLog{
  id: uuid,
  user_id: uuid,
  date: date,
  calories: float,
  protein_g: float,
  carbs_g: float,
  fat_g: float
}
```

### 4.3 Bot

```elixir
# conversation_states
%ConversationState{
  id: uuid,
  user_id: uuid,
  state: enum,            # :idle | :onboarding_* | :awaiting_confirmation
  context: map,           # arbitrary state payload (e.g., collected onboarding fields)
  updated_at: datetime
}
```

### 4.4 Billing

```elixir
# plans
%Plan{
  id: uuid,
  name: string,           # "monthly" | "annual"
  price_cents: integer,
  interval: enum          # :month | :year
}

# subscriptions
%Subscription{
  id: uuid,
  user_id: uuid,
  plan_id: uuid,
  status: enum,           # :trialing | :active | :canceled | :past_due
  current_period_end: datetime,
  external_id: string     # Stripe/Asaas subscription ID
}
```

---

## 5. Key Algorithms

### 5.1 BMR (Katch-McArdle)

```elixir
# lean_body_mass = weight_kg * (1 - body_fat_pct / 100)
# BMR = 370 + (21.6 * lean_body_mass)
def calculate_bmr(weight_kg, body_fat_pct) do
  lean_mass = weight_kg * (1 - body_fat_pct / 100)
  370 + 21.6 * lean_mass
end
```

### 5.2 TDEE Multipliers

| Activity Level | Multiplier |
|---|---|
| `:sedentary` | 1.2 |
| `:light` | 1.375 |
| `:moderate` | 1.55 |
| `:very_active` | 1.725 |
| `:extra_active` | 1.9 |

### 5.3 Default Macro Split

| Goal | Protein | Carbs | Fat |
|---|---|---|---|
| `:lose` | 35% | 35% | 30% |
| `:maintain` | 30% | 40% | 30% |
| `:gain` | 30% | 45% | 25% |

---

## 6. API Contracts

### 6.1 Claude API — Food Extraction Prompt

**Input:**
```
Extract foods and macros from this meal description. Return JSON only.
Description: "{user_message}"

Schema: [{
  "food": string,
  "quantity": number,
  "unit": string,
  "calories": number,
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number
}]
```

**Expected output:**
```json
[
  {"food": "egg", "quantity": 2, "unit": "unit", "calories": 156, "protein_g": 12, "carbs_g": 1, "fat_g": 11},
  {"food": "bread", "quantity": 1, "unit": "slice", "calories": 80, "protein_g": 3, "carbs_g": 15, "fat_g": 1}
]
```

### 6.2 Claude API — Vision Prompt

**Input:**
```
Analyze this meal photo. Identify all visible foods and estimate portions.
Return JSON only.
[base64 image]

Schema: [{
  "food": string,
  "quantity": number,
  "unit": string,
  "calories": number,
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number,
  "confidence": "high" | "medium" | "low"
}]
```

### 6.3 WhatsApp Webhook Payload

```json
{
  "entry": [{
    "changes": [{
      "value": {
        "messages": [{
          "from": "5511999999999",
          "type": "text" | "image" | "audio",
          "text": {"body": "..."},
          "image": {"id": "...", "mime_type": "image/jpeg"},
          "audio": {"id": "...", "mime_type": "audio/ogg"}
        }]
      }
    }]
  }]
}
```

---

## 7. Oban Workers

### 7.1 ProcessTextMeal

```
Input:  %{user_id: uuid, message: string}
Steps:
  1. Load user profile and goals
  2. Call AI.ClaudeClient.extract_meal(message)
  3. Parse JSON response into [FoodItem] structs
  4. Persist Meal + FoodItems via Nutrition context
  5. Update MacroLog for the day
  6. Broadcast PubSub "user:{id}:meal_logged"
  7. Send formatted reply via WhatsApp
Retries: 3 (Oban default backoff)
```

### 7.2 ProcessImageMeal

```
Input:  %{user_id: uuid, media_id: string}
Steps:
  1. Download image from WhatsApp API using media_id
  2. Upload image to Cloudflare R2, get URL
  3. Encode image as base64
  4. Call AI.ClaudeClient.analyze_image(base64)
  5. Set ConversationState to :awaiting_confirmation with parsed data
  6. Send confirmation message to user
  7. On confirmation → same as ProcessTextMeal steps 3–7
Retries: 3
```

### 7.3 TranscribeAudio

```
Input:  %{user_id: uuid, media_id: string}
Steps:
  1. Download audio from WhatsApp API
  2. Upload audio to R2
  3. Call AI.WhisperClient.transcribe(audio_binary)
  4. On success → enqueue ProcessTextMeal with transcribed text
  5. On failure → send error message to user
Retries: 2
```

---

## 8. Onboarding FSM States

```
:idle
  → user sends any message → :collecting_name

:collecting_name
  → user replies with name → :collecting_weight

:collecting_weight
  → user replies with weight → :collecting_height

:collecting_height
  → user replies with height → :collecting_body_fat

:collecting_body_fat
  → user replies with % → :collecting_goal

:collecting_goal
  → user selects goal → :collecting_activity

:collecting_activity
  → user selects level → calculate BMR/TDEE → persist profile → :done → :idle
```

State persisted in `conversation_states` table. Each state stores collected fields in `context` map.

---

## 9. Feature Gate

```elixir
# In Oban worker, before processing:
def check_feature_gate(user_id) do
  if Billing.subscriber?(user_id) do
    :ok
  else
    count = Nutrition.meal_count_today(user_id)
    if count >= 3, do: {:error, :trial_limit_reached}, else: :ok
  end
end
```

Free users receive a WhatsApp upgrade message when the limit is hit.

---

## 10. Magic Link Auth Flow

```
1. User sends "/login" to bot
2. Bot generates token: :crypto.strong_rand_bytes(32) |> Base.url_encode64()
3. Token hashed (SHA-256) and stored in DB with user_id + expires_at (15 min)
4. Bot sends: "Your login link: https://app.nutribot.com/auth/{raw_token}"
5. User clicks link → SessionController validates token hash
6. On valid: create Phoenix session, delete token, redirect to /dashboard
7. On expired/invalid: show error page
```

---

## 11. PubSub Events

| Event | Broadcaster | Subscriber |
|---|---|---|
| `"user:{id}:meal_logged"` | `Nutrition` context | `DashboardLive` |
| `"user:{id}:onboarding_complete"` | `Accounts` context | `DashboardLive` |

---

## 12. Testing Strategy

| Layer | Tool | Approach |
|---|---|---|
| BMR/TDEE calculations | ExUnit | Pure function tests, no mocks needed |
| Claude API | Mox (`AI.ClaudeClientBehaviour`) | Mock responses, never hit real API |
| Whisper API | Mox (`AI.WhisperClientBehaviour`) | Mock transcription responses |
| WhatsApp API | Mox | Mock send/download |
| R2 uploads | Mox | Mock upload, return fake URL |
| Oban workers | `Oban.Testing` | Use `perform_job/2` in tests |
| LiveView | `Phoenix.LiveViewTest` | Simulate user interactions |
| Billing webhooks | `Plug.Test` | Simulate Stripe/Asaas webhook payloads |

All Mox behaviours defined in `test/support/mocks.ex`.

---

## 13. Database Indexes

```sql
-- Fast daily macro aggregation
CREATE INDEX macro_logs_user_date ON macro_logs (user_id, date);

-- Meal history per user
CREATE INDEX meals_user_logged_at ON meals (user_id, logged_at);

-- Active subscription lookup
CREATE INDEX subscriptions_user_status ON subscriptions (user_id, status);

-- Magic link token validation
CREATE UNIQUE INDEX magic_tokens_hash ON magic_tokens (token_hash);
```

---

## 14. Error Handling

| Scenario | Behavior |
|---|---|
| Claude API timeout | Oban retries up to 3x with exponential backoff; user notified on permanent failure |
| Whisper API failure | User notified: "Could not transcribe audio. Please try sending a text instead." |
| R2 upload failure | Oban retries; meal not persisted until upload succeeds |
| WhatsApp send failure | Log error; do not retry (avoid duplicate messages) |
| Invalid subscription webhook | Return 400; log the invalid payload |
| Trial limit reached | Friendly message with upgrade link; no error in logs |
