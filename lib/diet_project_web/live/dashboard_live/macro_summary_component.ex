defmodule DietProjectWeb.DashboardLive.MacroSummaryComponent do
  @moduledoc """
  LiveComponent that displays the daily macro totals with progress bars.

  Shows calories, protein, carbs, and fat consumed today versus the user's
  goals. Progress bars fill proportionally from 0–100% and turn red when
  a macro exceeds the daily target.
  """

  use DietProjectWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-2xl border border-gray-200 bg-white p-6 shadow-sm space-y-4">
      <h2 class="text-lg font-semibold text-gray-800">Today's Macros</h2>

      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <.macro_card
          label="Calories"
          value={round_val(@summary[:calories])}
          unit="kcal"
          goal={goal_val(@goals, :calories)}
        />
        <.macro_card
          label="Protein"
          value={round_val(@summary[:protein_g])}
          unit="g"
          goal={goal_val(@goals, :protein_g)}
        />
        <.macro_card
          label="Carbs"
          value={round_val(@summary[:carbs_g])}
          unit="g"
          goal={goal_val(@goals, :carbs_g)}
        />
        <.macro_card
          label="Fat"
          value={round_val(@summary[:fat_g])}
          unit="g"
          goal={goal_val(@goals, :fat_g)}
        />
      </div>
    </div>
    """
  end

  defp macro_card(assigns) do
    pct =
      if assigns.goal && assigns.goal > 0,
        do: min(round(assigns.value / assigns.goal * 100), 100),
        else: 0

    over? = assigns.goal && assigns.goal > 0 && assigns.value > assigns.goal
    assigns = assign(assigns, pct: pct, over?: over?)

    ~H"""
    <article class="flex flex-col gap-1">
      <span class="text-xs font-medium text-gray-500 uppercase tracking-wide">{@label}</span>
      <span class="text-xl font-bold text-gray-900">
        {@value} <span class="text-sm font-normal text-gray-400">{@unit}</span>
      </span>
      <%= if @goal do %>
        <span class="text-xs text-gray-400">of {@goal} {@unit}</span>
        <div class="h-1.5 w-full rounded-full bg-gray-100 overflow-hidden">
          <div
            class={[
              "h-full rounded-full transition-all",
              if(@over?, do: "bg-red-500", else: "bg-emerald-500")
            ]}
            style={"width: #{@pct}%"}
          >
          </div>
        </div>
      <% end %>
    </article>
    """
  end

  defp round_val(nil), do: 0
  defp round_val(v) when is_float(v), do: round(v)
  defp round_val(v), do: v

  defp goal_val(nil, _key), do: nil
  defp goal_val(goals, key), do: Map.get(goals, key)
end
