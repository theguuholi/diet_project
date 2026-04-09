defmodule DietProject.NutritionFixtures do
  @moduledoc """
  Test helpers for creating entities via the `DietProject.Nutrition` context.
  """

  def valid_food_item_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Chicken breast",
      quantity: 200.0,
      unit: "g",
      calories: 330.0,
      protein_g: 62.0,
      carbs_g: 0.0,
      fat_g: 7.2
    })
  end

  def meal_fixture(user_id, attrs \\ %{}) do
    food_items = [valid_food_item_attrs()]

    {:ok, meal} =
      attrs
      |> Enum.into(%{input_type: :text, raw_input: "chicken breast 200g", food_items: food_items})
      |> then(&DietProject.Nutrition.create_meal(user_id, &1))

    meal
  end
end
