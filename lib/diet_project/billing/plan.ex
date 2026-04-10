defmodule DietProject.Billing.Plan do
  @moduledoc """
  Represents a subscription tier available to NutriBot users.

  A `Plan` defines the price and billing interval for a subscription.
  Plans are referenced by `Subscription` records and are created at
  application boot via seeds — users cannot create plans directly.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Human-readable plan name, e.g. Pro or Free"
  @type name :: String.t()

  @typedoc "Plan price in the smallest currency unit (e.g. cents for BRL/USD)"
  @type price_cents :: non_neg_integer()

  @typedoc "Billing recurrence — `:monthly` or `:yearly`"
  @type interval :: :monthly | :yearly

  @type t :: %__MODULE__{
          id: id(),
          name: name(),
          price_cents: price_cents(),
          interval: interval()
        }

  schema "plans" do
    field :name, :string
    field :price_cents, :integer
    field :interval, Ecto.Enum, values: [:monthly, :yearly]

    has_many :subscriptions, DietProject.Billing.Subscription

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a plan.

  ## Examples

      iex> DietProject.Billing.Plan.changeset(%DietProject.Billing.Plan{}, %{}) |> Map.get(:valid?)
      false

  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :price_cents, :interval])
    |> validate_required([:name, :price_cents, :interval])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
  end
end
