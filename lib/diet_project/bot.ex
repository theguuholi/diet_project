defmodule DietProject.Bot do
  @moduledoc """
  Manages the WhatsApp bot conversation flow and FSM state persistence.

  This context is the single source of truth for where each user is in the
  bot interaction lifecycle. It owns the `ConversationState` schema and
  exposes an FSM-driven API used by Oban workers to handle incoming WhatsApp
  messages.

  Contexts do not call each other directly — the Bot context makes two
  documented exceptions: it calls `DietProject.Accounts` to persist the user
  profile when onboarding completes, and it calls `DietProject.Nutrition` and
  `DietProject.Integrations` to persist confirmed image meals when the user
  replies "yes" to the confirmation prompt. Both cross-context calls are
  integral to the bot flow and require no intermediate domain event.
  """

  import Ecto.Query, warn: false

  alias DietProject.Accounts
  alias DietProject.Bot.ConversationState
  alias DietProject.Integrations
  alias DietProject.Nutrition
  alias DietProject.Repo

  @activity_levels ["sedentary", "light", "moderate", "active", "very_active"]
  @valid_goals ["lose", "maintain", "gain"]

  @doc """
  Returns the existing conversation state for `user_id`, or creates a new
  idle state if none exists.

  ## Examples

      # returns {:ok, %ConversationState{state: :idle}}

  """
  @spec get_or_create_state(user_id :: binary()) ::
          {:ok, ConversationState.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_state(user_id) do
    case Repo.get_by(ConversationState, user_id: user_id) do
      nil ->
        %ConversationState{user_id: user_id}
        |> ConversationState.changeset(%{state: :idle, context: %{}})
        |> Repo.insert()

      state ->
        {:ok, state}
    end
  end

  @doc """
  Advances the FSM for `user_id` given the user's `input`, persists the new
  state, and returns the response message to send back via WhatsApp.

  Returns `{:ok, updated_state, response_text}` on success.

  ## Examples

      # returns {:ok, %ConversationState{state: :collecting_name}, "What's your name?"}

  """
  @spec advance_state(user_id :: binary(), input :: String.t()) ::
          {:ok, ConversationState.t(), String.t()} | {:error, term()}
  def advance_state(user_id, input) do
    with {:ok, state} <- get_or_create_state(user_id) do
      do_transition(state, String.trim(input))
    end
  end

  @doc """
  Sets the conversation state to `:awaiting_confirmation` and stores
  `food_data` in the context under the `"food_data"` key.

  Used by the AI meal-logging workers to present parsed food to the user
  before persisting.

  ## Examples

      # returns {:ok, %ConversationState{state: :awaiting_confirmation}}

  """
  @spec set_awaiting_confirmation(user_id :: binary(), food_data :: map()) ::
          {:ok, ConversationState.t()} | {:error, term()}
  def set_awaiting_confirmation(user_id, food_data) do
    with {:ok, state} <- get_or_create_state(user_id) do
      state
      |> ConversationState.changeset(%{
        state: :awaiting_confirmation,
        context: Map.put(state.context, "food_data", food_data)
      })
      |> Repo.update()
    end
  end

  @doc """
  Formats daily macro totals as a WhatsApp-friendly message string.

  ## Examples

      iex> macros = %{calories: 1200, protein_g: 85, carbs_g: 120, fat_g: 45}
      iex> DietProject.Bot.format_macro_reply(macros, %{})
      "📊 Today's macros: 1200 kcal | 85g protein | 120g carbs | 45g fat"

  """
  @spec format_macro_reply(macros :: map(), goals :: map()) :: String.t()
  def format_macro_reply(macros, _goals) do
    cal = round_macro(get_field(macros, :calories))
    prot = round_macro(get_field(macros, :protein_g))
    carbs = round_macro(get_field(macros, :carbs_g))
    fat = round_macro(get_field(macros, :fat_g))

    "📊 Today's macros: #{cal} kcal | #{prot}g protein | #{carbs}g carbs | #{fat}g fat"
  end

  @doc """
  Formats daily macro progress versus the user's goals as a WhatsApp message.

  ## Examples

      iex> macros = %{calories: 1200, protein_g: 85, carbs_g: 120, fat_g: 45}
      iex> goals = %{calories: 2000, protein_g: 150, carbs_g: 200, fat_g: 67}
      iex> DietProject.Bot.format_daily_balance(macros, goals, ~D[2026-04-09])
      "📅 Apr 9: 1200/2000 kcal (60%) | 85/150g protein | 120/200g carbs | 45/67g fat"

  """
  @spec format_daily_balance(macros :: map(), goals :: map(), date :: Date.t()) :: String.t()
  def format_daily_balance(macros, goals, date) do
    cal = round_macro(get_field(macros, :calories))
    prot = round_macro(get_field(macros, :protein_g))
    carbs = round_macro(get_field(macros, :carbs_g))
    fat = round_macro(get_field(macros, :fat_g))

    goal_cal = get_field(goals, :calories)
    goal_prot = get_field(goals, :protein_g)
    goal_carbs = get_field(goals, :carbs_g)
    goal_fat = get_field(goals, :fat_g)

    pct = calorie_pct(cal, goal_cal)
    date_str = Calendar.strftime(date, "%b %-d")

    "📅 #{date_str}: #{cal}/#{goal_cal} kcal (#{pct}%) | #{prot}/#{goal_prot}g protein | #{carbs}/#{goal_carbs}g carbs | #{fat}/#{goal_fat}g fat"
  end

  # --- Private FSM transitions ---

  defp do_transition(%ConversationState{state: :idle} = state, _input) do
    update_state(state, :collecting_name, %{}, "What's your name?")
  end

  defp do_transition(%ConversationState{state: :collecting_name} = state, name) do
    ctx = Map.put(state.context, "name", name)
    update_state(state, :collecting_weight, ctx, "Thanks, #{name}! What's your weight in kg?")
  end

  defp do_transition(%ConversationState{state: :collecting_weight} = state, input) do
    case parse_float(input) do
      {:ok, weight} ->
        ctx = Map.put(state.context, "weight_kg", weight)
        update_state(state, :collecting_height, ctx, "Got it! What's your height in cm?")

      :error ->
        update_state(
          state,
          :collecting_weight,
          state.context,
          "I didn't understand. Please try again."
        )
    end
  end

  defp do_transition(%ConversationState{state: :collecting_height} = state, input) do
    case parse_float(input) do
      {:ok, height} ->
        ctx = Map.put(state.context, "height_cm", height)
        update_state(state, :collecting_body_fat, ctx, "What's your body fat percentage?")

      :error ->
        update_state(
          state,
          :collecting_height,
          state.context,
          "I didn't understand. Please try again."
        )
    end
  end

  defp do_transition(%ConversationState{state: :collecting_body_fat} = state, input) do
    case parse_float(input) do
      {:ok, bf} ->
        ctx = Map.put(state.context, "body_fat_pct", bf)
        update_state(state, :collecting_goal, ctx, "What's your goal? (lose/maintain/gain)")

      :error ->
        update_state(
          state,
          :collecting_body_fat,
          state.context,
          "I didn't understand. Please try again."
        )
    end
  end

  defp do_transition(%ConversationState{state: :collecting_goal} = state, input) do
    goal = String.downcase(input)

    if goal in @valid_goals do
      ctx = Map.put(state.context, "goal", goal)

      update_state(
        state,
        :collecting_activity,
        ctx,
        "What's your activity level? (sedentary/light/moderate/active/very_active)"
      )
    else
      update_state(
        state,
        :collecting_goal,
        state.context,
        "I didn't understand. Please try again."
      )
    end
  end

  defp do_transition(%ConversationState{state: :collecting_activity} = state, input) do
    level = String.downcase(input)

    if level in @activity_levels do
      ctx = Map.put(state.context, "activity_level", level)
      finish_onboarding(state, ctx)
    else
      update_state(
        state,
        :collecting_activity,
        state.context,
        "I didn't understand. Please try again."
      )
    end
  end

  defp do_transition(%ConversationState{state: :awaiting_confirmation} = state, input) do
    case String.downcase(input) do
      "yes" ->
        maybe_persist_image_meal(state)
        update_state(state, :idle, %{}, "Confirmed!")

      "no" ->
        update_state(state, :idle, %{}, "Cancelled.")

      _ ->
        update_state(
          state,
          :awaiting_confirmation,
          state.context,
          "I didn't understand. Please try again."
        )
    end
  end

  defp do_transition(state, _input) do
    update_state(state, state.state, state.context, "I didn't understand. Please try again.")
  end

  defp maybe_persist_image_meal(%ConversationState{
         context: %{
           "food_data" => %{"food_items" => food_items, "user_id" => user_id, "phone" => phone}
         }
       }) do
    case Nutrition.create_meal(user_id, %{
           input_type: :photo,
           raw_input: "image",
           food_items: food_items
         }) do
      {:ok, meal} ->
        Nutrition.update_macro_log(user_id, DateTime.to_date(meal.logged_at))
        Nutrition.broadcast_meal_logged(user_id, meal)
        Integrations.send_message(phone, "✅ Meal logged!")

      _ ->
        :ok
    end
  end

  defp maybe_persist_image_meal(_state), do: :ok

  defp finish_onboarding(state, ctx) do
    user = Accounts.get_user!(state.user_id)

    weight = ctx["weight_kg"]
    height = ctx["height_cm"]
    body_fat = ctx["body_fat_pct"]
    goal = String.to_existing_atom(ctx["goal"])
    activity_level = String.to_existing_atom(ctx["activity_level"])
    name = ctx["name"]

    bmr = Accounts.calculate_bmr(weight, body_fat)
    tdee = Accounts.calculate_tdee(bmr, activity_level)

    profile_attrs = %{
      weight_kg: weight,
      height_cm: height,
      body_fat_pct: body_fat,
      goal: goal,
      activity_level: activity_level,
      bmr: bmr,
      tdee: tdee
    }

    {:ok, _profile} = Accounts.create_profile(user, profile_attrs)

    response =
      "Welcome, #{name}! 🎉\n" <>
        "Your BMR is #{bmr} kcal and your TDEE is #{tdee} kcal/day.\n" <>
        "Goal: #{ctx["goal"]} | Activity: #{ctx["activity_level"]}"

    update_state(state, :idle, %{}, response)
  end

  defp update_state(state, new_state, new_context, response) do
    updated =
      state
      |> ConversationState.changeset(%{state: new_state, context: new_context})
      |> Repo.update!()

    {:ok, updated, response}
  end

  defp parse_float(input) do
    case Float.parse(input) do
      {value, ""} ->
        {:ok, value}

      {value, rest} when rest in ["", " "] ->
        {:ok, value}

      _ ->
        case Integer.parse(input) do
          {value, ""} -> {:ok, value * 1.0}
          _ -> :error
        end
    end
  end

  defp round_macro(value) when is_float(value), do: round(value)
  defp round_macro(value) when is_integer(value), do: value
  defp round_macro(nil), do: 0

  defp get_field(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp calorie_pct(_cal, nil), do: 0
  defp calorie_pct(_cal, 0), do: 0
  defp calorie_pct(cal, goal_cal), do: round(cal / goal_cal * 100)
end
