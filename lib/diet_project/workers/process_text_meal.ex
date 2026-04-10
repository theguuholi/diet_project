defmodule DietProject.Workers.ProcessTextMeal do
  @moduledoc """
  Oban worker that processes a text-based meal log submitted via WhatsApp.

  Receives the user's free-text meal description, enforces the free-tier
  feature gate (3 meals/day), calls the Claude API to extract structured
  food and macro data, persists the meal and daily macro log, broadcasts
  a PubSub event for the LiveView dashboard, and sends the formatted
  reply back to the user via WhatsApp.

  This worker is enqueued by `BotController` immediately after the WhatsApp
  webhook is received, keeping the HTTP response under 2 seconds.
  """

  use Oban.Worker, queue: :meals, max_attempts: 3

  alias DietProject.Accounts
  alias DietProject.AI
  alias DietProject.Billing
  alias DietProject.Bot
  alias DietProject.Integrations
  alias DietProject.Nutrition

  @free_tier_limit 3
  @upgrade_message "You've reached your free daily limit of #{@free_tier_limit} meal logs. Upgrade to Pro to log unlimited meals! 🚀"

  @doc """
  Executes the text meal processing job.

  Expects job args:
  - `"user_id"` — UUID of the user who sent the message
  - `"phone"`   — E.164 phone number to reply to
  - `"message"` — raw text of the WhatsApp message

  Returns `:ok` on success or `{:error, reason}` to trigger Oban retry.
  """
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "phone" => phone, "message" => message}}) do
    user = Accounts.get_user!(user_id)

    if gate_passed?(user) do
      process_meal(user, phone, message)
    else
      Integrations.send_message(phone, @upgrade_message)
    end
  end

  # --- Private helpers ---

  defp gate_passed?(user) do
    Billing.subscriber?(user) or Nutrition.meal_count_today(user.id) < @free_tier_limit
  end

  defp process_meal(user, phone, message) do
    with {:ok, food_items} <- AI.extract_meal(message),
         {:ok, meal} <- Nutrition.create_meal(user.id, %{input_type: :text, raw_input: message, food_items: food_items}),
         date = DateTime.to_date(meal.logged_at),
         {:ok, macro_log} <- Nutrition.update_macro_log(user.id, date) do
      :ok = Nutrition.broadcast_meal_logged(user.id, meal)

      goals = Accounts.get_goals(user)
      macros = macro_log_to_map(macro_log)
      reply = Bot.format_macro_reply(macros, goals_to_map(goals))
      Integrations.send_message(phone, reply)
    end
  end

  defp macro_log_to_map(macro_log) do
    %{
      calories: macro_log.calories,
      protein_g: macro_log.protein_g,
      carbs_g: macro_log.carbs_g,
      fat_g: macro_log.fat_g
    }
  end

  defp goals_to_map(nil), do: %{}

  defp goals_to_map(goals) do
    %{
      calories: goals.calories,
      protein_g: goals.protein_g,
      carbs_g: goals.carbs_g,
      fat_g: goals.fat_g
    }
  end
end
