defmodule DietProjectWeb.DashboardLive.MealListComponent do
  @moduledoc """
  LiveComponent that renders the stream-based list of today's meals.

  Accepts a `meals` list assign and manages its own stream for efficient
  DOM updates. Each refresh resets the stream with the latest meal list.
  """

  use DietProjectWeb, :live_component

  @impl true
  def update(%{meals: meals} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> stream(:meals, meals, reset: true)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
      <h2 class="text-lg font-semibold text-gray-800 mb-4">Meals Today</h2>

      <ul id="meals-stream" phx-update="stream" class="space-y-3">
        <li
          :for={{dom_id, meal} <- @streams.meals}
          id={dom_id}
          data-role="meal"
          data-id={meal.id}
          class="flex items-center justify-between rounded-xl bg-gray-50 px-4 py-3"
        >
          <div class="flex flex-col gap-0.5">
            <span class="text-sm font-medium text-gray-800 capitalize">{meal.input_type}</span>
            <span class="text-xs text-gray-400">
              {Calendar.strftime(meal.logged_at, "%H:%M")}
            </span>
          </div>
          <span class="text-xs font-medium text-gray-500">
            {round(Enum.sum(Enum.map(meal.food_items, & &1.calories)))} kcal
          </span>
        </li>
      </ul>

      <p :if={@meals == []} class="text-sm text-gray-400 text-center py-4">
        No meals logged today. Send a message to your WhatsApp bot to start!
      </p>
    </div>
    """
  end
end
