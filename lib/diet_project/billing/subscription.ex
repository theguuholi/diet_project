defmodule DietProject.Billing.Subscription do
  @moduledoc """
  Represents a user's subscription to a NutriBot plan.

  A `Subscription` links a user to a `Plan` and tracks the current billing
  status. The `external_id` field stores the Stripe subscription ID so that
  webhook events can look up the correct record without exposing internal IDs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @active_statuses [:active, :trialing]

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key to the subscribing user"
  @type user_id :: Ecto.UUID.t()

  @typedoc "Foreign key to the subscribed plan"
  @type plan_id :: Ecto.UUID.t()

  @typedoc """
  Current billing status mirroring Stripe subscription statuses.
  Only `:active` and `:trialing` grant access to paid features.
  """
  @type status :: :active | :trialing | :canceled | :past_due | :incomplete | :unpaid

  @typedoc "UTC datetime when the current billing period ends"
  @type current_period_end :: DateTime.t() | nil

  @typedoc "Stripe subscription ID for webhook reconciliation"
  @type external_id :: String.t() | nil

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          plan_id: plan_id(),
          status: status(),
          current_period_end: current_period_end(),
          external_id: external_id()
        }

  def active_statuses, do: @active_statuses

  schema "subscriptions" do
    field :status, Ecto.Enum,
      values: [:active, :trialing, :canceled, :past_due, :incomplete, :unpaid]

    field :current_period_end, :utc_datetime
    field :external_id, :string

    belongs_to :user, DietProject.Accounts.User
    belongs_to :plan, DietProject.Billing.Plan

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a subscription.

  ## Examples

      iex> DietProject.Billing.Subscription.changeset(%DietProject.Billing.Subscription{}, %{}) |> Map.get(:valid?)
      false

  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:status, :current_period_end, :external_id])
    |> validate_required([:status])
  end
end
