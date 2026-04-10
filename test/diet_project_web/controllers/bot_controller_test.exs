defmodule DietProjectWeb.BotControllerTest do
  use DietProjectWeb.ConnCase, async: false

  import Mox
  import DietProject.AccountsFixtures

  setup :verify_on_exit!

  describe "GET /webhooks/whatsapp (verification)" do
    test "responds with challenge for valid verification request", %{conn: conn} do
      conn =
        get(conn, "/webhooks/whatsapp", %{
          "hub.mode" => "subscribe",
          "hub.challenge" => "abc123",
          "hub.verify_token" => "mytoken"
        })

      assert conn.status == 200
      assert conn.resp_body == "abc123"
    end
  end

  describe "POST /webhooks/whatsapp (text message)" do
    test "enqueues ProcessTextMeal for text message from known user", %{conn: conn} do
      user = user_fixture(%{phone: "+5511987650001"})

      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn _message ->
        {:ok,
         [
           %{
             "name" => "chicken",
             "calories" => 200.0,
             "protein_g" => 30.0,
             "carbs_g" => 0.0,
             "fat_g" => 5.0,
             "quantity" => 100.0,
             "unit" => "g"
           }
         ]}
      end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, _msg -> {:ok, %{}} end)

      payload = whatsapp_text_payload(user.phone, "I had grilled chicken")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200
    end

    test "responds 200 for message from unknown user", %{conn: conn} do
      payload = whatsapp_text_payload("+5511000000000", "some food")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200
    end

    test "responds 200 for unknown payload structure", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", %{})

      assert conn.status == 200
    end

    test "responds 200 for entry without changes key", %{conn: conn} do
      payload = %{"entry" => [%{"no_changes_key" => []}]}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200
    end

    test "responds 200 for change without messages/contacts", %{conn: conn} do
      payload = %{
        "entry" => [%{"changes" => [%{"value" => %{"metadata" => "only"}}]}]
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200
    end

    test "responds 200 for unknown message type from known user", %{conn: conn} do
      user = user_fixture(%{phone: "+5511987650005"})

      payload = %{
        "entry" => [
          %{
            "changes" => [
              %{
                "value" => %{
                  "messages" => [%{"type" => "sticker", "sticker" => %{"id" => "sticker_id"}}],
                  "contacts" => [%{"wa_id" => "5511987650005"}]
                }
              }
            ]
          }
        ]
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200

      # Only needed to avoid unused variable warning
      assert user.phone == "+5511987650005"
    end
  end

  describe "POST /webhooks/whatsapp (image message)" do
    test "enqueues ProcessImageMeal for image message from known user", %{conn: conn} do
      user = user_fixture(%{phone: "+5511987650003"})

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn "img_media_id" -> {:ok, <<1, 2, 3>>} end)

      DietProject.Integrations.R2ClientMock
      |> expect(:upload, fn _filename, _binary, _type ->
        {:ok, "https://r2.example.com/img.jpg"}
      end)

      DietProject.AI.ClaudeClientMock
      |> expect(:analyze_image, fn _base64 ->
        {:ok,
         [
           %{
             "name" => "pizza",
             "calories" => 800.0,
             "confidence" => 0.9,
             "protein_g" => 25.0,
             "carbs_g" => 100.0,
             "fat_g" => 30.0,
             "quantity" => 1.0,
             "unit" => "slice"
           }
         ]}
      end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, _msg -> {:ok, %{}} end)

      payload = whatsapp_image_payload(user.phone, "img_media_id")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200
    end
  end

  describe "POST /webhooks/whatsapp (audio message)" do
    test "enqueues TranscribeAudio for audio message from known user", %{conn: conn} do
      user = user_fixture(%{phone: "+5511987650004"})

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:download_media, fn "audio_media_id" -> {:ok, <<4, 5, 6>>} end)

      DietProject.Integrations.R2ClientMock
      |> expect(:upload, fn _filename, _binary, _type ->
        {:ok, "https://r2.example.com/audio.ogg"}
      end)

      DietProject.AI.WhisperClientMock
      |> expect(:transcribe, fn _binary -> {:ok, "I had grilled chicken"} end)

      DietProject.AI.ClaudeClientMock
      |> expect(:extract_meal, fn _text ->
        {:ok,
         [
           %{
             "name" => "chicken",
             "calories" => 200.0,
             "protein_g" => 30.0,
             "carbs_g" => 0.0,
             "fat_g" => 5.0,
             "quantity" => 100.0,
             "unit" => "g"
           }
         ]}
      end)

      DietProject.Integrations.WhatsAppClientMock
      |> expect(:send_message, fn _phone, _msg -> {:ok, %{}} end)

      payload = whatsapp_audio_payload(user.phone, "audio_media_id")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/whatsapp", payload)

      assert conn.status == 200
    end
  end

  # --- Helpers ---

  defp whatsapp_text_payload(phone, text) do
    wa_id = String.replace_leading(phone, "+", "")
    whatsapp_payload(wa_id, %{"type" => "text", "text" => %{"body" => text}})
  end

  defp whatsapp_image_payload(phone, media_id) do
    wa_id = String.replace_leading(phone, "+", "")
    whatsapp_payload(wa_id, %{"type" => "image", "image" => %{"id" => media_id}})
  end

  defp whatsapp_audio_payload(phone, media_id) do
    wa_id = String.replace_leading(phone, "+", "")
    whatsapp_payload(wa_id, %{"type" => "audio", "audio" => %{"id" => media_id}})
  end

  defp whatsapp_payload(wa_id, message) do
    %{
      "entry" => [
        %{
          "changes" => [
            %{
              "value" => %{
                "messages" => [message],
                "contacts" => [%{"wa_id" => wa_id}]
              }
            }
          ]
        }
      ]
    }
  end
end
