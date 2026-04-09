# TDD — Week 03: Advanced AI

**Version:** 1.0
**Date:** 2026-04-08
**Phase:** 3 — Advanced AI
**Reference:** [Concept Doc](../concept_docs/week-03.md)

---

## 1. Overview

Transforms the bot into a context-aware conversational assistant. Introduces multi-turn conversation history, personalized food suggestions, glycemic index evaluation per meal, and habit pattern detection with weekly insights. All AI calls remain async via Oban; conversation context is injected into every Claude prompt.

---

## 2. System Architecture

```
WhatsApp Message
        │
        ▼
Bot.IntentDetector
  ├── :log_meal         → (Week 01/02 pipeline, unchanged)
  ├── :ask_question     → Bot.ConversationalHandler
  ├── :command          → Bot.CommandRouter
  └── :correction       → Bot.CorrectionHandler
        │
        ▼
Bot.ContextBuilder
  ├── load Profile + Goals
  ├── load daily_summary (today's macros + exercise)
  ├── load last 3 meals
  └── load ConversationHistory (last 10 messages)
        │
        ▼
AI.ClaudeClient.chat(system_prompt, history, user_message)
        │
        ▼
Bot.ResponseFormatter → WhatsApp reply

Background Jobs (Oban)
  ├── WeeklyInsightJob   — fires Sunday with WeeklyReportJob
  └── (existing meal processing jobs extended with GI/frequency updates)
```

---

## 3. Data Models

### 3.1 Conversation History

```elixir
# conversation_messages
%ConversationMessage{
  id: uuid,
  user_id: uuid,
  role: enum,         # :user | :assistant
  content: string,
  inserted_at: datetime
}
# Scoped to last 10 per user; auto-expired after 24h inactivity
```

### 3.2 Glycemic Data

```elixir
# glycemic_index_db (seeded from TACO + USDA)
%GlycemicIndexEntry{
  id: uuid,
  food_name: string,
  gi_value: integer,      # 0–100
  food_category: string
}

# macro_logs extended (new columns)
%MacroLog{
  ...
  glycemic_load: float,   # sum of (GI × carbs_g / 100) per food item
  avg_gi: float           # weighted average GI for the meal
}
```

### 3.3 Food Frequencies

```elixir
# food_frequencies
%FoodFrequency{
  id: uuid,
  user_id: uuid,
  food_name: string,
  count: integer,
  last_logged_at: datetime
}
# Upserted on every meal log (insert or increment count)
```

---

## 4. Bot.ContextBuilder

Assembles the system prompt for every conversational request. Must be fast (< 50ms) — reads from DB with a single query per data type.

### 4.1 System Prompt Structure

```
You are NutriBot, a nutritional assistant. Be friendly, concise, and use Brazilian Portuguese.

[PROFILE]
Name: {name}
Goal: {goal}
Daily targets: {calories} kcal | Protein: {protein}g | Carbs: {carbs}g | Fat: {fat}g

[TODAY - {date}]
Consumed: {consumed_calories} kcal | Protein: {protein}g | Carbs: {carbs}g | Fat: {fat}g
Burned (exercise): {burned_calories} kcal
Remaining: {remaining_calories} kcal

[RECENT MEALS]
{meal_1_time}: {meal_1_description} ({meal_1_calories} kcal)
{meal_2_time}: ...
{meal_3_time}: ...

Answer the user's question based on this context.
```

**Token budget:** keep system prompt under 800 tokens. Use abbreviated field names if needed.

### 4.2 Context Assembly

```elixir
def build(user_id) do
  profile  = Accounts.get_profile(user_id)
  goals    = Accounts.get_goals(user_id)
  summary  = Nutrition.daily_summary(user_id, Date.utc_today())
  meals    = Nutrition.recent_meals(user_id, limit: 3)

  %{
    system_prompt: render_system_prompt(profile, goals, summary, meals),
    history:       ConversationHistory.get(user_id, limit: 10)
  }
end
```

---

## 5. Bot.IntentDetector

Classifies incoming messages into intents. Uses rule-based matching first (fast, free), falls back to Claude for ambiguous cases.

### 5.1 Rule-Based (Priority 1)

| Pattern | Intent |
|---|---|
| Starts with `/` | `:command` |
| Contains `photo`, `image` (+ attachment) | `:log_meal` |
| Contains `yes`, `correct`, `sim`, `correto` | `:correction` |
| Contains `I ate`, `I had`, `comi`, `tomei` | `:log_meal` |
| Contains `exercise`, `ran`, `corri`, `treino` | `:log_exercise` |
| Contains `kg`, `weight`, `peso` + number | `:log_body` |

### 5.2 Claude Classification (Fallback)

**Prompt:**
```
Classify this message into one intent. Return JSON only.
Message: "{message}"

Options: "log_meal" | "ask_question" | "command" | "correction" | "log_exercise" | "log_water"

{"intent": "..."}
```

Use `claude-haiku` for this call — fast and cheap.

---

## 6. Conversational Flow

### 6.1 Multi-Turn Conversation

```elixir
def handle_question(user_id, user_message) do
  %{system_prompt: sp, history: history} = ContextBuilder.build(user_id)

  messages = history ++ [%{role: "user", content: user_message}]

  {:ok, reply} = AI.ClaudeClient.chat(sp, messages)

  # Persist both sides of the exchange
  ConversationHistory.append(user_id, :user, user_message)
  ConversationHistory.append(user_id, :assistant, reply)

  # Trim to last 10 messages
  ConversationHistory.trim(user_id, keep: 10)

  Bot.WhatsApp.send(user_id, reply)
end
```

### 6.2 Food Suggestions

When user asks "what can I eat for dinner?":

```elixir
def suggest_foods(user_id) do
  summary     = Nutrition.daily_summary(user_id, Date.utc_today())
  frequent    = FoodFrequency.top(user_id, limit: 10)
  remaining   = summary.remaining

  prompt = """
  Suggest 3 meal options for the user's next meal.
  Remaining macros: #{remaining.calories} kcal, #{remaining.protein_g}g protein,
                    #{remaining.carbs_g}g carbs, #{remaining.fat_g}g fat.
  User's favorite foods: #{Enum.join(frequent, ", ")}.
  Be specific with portions. Use common Brazilian foods. Return in Portuguese.
  """

  AI.ClaudeClient.complete(prompt)
end
```

---

## 7. Glycemic Index Evaluation

### 7.1 GL Calculation

```elixir
def calculate_meal_gl(food_items) do
  food_items
  |> Enum.map(fn item ->
    gi = GlycemicDB.lookup(item.name) || 55  # default GI when unknown
    (gi * item.carbs_g) / 100
  end)
  |> Enum.sum()
  |> Float.round(1)
end

# GL classification
def classify_gl(gl) when gl < 10,  do: :low
def classify_gl(gl) when gl < 20,  do: :medium
def classify_gl(gl),               do: :high
```

### 7.2 GI Database Lookup

```elixir
# Fuzzy match against glycemic_index_db
def lookup(food_name) do
  Repo.one(
    from g in GlycemicIndexEntry,
    where: fragment("similarity(?, ?) > 0.4", g.food_name, ^food_name),
    order_by: fragment("similarity(?, ?) DESC", g.food_name, ^food_name),
    limit: 1,
    select: g.gi_value
  )
end
```

**Requires** `pg_trgm` extension: `CREATE EXTENSION IF NOT EXISTS pg_trgm;`

### 7.3 High-GL Alert

```
Triggered when: meal GL ≥ 20
Message: "⚠️ This meal has a high glycemic load (GL: {gl}).
          Consider pairing with protein or fiber to slow absorption."
```

---

## 8. Habit Learning

### 8.1 Food Frequency Upsert

```elixir
# Called inside ProcessTextMeal / ProcessImageMeal after persisting FoodItems
def update_frequencies(user_id, food_items) do
  Enum.each(food_items, fn item ->
    Repo.insert(
      %FoodFrequency{user_id: user_id, food_name: item.name, count: 1, last_logged_at: DateTime.utc_now()},
      on_conflict: [inc: [count: 1], set: [last_logged_at: DateTime.utc_now()]],
      conflict_target: [:user_id, :food_name]
    )
  end)
end
```

### 8.2 Pattern Detection Queries

```elixir
# Skipped breakfast: days with no Meal before noon in last 30 days
def skipped_breakfasts(user_id) do
  Repo.all(
    from m in Meal,
    where: m.user_id == ^user_id
      and m.logged_at >= ago(30, "day")
      and fragment("EXTRACT(hour FROM ?)", m.logged_at) < 12,
    select: fragment("DATE(?)", m.logged_at),
    distinct: true
  )
  # Days NOT in result = skipped breakfasts
end

# Calorie spikes: days > 20% over goal
def calorie_spike_days(user_id, goal_calories) do
  threshold = goal_calories * 1.2
  Repo.all(
    from l in MacroLog,
    where: l.user_id == ^user_id
      and l.date >= ago(30, "day")
      and l.calories > ^threshold,
    select: l.date
  )
end
```

### 8.3 WeeklyInsightJob

```
Input: %{user_id: uuid}
Steps:
  1. Run pattern detection queries (skipped meals, spikes, top foods)
  2. Build insight prompt:
     "User data: skipped breakfast X times last month, calorie spikes on {days},
      top foods: {foods}. Write a 2-sentence personalized nutritional insight in Portuguese.
      Be factual, supportive, and actionable. Do not be judgmental."
  3. Call AI.ClaudeClient.complete(prompt)
  4. Send WhatsApp message with insight
  5. Log to NotificationLog
```

---

## 9. Prompt Versioning

All prompts stored as module constants with explicit version tags:

```elixir
defmodule DietProject.AI.Prompts.FoodExtraction do
  @version "1.2"

  def system_prompt do
    """
    [v#{@version}] Extract foods and macros...
    """
  end
end
```

Log version with every `ai_request_logs` entry for A/B tracking.

---

## 10. AI Request Logging

```elixir
# ai_request_logs
%AIRequestLog{
  id: uuid,
  user_id: uuid,
  prompt_type: string,    # "food_extraction" | "intent_detection" | "conversation" | ...
  prompt_version: string,
  model: string,          # "claude-sonnet-4-6" | "claude-haiku-4-5"
  input_tokens: integer,
  output_tokens: integer,
  latency_ms: integer,
  success: boolean,
  inserted_at: datetime
}
```

This table feeds cost monitoring and prompt performance dashboards.

---

## 11. Model Selection Strategy

| Use Case | Model | Reason |
|---|---|---|
| Intent detection | `claude-haiku` | Fast, cheap, simple classification |
| Reminder parsing | `claude-haiku` | Structured JSON, low complexity |
| Food extraction (text) | `claude-sonnet` | Accuracy matters for nutrition data |
| Food extraction (vision) | `claude-sonnet` | Vision capability required |
| Conversational Q&A | `claude-sonnet` | Nuanced, personalized responses |
| Weekly insights | `claude-sonnet` | Creative, personalized copy |

---

## 12. ConversationHistory Module

```elixir
defmodule DietProject.Bot.ConversationHistory do
  # Returns messages in Claude multi-turn format
  def get(user_id, limit: 10) do
    Repo.all(
      from m in ConversationMessage,
      where: m.user_id == ^user_id,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Enum.reverse()
    |> Enum.map(&%{role: to_string(&1.role), content: &1.content})
  end

  # Auto-expire: delete messages older than 24h since last activity
  def trim(user_id, keep: n) do
    ids_to_keep =
      Repo.all(from m in ConversationMessage,
        where: m.user_id == ^user_id,
        order_by: [desc: m.inserted_at],
        limit: ^n,
        select: m.id)

    Repo.delete_all(
      from m in ConversationMessage,
      where: m.user_id == ^user_id and m.id not in ^ids_to_keep
    )
  end
end
```

---

## 13. Testing Strategy

| Feature | Approach |
|---|---|
| IntentDetector (rule-based) | Pure unit tests — cover all intent patterns |
| IntentDetector (Claude fallback) | Mox — verify correct prompt structure |
| ContextBuilder | Unit test with fixture data — verify token budget |
| GL calculation | Pure function tests — known GI × carbs inputs |
| GI DB lookup | DB integration test with seeded TACO data |
| FoodFrequency upsert | DB integration test — verify count increments |
| Pattern detection queries | DB integration test with seeded meal history |
| WeeklyInsightJob | Mox for Claude; assert NotificationLog entry |
| Conversation history trim | Unit test — verify only N records kept |
| Multi-turn conversation | Mox for Claude; verify history passed correctly |

---

## 14. Database Indexes

```sql
-- Conversation history per user (chronological)
CREATE INDEX conv_messages_user_inserted ON conversation_messages (user_id, inserted_at DESC);

-- Food frequency top lookup
CREATE INDEX food_freq_user_count ON food_frequencies (user_id, count DESC);

-- Upsert conflict target
CREATE UNIQUE INDEX food_freq_user_food ON food_frequencies (user_id, food_name);

-- GI fuzzy lookup
CREATE INDEX gi_db_name_trgm ON glycemic_index_db USING gin (food_name gin_trgm_ops);

-- AI request log cost queries
CREATE INDEX ai_logs_user_inserted ON ai_request_logs (user_id, inserted_at DESC);
```

---

## 15. Error Handling

| Scenario | Behavior |
|---|---|
| Intent detection failure | Default to `:ask_question` intent; log warning |
| ContextBuilder DB timeout | Return minimal context (profile only); log error |
| Conversation history gap | Silently rebuild — Claude handles missing context gracefully |
| GI lookup miss | Use default GI = 55 (medium); note in `MacroLog` |
| WeeklyInsight Claude failure | Skip insight text; send report numbers only |
| Token budget exceeded | Truncate history first, then truncate meal list |
