# NutriBot — CLAUDE.md

## Project Overview

**NutriBot** is an intelligent nutritional assistant that operates primarily via WhatsApp, allowing users to log meals (photo, audio, or text) and instantly receive calorie and macronutrient calculations. Inspired by Dieta.ai, built on Elixir/Phoenix for native concurrency and low infrastructure cost.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Elixir + Phoenix 1.7 |
| Web Dashboard | Phoenix LiveView |
| Media Queues | Oban Pro |
| Database | PostgreSQL (Gigalixir) |
| AI (vision/text) | Claude API (claude-sonnet) |
| AI (audio) | OpenAI Whisper API |
| Object Storage | Cloudflare R2 |
| Deploy | Gigalixir |
| Bot | WhatsApp Business API |
| Authentication | Pow + Pow Assent (Google/Apple OAuth) |
| Monitoring | AppSignal or Sentry |

---

## Essential Commands

```bash
# Initial setup
mix setup               # installs deps, creates DB, runs migrations, compiles assets

# Development
mix phx.server          # starts server at localhost:4000
iex -S mix phx.server   # server with interactive IEx

# Database
mix ecto.create         # creates the database
mix ecto.migrate        # runs migrations
mix ecto.reset          # drop + full setup

# Assets
mix assets.build        # compiles Tailwind + esbuild
mix assets.deploy       # minified build for production

# Tests
mix test                           # runs all tests (creates/migrates DB automatically)
mix test test/path/to_test.exs     # runs a specific test file
mix test --failed                  # re-run only previously failing tests
```

---

## Context Architecture

The project follows Phoenix context architecture. Contexts **do not call each other directly** — communication happens via PubSub or Oban Jobs when needed.

| Context | Responsibility | Main Schemas |
|---|---|---|
| `Accounts` | Users, auth, profiles, goals | `User`, `Profile`, `Goals` |
| `Nutrition` | Meals, foods, macros, recipes | `Meal`, `FoodItem`, `Recipe`, `MacroLog` |
| `Tracking` | Exercise, weight, water, fasting, body measurements | `Exercise`, `WaterLog`, `BodyMeasurement`, `FastingSession` |
| `Notifications` | Reminders, reports, WhatsApp alerts | `Reminder`, `NotificationLog` |
| `Integrations` | Strava, LibreLink, WhatsApp Business API | `StravaToken`, `GlucoseReading` |
| `Bot` | WhatsApp FSM, intent detection, response formatting | `Conversation`, `ConversationState` |
| `AI` | Claude API and Whisper API wrappers | — |
| `Billing` | Stripe/Asaas, plans, invoices | `Plan`, `Invoice` |

---

## Architectural Principles

1. **Domain-separated contexts** — each context has a clear public API
2. **All media processing is async via Oban** — never synchronous in the request (photos, audio, AI calls)
3. **WhatsApp as primary channel**, LiveView as secondary dashboard
4. **Feature flags from day one** for incremental rollout
5. **Tests from day one**: ExUnit + Mox for external dependencies (Claude API, Whisper, WhatsApp)
6. **WhatsApp webhook must respond in < 2s** — all heavy work goes to the Oban queue

---

## Media Processing Flow

```
1. BotController receives WhatsApp webhook → responds 200 in < 2s
2. Enqueues Oban Job with message payload
3. Oban Worker downloads media from WhatsApp → saves to R2
4. Oban Worker processes with AI (Claude API or Whisper)
5. Nutrition context persists Meal + MacroLog
6. Bot context sends formatted response via WhatsApp
```

---

## Development Phases

| Phase | Period | Main Deliverable |
|---|---|---|
| **Phase 1 — MVP** | Weeks 1–8 | WhatsApp + AI + macros + dashboard + subscription |
| **Phase 2 — Tracking** | Weeks 9–14 | Exercise, water, body, reminders, recipes |
| **Phase 3 — Advanced AI** | Weeks 15–20 | Conversational assistant, glycemic index, habit learning |
| **Phase 4 — Integrations** | Weeks 21–28 | Strava, Garmin, FreeStyle Libre |

### Phase 1 — MVP (current focus)

- **1.1** WhatsApp onboarding (FSM via GenServer, data collection, BMR/TDEE calculation)
- **1.2** Text meal logging (Claude API + Oban Job `ProcessTextMeal`)
- **1.3** Photo meal logging (R2 upload + Claude vision + `ProcessImageMeal`)
- **1.4** Audio meal logging (Whisper transcription + `TranscribeAudio`)
- **1.5** Daily caloric balance (aggregated query + WhatsApp formatting)
- **1.6** LiveView Web Dashboard (magic link auth, real-time dashboard, weekly chart)
- **1.7** Subscription and payment (Stripe/Asaas, feature gate, free trial 3 logs/day)

---

## Test-Driven Development (TDD)

**All implementation code must follow TDD. Always write the test first.**

1. Write a failing test that describes the expected behaviour
2. Write the minimum implementation to make it pass
3. Refactor while keeping tests green

Never write implementation code without a corresponding test written first. This applies to context functions, LiveViews, Oban workers, and AI wrappers alike.

---

## Workflow

- **Always** write implementation plans to the `plan/` folder before touching code. Every plan must be a file in `plan/` — never write plans inline or in other locations. Each plan must explain **why** every migration and context module exists — what problem it solves, what data it owns, or what responsibility it carries.
- **Always** run `mix precommit` before every commit and **fix every issue it reports**. A failing `mix precommit` means the work is not done — do not commit until it passes clean.
- For HTTP requests, use the included `:req` (`Req`) library. **Never** use `:httpoison`, `:tesla`, or `:httpc`.
- Read task docs before running unfamiliar mix tasks: `mix help task_name`
- **Never** use `mix deps.clean --all` unless there is a concrete reason

### Test Coverage — Protected Files

**Never** modify these two files under any circumstances:

- `mix.exs` — the `summary: [threshold: 97]` line inside `test_coverage:`. This is the minimum coverage gate; lowering it is not acceptable.
- `.test_coverage_ignore.exs` — lists modules excluded from coverage. Do not add modules here to paper over missing tests; write the tests instead.

---

## Code Conventions

- Follow the [Elixir style guide](https://github.com/christopheradams/elixir_style_guide) and standard `mix format`
- Context modules at `lib/diet_project/<context>.ex` with well-defined public functions
- Ecto schemas at `lib/diet_project/<context>/<schema>.ex`
- LiveViews at `lib/diet_project_web/live/`
- Oban Workers at `lib/diet_project/workers/`
- Use Mox to mock external dependencies in tests — never make real API calls in tests
- Use `Req` as the HTTP client for external integrations

---

## Elixir

- Lists **do not support index-based access** via `list[i]`. Use `Enum.at/2`, pattern matching, or `List` functions instead.
- Block expressions (`if`, `case`, `cond`) **must** have their result bound at the call site — you cannot rebind inside the block:

  ```elixir
  # WRONG — socket is rebound inside the if, result is lost
  if connected?(socket) do
    socket = assign(socket, :val, val)
  end

  # CORRECT — bind the result of the if expression
  socket =
    if connected?(socket) do
      assign(socket, :val, val)
    end
  ```

- **Never** nest multiple modules in the same file — causes cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs — use `my_struct.field` or `Ecto.Changeset.get_field/2`
- **Never** use `String.to_atom/1` on user input — memory leak risk
- Predicate function names must **not** start with `is_` and must end in `?`. Reserve `is_thing` style for guards only
- Use `Task.async_stream(collection, callback, timeout: :infinity)` for concurrent enumeration with back-pressure
- Use `Time`, `Date`, `DateTime`, and `Calendar` from the standard library for date/time work. Only add `date_time_parser` for parsing. **Never** add other date/time deps
- Elixir has `if/else` but **no `else if` or `elsif`**. Use `cond` or `case` for multiple branches

---

## Ecto

- **Always use changesets** for data validation and mutation — never validate params manually with `if/case` logic or raw map checks
- **Always preload associations** in context queries when they will be accessed in templates
- `Ecto.Schema` fields use `:string` even for text columns: `field :name, :string`
- `Ecto.Changeset.validate_number/2` does **not** support `:allow_nil` — omit it, validations already skip nil values by default
- Use `Ecto.Changeset.get_field(changeset, :field)` to read changeset values — never `changeset[:field]`
- Fields set programmatically (e.g. `user_id`) must **not** appear in `cast/3` — set them explicitly on the struct
- `import Ecto.Query` in `seeds.exs` and any module that builds raw queries

---

## Module Documentation

> See also: [`lib/diet_project/CLAUDE.md`](lib/diet_project/CLAUDE.md) for full examples with doctests.

### Context Modules

Every context module requires `@moduledoc` (why it exists), `@doc` + `@spec` on every public function, and at least one doctest per function:

```elixir
defmodule DietProject.Nutrition do
  @moduledoc """
  Manages meal logging, food item storage, and daily macro aggregation.

  Single source of truth for what a user has eaten. Owns Meal, FoodItem,
  and MacroLog. Exposes a public API consumed by Oban workers and LiveView.
  """

  @doc """
  Returns aggregated macro totals for a user on a given date.

  ## Examples

      iex> DietProject.Nutrition.daily_summary("user-uuid", ~D[2026-04-09])
      %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}

  """
  @spec daily_summary(user_id :: Ecto.UUID.t(), date :: Date.t()) :: map()
  def daily_summary(user_id, date), do: ...
end
```

### Schema Modules

Every schema requires `@moduledoc` (why it exists), `@typedoc` + `@type` per field, and `@type t`:

```elixir
defmodule DietProject.Nutrition.Meal do
  @moduledoc """
  Represents a single meal logging event submitted by a user.

  Created whenever a user logs food via WhatsApp. Groups one or more
  FoodItems and tracks the input method and confirmation status.
  """

  use Ecto.Schema

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this meal to its owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc """
  How the meal was submitted.
  - `:text`  — free-text WhatsApp message
  - `:photo` — image analysed by Claude vision
  - `:audio` — voice message transcribed by Whisper then analysed by Claude
  """
  @type input_type :: :text | :photo | :audio

  @typedoc "Whether the user confirmed the AI-parsed food items"
  @type confirmed :: boolean()

  @type t :: %__MODULE__{
    id:         id(),
    user_id:    user_id(),
    input_type: input_type(),
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

## Phoenix Router

- Router `scope` blocks carry an optional alias that prefixes all routes inside — **never** add a manual `alias` for route modules inside a scope
- `Phoenix.View` is no longer included with Phoenix — do not use it

### Authentication (`phx.gen.auth`)

| Plug / live_session | Purpose |
|---|---|
| `:fetch_current_scope_for_user` | Default browser pipeline. Assigns `@current_scope` to every request. |
| `:require_authenticated_user` | Redirects to login if not authenticated. |
| `live_session :require_authenticated_user` | LiveViews that require login. |
| `live_session :current_user` | LiveViews that work with or without login. |
| `:redirect_if_user_is_authenticated` | Registration/login pages that redirect away when already logged in. |

`phx.gen.auth` assigns `current_scope`, **not** `current_user`. Always:
- Pass `current_scope` as the first argument to context functions
- Use `@current_scope.user` in templates — **never** `@current_user`
- Filter queries with `current_scope.user`

**Never** duplicate `live_session` names — each name can only appear once in the router.

#### Routes requiring authentication

```elixir
scope "/", DietProjectWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{DietProjectWeb.UserAuth, :require_authenticated}] do
    live "/users/settings", UserLive.Settings, :edit
    live "/dashboard", DashboardLive, :index
  end
end
```

#### Routes that work with or without authentication

```elixir
scope "/", DietProjectWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{DietProjectWeb.UserAuth, :mount_current_scope}] do
    live "/", PublicLive
  end
end
```

---

## Phoenix HTML & HEEx

- Templates always use `~H` or `.html.heex` files. **Never** use `~E`
- **Never** call `<.flash_group>` outside of `layouts.ex`
- **Always** use `<.icon name="hero-x-mark">` for icons — **never** use `Heroicons` modules directly
- **Always** use the `<.input>` component from `core_components.ex` for form inputs
- Use `<.link navigate={href}>` and `<.link patch={href}>` — **never** `live_redirect` or `live_patch`
- **Never** write inline `<script>` tags in HEEx — write JS in `assets/js/` and import via `app.js`
- Use `phx-hook="MyHook"` + `phx-update="ignore"` together whenever a JS hook manages its own DOM

### Single Responsibility

If a LiveView page has many responsibilities, break it into smaller focused components:

```heex
<.live_component module={DietProjectWeb.Dashboard.MacroSummaryComponent} id="macro-summary" summary={@summary} />
<.live_component module={DietProjectWeb.Dashboard.MealListComponent} id="meal-list" meals={@meals} />
<.live_component module={DietProjectWeb.Dashboard.WeeklyChartComponent} id="weekly-chart" data={@chart_data} />
```

### Interpolation Rules

| Situation | Correct syntax |
|---|---|
| Value inside tag body | `{@assign}` |
| Value inside tag attribute | `{@assign}` |
| Block construct in tag body (`if`, `for`, `case`) | `<%= ... %>` |
| Tag attribute | **never** `<%= %>` |

```heex
<%!-- CORRECT --%>
<div id={@id}>
  {@title}
  <%= if @show do %>
    {@body}
  <% end %>
</div>

<%!-- WRONG — will crash --%>
<div id="<%= @id %>">
  {if @show do}
  {end}
</div>
```

### For Loops — Always Use `:for` on the HTML Tag

```heex
<%!-- CORRECT --%>
<ul>
  <li :for={item <- @items} id={item.id}>{item.name}</li>
</ul>

<%!-- WRONG --%>
<ul>
  <%= for item <- @items do %>
    <li>{item.name}</li>
  <% end %>
</ul>
```

### Conditional Classes

```heex
<a class={[
  "px-2 text-white",
  @active && "font-bold",
  if(@error, do: "border-red-500", else: "border-base-300"),
]}>
```

### Literal Curly Braces

```heex
<code phx-no-curly-interpolation>
  let obj = {key: "val"}
</code>
```

### HEEx Comments

Always use `<%!-- comment --%>`, not `<!-- -->`.

---

## Forms

```elixir
# In the LiveView
assign(socket, form: to_form(changeset))
```

```heex
<.form for={@form} id="my-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:name]} type="text" />
</.form>
```

- **Never** pass the changeset directly to `<.form>` — always go through `to_form/2`
- **Never** use `<.form let={f}>` — always `<.form for={@form}>`
- **Never** access `@changeset` in the template
- Always give forms a unique DOM `id`

```elixir
# Form from raw params
def handle_event("submitted", %{"meal" => params}, socket) do
  {:noreply, assign(socket, form: to_form(params, as: :meal))}
end
```

---

## Phoenix Hooks

Each hook lives in its own folder. Register all hooks in `hooks.js`.

### File Layout

```
assets/js/
├── app.js
├── hooks.js                   # registry
└── hooks/
    └── CalorieChart/
        └── index.js
```

### `hooks.js` — Registry

```js
import CalorieChart from "./hooks/CalorieChart";
import WeightChart from "./hooks/WeightChart";

let Hooks = { CalorieChart, WeightChart };

export default Hooks;
```

### Individual Hook

```js
// assets/js/hooks/CalorieChart/index.js
const CalorieChart = {
  mounted() {
    const data = JSON.parse(this.el.dataset.chartData);
    this.chart = new Chart(this.el, { type: "bar", data });
  },
  updated() {
    const data = JSON.parse(this.el.dataset.chartData);
    this.chart.data = data;
    this.chart.update();
  }
};

export default CalorieChart;
```

### Hook Tests

Assert state **before** the hook fires, trigger with `render_hook/3`, assert **after**:

```elixir
test "load more meals", %{conn: conn, scope: scope} do
  meals = for _ <- 0..12, do: meal_fixture(scope)
  {:ok, view, _html} = live(conn, ~p"/dashboard")

  [page_1, page_2] = Enum.chunk_every(meals, 8)

  Enum.each(page_1, &assert(has_element?(view, "[data-role=meal][data-id=#{&1.id}]")))
  Enum.each(page_2, &refute(has_element?(view, "[data-role=meal][data-id=#{&1.id}]")))

  view |> element("#load-more-meals") |> render_hook("load_more_meals", %{})

  Enum.each(page_2, &assert(has_element?(view, "[data-role=meal][data-id=#{&1.id}]")))
end
```

---

## JS & CSS

- Use **Tailwind CSS** for all styling. No `@apply` in raw CSS.
- Tailwind v4 `app.css` import — **always maintain it**:

  ```css
  @import "tailwindcss" source(none);
  @source "../css";
  @source "../js";
  @source "../../lib/diet_project_web";
  ```

- Only `app.js` and `app.css` bundles are supported — import vendor deps into those files
- **Never** use daisyUI — write your own Tailwind components
- **Never** write inline `<script>` tags in templates

---

## UI/UX

- Produce world-class UI: focus on usability, aesthetics, and modern design principles
- Implement subtle micro-interactions: hover effects, smooth transitions, loading states
- Clean typography, spacing, and layout balance for a refined, premium look

---

## LiveView Test Conventions

### Module Boilerplate

```elixir
defmodule DietProjectWeb.MyLiveTest do
  use DietProjectWeb.ConnCase

  import Phoenix.LiveViewTest
  import DietProject.MyFixtures
end
```

**Never** `use ExUnit.Case` directly — always `use DietProjectWeb.ConnCase`.

### Setup Helpers

| Scenario | Setup | Context keys |
|---|---|---|
| Authenticated user | `setup :register_and_log_in_user` | `conn`, `user`, `scope` |
| Unauthenticated | _(none)_ | `conn` |

```elixir
defp create_meal(%{scope: scope}), do: %{meal: meal_fixture(scope)}

describe "Index" do
  setup [:create_meal]
end
```

### Fixture Functions

| Fixture | Returns |
|---|---|
| `user_fixture()` | `%User{}` |
| `profile_fixture(scope)` | `%Profile{}` |
| `meal_fixture(scope)` | `%Meal{}` |
| `meal_fixture(scope, attrs)` | `%Meal{}` with overrides |
| `macro_log_fixture(scope)` | `%MacroLog{}` |

**Never** build records with `Repo.insert!` directly in tests.

### Mounting

```elixir
{:ok, view, _html} = live(conn, ~p"/dashboard")
{:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
```

Always discard the initial HTML with `_html`.

### Assertions

**Always** use `has_element?`. **Never** use `html =~` or `render(view) =~`.

```elixir
assert has_element?(view, "#macro-summary")
assert has_element?(view, "button", "Save")
refute has_element?(view, "#meal-#{meal.id}")
```

### Interactions

Always pass visible text as the third argument to `element/3`. Never assert on `render_click()` return value.

```elixir
# CORRECT
view |> element("button", "Delete") |> render_click()
refute has_element?(view, "#meal-#{meal.id}")

# WRONG
assert view |> element("button", "Delete") |> render_click() =~ "Deleted"
view |> element("button") |> render_click()
```

### Forms

```elixir
view |> form("#meal-form", meal: %{notes: "x"}) |> render_change()
view |> form("#meal-form", meal: @valid_attrs) |> render_submit()
```

### Redirect Chains

```elixir
assert {:ok, dest_live, _html} =
         view |> form("#meal-form", meal: @valid_attrs) |> render_submit()
         |> follow_redirect(conn, ~p"/dashboard")

view |> element("a", "This Week") |> render_click()
assert_patch(view, ~p"/dashboard?period=week")
```

### PubSub Testing

```elixir
Phoenix.PubSub.broadcast(DietProject.PubSub, "user:#{scope.user.id}:meal_logged", {:meal_logged, meal})
assert has_element?(view, "#macro-summary", "1,200 kcal")
```

### `describe` Block Structure

```elixir
describe "Index" do ... end
describe "New form" do ... end
describe "Edit form" do ... end
describe "Form error paths" do ... end
describe "Access control" do ... end
describe "Subscription gate" do ... end
```

### Element ID Conventions

Target stable `id` attributes, never CSS classes:

```elixir
assert has_element?(view, "#macro-summary")       # CORRECT
assert has_element?(view, ".bg-green-500")        # WRONG
```

### What NOT to Test in LiveView Tests

- Internal assigns (`socket.assigns`)
- Context function correctness — unit-test in `test/diet_project/`
- CSS classes or visual styling
- Raw HTML strings
- `element/2` without visible text
- Return value of `render_click()`

---

## Environment Variables

```bash
DATABASE_URL          # PostgreSQL connection URL
SECRET_KEY_BASE       # Phoenix secret key
CLAUDE_API_KEY        # Anthropic Claude API
OPENAI_API_KEY        # Whisper API
CLOUDFLARE_R2_*       # R2 credentials
WHATSAPP_TOKEN        # WhatsApp Business API token
STRIPE_SECRET_KEY     # or ASAAS_API_KEY
STRAVA_CLIENT_ID
STRAVA_CLIENT_SECRET
LIBRE_VIEW_CLIENT_ID
LIBRE_VIEW_CLIENT_SECRET
CLOAK_KEY             # encryption key for OAuth tokens at rest
```

---

## File Structure

```
plan/                           # implementation plans (written before any code)
lib/
├── diet_project/
│   ├── accounts/
│   ├── nutrition/
│   ├── tracking/
│   ├── notifications/
│   ├── integrations/
│   ├── bot/
│   ├── ai/
│   │   └── prompts/            # versioned Claude prompt modules
│   ├── billing/
│   ├── workers/
│   ├── application.ex
│   ├── mailer.ex
│   └── repo.ex
├── diet_project_web/
│   ├── controllers/
│   ├── live/
│   ├── components/
│   ├── endpoint.ex
│   └── router.ex
assets/
├── js/
│   ├── app.js
│   ├── hooks.js                # hook registry
│   └── hooks/
│       └── <HookName>/
│           └── index.js
└── css/
    └── app.css
priv/
├── repo/migrations/
└── repo/seeds.exs
test/
├── diet_project/               # context + unit tests
├── diet_project_web/           # LiveView + controller tests
└── support/                    # factories, mocks (Mox)
docs/
├── concept_docs/               # weekly concept docs
├── tdd/                        # technical design documents
├── specs/                      # YYYY-MM-DD-<feature>-design.md
├── plans/                      # YYYY-MM-DD-<feature>-plan.md
├── decisions/                  # architectural decision records
├── research/                   # YYYY-MM-DD-<topic>.md
└── plano_nutribot.docx
```

---

## Deploy (Gigalixir)

```bash
git push gigalixir master
gigalixir run mix ecto.migrate
```

---

## AI-Generated Documentation

Every plan, spec, design, or document generated by AI **must be saved inside `docs/`**:

- Prefix filenames with `YYYY-MM-DD`
- Filenames in kebab-case
- Never save outside `docs/`
- Commit docs alongside (or before) the related code

---

## Reference Documentation

- Module documentation standards: [`lib/diet_project/CLAUDE.md`](lib/diet_project/CLAUDE.md)
- Full product plan: `docs/plano_nutribot.docx`
- [Phoenix Docs](https://hexdocs.pm/phoenix)
- [Oban Docs](https://hexdocs.pm/oban)
- [Claude API](https://docs.anthropic.com)
