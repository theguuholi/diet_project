# lib/diet_project — Module Documentation Standards

Every file under this directory must follow these standards without exception.

---

## Context Modules

Every context module requires:

1. `@moduledoc` — explains **why the module exists**, what domain it owns, and what problem it solves
2. `@doc` on every public function — explains what the function does, its parameters, and its return value, with at least one `doctest`
3. `@spec` on every public function

```elixir
defmodule DietProject.Nutrition do
  @moduledoc """
  Manages meal logging, food item storage, and daily macro aggregation.

  This context is the single source of truth for everything a user has eaten.
  It owns the `Meal`, `FoodItem`, and `MacroLog` schemas and exposes a public
  API consumed by Oban workers and the LiveView dashboard.

  Contexts do not call each other directly — cross-context communication
  happens via `Phoenix.PubSub` events or Oban jobs.
  """

  @doc """
  Returns the aggregated macro totals for a user on a given date.

  Sums calories, protein, carbs, and fat across all `MacroLog` entries
  for `user_id` on `date`. Returns a map with zeroed values when no meals
  have been logged yet.

  ## Parameters

  - `user_id` — the UUID of the user
  - `date` — the calendar date to aggregate (e.g. `Date.utc_today()`)

  ## Examples

      iex> DietProject.Nutrition.daily_summary("user-uuid", ~D[2026-04-09])
      %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}

  """
  @spec daily_summary(user_id :: Ecto.UUID.t(), date :: Date.t()) :: map()
  def daily_summary(user_id, date) do
    ...
  end
end
```

---

## Schema Modules

Every schema requires:

1. `@moduledoc` — explains **why this table/record exists** and what it represents in the domain
2. A `@type` for **every field** — the type annotation and a brief explanation of what the field holds
3. A `@type t` representing the full struct

```elixir
defmodule DietProject.Nutrition.Meal do
  @moduledoc """
  Represents a single meal logging event submitted by a user.

  A `Meal` is created whenever a user logs food via WhatsApp — whether by
  text, photo, or audio. It acts as the parent record for one or more
  `FoodItem` entries and tracks which input method was used and whether
  the user has confirmed the AI-parsed result.
  """

  use Ecto.Schema

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this meal to its owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc """
  How the meal was submitted.
  - `:text`  — free-text WhatsApp message
  - `:photo` — image sent via WhatsApp, analysed by Claude vision
  - `:audio` — voice message, transcribed by Whisper then analysed by Claude
  """
  @type input_type :: :text | :photo | :audio

  @typedoc "UTC timestamp of when the meal was logged"
  @type logged_at :: DateTime.t()

  @typedoc """
  Whether the user has confirmed the AI-parsed food items.
  Always `true` for text input. Starts `false` for photo/audio until
  the user replies to the confirmation prompt.
  """
  @type confirmed :: boolean()

  @type t :: %__MODULE__{
    id:         id(),
    user_id:    user_id(),
    input_type: input_type(),
    logged_at:  logged_at(),
    confirmed:  confirmed()
  }

  schema "meals" do
    field :input_type, Ecto.Enum, values: [:text, :photo, :audio]
    field :confirmed,  :boolean, default: false
    belongs_to :user, DietProject.Accounts.User
    has_many   :food_items, DietProject.Nutrition.FoodItem
    timestamps()
  end
end
```

---

## Doctests

Every public function must have at least one `doctest` in its `@doc`. Doctests are picked up automatically by ExUnit — add `doctest DietProject.MyModule` to the corresponding test file.

### Writing good doctests

```elixir
@doc """
Calculates the Basal Metabolic Rate using the Katch-McArdle formula.

BMR = 370 + (21.6 × lean_body_mass_kg)
where lean_body_mass_kg = weight_kg × (1 - body_fat_pct / 100)

## Parameters

- `weight_kg`     — total body weight in kilograms
- `body_fat_pct`  — body fat percentage (0–100)

## Examples

    iex> DietProject.Accounts.calculate_bmr(80.0, 20.0)
    1748.8

    iex> DietProject.Accounts.calculate_bmr(60.0, 15.0)
    1371.4

"""
@spec calculate_bmr(weight_kg :: float(), body_fat_pct :: float()) :: float()
def calculate_bmr(weight_kg, body_fat_pct) do
  lean_mass = weight_kg * (1 - body_fat_pct / 100)
  Float.round(370 + 21.6 * lean_mass, 1)
end
```

Activating doctests in the test file:

```elixir
# test/diet_project/accounts_test.exs
defmodule DietProject.AccountsTest do
  use DietProject.DataCase

  doctest DietProject.Accounts
end
```

### Doctest rules

- Use realistic values — not `1`, `2`, `3`
- Cover the happy path and at least one edge case (e.g. zero, empty list, nil)
- For functions with side effects (DB writes, API calls), use `@doc` examples marked with `# returns` comments instead of runnable doctests, or extract the pure computation into a separate function and doctest that
- Doctests on functions that require DB state should be skipped with `:skip` tag or moved to the ExUnit test file

---

## Oban Worker Modules

Workers follow the same rules:

```elixir
defmodule DietProject.Workers.ProcessTextMeal do
  @moduledoc """
  Oban worker that processes a text-based meal log submitted via WhatsApp.

  Receives the user's free-text meal description, calls the Claude API to
  extract structured food and macro data, persists the result, updates the
  daily `MacroLog`, broadcasts a PubSub event for the LiveView dashboard,
  and sends the formatted response back to the user via WhatsApp.

  This worker is enqueued by `BotController` immediately after the WhatsApp
  webhook is received, ensuring the HTTP response stays under 2 seconds.
  """

  use Oban.Worker, queue: :meals, max_attempts: 3

  @doc """
  Executes the text meal processing job.

  Expects a job args map with:
  - `"user_id"` — UUID of the user who sent the message
  - `"message"` — raw text of the WhatsApp message

  Returns `:ok` on success or `{:error, reason}` to trigger Oban retry.
  """
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "message" => message}}) do
    ...
  end
end
```

---

## AI Wrapper Modules

```elixir
defmodule DietProject.AI.ClaudeClient do
  @moduledoc """
  HTTP client wrapper for the Anthropic Claude API.

  Centralises all Claude API communication for the application. Every
  Claude call goes through this module so that request logging, error
  handling, token tracking, and Mox stubbing in tests have a single
  point of control.

  Implements `DietProject.AI.ClaudeClientBehaviour` so it can be swapped
  for a `Mox` mock in tests without hitting the real API.
  """

  @doc """
  Sends a single-turn completion request to the Claude API.

  ## Parameters

  - `prompt`  — the user prompt string
  - `opts`    — keyword options:
    - `:model`      — Claude model ID (default: `"claude-sonnet-4-6"`)
    - `:max_tokens` — maximum tokens in the response (default: `1024`)

  ## Examples

      iex> DietProject.AI.ClaudeClient.complete("What is 2 + 2?")
      {:ok, "4"}

  """
  @spec complete(prompt :: String.t(), opts :: keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def complete(prompt, opts \\ []) do
    ...
  end
end
```

---

## Quick Reference

| Requirement | Context module | Schema module | Worker | AI wrapper |
|---|---|---|---|---|
| `@moduledoc` why it exists | ✅ required | ✅ required | ✅ required | ✅ required |
| `@doc` on every public function | ✅ required | — | ✅ required | ✅ required |
| `@spec` on every public function | ✅ required | — | ✅ required | ✅ required |
| Doctest in `@doc` | ✅ required | — | ✗ use ExUnit | ✅ where pure |
| `@type` per field | — | ✅ required | — | — |
| `@type t` for the struct | — | ✅ required | — | — |
