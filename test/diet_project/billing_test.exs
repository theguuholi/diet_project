defmodule DietProject.BillingTest do
  use DietProject.DataCase

  import DietProject.AccountsFixtures
  import DietProject.BillingFixtures

  alias DietProject.Billing
  alias DietProject.Billing.Plan
  alias DietProject.Billing.Subscription

  describe "subscriber?/1" do
    test "returns false for a user with no subscription" do
      user = user_fixture()
      refute Billing.subscriber?(user)
    end

    test "returns true for a user with an active subscription" do
      user = user_fixture()
      plan = plan_fixture()
      subscription_fixture(user, plan, %{status: :active})
      assert Billing.subscriber?(user)
    end

    test "returns true for a user with a trialing subscription" do
      user = user_fixture()
      plan = plan_fixture()
      subscription_fixture(user, plan, %{status: :trialing})
      assert Billing.subscriber?(user)
    end

    test "returns false for a user with a canceled subscription" do
      user = user_fixture()
      plan = plan_fixture()
      subscription_fixture(user, plan, %{status: :canceled})
      refute Billing.subscriber?(user)
    end

    test "returns false for a user with a past_due subscription" do
      user = user_fixture()
      plan = plan_fixture()
      subscription_fixture(user, plan, %{status: :past_due})
      refute Billing.subscriber?(user)
    end
  end

  describe "create_subscription/2" do
    test "creates a subscription with valid attributes" do
      user = user_fixture()
      plan = plan_fixture()

      attrs = %{
        status: :trialing,
        current_period_end: DateTime.utc_now() |> DateTime.add(30, :day),
        external_id: "sub_123"
      }

      assert {:ok, %Subscription{} = sub} = Billing.create_subscription(user, plan, attrs)
      assert sub.user_id == user.id
      assert sub.plan_id == plan.id
      assert sub.status == :trialing
    end

    test "returns error with invalid attributes" do
      user = user_fixture()
      plan = plan_fixture()
      assert {:error, %Ecto.Changeset{}} = Billing.create_subscription(user, plan, %{status: :invalid_status})
    end
  end

  describe "update_subscription_status/2" do
    test "updates the subscription status" do
      user = user_fixture()
      plan = plan_fixture()
      sub = subscription_fixture(user, plan, %{status: :trialing})

      assert {:ok, updated} = Billing.update_subscription_status(sub, :active)
      assert updated.status == :active
    end
  end

  describe "handle_stripe_webhook/1" do
    test "activates subscription on checkout.session.completed" do
      user = user_fixture()
      plan = plan_fixture()
      sub = subscription_fixture(user, plan, %{status: :trialing, external_id: "sub_test_123"})

      event = %{
        "type" => "customer.subscription.updated",
        "data" => %{
          "object" => %{
            "id" => sub.external_id,
            "status" => "active"
          }
        }
      }

      assert {:ok, updated} = Billing.handle_stripe_webhook(event)
      assert updated.status == :active
    end

    test "cancels subscription on customer.subscription.deleted" do
      user = user_fixture()
      plan = plan_fixture()
      sub = subscription_fixture(user, plan, %{status: :active, external_id: "sub_cancel_456"})

      event = %{
        "type" => "customer.subscription.deleted",
        "data" => %{
          "object" => %{
            "id" => sub.external_id,
            "status" => "canceled"
          }
        }
      }

      assert {:ok, updated} = Billing.handle_stripe_webhook(event)
      assert updated.status == :canceled
    end

    test "returns ok on unhandled event type" do
      event = %{"type" => "payment_intent.created", "data" => %{"object" => %{}}}
      assert :ok = Billing.handle_stripe_webhook(event)
    end
  end

  describe "Plans" do
    test "plan_fixture creates a plan" do
      plan = plan_fixture()
      assert %Plan{} = plan
      assert plan.name != nil
    end
  end
end
