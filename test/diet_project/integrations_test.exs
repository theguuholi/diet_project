defmodule DietProject.IntegrationsTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  alias DietProject.Integrations

  describe "upload/3" do
    test "delegates to configured R2 adapter and returns URL" do
      DietProject.Integrations.R2ClientMock
      |> expect(:upload, fn "meal_photo.jpg", <<1, 2, 3>>, "image/jpeg" ->
        {:ok, "https://cdn.example.com/meal_photo.jpg"}
      end)

      assert {:ok, "https://cdn.example.com/meal_photo.jpg"} =
               Integrations.upload("meal_photo.jpg", <<1, 2, 3>>, "image/jpeg")
    end

    test "propagates errors from the adapter" do
      DietProject.Integrations.R2ClientMock
      |> expect(:upload, fn _, _, _ -> {:error, :connection_refused} end)

      assert {:error, :connection_refused} =
               Integrations.upload("file.jpg", <<>>, "image/jpeg")
    end
  end

  describe "send_message/2" do
    test "delegates to configured WhatsApp adapter" do
      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn "+5511999999999", "Hello!" -> :ok end)

      assert :ok = Integrations.send_message("+5511999999999", "Hello!")
    end

    test "propagates errors from the adapter" do
      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _, _ -> {:error, :unauthorized} end)

      assert {:error, :unauthorized} = Integrations.send_message("+5511999999999", "Hello!")
    end
  end

  describe "download_media/1" do
    test "delegates to configured WhatsApp adapter and returns binary" do
      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn "media-id-123" -> {:ok, <<0, 1, 2, 3>>} end)

      assert {:ok, <<0, 1, 2, 3>>} = Integrations.download_media("media-id-123")
    end

    test "propagates errors from the adapter" do
      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn _ -> {:error, :not_found} end)

      assert {:error, :not_found} = Integrations.download_media("bad-media-id")
    end
  end
end
