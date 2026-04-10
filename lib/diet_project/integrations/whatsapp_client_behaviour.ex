defmodule DietProject.Integrations.WhatsAppClientBehaviour do
  @moduledoc """
  Behaviour contract for the WhatsApp Business API client.

  Defines the interface that both the production `WhatsAppClient` and the
  `WhatsAppClientMock` must implement. Tests never send real WhatsApp messages.
  """

  @doc """
  Sends a text message to a WhatsApp phone number.

  - `phone` — E.164 formatted destination number (e.g. `"+5511999999999"`)
  - `message` — plain-text message body
  """
  @callback send_message(phone :: String.t(), message :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Downloads a media file from WhatsApp using its media ID.

  Returns the raw binary of the media file or an error tuple.
  """
  @callback download_media(media_id :: String.t()) ::
              {:ok, binary()} | {:error, term()}
end
