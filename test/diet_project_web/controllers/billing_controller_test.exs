defmodule DietProjectWeb.BillingControllerTest do
  use DietProjectWeb.ConnCase, async: true

  import DietProject.AccountsFixtures
  import DietProject.BillingFixtures

  describe "POST /webhooks/stripe" do
    test "responds 200 for a valid subscription.updated event", %{conn: conn} do
      user = user_fixture()
      plan = plan_fixture()
      sub = subscription_fixture(user, plan)

      payload = %{
        "type" => "customer.subscription.updated",
        "data" => %{
          "object" => %{
            "id" => sub.external_id,
            "status" => "active"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/stripe", payload)

      assert conn.status == 200
    end

    test "responds 200 for unknown event type", %{conn: conn} do
      payload = %{
        "type" => "charge.succeeded",
        "data" => %{"object" => %{}}
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/stripe", payload)

      assert conn.status == 200
    end

    test "responds 200 for malformed payload", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/stripe", %{})

      assert conn.status == 200
    end

    test "responds 200 when subscription external_id is not found", %{conn: conn} do
      payload = %{
        "type" => "customer.subscription.updated",
        "data" => %{
          "object" => %{
            "id" => "sub_unknown_id",
            "status" => "active"
          }
        }
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/stripe", payload)

      assert conn.status == 200
    end
  end
end
