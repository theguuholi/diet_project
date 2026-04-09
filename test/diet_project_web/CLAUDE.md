# LiveView Test Conventions

## Module Boilerplate

Every LiveView test file follows this structure:

```elixir
defmodule AppWeb.MyLiveTest do
  use AppWeb.ConnCase

  import Phoenix.LiveViewTest
  import Loyalty.MyFixtures          # import only the fixtures this file needs
  import Loyalty.OtherFixtures       # multi-import with braces: import Loyalty.{A, B}
end
```

**Never** `use ExUnit.Case` directly — always `use AppWeb.ConnCase`.

---

## Setup Helpers

Choose the right setup helper based on what the LiveView requires:

| Scenario | Setup | Context keys provided |
|---|---|---|
| Authenticated user, no establishment | `setup :register_and_log_in_user` | `conn`, `user`, `scope` |
| Authenticated user with establishment | `setup :register_and_log_in_user_with_establishment` | `conn`, `scope` (with `scope.establishment`) |
| Unauthenticated (public pages) | _(none — `conn` is provided by ConnCase)_ | `conn` |
| Admin-only pages | Custom `defp log_in_admin/1` in the test file | `conn` |

```elixir
# Authenticated with no establishment
setup :register_and_log_in_user

# Authenticated with establishment (scope.establishment is populated)
setup :register_and_log_in_user_with_establishment

# Admin: create an admin user by email and log them in
@admin_email Application.compile_env(:loyalty, :admin_email)

defp log_in_admin(conn) do
  user = user_fixture(%{email: @admin_email})
  log_in_user(conn, user)
end

# Per-describe setup: return a map that gets merged into context
defp create_loyalty_card(%{scope: scope}) do
  %{loyalty_card: loyalty_card_fixture(scope)}
end

describe "Index" do
  setup [:create_loyalty_card]
  ...
end
```

---

## Fixture Functions

Always call fixture functions with a `scope` when the resource is scoped to a user or establishment.

| Fixture | Returns | Notes |
|---|---|---|
| `user_fixture()` | `%User{}` | confirmed user |
| `user_scope_fixture()` | `%Scope{}` | creates user + scope |
| `establishment_scope_fixture()` | `%Scope{}` | creates user + establishment + scope |
| `establishment_scope_fixture(scope)` | `%Scope{}` | adds establishment to existing scope |
| `establishment_fixture(scope)` | `%Establishment{}` | requires a scope |
| `loyalty_program_fixture(scope)` | `%LoyaltyProgram{}` | requires scope with establishment |
| `loyalty_card_fixture(scope)` | `%LoyaltyCard{}` | requires scope with establishment |
| `loyalty_card_fixture(scope, attrs)` | `%LoyaltyCard{}` | with overrides e.g. `%{stamps_current: 5}` |

**Never** build records with `Repo.insert!` directly in tests — always use fixture functions.

---

## Mounting a LiveView

```elixir
# Success
{:ok, view, html} = live(conn, ~p"/path")

# Expect a redirect (unauthenticated or access denied)
{:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/protected")

# Expect a redirect with flash
{:error, {:redirect, %{to: "/", flash: %{"error" => _}}}} = live(conn, ~p"/admin")

# Abbreviated when redirect target doesn't matter
assert {:error, _} = live(conn, ~p"/path")
```

Always discard the initial `html` with `_html` — never use it for assertions. Use `view` and `has_element?` for all checks, including initial state.

---

## Assertions

**Always** use `has_element?/2` and `has_element?/3` to assert on the view. **Never** use `html =~` or `render(view) =~` — they couple tests to raw HTML strings, break on markup changes, and give poor failure messages.

```elixir
# By id
assert has_element?(view, "#my-element-id")
refute has_element?(view, "#deleted-item-#{item.id}")

# By selector and visible text
assert has_element?(view, "button", "Save")
assert has_element?(view, "p", "No cards yet.")
assert has_element?(view, "#flash-info", "Saved successfully.")

# Combine selector and id for precision
assert has_element?(view, "#establishment-form .error", "can't be blank")
```

```elixir
# WRONG — couples test to raw markup, stale after interactions, poor error messages
assert html =~ "Page Title"
assert render(view) =~ "Saved."
```

Always discard the initial render with `_html`:

```elixir
{:ok, view, _html} = live(conn, ~p"/path")
```

---

## Interactions

### Clicking elements

**Always** pass the visible text as the third argument to `element/3`. This makes the test self-documenting and prevents accidentally clicking the wrong element when multiple elements share a selector.

```elixir
# CORRECT — selector + text
view |> element("#my-button", "Save") |> render_click()
view |> element("a", "Edit") |> render_click()
view |> element("button", "Delete") |> render_click()
view |> element("#lookup-type-whatsapp", "WhatsApp") |> render_click()
```

```elixir
# WRONG — selector only, no text
view |> element("#my-button") |> render_click()
view |> element("a") |> render_click()
```

After clicking, **never** assert on the return value of `render_click()`. Instead, assert on the view using `has_element?`:

```elixir
# CORRECT — assert state using has_element? after the click
view |> element("button", "Delete") |> render_click()
refute has_element?(view, "#item-#{item.id}")

view |> element("#lookup-type-whatsapp", "WhatsApp") |> render_click()
assert has_element?(view, "#cards-entry-whatsapp")
```

```elixir
# WRONG — asserting on the render_click() return value
assert view |> element("button", "Delete") |> render_click()
assert view |> element("#my-button", "Save") |> render_click() =~ "Saved"
```

### Forms

```elixir
# Trigger phx-change (validate)
view
|> form("#my-form", resource: %{field: "value"})
|> render_change()

# Trigger phx-submit
view
|> form("#my-form", resource: @valid_attrs)
|> render_submit()
```

Form params mirror the form field namespace. Use atoms for the outer key and string or atom keys for nested params:

```elixir
# Nested under a resource name
|> form("#establishment-form", establishment: %{name: "Acme"})

# Flat (no namespace)
|> form("#cards-entry-form", %{"cards_entry" => %{"email" => "a@b.com"}})
```

---

## Redirect Chains

### Form submits that redirect to another LiveView

Use `follow_redirect/2` to mount the destination LiveView:

```elixir
assert {:ok, destination_live, _html} =
         view
         |> form("#my-form", resource: @valid_attrs)
         |> render_submit()
         |> follow_redirect(conn, ~p"/destination")
```

### Click that redirects to another LiveView

```elixir
assert {:ok, form_live, _} =
         index_live
         |> element("a", "New Establishment")
         |> render_click()
         |> follow_redirect(conn, ~p"/establishments/new")
```

### `push_patch` navigation

Use `assert_patch/2` to assert a patch without following it:

```elixir
view |> element("a", "Active") |> render_click()
assert_patch(view, ~p"/admin?filter=active")
```

### PubSub-triggered redirect

Use `assert_redirect/2` after broadcasting:

```elixir
Phoenix.PubSub.broadcast(Loyalty.PubSub, "topic", {:deleted, resource})
assert_redirect(view, ~p"/establishments")
```

---

## PubSub Testing

Broadcast directly with `Phoenix.PubSub.broadcast/3`, then call `render/1` to observe the result:

```elixir
test "PubSub update refreshes the view", %{conn: conn, scope: scope} do
  establishment = establishment_fixture(scope)
  {:ok, view, _html} = live(conn, ~p"/establishments/#{establishment}")

  {:ok, updated} =
    establishment
    |> Ecto.Changeset.change(%{subscription_status: "active"})
    |> Loyalty.Repo.update()

  Phoenix.PubSub.broadcast(
    Loyalty.PubSub,
    "user:#{scope.user.id}:establishments",
    {:updated, updated}
  )

  assert has_element?(view, "#subscription-status-badge", "Active")
end
```

Always use the correct topic format — check the context module's `subscribe/1` for the exact topic string.

---

## Testing Race Conditions and State Changes

To simulate state that changes **between mount and a user action**, mutate the database directly before the action:

```elixir
test "shows error when billing deactivated after mount", %{conn: conn, scope: scope} do
  {:ok, form_live, _html} = live(conn, ~p"/establishments/#{scope.establishment.id}/loyalty_cards/new")

  # Change state after mount but before submit
  scope.establishment
  |> Ecto.Changeset.change(%{subscription_status: "past_due"})
  |> Loyalty.Repo.update()

  form_live
  |> form("#loyalty_card-form", loyalty_card: %{email: "test@example.com", ...})
  |> render_submit()

  assert has_element?(form_live, "#loyalty_card-form .error", "Billing is not active")
end
```

---

## Application Environment Overrides

Use `on_exit` to restore env vars after the test:

```elixir
test "shows error when Stripe key is blank", %{conn: conn, scope: scope} do
  prev = Application.get_env(:loyalty, :stripe)
  on_exit(fn -> Application.put_env(:loyalty, :stripe, prev) end)

  Application.put_env(:loyalty, :stripe, Keyword.merge(prev, secret_key: ""))

  {:ok, view, _html} = live(conn, ~p"/establishments/#{scope.establishment}")
  view |> element("#stripe-checkout-button") |> render_click()

  assert has_element?(view, "#flash-error", "Stripe")
end
```

Always capture and restore the **full** previous value, not just the key you're overriding.

---

## `describe` Block Structure

Group tests by logical section of the page, not by implementation detail:

```elixir
describe "Index" do ... end          # list view
describe "Show" do ... end           # detail view
describe "New form" do ... end       # create flow
describe "Edit form" do ... end      # update flow
describe "Form error paths" do end   # validation / access errors
describe "Billing" do ... end        # billing-gated behaviour
describe "Access control" do ... end # auth / role guards
```

Use a `describe`-level `setup` for data that only some groups need:

```elixir
defp create_card(%{scope: scope}), do: %{card: loyalty_card_fixture(scope)}

describe "Index" do
  setup [:create_card]
  ...
end
```

---

## Scope in Tests

Tests receive `scope` from the setup helper. `scope` is a `%Loyalty.Accounts.Scope{}`:

```elixir
# Access the user
scope.user

# Access the establishment (only when using register_and_log_in_user_with_establishment)
scope.establishment
scope.establishment.id

# Build a scope manually (for multi-user tests)
other_scope = Loyalty.AccountsFixtures.user_scope_fixture()
```

**Never** reference `current_user` — always use `scope.user`.

---

## Element ID Conventions

Test assertions must target stable, predictable `id` attributes. Always use IDs that are defined in the template, not CSS classes:

```elixir
# CORRECT — targets a stable id set in the template
assert has_element?(view, "#dashboard-payment-issue-banner")
assert has_element?(view, "#loyalty-cards-empty-message")
refute has_element?(view, "#establishments-#{establishment.id}")

# WRONG — fragile, couples test to visual structure
assert has_element?(view, ".bg-red-500")
```

For stream items the id follows the pattern `#resource_name-{dom_id}`:

```elixir
refute has_element?(index_live, "#establishments-#{establishment.id}")
```

---

## What NOT to Test in LiveView Tests

- Internal assigns — test observable output (element presence, text), not `socket.assigns`
- Context function correctness — unit-test those in `test/loyalty/` instead
- CSS classes or visual styling — test presence and text, not class names
- Raw HTML strings — never use `html =~` or `render(view) =~`; always use `has_element?`
- `element/2` with selector only — always pass the visible text as third arg: `element("#id", "Label")`
- Return value of `render_click()` — never assert on it; assert state with `has_element?` after the click


### HEEx comments

Always use `<%!-- comment --%>` for template comments, not `<!-- -->`.

---

---
## Hooks
Hooks using Phoenix and Liveview MUST follow the folder structure add in the hooks.js, create a folder and add the index and everything related to hooks must be inside the folder

assets/js/hooks.js
```js
import ClipboardCopy from "./hooks/ClipboardCopy";

let Hooks = {
    ClipboardCopy: ClipboardCopy
};

export default Hooks;
```

assets/js/hooks/ClipboardCopy/index.js

```js index.js
const ClipboardCopy = {
  mounted() {
    this.el.addEventListener("click", () => {
      const url = this.el.dataset.url;
      navigator.clipboard.writeText(url).then(() => {
        const orig = this.el.textContent;
        this.el.textContent = "Copiado!";
        setTimeout(() => { this.el.textContent = orig; }, 1500);
      });
    });
  }
}

export default ClipboardCopy;
```

The test must be created using the hook in the *test.exs related to the liveview page 
like and it must have event before and after the hook result 

```elixir
  test "load more products", %{conn: conn} do
    products = for _ <- 0..12, do: product_fixture()

    {:ok, view, _html} = live(conn, ~p"/")

    [products_page_1, products_page_2] = products |> Enum.chunk_every(8)

    Enum.each(products_page_1, fn product ->
      assert has_element?(view, "[data-role=item][data-id=#{product.id}]")
    end)

    Enum.each(products_page_2, fn product ->
      refute has_element?(view, "[data-role=item][data-id=#{product.id}]")
    end)

    view
    |> element("#load_more_products")
    |> render_hook("load_more_products", %{})

    view
    |> element("#load_more_products")
    |> render_hook("load_more_products", %{})

    Enum.each(products_page_2, fn product ->
      assert has_element?(view, "[data-role=item][data-id=#{product.id}]")
    end)
  end

```