defmodule DietProjectWeb.DashboardLive.WeeklyChartComponent do
  @moduledoc """
  LiveComponent that renders a weekly calorie chart using Chart.js via a Phoenix hook.

  Fetches the last 7 days of macro logs for the user and serialises them as
  JSON in a `data-chart-data` attribute. The `WeeklyChart` JS hook reads this
  attribute on mount and on update to render/refresh the chart.
  """

  use DietProjectWeb, :live_component

  alias DietProject.Nutrition

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{user_id: user_id} = assigns, socket) do
    today = Date.utc_today()
    chart_data = build_chart_data(user_id, today)

    socket =
      socket
      |> assign(assigns)
      |> assign(:chart_data, chart_data)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
      <h2 class="text-lg font-semibold text-gray-800 mb-4">This Week</h2>
      <canvas
        id="weekly-chart-canvas"
        phx-hook="WeeklyChart"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@chart_data)}
        class="w-full"
        style="max-height: 200px;"
        aria-label="Weekly calorie chart"
        role="img"
      >
      </canvas>
    </div>
    """
  end

  defp build_chart_data(user_id, today) do
    dates = Enum.map(6..0//-1, &Date.add(today, -&1))

    {labels, data} =
      Enum.map_reduce(dates, [], fn date, acc ->
        summary = Nutrition.daily_summary(user_id, date)
        label = Calendar.strftime(date, "%a")
        {label, [round(summary[:calories]) | acc]}
      end)

    %{
      labels: labels,
      datasets: [
        %{
          label: "Calories",
          data: Enum.reverse(data),
          backgroundColor: "rgba(16, 185, 129, 0.2)",
          borderColor: "rgba(16, 185, 129, 1)",
          borderWidth: 2,
          tension: 0.4
        }
      ]
    }
  end
end
