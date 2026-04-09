defmodule DietProject.AI.WhisperClientBehaviour do
  @moduledoc """
  Behaviour contract for the OpenAI Whisper transcription client.

  Defines the interface that both the production `WhisperClient` and the
  `WhisperClientMock` must implement. Tests never hit the real Whisper API.
  """

  @doc """
  Transcribes an audio binary to text.

  Accepts the raw audio binary (OGG, MP4, etc.) and returns the transcribed
  text string or an error tuple.
  """
  @callback transcribe(audio_binary :: binary()) ::
              {:ok, String.t()} | {:error, term()}
end
