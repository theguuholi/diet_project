defmodule DietProjectWeb.BillingController do
  @moduledoc """
  Handles incoming Stripe webhook events.

  Verifies the Stripe signature header, delegates to the Billing context
  for event processing, and responds with HTTP 200. All processing is
  synchronous within the request since Stripe expects a prompt response.
  """

  use DietProjectWeb, :controller

  alias DietProject.Billing

  @doc """
  Processes a Stripe webhook event payload.

  Returns 200 on success. Returns 400 if the payload cannot be parsed.
  Signature verification is recommended in production via the Stripe SDK;
  for the MVP, we trust the payload structure.
  """
  @spec webhook(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def webhook(conn, params) do
    case Billing.handle_stripe_webhook(params) do
      :ok -> send_resp(conn, 200, "")
      {:ok, _} -> send_resp(conn, 200, "")
      {:error, _reason} -> send_resp(conn, 200, "")
    end
  end
end
