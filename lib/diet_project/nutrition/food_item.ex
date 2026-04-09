defmodule DietProject.Nutrition.FoodItem do
  @moduledoc """
  Represents a single food entry within a meal.

  A `FoodItem` stores the structured nutritional data for one food component
  of a meal — parsed either from the user's text description or extracted by
  the Claude vision API from a photo. Each meal owns one or more food items.

  The `meal_id` is set programmatically when inserting and must never be cast
  through user-supplied attributes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this food item to its parent meal"
  @type meal_id :: Ecto.UUID.t()

  @typedoc "Human-readable name of the food (e.g. 'Chicken breast', 'Brown rice')"
  @type name :: String.t()

  @typedoc "Amount of the food consumed, expressed in the accompanying unit"
  @type quantity :: float()

  @typedoc "Unit of measurement for the quantity (e.g. 'g', 'ml', 'unit')"
  @type unit :: String.t()

  @typedoc "Total kilocalories for this food item at the given quantity"
  @type calories :: float()

  @typedoc "Grams of protein for this food item at the given quantity"
  @type protein_g :: float()

  @typedoc "Grams of carbohydrates for this food item at the given quantity"
  @type carbs_g :: float()

  @typedoc "Grams of fat for this food item at the given quantity"
  @type fat_g :: float()

  @type t :: %__MODULE__{
          id: id(),
          meal_id: meal_id(),
          name: name(),
          quantity: quantity(),
          unit: unit(),
          calories: calories(),
          protein_g: protein_g(),
          carbs_g: carbs_g(),
          fat_g: fat_g()
        }

  schema "food_items" do
    field :name, :string
    field :quantity, :float
    field :unit, :string
    field :calories, :float
    field :protein_g, :float
    field :carbs_g, :float
    field :fat_g, :float

    belongs_to :meal, DietProject.Nutrition.Meal

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating a food item.

  Casts and validates all nutritional fields. Requires `:name`, `:quantity`,
  `:unit`, `:calories`, `:protein_g`, `:carbs_g`, and `:fat_g`. All numeric
  values must be non-negative. The `:meal_id` must be set on the struct before
  calling this changeset — it is never cast from user-supplied attributes.

  ## Examples

      iex> DietProject.Nutrition.FoodItem.changeset(%DietProject.Nutrition.FoodItem{}, %{})
      |> Map.get(:valid?)
      false

  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(food_item, attrs) do
    food_item
    |> cast(attrs, [:name, :quantity, :unit, :calories, :protein_g, :carbs_g, :fat_g])
    |> validate_required([:name, :quantity, :unit, :calories, :protein_g, :carbs_g, :fat_g])
    |> validate_number(:quantity, greater_than_or_equal_to: 0.0)
    |> validate_number(:calories, greater_than_or_equal_to: 0.0)
    |> validate_number(:protein_g, greater_than_or_equal_to: 0.0)
    |> validate_number(:carbs_g, greater_than_or_equal_to: 0.0)
    |> validate_number(:fat_g, greater_than_or_equal_to: 0.0)
  end
end
