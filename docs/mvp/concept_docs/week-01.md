# Week 01 — MVP

**Phase:** 1
**Period:** Weeks 1–8 of the original roadmap

---

## Goal

Deliver a fully functional, monetizable product: WhatsApp bot operating with AI-powered macro calculation, a basic web dashboard, and an active subscription system.

---

## Features

### 1.1 — WhatsApp Onboarding
Bot collects name, weight, height, body fat %, goal (lose / maintain / gain), and activity level. Automatically calculates BMR (Katch-McArdle), TDEE, and daily macro targets.

| Task | Priority |
|---|---|
| WhatsApp bot with onboarding FSM (GenServer) | P0 |
| Accounts context: `User`, `Profile`, `Goals` | P0 |
| BMR + TDEE calculation | P0 |
| Macro targets persisted to profile | P0 |
| Unit tests for nutritional calculations | P0 |

### 1.2 — Text Meal Logging
User sends free text ("I ate 2 eggs with bread and cheese"). Claude API parses it into structured JSON with calories and macros. System persists and updates the daily balance.

| Task | Priority |
|---|---|
| Claude API integration (`Req` HTTP client) | P0 |
| Prompt engineering for food/macro extraction | P0 |
| Nutrition context: `Meal`, `FoodItem`, `MacroLog` | P0 |
| Oban Job: `ProcessTextMeal` | P0 |
| Formatted WhatsApp response | P0 |
| Mox tests for Claude API | P0 |

### 1.3 — Photo Meal Logging
User sends a photo. Image is uploaded to Cloudflare R2 and processed asynchronously. Claude vision identifies foods and estimates portions. User can confirm or correct.

| Task | Priority |
|---|---|
| Image upload to Cloudflare R2 | P0 |
| Oban Job: `ProcessImageMeal` | P0 |
| Claude vision integration (base64) | P0 |
| Confirmation flow via bot | P0 |
| Manual quantity correction | P1 |

### 1.4 — Audio Meal Logging
User sends an audio describing the meal. Whisper API transcribes it, then the text flows through the same Claude pipeline as text logging.

| Task | Priority |
|---|---|
| Audio upload to R2 | P0 |
| Oban Job: `TranscribeAudio` (Whisper API) | P0 |
| Pipeline: audio → text → Claude → macros | P0 |
| Transcription error handling | P1 |

### 1.5 — Daily Caloric Balance
User asks "how much can I still eat?" or "my summary". Bot replies with consumed vs. target for calories, protein, carbs, and fat.

| Task | Priority |
|---|---|
| Aggregated macro query (`user_id + date`) | P0 |
| WhatsApp response with progress bars | P0 |
| `/summary` command + intent detection | P0 |

### 1.6 — LiveView Web Dashboard
Mobile-accessible web interface showing real-time daily summary, weekly history, and macro progress bars.

| Task | Priority |
|---|---|
| Magic link auth sent via WhatsApp | P0 |
| LiveView dashboard: real-time daily macros | P0 |
| Weekly calorie chart (Chart.js) | P1 |
| Meal list with delete option | P1 |
| PWA: `manifest.json` + service worker | P1 |

### 1.7 — Subscription & Payment
Monthly/annual subscription via Stripe or Asaas. Free users limited to 3 meal logs/day as trial.

| Task | Priority |
|---|---|
| Billing context: `Subscription`, `Plan`, `Invoice` | P0 |
| Stripe Checkout or Asaas integration | P0 |
| Payment webhook → activate subscription | P0 |
| Feature gate middleware (subscriber vs. free) | P0 |
| Cancellation via WhatsApp or dashboard | P1 |

---

## Key Architectural Rules

- `BotController` must respond to WhatsApp webhook in **< 2s** — all heavy work goes to Oban
- All media processing (photo, audio, AI calls) is **async via Oban** — never sync in the request
- Contexts do **not call each other directly** — use PubSub or Oban Jobs for cross-context communication
- Use **Mox** for all external dependencies in tests — no real API calls

---

## Environment Variables Required

```
CLAUDE_API_KEY
OPENAI_API_KEY
CLOUDFLARE_R2_*
WHATSAPP_TOKEN
STRIPE_SECRET_KEY or ASAAS_API_KEY
```
