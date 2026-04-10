defmodule DietProject.Workers.TranscribeAudioTest do
  use DietProject.DataCase
  use Oban.Testing, repo: DietProject.Repo

  import Mox
  import DietProject.AccountsFixtures

  setup :verify_on_exit!

  alias DietProject.Workers.TranscribeAudio

  describe "perform/1" do
    # Oban is configured with testing: :inline, so ProcessTextMeal is also
    # executed immediately when TranscribeAudio enqueues it. We set up all
    # expected mock calls for the full chain and verify via verify_on_exit!.
    test "downloads audio, uploads to R2, transcribes, and processes text meal" do
      user = user_fixture()

      food_items = [
        %{
          "name" => "pasta",
          "quantity" => 200.0,
          "unit" => "g",
          "calories" => 300.0,
          "protein_g" => 10.0,
          "carbs_g" => 55.0,
          "fat_g" => 3.0
        }
      ]

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn "audio-xyz" -> {:ok, <<10, 20, 30>>} end)

      DietProject.Integrations.R2ClientMock
      |> expect(:upload, fn filename, <<10, 20, 30>>, "audio/ogg" ->
        assert String.ends_with?(filename, ".ogg")
        {:ok, "https://cdn.example.com/#{filename}"}
      end)

      DietProject.AI.WhisperClientMock
      |> expect(:transcribe, fn <<10, 20, 30>> -> {:ok, "I had pasta for dinner"} end)

      # ProcessTextMeal is enqueued and executed inline:
      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn "I had pasta for dinner" -> {:ok, food_items} end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn "+5511999999999", _message -> :ok end)

      assert :ok =
               perform_job(TranscribeAudio, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "media_id" => "audio-xyz"
               })
    end

    test "returns error when audio download fails" do
      user = user_fixture()

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn _ -> {:error, :not_found} end)

      assert {:error, :not_found} =
               perform_job(TranscribeAudio, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "media_id" => "bad-audio"
               })
    end
  end
end
