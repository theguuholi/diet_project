defmodule DietProject.Integrations.R2Client do
  @moduledoc """
  Cloudflare R2 object storage client.

  Uploads media files (meal photos, audio) to Cloudflare R2 using the
  ExAws S3-compatible API. All uploads from the application flow through
  this module, giving a single point of control for retry logic, URL
  construction, and Mox stubbing in tests.

  Implements `DietProject.Integrations.R2ClientBehaviour`.

  ## Required environment variables

  - `CLOUDFLARE_R2_BUCKET` — the R2 bucket name
  - `CLOUDFLARE_R2_PUBLIC_URL` — base public URL (e.g. `https://cdn.example.com`)
  - `AWS_ACCESS_KEY_ID` — R2 access key ID
  - `AWS_SECRET_ACCESS_KEY` — R2 secret access key
  - `CLOUDFLARE_ACCOUNT_ID` — used to build the R2 endpoint URL
  """

  @behaviour DietProject.Integrations.R2ClientBehaviour

  @doc """
  Uploads a binary to Cloudflare R2 and returns the public URL.

  ## Examples

      # In production (not for doctests — hits real R2):
      # {:ok, "https://cdn.example.com/filename.jpg"}

  """
  @spec upload(filename :: String.t(), binary :: binary(), content_type :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  @impl DietProject.Integrations.R2ClientBehaviour
  def upload(filename, binary, content_type) do
    bucket = System.fetch_env!("CLOUDFLARE_R2_BUCKET")
    public_url = System.fetch_env!("CLOUDFLARE_R2_PUBLIC_URL")
    account_id = System.fetch_env!("CLOUDFLARE_ACCOUNT_ID")

    config =
      ExAws.Config.new(:s3,
        access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
        scheme: "https://",
        host: "#{account_id}.r2.cloudflarestorage.com",
        region: "auto"
      )

    operation =
      ExAws.S3.put_object(bucket, filename, binary,
        content_type: content_type,
        acl: :public_read
      )

    case ExAws.request(operation, config) do
      {:ok, _} -> {:ok, "#{public_url}/#{filename}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
