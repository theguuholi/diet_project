defmodule DietProject.Workers.ProcessImageMealTest do
  use DietProject.DataCase
  use Oban.Testing, repo: DietProject.Repo

  import Mox
  import DietProject.AccountsFixtures

  setup :verify_on_exit!

  alias DietProject.Workers.ProcessImageMeal

  @food_items [
    %{
      "name" => "pizza slice",
      "quantity" => 1.0,
      "unit" => "slice",
      "calories" => 285.0,
      "protein_g" => 12.0,
      "carbs_g" => 36.0,
      "fat_g" => 10.0,
      "confidence" => 0.9
    }
  ]

  describe "perform/1" do
    test "downloads media, uploads to R2, analyzes with Claude, sets awaiting confirmation" do
      user = user_fixture()

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn "media-abc123" -> {:ok, <<1, 2, 3>>} end)

      DietProject.Integrations.R2ClientMock
      |> expect(:upload, fn filename, <<1, 2, 3>>, "image/jpeg" ->
        assert String.ends_with?(filename, ".jpg")
        {:ok, "https://cdn.example.com/#{filename}"}
      end)

      DietProject.AI.ClaudeClientMock
      |> expect(:analyze_image, fn _base64 -> {:ok, @food_items} end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, message ->
        assert message =~ "pizza"
        assert message =~ "yes"
        :ok
      end)

      assert :ok =
               perform_job(ProcessImageMeal, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "media_id" => "media-abc123"
               })

      {:ok, state} = DietProject.Bot.get_or_create_state(user.id)
      assert state.state == :awaiting_confirmation
    end

    test "returns error when media download fails" do
      user = user_fixture()

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn _ -> {:error, :not_found} end)

      assert {:error, :not_found} =
               perform_job(ProcessImageMeal, %{
                 "user_id" => user.id,
                 "phone" => "+5511999999999",
                 "media_id" => "bad-media"
               })
    end
  end
end
