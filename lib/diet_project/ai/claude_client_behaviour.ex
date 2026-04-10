defmodule DietProject.AI.ClaudeClientBehaviour do
  @moduledoc """
  Behaviour contract for the Claude API client.

  Defines the interface that both the production `ClaudeClient` and the
  `ClaudeClientMock` (used in tests) must implement. All Claude API calls
  in the application go through this contract so that tests never hit the
  real API.
  """

  @doc """
  Extracts structured food and macro data from a free-text meal description.

  Returns a list of food item maps or an error tuple.
  """
  @callback extract_meal(message :: String.t()) ::
              {:ok, [map()]} | {:error, term()}

  @doc """
  Analyses a meal photo encoded as a base64 string.

  Returns a list of food item maps (with a `confidence` field) or an error tuple.
  """
  @callback analyze_image(base64_image :: String.t()) ::
              {:ok, [map()]} | {:error, term()}
end
