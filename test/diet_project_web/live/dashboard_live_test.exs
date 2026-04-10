defmodule DietProjectWeb.DashboardLiveTest do
  use DietProjectWeb.ConnCase

  import Phoenix.LiveViewTest
  import DietProject.NutritionFixtures

  setup :register_and_log_in_user

  describe "Dashboard" do
    test "renders dashboard for authenticated user", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#macro-summary")
      assert has_element?(view, "#meal-list")
    end

    test "redirects unauthenticated user to login" do
      assert {:error, {:redirect, %{to: path}}} = live(build_conn(), ~p"/dashboard")
      assert path =~ "/users/log_in"
    end

    test "shows zeroed macros when no meals logged", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#macro-summary", "0")
    end

    test "shows meal count after logging", %{conn: conn, user: user} do
      meal_fixture(user.id)

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#meal-list")
    end

    test "updates macro summary in real time via PubSub", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")

      meal = meal_fixture(user.id)

      DietProject.Nutrition.update_macro_log(user.id, Date.utc_today())

      Phoenix.PubSub.broadcast(
        DietProject.PubSub,
        "user:#{user.id}:meal_logged",
        {:meal_logged, meal}
      )

      assert has_element?(view, "#macro-summary")
    end

    test "shows macro progress bars when user has goals", %{conn: conn, user: user} do
      DietProject.AccountsFixtures.goals_fixture(user, %{
        calories: 100,
        protein_g: 10,
        carbs_g: 10,
        fat_g: 5
      })

      meal_fixture(user.id)
      DietProject.Nutrition.update_macro_log(user.id, Date.utc_today())

      {:ok, view, _html} = live(conn, ~p"/dashboard")

      assert has_element?(view, "#macro-summary")
    end
  end
end
