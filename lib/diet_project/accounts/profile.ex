defmodule DietProject.Accounts.Profile do
  @moduledoc """
  Represents the physical and activity profile of a user.

  A `Profile` is created during onboarding and stores the data needed to
  calculate the user's Basal Metabolic Rate (BMR) and Total Daily Energy
  Expenditure (TDEE). These values drive the daily caloric target and macro
  splits shown on the dashboard and sent via WhatsApp.

  One profile exists per user. Updates recalculate BMR and TDEE before saving.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this profile to its owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc "Total body weight in kilograms"
  @type weight_kg :: float()

  @typedoc "Standing height in centimetres"
  @type height_cm :: float()

  @typedoc "Body fat as a percentage of total body weight (0.0–100.0)"
  @type body_fat_pct :: float()

  @typedoc """
  Self-reported physical activity level used to scale the BMR into TDEE.

  - `:sedentary`    — little or no exercise
  - `:light`        — light exercise 1–3 days/week
  - `:moderate`     — moderate exercise 3–5 days/week
  - `:very_active`  — hard exercise 6–7 days/week
  - `:extra_active` — very hard exercise or physical job
  """
  @type activity_level :: :sedentary | :light | :moderate | :very_active | :extra_active

  @typedoc """
  The user's dietary goal.

  - `:lose`     — caloric deficit to lose weight
  - `:maintain` — maintenance calories
  - `:gain`     — caloric surplus to gain weight
  """
  @type goal :: :lose | :maintain | :gain

  @typedoc "Basal Metabolic Rate in kcal/day (Katch-McArdle formula)"
  @type bmr :: float()

  @typedoc "Total Daily Energy Expenditure in kcal/day (BMR × activity multiplier)"
  @type tdee :: float()

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          weight_kg: weight_kg(),
          height_cm: height_cm(),
          body_fat_pct: body_fat_pct(),
          activity_level: activity_level(),
          goal: goal(),
          bmr: bmr(),
          tdee: tdee()
        }

  schema "profiles" do
    field :weight_kg, :float
    field :height_cm, :float
    field :body_fat_pct, :float

    field :activity_level, Ecto.Enum,
      values: [:sedentary, :light, :moderate, :very_active, :extra_active]

    field :goal, Ecto.Enum, values: [:lose, :maintain, :gain]
    field :bmr, :float
    field :tdee, :float

    belongs_to :user, DietProject.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a profile.

  Validates all required fields, ensures numeric fields are positive, and
  constrains `body_fat_pct` to the range 0.0–100.0.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:weight_kg, :height_cm, :body_fat_pct, :activity_level, :goal, :bmr, :tdee])
    |> validate_required([
      :weight_kg,
      :height_cm,
      :body_fat_pct,
      :activity_level,
      :goal,
      :bmr,
      :tdee
    ])
    |> validate_number(:weight_kg, greater_than: 0)
    |> validate_number(:height_cm, greater_than: 0)
    |> validate_number(:body_fat_pct, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    |> validate_number(:bmr, greater_than: 0)
    |> validate_number(:tdee, greater_than: 0)
  end
end
