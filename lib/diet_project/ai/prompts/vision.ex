defmodule DietProject.AI.Prompts.Vision do
  @moduledoc """
  Versioned prompt for analysing meal photos via the Claude vision API.

  Keeping vision prompts separate from text prompts allows independent
  tuning of the two analysis paths as Claude's vision capabilities evolve.
  """

  @prompt_version "1.0"

  @doc """
  Returns the current prompt version string.

  ## Examples

      iex> DietProject.AI.Prompts.Vision.version()
      "1.0"

  """
  @spec version() :: String.t()
  def version, do: @prompt_version

  @doc """
  Builds the system prompt for vision-based food analysis.

  ## Examples

      iex> is_binary(DietProject.AI.Prompts.Vision.system_prompt())
      true

  """
  @spec system_prompt() :: String.t()
  def system_prompt do
    """
    You are a nutritional analysis assistant with computer vision capabilities.
    Analyse the food in the provided image and return structured macro data.

    Always respond with a valid JSON array of food items. Each item must have:
    - "name" (string): the food item name
    - "quantity" (number): estimated amount consumed
    - "unit" (string): unit of measurement (e.g. "g", "ml", "piece")
    - "calories" (number): estimated calories
    - "protein_g" (number): protein in grams
    - "carbs_g" (number): carbohydrates in grams
    - "fat_g" (number): fat in grams
    - "confidence" (number): confidence score between 0.0 and 1.0

    Use realistic nutritional values. When the portion size is unclear, estimate
    based on visual cues (plate size, context). Return ONLY the JSON array.
    """
  end

  @doc """
  Builds the user message text accompanying the base64 image for the vision API.

  ## Examples

      iex> is_binary(DietProject.AI.Prompts.Vision.build("base64=="))
      true

  """
  @spec build(base64_image :: String.t()) :: String.t()
  def build(_base64_image) do
    "Please analyse the food items visible in this image and return their nutritional data."
  end
end
