defmodule DietProject.AI.WhisperClientTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  alias DietProject.AI

  describe "transcribe/1" do
    test "delegates to configured adapter and returns transcribed text" do
      audio = <<0, 1, 2, 3>>

      DietProject.AI.WhisperClientMock
      |> expect(:transcribe, fn ^audio -> {:ok, "I had pasta for dinner"} end)

      assert {:ok, "I had pasta for dinner"} = AI.transcribe(audio)
    end

    test "propagates errors from the adapter" do
      DietProject.AI.WhisperClientMock
      |> expect(:transcribe, fn _ -> {:error, :audio_too_short} end)

      assert {:error, :audio_too_short} = AI.transcribe(<<0>>)
    end
  end
end
