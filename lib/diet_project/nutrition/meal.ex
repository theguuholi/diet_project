defmodule DietProject.Nutrition.Meal do
  @moduledoc """
  Represents a single meal logging event submitted by a user.

  A `Meal` is created whenever a user logs food via WhatsApp — whether by
  text, photo, or audio. It acts as the parent record for one or more
  `FoodItem` entries and tracks which input method was used and whether
  the user has confirmed the AI-parsed result.

  The `user_id` is set programmatically from the authenticated context and
  must never be cast through user-supplied attributes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this meal to its owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc """
  How the meal was submitted.
  - `:text`  — free-text WhatsApp message
  - `:photo` — image sent via WhatsApp, analysed by Claude vision
  - `:audio` — voice message, transcribed by Whisper then analysed by Claude
  """
  @type input_type :: :text | :photo | :audio

  @typedoc "UTC timestamp of when the meal was logged"
  @type logged_at :: DateTime.t()

  @typedoc """
  Optional raw input text provided by the user or transcribed from audio/photo.
  Nil for photo and audio inputs before processing.
  """
  @type raw_input :: String.t() | nil

  @typedoc """
  Whether the user has confirmed the AI-parsed food items.
  Always `true` for text input. Starts `false` for photo/audio until
  the user replies to the confirmation prompt.
  """
  @type confirmed :: boolean()

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          input_type: input_type(),
          logged_at: logged_at(),
          raw_input: raw_input(),
          confirmed: confirmed()
        }

  schema "meals" do
    field :logged_at, :utc_datetime
    field :input_type, Ecto.Enum, values: [:text, :photo, :audio]
    field :raw_input, :string
    field :confirmed, :boolean, default: false

    belongs_to :user, DietProject.Accounts.User
    has_many :food_items, DietProject.Nutrition.FoodItem

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating or updating a meal.

  Casts `:logged_at`, `:input_type`, `:raw_input`, and `:confirmed`.
  Requires `:logged_at` and `:input_type`. The `:user_id` must be set
  on the struct before calling this changeset — it is never cast from
  user-supplied attributes.

  ## Examples

      iex> DietProject.Nutrition.Meal.changeset(%DietProject.Nutrition.Meal{}, %{})
      |> Map.get(:valid?)
      false

  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(meal, attrs) do
    meal
    |> cast(attrs, [:logged_at, :input_type, :raw_input, :confirmed])
    |> validate_required([:logged_at, :input_type])
  end
end
