defmodule DietProject.Integrations.R2ClientBehaviour do
  @moduledoc """
  Behaviour contract for the Cloudflare R2 object storage client.

  Defines the interface that both the production `R2Client` and the
  `R2ClientMock` must implement. Tests never perform real S3/R2 uploads.
  """

  @doc """
  Uploads a binary to Cloudflare R2 and returns the public URL.

  - `filename` — the object key / filename in the bucket
  - `binary` — raw file bytes
  - `content_type` — MIME type string (e.g. `"image/jpeg"`, `"audio/ogg"`)
  """
  @callback upload(filename :: String.t(), binary :: binary(), content_type :: String.t()) ::
              {:ok, url :: String.t()} | {:error, term()}
end
