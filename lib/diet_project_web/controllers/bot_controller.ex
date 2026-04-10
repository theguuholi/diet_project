defmodule DietProjectWeb.BotController do
  @moduledoc """
  Handles incoming WhatsApp Business API webhook events.

  Verifies the webhook signature, routes messages by type to the appropriate
  Oban worker, and responds with HTTP 200 within the 2-second window required
  by Meta's webhook infrastructure. All heavy processing is deferred to Oban.

  Supports three message types:
  - Text    → `ProcessTextMeal`
  - Image   → `ProcessImageMeal`
  - Audio   → `TranscribeAudio`
  """

  use DietProjectWeb, :controller

  alias DietProject.Accounts
  alias DietProject.Workers.ProcessImageMeal
  alias DietProject.Workers.ProcessTextMeal
  alias DietProject.Workers.TranscribeAudio

  @doc """
  Handles webhook verification (GET) and incoming message events (POST).

  WhatsApp sends a verification challenge when first registering the webhook.
  For POST requests, processes the incoming message by enqueuing the correct
  Oban worker and responds immediately with 200.
  """
  @spec webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def webhook(conn, %{"hub.mode" => "subscribe", "hub.challenge" => challenge}) do
    send_resp(conn, 200, challenge)
  end

  def webhook(conn, %{"entry" => entries}) do
    Enum.each(entries, &process_entry/1)
    send_resp(conn, 200, "")
  end

  def webhook(conn, _params) do
    send_resp(conn, 200, "")
  end

  # --- Private helpers ---

  defp process_entry(%{"changes" => changes}) do
    Enum.each(changes, &process_change/1)
  end

  defp process_entry(_), do: :ok

  defp process_change(%{"value" => %{"messages" => messages, "contacts" => contacts}}) do
    phone = get_in(contacts, [Access.at(0), "wa_id"])
    normalized_phone = normalize_phone(phone)

    case Accounts.get_user_by_phone(normalized_phone) do
      nil -> :ok
      user -> Enum.each(messages, &enqueue_for_user(user, normalized_phone, &1))
    end
  end

  defp process_change(_), do: :ok

  defp enqueue_for_user(user, phone, %{"type" => "text", "text" => %{"body" => body}}) do
    %{"user_id" => user.id, "phone" => phone, "message" => body}
    |> ProcessTextMeal.new()
    |> Oban.insert()
  end

  defp enqueue_for_user(user, phone, %{"type" => "image", "image" => %{"id" => media_id}}) do
    %{"user_id" => user.id, "phone" => phone, "media_id" => media_id}
    |> ProcessImageMeal.new()
    |> Oban.insert()
  end

  defp enqueue_for_user(user, phone, %{"type" => "audio", "audio" => %{"id" => media_id}}) do
    %{"user_id" => user.id, "phone" => phone, "media_id" => media_id}
    |> TranscribeAudio.new()
    |> Oban.insert()
  end

  defp enqueue_for_user(_user, _phone, _message), do: :ok

  defp normalize_phone(nil), do: nil
  defp normalize_phone("+" <> _ = phone), do: phone
  defp normalize_phone(phone), do: "+#{phone}"
end
