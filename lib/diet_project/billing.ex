defmodule DietProject.Billing do
  @moduledoc """
  Manages subscription plans, user subscriptions, and Stripe webhook processing.

  This context is the single source of truth for whether a user has paid
  access to NutriBot features. It owns the `Plan` and `Subscription` schemas
  and exposes a public API consumed by Oban workers (feature gate) and the
  billing webhook controller.

  Contexts do not call each other directly — cross-context communication
  happens via PubSub or Oban jobs when needed.
  """

  import Ecto.Query, warn: false

  alias DietProject.Accounts.User
  alias DietProject.Billing.Plan
  alias DietProject.Billing.Subscription
  alias DietProject.Repo

  @doc """
  Returns `true` if the user has an active or trialing subscription.

  Used by Oban workers to enforce the free-tier feature gate (3 meals/day).

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "no-sub-uuid"}
      iex> DietProject.Billing.subscriber?(user)
      false

  """
  @spec subscriber?(user :: User.t()) :: boolean()
  def subscriber?(user) do
    active = Subscription.active_statuses()

    from(s in Subscription, where: s.user_id == ^user.id and s.status in ^active)
    |> Repo.exists?()
  end

  @doc """
  Creates a subscription linking `user` to `plan` with the given attributes.

  Returns `{:ok, subscription}` on success or `{:error, changeset}` on failure.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "some-uuid"}
      iex> plan = %DietProject.Billing.Plan{id: "some-plan-uuid"}
      iex> match?({:error, %Ecto.Changeset{}}, DietProject.Billing.create_subscription(user, plan, %{}))
      true

  """
  @spec create_subscription(user :: User.t(), plan :: Plan.t(), attrs :: map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def create_subscription(user, plan, attrs) do
    %Subscription{user_id: user.id, plan_id: plan.id}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the status of an existing subscription.

  Returns `{:ok, subscription}` on success or `{:error, changeset}` on failure.

  ## Examples

      iex> match?({:error, %Ecto.Changeset{}}, DietProject.Billing.update_subscription_status(%DietProject.Billing.Subscription{}, :invalid))
      true

  """
  @spec update_subscription_status(subscription :: Subscription.t(), status :: atom()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def update_subscription_status(subscription, status) do
    subscription
    |> Subscription.changeset(%{status: status})
    |> Repo.update()
  end

  @doc """
  Creates a subscription plan with the given attributes.

  Returns `{:ok, plan}` on success or `{:error, changeset}` on failure.

  ## Examples

      iex> match?({:error, %Ecto.Changeset{}}, DietProject.Billing.create_plan(%{}))
      true

  """
  @spec create_plan(attrs :: map()) :: {:ok, Plan.t()} | {:error, Ecto.Changeset.t()}
  def create_plan(attrs) do
    %Plan{}
    |> Plan.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Processes a Stripe webhook event and updates subscription state accordingly.

  Handles `customer.subscription.updated` and `customer.subscription.deleted`
  events. Returns `:ok` for unrecognised event types (safe to acknowledge).

  ## Examples

      iex> DietProject.Billing.handle_stripe_webhook(%{"type" => "unknown", "data" => %{"object" => %{}}})
      :ok

  """
  @spec handle_stripe_webhook(event :: map()) ::
          {:ok, Subscription.t()} | {:error, term()} | :ok
  def handle_stripe_webhook(%{"type" => type, "data" => %{"object" => object}}) do
    case type do
      event_type
      when event_type in ["customer.subscription.updated", "customer.subscription.deleted"] ->
        handle_subscription_event(object)

      _ ->
        :ok
    end
  end

  def handle_stripe_webhook(_event), do: :ok

  # --- Private helpers ---

  defp handle_subscription_event(%{"id" => external_id, "status" => status_str}) do
    case Repo.get_by(Subscription, external_id: external_id) do
      nil ->
        {:error, :subscription_not_found}

      subscription ->
        known = [:active, :trialing, :canceled, :past_due, :incomplete, :unpaid]
        status = Enum.find(known, fn s -> Atom.to_string(s) == status_str end)

        if status do
          update_subscription_status(subscription, status)
        else
          {:error, :unknown_status}
        end
    end
  end
end
