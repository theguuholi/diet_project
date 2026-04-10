defmodule DietProject.AI.WhisperClient do
  @moduledoc """
  HTTP client wrapper for the OpenAI Whisper speech-to-text API.

  Handles audio transcription for voice-based meal logging. All Whisper
  calls go through this module so that Mox stubbing in tests has a single
  point of control and the real API is never called during tests.

  Implements `DietProject.AI.WhisperClientBehaviour`.
  Reads the `OPENAI_API_KEY` environment variable at call time.
  Uses the `Req` HTTP client as mandated by CLAUDE.md.
  """

  @behaviour DietProject.AI.WhisperClientBehaviour

  @whisper_url "https://api.openai.com/v1/audio/transcriptions"
  @model "whisper-1"

  @doc """
  Transcribes an audio binary to text using the OpenAI Whisper API.

  Accepts raw audio binary data (OGG, MP4, M4A, WAV, etc.) and returns
  the transcribed text string on success.

  ## Examples

      # In production (not for doctests — hits real API):
      # {:ok, "I had a chicken salad for lunch"}

  """
  @spec transcribe(audio_binary :: binary()) :: {:ok, String.t()} | {:error, term()}
  @impl DietProject.AI.WhisperClientBehaviour
  def transcribe(audio_binary) do
    api_key = System.fetch_env!("OPENAI_API_KEY")

    boundary = "----NutribotBoundary#{:rand.uniform(999_999)}"

    body = build_multipart(boundary, audio_binary)

    case Req.post(@whisper_url,
           body: body,
           headers: [
             {"authorization", "Bearer #{api_key}"},
             {"content-type", "multipart/form-data; boundary=#{boundary}"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_multipart(boundary, audio_binary) do
    sep = "--#{boundary}\r\n"

    model_part =
      sep <> ~s(Content-Disposition: form-data; name="model"\r\n\r\n) <> "#{@model}\r\n"

    file_part =
      sep <>
        ~s(Content-Disposition: form-data; name="file"; filename="audio.ogg"\r\n) <>
        "Content-Type: audio/ogg\r\n\r\n"

    model_part <> file_part <> audio_binary <> "\r\n--#{boundary}--\r\n"
  end
end
