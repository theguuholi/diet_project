# LiveView Conventions

## File Responsibility Split

Every LiveView **must** be split into two files:

- `my_live/index.ex` — logic only: `mount/3`, `handle_event/3`, `handle_info/2`, private helpers, and `render/1` that delegates to the template
- `my_live/index.html.heex` — markup only, no business logic

The page MUST HAVE ONLY 1 RESPONSIBILITY AND IF THE PAGE MAKES A LOT OF THING THEN CREATE COMPONENTS IN LIVEVIEW AND TEST IT 

The `.ex` file **must not** contain an inline `~H"""..."""` template. Instead, omit `render/1` entirely and let Phoenix auto-render the matching `.html.heex` file:

```elixir
# CORRECT — no render/1, Phoenix picks up index.html.heex automatically
defmodule AppWeb.MyLive.Index do
  use AppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "My Page")}
  end

  @impl true
  def handle_event("save", params, socket) do
    {:noreply, socket}
  end
end
```

```heex
<%!-- index.html.heex --%>
<Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale}>
  ...
</Layouts.app>
```

**Never** do this:

```elixir
# WRONG — inline template leaks markup into the logic file
def render(assigns) do
  ~H"""
  <Layouts.app ...>...</Layouts.app>
  """
end
```

---

## For Loops — Always on HTML Tags

Use the `:for` attribute directly on HTML elements. **Never** use `<%= for ... do %>` block expressions to generate markup.

```heex
<%!-- CORRECT — :for on the HTML tag --%>
<ul>
  <li :for={item <- @items} id={item.id}>
    {item.name}
  </li>
</ul>

<%!-- CORRECT — streams use :for on the stream container child --%>
<div id="items" phx-update="stream">
  <article :for={{dom_id, item} <- @streams.items} id={dom_id}>
    {item.name}
  </article>
</div>
```

```heex
<%!-- WRONG — block-style for loop --%>
<ul>
  <%= for item <- @items do %>
    <li>{item.name}</li>
  <% end %>
</ul>
```

---

## Mobile-First HTML

All layouts and components must be designed **mobile-first** using Tailwind's responsive prefix convention (`sm:`, `md:`, `lg:`). Start with the smallest viewport and progressively enhance.

Rules:
- Default (unprefixed) Tailwind classes target mobile (`< 640px`)
- Use `sm:` / `md:` / `lg:` to expand layout for larger screens
- Avoid fixed pixel widths; prefer `w-full`, `max-w-*`, and fluid grids
- Use `flex-col` as the default direction; switch to `flex-row` at `sm:` or above
- Touch targets must be at least `44px` tall — use `min-h-11` or `p-3` on interactive elements
- Use `gap-*` on flex/grid parents instead of margins on children

```heex
<%!-- Mobile-first card grid example --%>
<section class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
  <article :for={{dom_id, card} <- @streams.cards} id={dom_id}
    class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm">
    ...
  </article>
</section>
```

---

## HTML5 Semantic Markup

Use the correct semantic element for every piece of content. **Never** use `<div>` when a more specific HTML5 element applies.

| Purpose | Element |
|---------|---------|
| Page-level sections | `<main>`, `<section>`, `<article>`, `<aside>` |
| Navigation | `<nav>` |
| Page/section headings | `<h1>`–`<h6>` (one `<h1>` per page) |
| Header area of a section | `<header>` |
| Footer area of a section | `<footer>` |
| Lists of items | `<ul>` / `<ol>` + `<li>` |
| Data tables | `<table>`, `<thead>`, `<tbody>`, `<th scope="col/row">` |
| Standalone media | `<figure>` + `<figcaption>` |
| Inline highlights | `<strong>`, `<em>`, `<time datetime="...">` |
| Forms | `<form>`, `<fieldset>`, `<legend>`, `<label for="...">` |

One `<main>` per page, wrapping the primary content inside `<Layouts.app>`.

```heex
<%!-- CORRECT --%>
<Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale}>
  <main class="mx-auto max-w-5xl px-4 py-8">
    <header class="mb-6">
      <h1 class="text-2xl font-bold">{@page_title}</h1>
    </header>
    <section aria-label="Loyalty cards">
      <ul id="loyalty-cards" phx-update="stream" class="space-y-4">
        <li :for={{dom_id, card} <- @streams.loyalty_cards} id={dom_id}>
          ...
        </li>
      </ul>
    </section>
  </main>
</Layouts.app>
```

---

## SEO

Every LiveView **must** set `page_title` in `mount/3`. Phoenix uses this for the `<title>` tag:

```elixir
assign(socket, :page_title, gettext("Loyalty programs – My Business"))
```

Markup rules for SEO:
- One `<h1>` per page that matches or closely reflects the `page_title`
- Use `<h2>`–`<h4>` for sub-sections, never skip heading levels
- All images need descriptive `alt` attributes; decorative images use `alt=""`
- Use `<a>` (via `<.link>`) for navigation, `<button>` for actions — never swap them
- Add `aria-label` to icon-only buttons: `<button aria-label={gettext("Delete card")}>`
- Use `<time datetime={DateTime.to_iso8601(@updated_at)}>` for dates
- Prefer descriptive link text over generic "click here" or "read more"
- Add `<meta name="description">` via the layout when a meaningful description is available

```heex
<%!-- Good: descriptive link text, semantic time --%>
<p>
  {gettext("Last updated")}
  <time datetime={DateTime.to_iso8601(@card.updated_at)}>
    {Calendar.strftime(@card.updated_at, "%B %d, %Y")}
  </time>
</p>
<.link navigate={~p"/establishments/#{@establishment}"}>
  {gettext("View %{name} dashboard", name: @establishment.name)}
</.link>
```

---

## Boolean Assigns — Always Use the `?` Suffix

Assigns that represent a boolean state **must** end in `?`. This makes template conditionals self-documenting and immediately distinguishable from data assigns.

```elixir
# CORRECT
assign(socket, :cards_empty?, list == [])
assign(socket, :can_add_client?, can_add)
```

```heex
<%!-- CORRECT — intent is obvious at a glance --%>
<div :if={@cards_empty?}>No cards yet.</div>
<.button :if={@can_add_client?}>Register client</.button>
```

```elixir
# WRONG — ambiguous, looks like data
assign(socket, :cards_empty, list == [])
assign(socket, :can_add_client, can_add)
```

---

## PubSub Subscriptions — Always Guard with `connected?/1`

Subscribe to PubSub topics only after the WebSocket connection is established. **Always** wrap the subscription in `if connected?(socket)` inside `mount/3` to prevent double-firing during server-side rendering.

```elixir
# CORRECT
@impl true
def mount(_params, _session, socket) do
  if connected?(socket) do
    MyContext.subscribe(socket.assigns.current_scope)
  end

  {:ok, socket}
end
```

```elixir
# WRONG — subscribes during SSR, causing duplicate events
@impl true
def mount(_params, _session, socket) do
  MyContext.subscribe(socket.assigns.current_scope)
  {:ok, socket}
end
```

---

## Callback Order — `@impl` Callbacks First, `defp` Helpers Last

Always declare module contents in this order:

1. `use`, `alias`, `import` at the top
2. `@impl true` callbacks (`mount/3`, `handle_params/3`, `handle_event/3`, `handle_info/2`) in logical order
3. `defp` private helpers at the bottom

```elixir
defmodule AppWeb.MyLive.Index do
  use AppWeb, :live_view

  alias Loyalty.MyContext

  @impl true
  def mount(...), do: ...

  @impl true
  def handle_event(...), do: ...

  @impl true
  def handle_info(...), do: ...

  # private helpers always last
  defp list_items(scope), do: MyContext.list_items(scope)
  defp compute_something(val), do: ...
end
```

---

## No `Repo` Calls in LiveViews

LiveViews **must never** call `Repo` directly. All database access must go through the context module. This includes preloading associations — the context function is responsible for returning fully-loaded structs.

```elixir
# WRONG — Repo leaks into the LiveView
updated = Loyalty.Repo.preload(updated, [:customer, :loyalty_program])

# WRONG — direct Repo query in LiveView
items = Loyalty.Repo.all(MySchema)
```

```elixir
# CORRECT — context handles all data access and preloading
updated = MyContext.get_item_with_associations!(scope, id)
items = MyContext.list_items(scope)
```

If a context function does not preload the associations you need, **add the preload to that context function** rather than calling `Repo` from the LiveView.

---

## Stream Naming — Plural Snake Case Matching the Schema

Stream keys **must** be the plural snake_case of the schema module name. This prevents `@streams.loyalty_card` vs `@streams.loyalty_cards` bugs and keeps stream references consistent between the LiveView and the template.

```elixir
# CORRECT — matches schema name LoyaltyCard → :loyalty_cards
stream(socket, :loyalty_cards, list)
stream_delete(socket, :loyalty_cards, card)
```

```heex
<%!-- CORRECT — consistent in template --%>
<div id="loyalty-cards" phx-update="stream">
  <div :for={{dom_id, card} <- @streams.loyalty_cards} id={dom_id}>
    ...
  </div>
</div>
```

```elixir
# WRONG — singular, inconsistent
stream(socket, :loyalty_card, list)
```

---

## `handle_event` — Always Pattern Match `{:ok, _}` and `{:error, _}`

Every `handle_event/3` that calls a context function **must** pattern match on both success and error tuples. Silent failures are not acceptable.

```elixir
# CORRECT
@impl true
def handle_event("save", %{"item" => params}, socket) do
  case MyContext.create_item(socket.assigns.current_scope, params) do
    {:ok, _item} ->
      {:noreply, put_flash(socket, :info, gettext("Saved."))}

    {:error, changeset} ->
      {:noreply, assign(socket, form: to_form(changeset))}
  end
end
```

```elixir
# WRONG — ignores errors silently
@impl true
def handle_event("save", %{"item" => params}, socket) do
  {:ok, _} = MyContext.create_item(socket.assigns.current_scope, params)
  {:noreply, put_flash(socket, :info, gettext("Saved."))}
end
```

For destructive actions where only `{:ok, _}` is expected (e.g. delete), still use a `case` or assert with a comment explaining why the error branch is omitted.

---

## Field Errors — `<.input>` Handles Everything

Forms **must always** be backed by a changeset. Never validate form params manually with `if/case` guards or raw map checks — put all validation in the changeset and let `<.input>` surface the errors automatically.

When a form uses `<.input field={@form[:field]} ...>`, the component **already renders its own error message** from the changeset. There is nothing else to add.

The full pipeline is:
1. Context function returns `{:error, changeset}`
2. LiveView assigns `form: to_form(changeset)`
3. `<.input>` reads the error from the form field and displays it inline

```elixir
# CORRECT — put the changeset back into the form assign, nothing else needed
{:error, changeset} ->
  {:noreply, assign(socket, form: to_form(changeset))}
```

```heex
<%!-- CORRECT — <.input> renders label, input, and error automatically --%>
<.input field={@form[:name]} type="text" label="Name" />
```

**Never** add any extra error rendering around or below a `<.input>`:

```heex
<%!-- WRONG — manual error beside <.input> (error is already inside the component) --%>
<.input field={@form[:name]} type="text" label="Name" />
<p class="text-red-500">{hd(@form[:name].errors)}</p>

<%!-- WRONG — raw input with manual error (never bypass <.input>) --%>
<input name="name" />
<span>{@form[:name].errors}</span>
```

If you need a custom layout, extend or slot `<.input>` — **never** replace it with raw HTML and manual error markup.

---

## User-Facing Messages — Always via Flash

All user-facing feedback messages (success, error, info, warning) **must** use `put_flash/3`. **Never** render inline message banners, alert `<div>`s, or status text assigned to the socket for this purpose.

```elixir
# CORRECT — use put_flash for all user feedback
{:ok, _item} ->
  {:noreply, put_flash(socket, :info, gettext("Saved successfully."))}

{:error, _reason} ->
  {:noreply, put_flash(socket, :error, gettext("Something went wrong."))}
```

```heex
<%!-- WRONG — inline message div, not using flash --%>
<%= if @saved? do %>
  <div class="bg-green-100 text-green-800 p-4">Saved!</div>
<% end %>

<%!-- WRONG — status assign rendered as text --%>
<p :if={@error_message}>{@error_message}</p>
```

Flash is displayed automatically by the layout via `<Layouts.app flash={@flash} ...>` — do not add a second flash renderer anywhere in the template.
