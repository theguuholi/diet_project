defmodule DietProject.AI.ClaudeClientTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  alias DietProject.AI

  describe "extract_meal/1" do
    test "delegates to configured adapter and returns food items" do
      food_items = [%{"name" => "chicken breast", "calories" => 165, "protein_g" => 31}]

      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn "I had chicken breast for lunch" ->
        {:ok, food_items}
      end)

      assert {:ok, ^food_items} = AI.extract_meal("I had chicken breast for lunch")
    end

    test "propagates errors from the adapter" do
      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn _ -> {:error, :api_unavailable} end)

      assert {:error, :api_unavailable} = AI.extract_meal("some food")
    end
  end

  describe "analyze_image/1" do
    test "delegates to configured adapter and returns food items with confidence" do
      food_items = [%{"name" => "pizza", "calories" => 800, "confidence" => 0.9}]

      DietProject.AI.ClaudeClientMock
      |> expect(:analyze_image, fn "base64encodedimage==" ->
        {:ok, food_items}
      end)

      assert {:ok, ^food_items} = AI.analyze_image("base64encodedimage==")
    end

    test "propagates errors from the adapter" do
      DietProject.AI.ClaudeClientMock
      |> expect(:analyze_image, fn _ -> {:error, :invalid_image} end)

      assert {:error, :invalid_image} = AI.analyze_image("bad_image")
    end
  end
end
