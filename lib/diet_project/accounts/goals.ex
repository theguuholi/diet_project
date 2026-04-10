defmodule DietProject.Accounts.Goals do
  @moduledoc """
  Represents the daily macronutrient and calorie targets for a user.

  A `Goals` record is created after onboarding (or whenever the user
  updates their profile) and stores the integer gram targets for protein,
  carbohydrates, and fat as well as the total calorie budget. These values
  are used to compute progress bars and daily summaries on the dashboard
  and in WhatsApp reports.

  One goals record exists per user. It is regenerated automatically via
  `DietProject.Accounts.default_macro_targets/2` whenever the profile changes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking these goals to their owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc "Daily calorie target in kcal"
  @type calories :: integer()

  @typedoc "Daily protein target in grams"
  @type protein_g :: integer()

  @typedoc "Daily carbohydrate target in grams"
  @type carbs_g :: integer()

  @typedoc "Daily fat target in grams"
  @type fat_g :: integer()

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          calories: calories(),
          protein_g: protein_g(),
          carbs_g: carbs_g(),
          fat_g: fat_g()
        }

  schema "goals" do
    field :calories, :integer
    field :protein_g, :integer
    field :carbs_g, :integer
    field :fat_g, :integer

    belongs_to :user, DietProject.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating daily macro targets.

  Validates that all four nutrient fields are present and positive integers.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(goals, attrs) do
    goals
    |> cast(attrs, [:calories, :protein_g, :carbs_g, :fat_g])
    |> validate_required([:calories, :protein_g, :carbs_g, :fat_g])
    |> validate_number(:calories, greater_than: 0)
    |> validate_number(:protein_g, greater_than: 0)
    |> validate_number(:carbs_g, greater_than: 0)
    |> validate_number(:fat_g, greater_than: 0)
  end
end
