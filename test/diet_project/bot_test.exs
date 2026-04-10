defmodule DietProject.BotTest do
  use DietProject.DataCase

  import Mox
  import DietProject.AccountsFixtures

  setup :verify_on_exit!

  alias DietProject.Accounts
  alias DietProject.Bot
  alias DietProject.Bot.ConversationState

  doctest DietProject.Bot, only: [format_macro_reply: 2, format_daily_balance: 3]

  describe "get_or_create_state/1" do
    test "creates a new idle state for a new user" do
      user = user_fixture()

      assert {:ok, %ConversationState{state: :idle, context: %{}}} =
               Bot.get_or_create_state(user.id)
    end

    test "returns the existing state for the same user" do
      user = user_fixture()
      {:ok, first} = Bot.get_or_create_state(user.id)
      {:ok, second} = Bot.get_or_create_state(user.id)

      assert first.id == second.id
    end

    test "creates separate states for different users" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, state1} = Bot.get_or_create_state(user1.id)
      {:ok, state2} = Bot.get_or_create_state(user2.id)

      refute state1.id == state2.id
    end
  end

  describe "advance_state/2 — FSM transitions" do
    test "idle + any input → collecting_name, asks for name" do
      user = user_fixture()
      {:ok, _} = Bot.get_or_create_state(user.id)

      assert {:ok, %ConversationState{state: :collecting_name}, response} =
               Bot.advance_state(user.id, "hello")

      assert response == "What's your name?"
    end

    test "collecting_name + name → collecting_weight, thanks user" do
      user = user_fixture()
      {:ok, _} = Bot.get_or_create_state(user.id)
      {:ok, _, _} = Bot.advance_state(user.id, "start")

      assert {:ok, %ConversationState{state: :collecting_weight}, response} =
               Bot.advance_state(user.id, "Alice")

      assert response == "Thanks, Alice! What's your weight in kg?"
    end

    test "collecting_weight + number → collecting_height, asks for height" do
      user = user_fixture()
      setup_state_at(user.id, :collecting_weight)

      assert {:ok, %ConversationState{state: :collecting_height}, response} =
               Bot.advance_state(user.id, "70.5")

      assert response == "Got it! What's your height in cm?"
    end

    test "collecting_height + number → collecting_body_fat, asks for body fat" do
      user = user_fixture()
      setup_state_at(user.id, :collecting_height, %{"name" => "Bob", "weight_kg" => 70.5})

      assert {:ok, %ConversationState{state: :collecting_body_fat}, response} =
               Bot.advance_state(user.id, "175")

      assert response == "What's your body fat percentage?"
    end

    test "collecting_body_fat + number → collecting_goal, asks for goal" do
      user = user_fixture()

      setup_state_at(user.id, :collecting_body_fat, %{
        "name" => "Bob",
        "weight_kg" => 70.5,
        "height_cm" => 175.0
      })

      assert {:ok, %ConversationState{state: :collecting_goal}, response} =
               Bot.advance_state(user.id, "20")

      assert response == "What's your goal? (lose/maintain/gain)"
    end

    test "collecting_goal + valid goal → collecting_activity, asks for activity level" do
      user = user_fixture()

      setup_state_at(user.id, :collecting_goal, %{
        "name" => "Bob",
        "weight_kg" => 70.5,
        "height_cm" => 175.0,
        "body_fat_pct" => 20.0
      })

      assert {:ok, %ConversationState{state: :collecting_activity}, response} =
               Bot.advance_state(user.id, "lose")

      assert response ==
               "What's your activity level? (sedentary/light/moderate/active/very_active)"
    end

    test "collecting_activity + valid level → idle, creates profile, returns summary" do
      user = user_fixture()

      setup_state_at(user.id, :collecting_activity, %{
        "name" => "Carol",
        "weight_kg" => 60.0,
        "height_cm" => 165.0,
        "body_fat_pct" => 25.0,
        "goal" => "maintain"
      })

      assert {:ok, %ConversationState{state: :idle}, response} =
               Bot.advance_state(user.id, "moderate")

      assert response =~ "Carol"
      assert response =~ "kcal"
    end

    test "awaiting_confirmation + 'yes' → idle, confirmed (no food_items)" do
      user = user_fixture()
      {:ok, _} = Bot.set_awaiting_confirmation(user.id, %{"food" => "rice"})

      assert {:ok, %ConversationState{state: :idle}, response} =
               Bot.advance_state(user.id, "yes")

      assert response == "Confirmed!"
    end

    test "awaiting_confirmation + 'yes' with food_items → persists meal and returns confirmed" do
      user = user_fixture()

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, _msg -> {:ok, %{}} end)

      food_items = [
        %{
          "name" => "pizza",
          "calories" => 800.0,
          "protein_g" => 25.0,
          "carbs_g" => 100.0,
          "fat_g" => 30.0,
          "quantity" => 1.0,
          "unit" => "slice"
        }
      ]

      {:ok, _} =
        Bot.set_awaiting_confirmation(user.id, %{
          "food_items" => food_items,
          "user_id" => user.id,
          "phone" => user.phone
        })

      assert {:ok, %ConversationState{state: :idle}, "Confirmed!"} =
               Bot.advance_state(user.id, "yes")
    end

    test "awaiting_confirmation + 'no' → idle, cancelled" do
      user = user_fixture()
      {:ok, _} = Bot.set_awaiting_confirmation(user.id, %{"food" => "rice"})

      assert {:ok, %ConversationState{state: :idle}, response} =
               Bot.advance_state(user.id, "no")

      assert response == "Cancelled."
    end

    test "invalid input stays in same state" do
      user = user_fixture()

      setup_state_at(user.id, :collecting_goal, %{
        "name" => "Dave",
        "weight_kg" => 75.0,
        "height_cm" => 180.0,
        "body_fat_pct" => 18.0
      })

      assert {:ok, %ConversationState{state: :collecting_goal}, response} =
               Bot.advance_state(user.id, "invalid_input")

      assert response == "I didn't understand. Please try again."
    end

    test "collecting_weight with non-numeric input stays in same state" do
      user = user_fixture()
      setup_state_at(user.id, :collecting_weight)

      assert {:ok, %ConversationState{state: :collecting_weight}, response} =
               Bot.advance_state(user.id, "not a number")

      assert response == "I didn't understand. Please try again."
    end

    test "collecting_weight with integer string advances to collecting_height" do
      user = user_fixture()
      setup_state_at(user.id, :collecting_weight)

      assert {:ok, %ConversationState{state: :collecting_height}, _response} =
               Bot.advance_state(user.id, "80")
    end

    test "collecting_height with invalid input stays in same state" do
      user = user_fixture()
      setup_state_at(user.id, :collecting_height)

      assert {:ok, %ConversationState{state: :collecting_height}, response} =
               Bot.advance_state(user.id, "not a number")

      assert response == "I didn't understand. Please try again."
    end

    test "collecting_body_fat with invalid input stays in same state" do
      user = user_fixture()
      setup_state_at(user.id, :collecting_body_fat)

      assert {:ok, %ConversationState{state: :collecting_body_fat}, response} =
               Bot.advance_state(user.id, "banana")

      assert response == "I didn't understand. Please try again."
    end
  end

  describe "advance_state/2 — full onboarding flow creates Profile" do
    test "completing the onboarding flow creates a profile in the DB" do
      user = user_fixture()
      {:ok, _} = Bot.get_or_create_state(user.id)

      # idle → collecting_name
      {:ok, _, _} = Bot.advance_state(user.id, "hi")
      # collecting_name → collecting_weight
      {:ok, _, _} = Bot.advance_state(user.id, "Eve")
      # collecting_weight → collecting_height
      {:ok, _, _} = Bot.advance_state(user.id, "65.0")
      # collecting_height → collecting_body_fat
      {:ok, _, _} = Bot.advance_state(user.id, "170")
      # collecting_body_fat → collecting_goal
      {:ok, _, _} = Bot.advance_state(user.id, "22")
      # collecting_goal → collecting_activity
      {:ok, _, _} = Bot.advance_state(user.id, "gain")
      # collecting_activity → idle (profile created)
      {:ok, %ConversationState{state: :idle}, _} = Bot.advance_state(user.id, "light")

      assert %Accounts.Profile{} = Accounts.get_profile(user)
    end
  end

  describe "set_awaiting_confirmation/2" do
    test "sets state to awaiting_confirmation and stores food_data in context" do
      user = user_fixture()
      food_data = %{"name" => "chicken breast", "calories" => 165}

      assert {:ok, %ConversationState{state: :awaiting_confirmation, context: ctx}} =
               Bot.set_awaiting_confirmation(user.id, food_data)

      assert ctx["food_data"] == food_data
    end

    test "overwrites previous context with new food_data" do
      user = user_fixture()
      {:ok, _} = Bot.set_awaiting_confirmation(user.id, %{"old" => "data"})

      {:ok, state} = Bot.set_awaiting_confirmation(user.id, %{"new" => "data"})

      assert state.context["food_data"] == %{"new" => "data"}
    end
  end

  describe "format_macro_reply/2" do
    test "formats macro totals as a WhatsApp-friendly string" do
      macros = %{calories: 1200, protein_g: 85, carbs_g: 120, fat_g: 45}
      goals = %{calories: 2000, protein_g: 150, carbs_g: 200, fat_g: 67}

      result = Bot.format_macro_reply(macros, goals)

      assert result == "📊 Today's macros: 1200 kcal | 85g protein | 120g carbs | 45g fat"
    end
  end

  describe "format_daily_balance/3" do
    test "formats progress vs goal for a given date" do
      macros = %{calories: 1200, protein_g: 85, carbs_g: 120, fat_g: 45}
      goals = %{calories: 2000, protein_g: 150, carbs_g: 200, fat_g: 67}
      date = ~D[2026-04-09]

      result = Bot.format_daily_balance(macros, goals, date)

      assert result ==
               "📅 Apr 9: 1200/2000 kcal (60%) | 85/150g protein | 120/200g carbs | 45/67g fat"
    end
  end

  # --- Helpers ---

  defp setup_state_at(user_id, state, context \\ %{}) do
    {:ok, conv_state} = Bot.get_or_create_state(user_id)

    conv_state
    |> ConversationState.changeset(%{state: state, context: context})
    |> DietProject.Repo.update!()
  end
end
