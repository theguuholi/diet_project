defmodule DietProject.Workers.ProcessTextMealTest do
  use DietProject.DataCase
  use Oban.Testing, repo: DietProject.Repo

  import Mox
  import DietProject.AccountsFixtures

  setup :verify_on_exit!

  alias DietProject.Workers.ProcessTextMeal

  @food_items [
    %{
      "name" => "grilled chicken",
      "quantity" => 200.0,
      "unit" => "g",
      "calories" => 330.0,
      "protein_g" => 62.0,
      "carbs_g" => 0.0,
      "fat_g" => 7.0
    }
  ]

  describe "perform/1" do
    test "extracts meal, persists it, updates macro log, and sends WhatsApp reply" do
      user = user_fixture()

      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn "I had grilled chicken" -> {:ok, @food_items} end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, message ->
        assert message =~ "330"
        :ok
      end)

      assert :ok =
               perform_job(ProcessTextMeal, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "message" => "I had grilled chicken"
               })
    end

    test "sends upgrade message when free user exceeds daily limit" do
      user = user_fixture()

      # Create 3 meals to hit the free limit
      for _ <- 1..3 do
        {:ok, meal} =
          DietProject.Nutrition.create_meal(user.id, %{
            input_type: :text,
            raw_input: "test",
            food_items: [
              %{
                "name" => "test",
                "quantity" => 1.0,
                "unit" => "piece",
                "calories" => 100.0,
                "protein_g" => 5.0,
                "carbs_g" => 10.0,
                "fat_g" => 3.0
              }
            ]
          })

        DietProject.Nutrition.update_macro_log(user.id, meal.logged_at |> DateTime.to_date())
      end

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, message ->
        assert message =~ "Upgrade"
        :ok
      end)

      assert :ok =
               perform_job(ProcessTextMeal, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "message" => "more food"
               })
    end

    test "returns error when AI extraction fails" do
      user = user_fixture()

      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn _ -> {:error, :api_unavailable} end)

      assert {:error, :api_unavailable} =
               perform_job(ProcessTextMeal, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "message" => "some food"
               })
    end

    test "formats reply with goal context when user has goals set up" do
      user = user_fixture()
      DietProject.AccountsFixtures.goals_fixture(user)

      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn "salad" -> {:ok, @food_items} end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, message ->
        assert message =~ "330"
        :ok
      end)

      assert :ok =
               perform_job(ProcessTextMeal, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999998",
                 "message" => "salad"
               })
    end
  end
end
