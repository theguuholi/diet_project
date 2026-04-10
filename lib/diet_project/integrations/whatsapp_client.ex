defmodule DietProject.Integrations.WhatsAppClient do
  @moduledoc """
  WhatsApp Business API client.

  Handles sending text messages and downloading media from WhatsApp.
  All WhatsApp API calls go through this module so that Mox stubbing in
  tests has a single point of control and production secrets are read at
  call time from environment variables.

  Implements `DietProject.Integrations.WhatsAppClientBehaviour`.
  Uses the `Req` HTTP client as mandated by CLAUDE.md.

  ## Required environment variables

  - `WHATSAPP_TOKEN` — Bearer token for the WhatsApp Business API
  - `WHATSAPP_PHONE_NUMBER_ID` — The numeric phone number ID from Meta console
  """

  @behaviour DietProject.Integrations.WhatsAppClientBehaviour

  @base_url "https://graph.facebook.com/v19.0"

  @doc """
  Sends a text message to a WhatsApp phone number via the Business API.

  ## Examples

      # In production (not for doctests — hits real API):
      # :ok

  """
  @spec send_message(phone :: String.t(), message :: String.t()) :: :ok | {:error, term()}
  @impl DietProject.Integrations.WhatsAppClientBehaviour
  def send_message(phone, message) do
    token = System.fetch_env!("WHATSAPP_TOKEN")
    phone_number_id = System.fetch_env!("WHATSAPP_PHONE_NUMBER_ID")

    body = %{
      messaging_product: "whatsapp",
      to: phone,
      type: "text",
      text: %{body: message}
    }

    case Req.post("#{@base_url}/#{phone_number_id}/messages",
           json: body,
           headers: [{"authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: resp_body}} -> {:error, {:api_error, status, resp_body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Downloads a media file from WhatsApp using its media ID.

  First retrieves the download URL from the media endpoint, then fetches
  the binary. Returns the raw binary content.

  ## Examples

      # In production (not for doctests — hits real API):
      # {:ok, <<binary_data>>}

  """
  @spec download_media(media_id :: String.t()) :: {:ok, binary()} | {:error, term()}
  @impl DietProject.Integrations.WhatsAppClientBehaviour
  def download_media(media_id) do
    token = System.fetch_env!("WHATSAPP_TOKEN")
    headers = [{"authorization", "Bearer #{token}"}]

    with {:ok, %{status: 200, body: %{"url" => url}}} <-
           Req.get("#{@base_url}/#{media_id}", headers: headers),
         {:ok, %{status: 200, body: binary}} <-
           Req.get(url, headers: headers) do
      {:ok, binary}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:api_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
