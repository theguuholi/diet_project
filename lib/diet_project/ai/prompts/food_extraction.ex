defmodule DietProject.AI.Prompts.FoodExtraction do
  @moduledoc """
  Versioned prompt for extracting structured food and macro data from
  a free-text meal description via the Claude API.

  Keeping prompts in versioned modules allows prompt improvements to be
  tracked in git history, A/B tested, and rolled back independently of
  the surrounding application logic.
  """

  @prompt_version "1.0"

  @doc """
  Returns the current prompt version string.

  ## Examples

      iex> DietProject.AI.Prompts.FoodExtraction.version()
      "1.0"

  """
  @spec version() :: String.t()
  def version, do: @prompt_version

  @doc """
  Builds the system prompt for food extraction.

  ## Examples

      iex> is_binary(DietProject.AI.Prompts.FoodExtraction.system_prompt())
      true

  """
  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are a nutritional analysis assistant. Extract structured food and macro data
    from meal descriptions.

    Always respond with a valid JSON array of food items. Each item must have these fields:
    - "name" (string): the food item name
    - "quantity" (number): the amount consumed
    - "unit" (string): unit of measurement (e.g. "g", "ml", "piece", "cup")
    - "calories" (number): estimated calories
    - "protein_g" (number): protein in grams
    - "carbs_g" (number): carbohydrates in grams
    - "fat_g" (number): fat in grams

    Use realistic nutritional values from standard food databases.
    If quantity is unclear, assume a typical serving size.
    Return ONLY the JSON array, no explanation text.
    """
  end

  @doc """
  Builds the user message for food extraction from a raw meal description.

  ## Examples

      iex> msg = DietProject.AI.Prompts.FoodExtraction.build("I had grilled chicken and rice")
      iex> String.contains?(msg, "grilled chicken")
      true

  """
  @spec build(user_message :: String.t()) :: String.t()
  def build(user_message) do
    "Extract the food items from this meal description: #{user_message}"
  end
end
