defmodule DietProject.BillingFixtures do
  @moduledoc """
  Test helpers for creating Billing entities: Plan and Subscription.
  """

  alias DietProject.Billing

  def plan_fixture(attrs \\ %{}) do
    {:ok, plan} =
      attrs
      |> Enum.into(%{
        name: "Pro",
        price_cents: 1990,
        interval: :monthly
      })
      |> Billing.create_plan()

    plan
  end

  def subscription_fixture(user, plan, attrs \\ %{}) do
    {:ok, sub} =
      attrs
      |> Enum.into(%{
        status: :active,
        current_period_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second),
        external_id: "sub_#{System.unique_integer([:positive])}"
      })
      |> then(&Billing.create_subscription(user, plan, &1))

    sub
  end
end
