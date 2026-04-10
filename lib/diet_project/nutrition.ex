defmodule DietProject.Nutrition do
  @moduledoc """
  Manages meal logging, food item storage, and daily macro aggregation.

  This context is the single source of truth for everything a user has eaten.
  It owns the `Meal`, `FoodItem`, and `MacroLog` schemas and exposes a public
  API consumed by Oban workers and the LiveView dashboard.

  Contexts do not call each other directly — cross-context communication
  happens via `Phoenix.PubSub` events or Oban jobs.
  """

  import Ecto.Query, warn: false

  alias DietProject.Nutrition.FoodItem
  alias DietProject.Nutrition.MacroLog
  alias DietProject.Nutrition.Meal
  alias DietProject.Repo

  @doc """
  Creates a meal with associated food items in a single database transaction.

  The `user_id` argument is set directly on the struct and is never taken from
  `attrs`. If `:logged_at` is not present in `attrs`, it defaults to the current
  UTC time.

  Returns `{:ok, meal}` on success with `:food_items` preloaded.
  Returns `{:error, changeset}` if the meal or any food item fails validation.

  ## Examples

      iex> DietProject.Nutrition.create_meal("non-existent-uuid", %{})
      |> elem(0)
      :error

  """
  @spec create_meal(user_id :: String.t(), attrs :: map()) ::
          {:ok, Meal.t()} | {:error, Ecto.Changeset.t()}
  def create_meal(user_id, attrs) do
    logged_at = Map.get(attrs, :logged_at, DateTime.utc_now() |> DateTime.truncate(:second))
    meal_attrs = Map.put(attrs, :logged_at, logged_at)
    food_item_attrs_list = Map.get(attrs, :food_items, [])

    meal_changeset =
      %Meal{user_id: user_id}
      |> Meal.changeset(meal_attrs)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:meal, meal_changeset)

    multi =
      food_item_attrs_list
      |> Enum.with_index()
      |> Enum.reduce(multi, fn {item_attrs, index}, acc ->
        Ecto.Multi.run(acc, {:food_item, index}, fn _repo, %{meal: meal} ->
          %FoodItem{meal_id: meal.id}
          |> FoodItem.changeset(item_attrs)
          |> Repo.insert()
        end)
      end)

    case Repo.transaction(multi) do
      {:ok, %{meal: meal}} ->
        {:ok, Repo.preload(meal, :food_items)}

      {:error, :meal, changeset, _changes} ->
        {:error, changeset}

      {:error, _food_item_key, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Aggregates macro totals from food items for the given user on the given date
  and upserts the result into `macro_logs`.

  If no meals exist for that date, the macro log is set to all zeroes.

  Returns `{:ok, macro_log}` on success.

  ## Examples

      iex> DietProject.Nutrition.update_macro_log("non-existent-uuid", ~D[2020-01-01])
      |> elem(0)
      :ok

  """
  @spec update_macro_log(user_id :: String.t(), date :: Date.t()) :: {:ok, MacroLog.t()}
  def update_macro_log(user_id, date) do
    totals =
      from(fi in FoodItem,
        join: m in Meal,
        on: fi.meal_id == m.id,
        where: m.user_id == ^user_id,
        where: fragment("DATE(?)", m.logged_at) == ^date,
        select: %{
          calories: coalesce(sum(fi.calories), 0.0),
          protein_g: coalesce(sum(fi.protein_g), 0.0),
          carbs_g: coalesce(sum(fi.carbs_g), 0.0),
          fat_g: coalesce(sum(fi.fat_g), 0.0)
        }
      )
      |> Repo.one()
      |> case do
        nil ->
          %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}

        result ->
          result
      end

    attrs = Map.put(totals, :date, date)

    %MacroLog{user_id: user_id}
    |> MacroLog.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:calories, :protein_g, :carbs_g, :fat_g]},
      conflict_target: [:user_id, :date]
    )
  end

  @doc """
  Returns the aggregated macro totals for a user on a given date.

  Reads from the `macro_logs` table. Returns a map with zeroed float values
  when no log exists for that date.

  ## Examples

      iex> DietProject.Nutrition.daily_summary("non-existent-uuid", ~D[2020-01-01])
      %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}

  """
  @spec daily_summary(user_id :: String.t(), date :: Date.t()) :: map()
  def daily_summary(user_id, date) do
    case Repo.get_by(MacroLog, user_id: user_id, date: date) do
      nil ->
        %{calories: 0.0, protein_g: 0.0, carbs_g: 0.0, fat_g: 0.0}

      log ->
        %{
          calories: log.calories,
          protein_g: log.protein_g,
          carbs_g: log.carbs_g,
          fat_g: log.fat_g
        }
    end
  end

  @doc """
  Returns the number of meals logged by the user today (UTC).

  ## Examples

      iex> DietProject.Nutrition.meal_count_today("non-existent-uuid")
      0

  """
  @spec meal_count_today(user_id :: String.t()) :: non_neg_integer()
  def meal_count_today(user_id) do
    today = Date.utc_today()

    from(m in Meal,
      where: m.user_id == ^user_id,
      where: fragment("DATE(?)", m.logged_at) == ^today,
      select: count(m.id)
    )
    |> Repo.one()
  end

  @doc """
  Lists meals for a user, ordered by `logged_at` descending (most recent first).

  Food items are preloaded for every meal. Supports `:limit` (default 20) and
  `:offset` (default 0) options for pagination.

  ## Examples

      iex> DietProject.Nutrition.list_meals("non-existent-uuid")
      []

  """
  @spec list_meals(user_id :: String.t(), opts :: keyword()) :: [Meal.t()]
  def list_meals(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)

    from(m in Meal,
      where: m.user_id == ^user_id,
      order_by: [desc: m.logged_at],
      limit: ^limit,
      offset: ^offset,
      preload: :food_items
    )
    |> Repo.all()
  end

  @doc """
  Broadcasts a `:meal_logged` event to the user's PubSub topic.

  The event is published to `"user:<user_id>:meal_logged"` with the payload
  `{:meal_logged, meal}`. LiveView processes subscribe to this topic to
  update the dashboard in real time.

  Always returns `:ok`.

  ## Examples

      iex> DietProject.Nutrition.broadcast_meal_logged("any-user-id", %DietProject.Nutrition.Meal{})
      :ok

  """
  @spec broadcast_meal_logged(user_id :: String.t(), meal :: Meal.t()) :: :ok
  def broadcast_meal_logged(user_id, meal) do
    Phoenix.PubSub.broadcast(
      DietProject.PubSub,
      "user:#{user_id}:meal_logged",
      {:meal_logged, meal}
    )
  end
end
