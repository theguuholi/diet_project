defmodule DietProjectWeb.DashboardLive.Index do
  @moduledoc """
  LiveView for the user's daily nutrition dashboard.

  Displays the daily macro summary, meal list, and weekly calorie chart.
  Subscribes to PubSub meal events when the WebSocket is connected so
  the dashboard updates in real time as new meals are logged via WhatsApp.
  """

  use DietProjectWeb, :live_view

  alias DietProject.Accounts
  alias DietProject.Nutrition

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    today = Date.utc_today()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(DietProject.PubSub, "user:#{user.id}:meal_logged")
    end

    summary = Nutrition.daily_summary(user.id, today)
    goals = Accounts.get_goals(user)
    meals = Nutrition.list_meals(user.id, limit: 20)

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:today, today)
      |> assign(:summary, summary)
      |> assign(:goals, goals)
      |> assign(:meals, meals)

    {:ok, socket}
  end

  @impl true
  def handle_info({:meal_logged, _meal}, socket) do
    user = socket.assigns.current_user
    today = socket.assigns.today
    summary = Nutrition.daily_summary(user.id, today)
    meals = Nutrition.list_meals(user.id, limit: 20)

    socket =
      socket
      |> assign(:summary, summary)
      |> assign(:meals, meals)

    {:noreply, socket}
  end
end
