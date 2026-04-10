defmodule DietProject.Workers.ProcessImageMeal do
  @moduledoc """
  Oban worker that processes a photo-based meal log submitted via WhatsApp.

  Downloads the image from WhatsApp, uploads it to Cloudflare R2, runs
  Claude vision to identify food items, then sets the conversation state
  to `:awaiting_confirmation` and sends the user a confirmation prompt.

  The confirmation step (yes/no reply) is handled by the regular bot FSM
  in a subsequent text message. On confirmation, the meal is persisted by
  `ProcessTextMeal` with the pre-parsed food data.

  Enqueued by `BotController` when the incoming message type is `"image"`.
  """

  use Oban.Worker, queue: :media, max_attempts: 3

  alias DietProject.AI
  alias DietProject.Bot
  alias DietProject.Integrations

  @doc """
  Executes the image meal processing job.

  Expects job args:
  - `"user_id"`  — UUID of the user who sent the image
  - `"phone"`    — E.164 phone number to reply to
  - `"media_id"` — WhatsApp media ID for the image

  Returns `:ok` on success or `{:error, reason}` to trigger Oban retry.
  """
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "phone" => phone, "media_id" => media_id}}) do
    filename = "meals/#{user_id}/#{System.unique_integer([:positive])}.jpg"

    with {:ok, binary} <- Integrations.download_media(media_id),
         {:ok, _url} <- Integrations.upload(filename, binary, "image/jpeg"),
         base64 = Base.encode64(binary),
         {:ok, food_items} <- AI.analyze_image(base64),
         {:ok, _state} <- Bot.set_awaiting_confirmation(user_id, %{"food_items" => food_items}) do
      confirmation_prompt = build_confirmation_prompt(food_items)
      Integrations.send_message(phone, confirmation_prompt)
    end
  end

  defp build_confirmation_prompt(food_items) do
    items_text =
      food_items
      |> Enum.map_join("\n", fn item ->
        name = item["name"] || item[:name]
        cal = item["calories"] || item[:calories]
        "• #{name} (~#{round(cal)} kcal)"
      end)

    "I found these food items:\n#{items_text}\n\nIs this correct? Reply *yes* to confirm or *no* to cancel."
  end
end
