defmodule DietProject.AI do
  @moduledoc """
  Public API for all AI integrations: Claude (vision + text) and Whisper (audio).

  This context acts as the single entry point for AI calls. It delegates to
  the configured adapter modules, enabling Mox mocks in tests without any
  production code changes.

  ## Configuration

  Set adapter modules in `config/test.exs`:

      config :diet_project,
        claude_client: DietProject.AI.ClaudeClientMock,
        whisper_client: DietProject.AI.WhisperClientMock

  Production defaults to the real clients automatically.
  """

  @doc """
  Extracts structured food and macro data from a free-text meal description.

  Delegates to the configured Claude client adapter.

  ## Examples

      # returns {:ok, [%{"name" => "chicken", "calories" => 165, ...}]}
      # returns {:error, :api_unavailable}

  """
  @spec extract_meal(message :: String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_meal(message) do
    claude_client().extract_meal(message)
  end

  @doc """
  Analyses a meal photo encoded as a base64 string.

  Delegates to the configured Claude client adapter.

  ## Examples

      # returns {:ok, [%{"name" => "pizza", "calories" => 800, "confidence" => 0.9}]}
      # returns {:error, :invalid_image}

  """
  @spec analyze_image(base64_image :: String.t()) :: {:ok, [map()]} | {:error, term()}
  def analyze_image(base64_image) do
    claude_client().analyze_image(base64_image)
  end

  @doc """
  Transcribes an audio binary to text via the Whisper API.

  Delegates to the configured Whisper client adapter.

  ## Examples

      # returns {:ok, "I had pasta for dinner"}
      # returns {:error, :audio_too_short}

  """
  @spec transcribe(audio_binary :: binary()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(audio_binary) do
    whisper_client().transcribe(audio_binary)
  end

  # --- Private adapter resolution ---

  defp claude_client do
    Application.get_env(:diet_project, :claude_client, DietProject.AI.ClaudeClient)
  end

  defp whisper_client do
    Application.get_env(:diet_project, :whisper_client, DietProject.AI.WhisperClient)
  end
end
