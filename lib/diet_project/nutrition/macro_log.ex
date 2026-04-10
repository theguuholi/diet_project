defmodule DietProject.Nutrition.MacroLog do
  @moduledoc """
  Stores the aggregated daily macro totals for a user.

  A `MacroLog` is an upserted summary record that holds the running totals of
  calories, protein, carbohydrates, and fat for a given user on a given calendar
  date. It is recalculated every time a meal is logged or updated and acts as the
  fast-read source for the LiveView dashboard and daily balance feature.

  There is at most one `MacroLog` per `(user_id, date)` pair, enforced by a
  unique database index.

  The `user_id` is set programmatically and must never be cast from user-supplied
  attributes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this log entry to its owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc "The calendar date this log entry covers"
  @type date :: Date.t()

  @typedoc "Total kilocalories consumed on this date"
  @type calories :: float()

  @typedoc "Total grams of protein consumed on this date"
  @type protein_g :: float()

  @typedoc "Total grams of carbohydrates consumed on this date"
  @type carbs_g :: float()

  @typedoc "Total grams of fat consumed on this date"
  @type fat_g :: float()

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          date: date(),
          calories: calories(),
          protein_g: protein_g(),
          carbs_g: carbs_g(),
          fat_g: fat_g()
        }

  schema "macro_logs" do
    field :date, :date
    field :calories, :float, default: 0.0
    field :protein_g, :float, default: 0.0
    field :carbs_g, :float, default: 0.0
    field :fat_g, :float, default: 0.0

    belongs_to :user, DietProject.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a macro log entry.

  Casts `:date`, `:calories`, `:protein_g`, `:carbs_g`, and `:fat_g`.
  Requires `:date`. The `:user_id` must be set on the struct before calling
  this changeset — it is never cast from user-supplied attributes.

  ## Examples

      iex> DietProject.Nutrition.MacroLog.changeset(%DietProject.Nutrition.MacroLog{}, %{})
      |> Map.get(:valid?)
      false

  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(macro_log, attrs) do
    macro_log
    |> cast(attrs, [:date, :calories, :protein_g, :carbs_g, :fat_g])
    |> validate_required([:date])
  end
end
