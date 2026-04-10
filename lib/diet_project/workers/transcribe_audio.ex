defmodule DietProject.Workers.TranscribeAudio do
  @moduledoc """
  Oban worker that transcribes a voice message and enqueues text meal processing.

  Downloads the audio from WhatsApp, uploads it to Cloudflare R2 for
  archival, transcribes it via the OpenAI Whisper API, and then enqueues
  a `ProcessTextMeal` job with the transcribed text.

  By chaining into `ProcessTextMeal`, this worker reuses the full meal
  extraction, persistence, and reply logic for audio-based meal logs.

  Enqueued by `BotController` when the incoming message type is `"audio"`.
  """

  use Oban.Worker, queue: :audio, max_attempts: 3

  alias DietProject.AI
  alias DietProject.Integrations
  alias DietProject.Workers.ProcessTextMeal

  @doc """
  Executes the audio transcription job.

  Expects job args:
  - `"user_id"`  — UUID of the user who sent the audio
  - `"phone"`    — E.164 phone number (passed through to ProcessTextMeal)
  - `"media_id"` — WhatsApp media ID for the audio file

  Returns `:ok` on success or `{:error, reason}` to trigger Oban retry.
  """
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "phone" => phone, "media_id" => media_id}}) do
    filename = "audio/#{user_id}/#{System.unique_integer([:positive])}.ogg"

    with {:ok, binary} <- Integrations.download_media(media_id),
         {:ok, _url} <- Integrations.upload(filename, binary, "audio/ogg"),
         {:ok, transcription} <- AI.transcribe(binary) do
      %{"user_id" => user_id, "phone" => phone, "message" => transcription}
      |> ProcessTextMeal.new()
      |> Oban.insert()

      :ok
    end
  end
end
