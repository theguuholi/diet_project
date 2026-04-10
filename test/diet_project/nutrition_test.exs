defmodule DietProject.NutritionTest do
  use DietProject.DataCase, async: true

  import DietProject.AccountsFixtures
  import DietProject.NutritionFixtures

  alias DietProject.Nutrition
  alias DietProject.Nutrition.MacroLog
  alias DietProject.Nutrition.Meal

  describe "create_meal/2" do
    test "creates a meal with food items and returns preloaded association" do
      user = user_fixture()

      food_items = [
        valid_food_item_attrs(%{name: "Chicken breast", calories: 330.0}),
        valid_food_item_attrs(%{
          name: "Brown rice",
          calories: 200.0,
          protein_g: 4.0,
          carbs_g: 45.0,
          fat_g: 1.0
        })
      ]

      attrs = %{
        input_type: :text,
        raw_input: "chicken breast 200g and brown rice 150g",
        food_items: food_items
      }

      assert {:ok, %Meal{} = meal} = Nutrition.create_meal(user.id, attrs)
      assert meal.user_id == user.id
      assert meal.input_type == :text
      assert meal.raw_input == "chicken breast 200g and brown rice 150g"
      assert meal.confirmed == false
      assert length(meal.food_items) == 2

      names = Enum.map(meal.food_items, & &1.name)
      assert "Chicken breast" in names
      assert "Brown rice" in names
    end

    test "sets logged_at to current time when not provided" do
      user = user_fixture()
      attrs = %{input_type: :text, food_items: [valid_food_item_attrs()]}

      assert {:ok, meal} = Nutrition.create_meal(user.id, attrs)
      assert %DateTime{} = meal.logged_at
    end

    test "persists user_id from argument, not from attrs" do
      user = user_fixture()
      attrs = %{input_type: :text, food_items: [valid_food_item_attrs()]}

      assert {:ok, meal} = Nutrition.create_meal(user.id, attrs)
      assert meal.user_id == user.id
    end

    test "returns error changeset when input_type is missing" do
      user = user_fixture()
      attrs = %{food_items: [valid_food_item_attrs()]}

      assert {:error, changeset} = Nutrition.create_meal(user.id, attrs)
      assert %{input_type: [_ | _]} = errors_on(changeset)
    end

    test "returns error changeset when input_type is invalid" do
      user = user_fixture()
      attrs = %{input_type: :fax, food_items: [valid_food_item_attrs()]}

      assert {:error, changeset} = Nutrition.create_meal(user.id, attrs)
      assert %{input_type: [_ | _]} = errors_on(changeset)
    end

    test "returns error changeset when food item calories are negative" do
      user = user_fixture()
      attrs = %{input_type: :text, food_items: [valid_food_item_attrs(%{calories: -10.0})]}

      assert {:error, changeset} = Nutrition.create_meal(user.id, attrs)
      assert %{calories: [_ | _]} = errors_on(changeset)
    end
  end

  describe "update_macro_log/2" do
    test "creates a macro_log aggregating food items from the meal" do
      user = user_fixture()
      _meal = meal_fixture(user.id)

      date = Date.utc_today()
      assert {:ok, %MacroLog{} = log} = Nutrition.update_macro_log(user.id, date)

      assert log.user_id == user.id
      assert log.date == date
      assert log.calories == 330.0
      assert log.protein_g == 62.0
      assert log.carbs_g == 0.0
      assert log.fat_g == 7.2
    end

    test "updates the macro_log when called again after a new meal" do
      user = user_fixture()
      _meal1 = meal_fixture(user.id)

      date = Date.utc_today()
      {:ok, _log1} = Nutrition.update_macro_log(user.id, date)

      _meal2 = meal_fixture(user.id)
      {:ok, log2} = Nutrition.update_macro_log(user.id, date)

      assert log2.calories == 660.0
      assert log2.protein_g == 124.0
    end

    test "creates a macro_log with zeroes when user has no meals on that date" do
      user = user_fixture()
      date = ~D[2020-01-01]

      assert {:ok, %MacroLog{} = log} = Nutrition.update_macro_log(user.id, date)
      assert log.calories == 0.0
      assert log.protein_g == 0.0
      assert log.carbs_g == 0.0
      assert log.fat_g == 0.0
    end
  end

  describe "daily_summary/2" do
    test "returns zeroed map when no meals have been logged for that date" do
      user = user_fixture()

      summary = Nutrition.daily_summary(user.id, ~D[2020-01-01])

      assert summary == %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}
    end

    test "returns correct totals after a meal is logged and macro_log updated" do
      user = user_fixture()
      _meal = meal_fixture(user.id)
      date = Date.utc_today()

      {:ok, _log} = Nutrition.update_macro_log(user.id, date)

      summary = Nutrition.daily_summary(user.id, date)

      assert summary.calories == 330.0
      assert summary.protein_g == 62.0
      assert summary.carbs_g == 0.0
      assert summary.fat_g == 7.2
    end

    test "returns zeroed map for a different user" do
      user1 = user_fixture()
      user2 = user_fixture()
      date = Date.utc_today()

      _meal = meal_fixture(user1.id)
      {:ok, _log} = Nutrition.update_macro_log(user1.id, date)

      summary = Nutrition.daily_summary(user2.id, date)
      assert summary == %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}
    end
  end

  describe "meal_count_today/1" do
    test "returns 0 when user has no meals" do
      user = user_fixture()
      assert Nutrition.meal_count_today(user.id) == 0
    end

    test "counts meals logged today" do
      user = user_fixture()
      _meal1 = meal_fixture(user.id)
      _meal2 = meal_fixture(user.id)

      assert Nutrition.meal_count_today(user.id) == 2
    end

    test "does not count meals from other users" do
      user1 = user_fixture()
      user2 = user_fixture()

      _meal = meal_fixture(user1.id)

      assert Nutrition.meal_count_today(user2.id) == 0
    end
  end

  describe "list_meals/2" do
    test "returns empty list when user has no meals" do
      user = user_fixture()
      assert Nutrition.list_meals(user.id) == []
    end

    test "returns meals ordered by logged_at descending (most recent first)" do
      user = user_fixture()
      meal1 = meal_fixture(user.id)
      meal2 = meal_fixture(user.id)

      meals = Nutrition.list_meals(user.id)
      ids = Enum.map(meals, & &1.id)

      # Both meals should be present; meal2 was inserted last so has a later logged_at
      assert meal1.id in ids
      assert meal2.id in ids

      first_logged_at = hd(meals).logged_at
      last_logged_at = List.last(meals).logged_at
      assert DateTime.compare(first_logged_at, last_logged_at) in [:gt, :eq]
    end

    test "preloads food_items for each meal" do
      user = user_fixture()
      _meal = meal_fixture(user.id)

      [meal] = Nutrition.list_meals(user.id)
      assert length(meal.food_items) == 1
      assert hd(meal.food_items).name == "Chicken breast"
    end

    test "respects the limit option" do
      user = user_fixture()
      for _ <- 1..5, do: meal_fixture(user.id)

      meals = Nutrition.list_meals(user.id, limit: 3)
      assert length(meals) == 3
    end

    test "respects the offset option" do
      user = user_fixture()
      for _ <- 1..5, do: meal_fixture(user.id)

      all_meals = Nutrition.list_meals(user.id, limit: 5)
      offset_meals = Nutrition.list_meals(user.id, limit: 5, offset: 2)

      assert length(offset_meals) == 3
      expected_ids = all_meals |> Enum.drop(2) |> Enum.map(& &1.id)
      actual_ids = Enum.map(offset_meals, & &1.id)
      assert actual_ids == expected_ids
    end
  end

  describe "broadcast_meal_logged/2" do
    test "broadcasts meal_logged event to the correct PubSub topic" do
      user = user_fixture()
      meal = meal_fixture(user.id)
      topic = "user:#{user.id}:meal_logged"

      :ok = Phoenix.PubSub.subscribe(DietProject.PubSub, topic)

      assert :ok = Nutrition.broadcast_meal_logged(user.id, meal)

      assert_receive {:meal_logged, ^meal}
    end

    test "does not broadcast to a different user's topic" do
      user1 = user_fixture()
      user2 = user_fixture()
      meal = meal_fixture(user1.id)
      topic2 = "user:#{user2.id}:meal_logged"

      :ok = Phoenix.PubSub.subscribe(DietProject.PubSub, topic2)

      assert :ok = Nutrition.broadcast_meal_logged(user1.id, meal)

      refute_receive {:meal_logged, _}, 100
    end
  end
end
