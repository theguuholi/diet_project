# NutriBot — CLAUDE.md

## Project Overview

**NutriBot** is an intelligent nutritional assistant that operates primarily via WhatsApp, allowing users to log meals (photo, audio, or text) and instantly receive calorie and macronutrient calculations. Inspired by Dieta.ai, built on Elixir/Phoenix for native concurrency and low infrastructure cost.

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
```

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

## Architectural Principles

1. **Domain-separated contexts** — each context has a clear public API
2. **All media processing is async via Oban** — never synchronous in the request (photos, audio, AI calls)
3. **WhatsApp as primary channel**, LiveView as secondary dashboard
4. **Feature flags from day one** for incremental rollout
5. **Tests from day one**: ExUnit + Mox for external dependencies (Claude API, Whisper, WhatsApp)
6. **WhatsApp webhook must respond in < 2s** — all heavy work goes to the Oban queue

## Media Processing Flow

```
1. BotController receives WhatsApp webhook → responds 200 in < 2s
2. Enqueues Oban Job with message payload
3. Oban Worker downloads media from WhatsApp → saves to R2
4. Oban Worker processes with AI (Claude API or Whisper)
5. Nutrition context persists Meal + MacroLog
6. Bot context sends formatted response via WhatsApp
```

## Development Phases

| Phase | Period | Main Deliverable |
|---|---|---|
| **Phase 1 — MVP** | Weeks 1–8 | WhatsApp + AI + macros + dashboard + subscription |
| **Phase 2 — Tracking** | Weeks 9–14 | Exercise, water, body, reminders, recipes |
| **Phase 3 — Advanced AI** | Weeks 15–20 | Conversational assistant, glycemic index, habit learning |
| **Phase 4 — Integrations** | Weeks 21–28 | Strava, Garmin, FreeStyle Libre |

### Phase 1 — MVP (current focus)

Features to implement:

- **1.1** WhatsApp onboarding (FSM via GenServer, data collection, BMR/TDEE calculation)
- **1.2** Text meal logging (Claude API + Oban Job `ProcessTextMeal`)
- **1.3** Photo meal logging (R2 upload + Claude vision + `ProcessImageMeal`)
- **1.4** Audio meal logging (Whisper transcription + `TranscribeAudio`)
- **1.5** Daily caloric balance (aggregated query + WhatsApp formatting)
- **1.6** LiveView Web Dashboard (magic link auth, real-time dashboard, weekly chart)
- **1.7** Subscription and payment (Stripe/Asaas, feature gate, free trial 3 logs/day)

## Code Conventions

- Follow the [Elixir style guide](https://github.com/christopheradams/elixir_style_guide) and standard `mix format`
- Context modules at `lib/diet_project/<context>.ex` with well-defined public functions
- Ecto schemas at `lib/diet_project/<context>/<schema>.ex`
- LiveViews at `lib/diet_project_web/live/`
- Oban Workers at `lib/diet_project/workers/`
- Use Mox to mock external dependencies in tests — never make real API calls in tests
- Use `Req` as the HTTP client for external integrations

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
- Debug test failures with `mix test test/my_test.exs` or `mix test --failed` for previously failed tests
- **Never** use `mix deps.clean --all` unless there is a concrete reason

### Test coverage — protected files

**Never** modify these two files under any circumstances:

- `mix.exs` — the `summary: [threshold: 97]` line inside `test_coverage:`. This is the minimum coverage gate; lowering it is not acceptable.
- `.test_coverage_ignore.exs` — lists modules excluded from coverage. Do not add modules here to paper over missing tests; write the tests instead.

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

## Phoenix Router

- Router `scope` blocks carry an optional alias that prefixes all routes inside — **never** add a manual `alias` for route modules inside a scope
- `Phoenix.View` is no longer included with Phoenix — do not use it

### Authentication (`phx.gen.auth`)

`phx.gen.auth` creates these plugs and `live_session` blocks — always place routes in the correct one:

| Plug / live_session | Purpose |
|---|---|
| `:fetch_current_scope_for_user` | Included in the default browser pipeline. Assigns `@current_scope` to every request. |
| `:require_authenticated_user` | Redirects to login if not authenticated. |
| `live_session :require_authenticated_user` | LiveViews that require login. |
| `live_session :current_user` | LiveViews that work with or without login. |
| `:redirect_if_user_is_authenticated` | For registration/login pages that should redirect away when already logged in. |

**Always say which scope/pipeline/live_session a new route goes in, and why.**

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
- **Never** call `<.flash_group>` outside of `layouts.ex` — Phoenix v1.8 moved it to the `Layouts` module
- **Always** use `<.icon name="hero-x-mark">` for icons — **never** use `Heroicons` modules directly
- **Always** use the `<.input>` component from `core_components.ex` for form inputs. If you override `class`, no defaults are inherited — your classes must fully style the input
- Use `<.link navigate={href}>` and `<.link patch={href}>` — **never** `live_redirect` or `live_patch`
- **Never** write inline `<script>` tags in HEEx — write JS in `assets/js/` and import via `app.js`
- Use `phx-hook="MyHook"` + `phx-update="ignore"` together whenever a JS hook manages its own DOM

### Single Responsibility in LiveView

If a LiveView page has many responsibilities, break it into smaller focused components. Each component should do one thing:

```heex
<%!-- Instead of one large LiveView template --%>
<.live_component module={DietProjectWeb.Dashboard.MacroSummaryComponent} id="macro-summary" summary={@summary} />
<.live_component module={DietProjectWeb.Dashboard.MealListComponent} id="meal-list" meals={@meals} />
<.live_component module={DietProjectWeb.Dashboard.WeeklyChartComponent} id="weekly-chart" data={@chart_data} />
```

### Interpolation rules

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

<%!-- WRONG — program will crash --%>
<div id="<%= @id %>">
  {if @show do}
  {end}
</div>
```

### For loops — always use `:for` on the HTML tag

**Never** use `<%= for ... do %>` block expressions or `Enum.each` to generate markup.

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

### Conditional classes

```heex
<a class={[
  "px-2 text-white",
  @active && "font-bold",
  if(@error, do: "border-red-500", else: "border-base-300"),
]}>
```

### Literal curly braces in templates

Annotate the parent tag with `phx-no-curly-interpolation` when outputting `{` or `}` as text:

```heex
<code phx-no-curly-interpolation>
  let obj = {key: "val"}
</code>
```

### HEEx comments

Always use `<%!-- comment --%>` for template comments, not `<!-- -->`.

---

## Forms

Always use `to_form/2` assigned in the LiveView and the `<.input>` component in the template:

```elixir
# In the LiveView
assign(socket, form: to_form(changeset))
```

```heex
<%!-- In the template --%>
<.form for={@form} id="my-form" phx-change="validate" phx-submit="save">
  <.input field={@form[:name]} type="text" />
</.form>
```

- **Never** pass the changeset directly to `<.form>` — always go through `to_form/2`
- **Never** use `<.form let={f}>` — always `<.form for={@form}>`
- **Never** access `@changeset` in the template
- Always give forms a unique DOM `id`

#### Form from raw params

```elixir
def handle_event("submitted", %{"meal" => params}, socket) do
  {:noreply, assign(socket, form: to_form(params, as: :meal))}
end
```

---

## Phoenix Hooks

Hooks **must** follow this folder structure. Register them in `hooks.js` and place each hook in its own folder under `assets/js/hooks/`.

### File layout

```
assets/js/
├── app.js
├── hooks.js                        # registry — import and export all hooks here
└── hooks/
    └── CalorieChart/
        └── index.js                # hook implementation
```

### `hooks.js` — registry

```js
import CalorieChart from "./hooks/CalorieChart";
import WeightChart from "./hooks/WeightChart";

let Hooks = {
  CalorieChart,
  WeightChart
};

export default Hooks;
```

### Individual hook — `hooks/CalorieChart/index.js`

```js
const CalorieChart = {
  mounted() {
    const data = JSON.parse(this.el.dataset.chartData);
    // initialise Chart.js with data
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

### Hook tests

Test hooks through the LiveView test — assert state **before** the hook fires, trigger it with `render_hook/3`, then assert the **after** state:

```elixir
test "load more meals", %{conn: conn, scope: scope} do
  meals = for _ <- 0..12, do: meal_fixture(scope)

  {:ok, view, _html} = live(conn, ~p"/dashboard")

  [page_1, page_2] = Enum.chunk_every(meals, 8)

  # Assert initial state (only page 1 visible)
  Enum.each(page_1, fn meal ->
    assert has_element?(view, "[data-role=meal][data-id=#{meal.id}]")
  end)

  Enum.each(page_2, fn meal ->
    refute has_element?(view, "[data-role=meal][data-id=#{meal.id}]")
  end)

  # Trigger hook
  view |> element("#load-more-meals") |> render_hook("load_more_meals", %{})

  # Assert after state (page 2 now visible)
  Enum.each(page_2, fn meal ->
    assert has_element?(view, "[data-role=meal][data-id=#{meal.id}]")
  end)
end
```

---

## JS & CSS

- Use **Tailwind CSS** for all styling. No `@apply` in raw CSS.
- Tailwind v4 uses this import syntax in `app.css` — **always maintain it**:

  ```css
  @import "tailwindcss" source(none);
  @source "../css";
  @source "../js";
  @source "../../lib/diet_project_web";
  ```

- Only `app.js` and `app.css` bundles are supported out of the box — import vendor deps into those files, never reference external `src` or `href` in layouts
- **Never** use daisyUI — write your own Tailwind components
- **Never** write inline `<script>` tags in templates

---

## UI/UX

- Produce world-class UI: focus on usability, aesthetics, and modern design principles
- Implement subtle micro-interactions: hover effects, smooth transitions, loading states
- Clean typography, spacing, and layout balance for a refined, premium look

---

## Module Documentation

### Context Modules

Every context module **must** have a `@moduledoc` explaining why it exists, and every public function **must** have a `@doc` and `@spec`:

```elixir
defmodule DietProject.Nutrition do
  @moduledoc """
  Manages meal logging, food item storage, and daily macro aggregation.

  This context is the single source of truth for what a user has eaten.
  It owns the Meal, FoodItem, and MacroLog schemas and exposes a public
  API consumed by Oban workers and the LiveView dashboard.
  """

  @doc """
  Returns the aggregated macro totals for a user on a given date.
  """
  @spec daily_summary(user_id :: Ecto.UUID.t(), date :: Date.t()) :: MacroSummary.t()
  def daily_summary(user_id, date) do
    ...
  end
end
```

### Schema Modules

Every schema **must** have:

1. A `@moduledoc` explaining why the schema exists
2. A `@type` per field documenting what it represents
3. A `@type t` for the full struct

```elixir
defmodule DietProject.Nutrition.Meal do
  @moduledoc """
  Represents a single meal logging event for a user.

  A Meal is created whenever a user logs food via WhatsApp (text, photo, or audio).
  It groups one or more FoodItems and tracks the input method used.
  """

  use Ecto.Schema

  @type id          :: Ecto.UUID.t()
  @type user_id     :: Ecto.UUID.t()
  @type input_type  :: :text | :photo | :audio
  @type logged_at   :: DateTime.t()
  @type confirmed   :: boolean()

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

## Environment Variables

Configured via `config/runtime.exs`. In development, use a `.env` file with `export` or set them directly:

```bash
DATABASE_URL          # PostgreSQL connection URL
SECRET_KEY_BASE       # Phoenix secret key
CLAUDE_API_KEY        # Anthropic Claude API
OPENAI_API_KEY        # Whisper API
CLOUDFLARE_R2_*       # R2 credentials
WHATSAPP_TOKEN        # WhatsApp Business API token
STRIPE_SECRET_KEY     # or ASAAS_API_KEY
```

## File Structure

```
plan/                           # implementation plans (one file per feature, written before code)
lib/
├── diet_project/               # business logic
│   ├── accounts/               # Accounts context
│   ├── nutrition/              # Nutrition context
│   ├── tracking/               # Tracking context
│   ├── notifications/          # Notifications context
│   ├── integrations/           # Integrations context
│   ├── bot/                    # Bot context (WhatsApp FSM)
│   ├── ai/
│   │   └── prompts/            # versioned Claude prompt modules
│   ├── billing/                # Billing context
│   ├── workers/                # Oban Workers
│   ├── application.ex
│   ├── mailer.ex
│   └── repo.ex
├── diet_project_web/           # web layer
│   ├── controllers/
│   ├── live/                   # LiveViews
│   ├── components/
│   ├── endpoint.ex
│   └── router.ex
assets/
├── js/
│   ├── app.js
│   ├── hooks.js                # hook registry
│   └── hooks/
│       └── <HookName>/
│           └── index.js        # one folder per hook
└── css/
    └── app.css
priv/
├── repo/migrations/            # Ecto migrations
└── repo/seeds.exs
test/
├── diet_project/               # context tests
├── diet_project_web/           # web/LiveView tests
└── support/                    # factories, mocks (Mox)
docs/
└── plano_nutribot.docx         # full product plan
```

## Deploy (Gigalixir)

```bash
git push gigalixir master          # deploy
gigalixir run mix ecto.migrate     # run migrations in production
```

## AI-Generated Documentation

Every plan, spec, design, or document generated by AI **must be saved inside `docs/`**, well organized following this structure:

```
docs/
├── specs/                  # feature specs (brainstorming → design)
│   └── YYYY-MM-DD-<feature>-design.md
├── plans/                  # AI-generated implementation plans
│   └── YYYY-MM-DD-<feature>-plan.md
├── decisions/              # architectural decision records (ADRs)
│   └── YYYY-MM-DD-<decision>.md
├── research/               # research, comparisons, technical analysis
│   └── YYYY-MM-DD-<topic>.md
└── plano_nutribot.docx     # original product plan
```

**Mandatory rules:**

- Always prefix filenames with `YYYY-MM-DD`
- Filenames in kebab-case, descriptive of the content
- Never save documents at the project root or outside `docs/`
- Commit docs alongside (or before) the related code
- Keep this CLAUDE.md index updated when adding relevant new docs

## LiveView Test Conventions

### Module Boilerplate

Every LiveView test file follows this structure:

```elixir
defmodule DietProjectWeb.MyLiveTest do
  use DietProjectWeb.ConnCase

  import Phoenix.LiveViewTest
  import DietProject.MyFixtures          # import only the fixtures this file needs
  import DietProject.{FixtureA, FixtureB} # multi-import with braces
end
```

**Never** `use ExUnit.Case` directly — always `use DietProjectWeb.ConnCase`.

---

### Setup Helpers

| Scenario | Setup | Context keys provided |
|---|---|---|
| Authenticated user | `setup :register_and_log_in_user` | `conn`, `user`, `scope` |
| Unauthenticated (public pages) | _(none — `conn` provided by ConnCase)_ | `conn` |

```elixir
# Per-describe setup — return a map merged into context
defp create_meal(%{scope: scope}) do
  %{meal: meal_fixture(scope)}
end

describe "Index" do
  setup [:create_meal]
  ...
end
```

---

### Fixture Functions

Always call fixture functions with a `scope` when the resource is scoped to a user.

| Fixture | Returns |
|---|---|
| `user_fixture()` | `%User{}` |
| `profile_fixture(scope)` | `%Profile{}` |
| `meal_fixture(scope)` | `%Meal{}` |
| `meal_fixture(scope, attrs)` | `%Meal{}` with overrides |
| `macro_log_fixture(scope)` | `%MacroLog{}` |

**Never** build records with `Repo.insert!` directly in tests — always use fixture functions.

---

### Mounting a LiveView

```elixir
# Success
{:ok, view, _html} = live(conn, ~p"/dashboard")

# Expect redirect (unauthenticated)
{:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/dashboard")
```

Always discard the initial HTML with `_html` — use `has_element?` for all assertions, including initial state.

---

### Assertions

**Always** use `has_element?/2` and `has_element?/3`. **Never** use `html =~` or `render(view) =~`.

```elixir
# CORRECT
assert has_element?(view, "#macro-summary")
assert has_element?(view, "button", "Save")
assert has_element?(view, "#flash-info", "Meal logged.")
refute has_element?(view, "#meal-#{meal.id}")

# WRONG — couples test to raw HTML
assert render(view) =~ "Meal logged."
assert html =~ "Dashboard"
```

---

### Interactions

**Always** pass visible text as the third argument to `element/3`:

```elixir
# CORRECT
view |> element("button", "Delete") |> render_click()
view |> element("a", "Edit") |> render_click()

# WRONG — no text, fragile
view |> element("button") |> render_click()
```

**Never** assert on the return value of `render_click()`. Assert state with `has_element?` after the action:

```elixir
# CORRECT
view |> element("button", "Delete") |> render_click()
refute has_element?(view, "#meal-#{meal.id}")

# WRONG
assert view |> element("button", "Delete") |> render_click() =~ "Deleted"
```

### Forms

```elixir
# phx-change (validate)
view |> form("#meal-form", meal: %{notes: "x"}) |> render_change()

# phx-submit
view |> form("#meal-form", meal: @valid_attrs) |> render_submit()
```

---

### Redirect Chains

```elixir
# Form submit that redirects to another LiveView
assert {:ok, dest_live, _html} =
         view
         |> form("#meal-form", meal: @valid_attrs)
         |> render_submit()
         |> follow_redirect(conn, ~p"/dashboard")

# Click that redirects
assert {:ok, form_live, _} =
         index_live
         |> element("a", "New Meal")
         |> render_click()
         |> follow_redirect(conn, ~p"/meals/new")

# push_patch navigation
view |> element("a", "This Week") |> render_click()
assert_patch(view, ~p"/dashboard?period=week")
```

---

### PubSub Testing

Broadcast directly, then assert with `has_element?`:

```elixir
test "PubSub meal update refreshes the dashboard", %{conn: conn, scope: scope} do
  {:ok, view, _html} = live(conn, ~p"/dashboard")

  Phoenix.PubSub.broadcast(
    DietProject.PubSub,
    "user:#{scope.user.id}:meal_logged",
    {:meal_logged, meal}
  )

  assert has_element?(view, "#macro-summary", "1,200 kcal")
end
```

Always check the context module's `subscribe/1` for the exact topic string.

---

### `describe` Block Structure

```elixir
describe "Index" do ... end           # list view
describe "Show" do ... end            # detail view
describe "New form" do ... end        # create flow
describe "Edit form" do ... end       # update flow
describe "Form error paths" do ... end # validation errors
describe "Access control" do ... end  # auth guards
describe "Subscription gate" do ... end # billing-gated behaviour
```

---

### Element ID Conventions

Target stable `id` attributes defined in the template, not CSS classes:

```elixir
# CORRECT
assert has_element?(view, "#macro-summary")
assert has_element?(view, "#daily-balance-calories")
refute has_element?(view, "#meal-#{meal.id}")

# WRONG — fragile, ties test to visual structure
assert has_element?(view, ".bg-green-500")
```

Stream items follow the pattern `#resource-{dom_id}`:

```elixir
refute has_element?(index_live, "#meal-#{meal.id}")
```

---

### What NOT to Test in LiveView Tests

- Internal assigns — test observable output, not `socket.assigns`
- Context function correctness — unit-test those in `test/diet_project/` instead
- CSS classes or visual styling
- Raw HTML strings (`html =~`, `render(view) =~`)
- `element/2` with selector only — always pass visible text as third argument
- Return value of `render_click()` — assert state with `has_element?` after the click

---

## Reference Documentation

- Full product plan: `docs/plano_nutribot.docx`
- [Phoenix Docs](https://hexdocs.pm/phoenix)
- [Oban Docs](https://hexdocs.pm/oban)
- [Claude API](https://docs.anthropic.com)
