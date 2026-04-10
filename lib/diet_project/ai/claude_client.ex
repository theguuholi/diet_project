defmodule DietProject.AI.ClaudeClient do
  @moduledoc """
  HTTP client wrapper for the Anthropic Claude API.

  Centralises all Claude API communication. Every Claude call in the
  application goes through this module so that request logging, error
  handling, and Mox stubbing in tests have a single point of control.

  Implements `DietProject.AI.ClaudeClientBehaviour` so it can be replaced
  by a `Mox` mock in tests without hitting the real API.

  Reads the `CLAUDE_API_KEY` environment variable at call time.
  Uses the `Req` HTTP client as mandated by CLAUDE.md.
  """

  @behaviour DietProject.AI.ClaudeClientBehaviour

  alias DietProject.AI.Prompts.FoodExtraction
  alias DietProject.AI.Prompts.Vision

  @base_url "https://api.anthropic.com/v1"
  @default_model "claude-sonnet-4-6"
  @default_max_tokens 1024
  @api_version "2023-06-01"

  @doc """
  Extracts structured food and macro data from a free-text meal description.

  Calls the Claude API with the `FoodExtraction` prompt and parses the
  JSON response into a list of food item maps.

  ## Examples

      # In production (not for doctests — hits real API):
      # {:ok, [%{"name" => "chicken", "calories" => 165, ...}]}

  """
  @spec extract_meal(message :: String.t()) :: {:ok, [map()]} | {:error, term()}
  @impl DietProject.AI.ClaudeClientBehaviour
  def extract_meal(message) do
    system = FoodExtraction.system_prompt()
    user_text = FoodExtraction.build(message)

    case call_claude(system, [{:text, user_text}]) do
      {:ok, raw} -> Jason.decode(raw)
      error -> error
    end
  end

  @doc """
  Analyses a meal photo encoded as a base64 string via Claude vision.

  Calls the Claude API with the `Vision` prompt and the base64-encoded
  image, then parses the JSON response into a list of food item maps
  (each including a `"confidence"` field).

  ## Examples

      # In production (not for doctests — hits real API):
      # {:ok, [%{"name" => "pizza", "calories" => 800, "confidence" => 0.9}]}

  """
  @spec analyze_image(base64_image :: String.t()) :: {:ok, [map()]} | {:error, term()}
  @impl DietProject.AI.ClaudeClientBehaviour
  def analyze_image(base64_image) do
    system = Vision.system_prompt()
    user_text = Vision.build(base64_image)

    content = [
      {:image, base64_image},
      {:text, user_text}
    ]

    case call_claude(system, content) do
      {:ok, raw} -> Jason.decode(raw)
      error -> error
    end
  end

  # --- Private helpers ---

  defp call_claude(system_prompt, content_parts) do
    api_key = System.fetch_env!("CLAUDE_API_KEY")

    messages = [
      %{
        role: "user",
        content: Enum.map(content_parts, &build_content_block/1)
      }
    ]

    body = %{
      model: @default_model,
      max_tokens: @default_max_tokens,
      system: system_prompt,
      messages: messages
    }

    case Req.post("#{@base_url}/messages",
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", @api_version},
             {"content-type", "application/json"}
           ]
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_content_block({:text, text}) do
    %{type: "text", text: text}
  end

  defp build_content_block({:image, base64}) do
    %{
      type: "image",
      source: %{
        type: "base64",
        media_type: "image/jpeg",
        data: base64
      }
    }
  end
end
