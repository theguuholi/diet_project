defmodule DietProject.Integrations do
  @moduledoc """
  Public API for external service integrations: Cloudflare R2 and WhatsApp.

  Acts as the single entry point for all third-party integrations beyond the
  AI APIs. Delegates to configured adapter modules so that Mox mocks work in
  tests without any production code changes.

  ## Configuration

  Set adapter modules in `config/test.exs`:

      config :diet_project,
        r2_client: DietProject.Integrations.R2ClientMock,
        whatsapp_client: DietProject.Integrations.WhatsAppClientMock

  Production defaults to the real clients automatically.
  """

  @doc """
  Uploads a binary to Cloudflare R2 and returns the public URL.

  Delegates to the configured R2 client adapter.

  ## Examples

      # returns {:ok, "https://cdn.example.com/meal_photo.jpg"}
      # returns {:error, :connection_refused}

  """
  @spec upload(filename :: String.t(), binary :: binary(), content_type :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def upload(filename, binary, content_type) do
    r2_client().upload(filename, binary, content_type)
  end

  @doc """
  Sends a text message to a WhatsApp phone number.

  Delegates to the configured WhatsApp client adapter.

  ## Examples

      # returns :ok
      # returns {:error, :unauthorized}

  """
  @spec send_message(phone :: String.t(), message :: String.t()) :: :ok | {:error, term()}
  def send_message(phone, message) do
    whatsapp_client().send_message(phone, message)
  end

  @doc """
  Downloads a media file from WhatsApp using its media ID.

  Delegates to the configured WhatsApp client adapter.

  ## Examples

      # returns {:ok, <<binary_data>>}
      # returns {:error, :not_found}

  """
  @spec download_media(media_id :: String.t()) :: {:ok, binary()} | {:error, term()}
  def download_media(media_id) do
    whatsapp_client().download_media(media_id)
  end

  # --- Private adapter resolution ---

  defp r2_client do
    Application.get_env(:diet_project, :r2_client, DietProject.Integrations.R2Client)
  end

  defp whatsapp_client do
    Application.get_env(:diet_project, :whatsapp_client, DietProject.Integrations.WhatsAppClient)
  end
end
