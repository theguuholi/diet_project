defmodule DietProject.Bot.ConversationState do
  @moduledoc """
  Represents the current FSM state for a user's WhatsApp bot conversation.

  Each user has at most one `ConversationState` record. It persists the
  current FSM step (`:idle`, `:collecting_name`, etc.) and a `context` map
  that accumulates user-provided data (name, weight, height, etc.) as the
  onboarding flow progresses. This allows the bot to resume mid-flow after
  a server restart without losing data.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_states [
    :idle,
    :collecting_name,
    :collecting_weight,
    :collecting_height,
    :collecting_body_fat,
    :collecting_goal,
    :collecting_activity,
    :awaiting_confirmation
  ]

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key linking this state to its owner"
  @type user_id :: Ecto.UUID.t()

  @typedoc """
  The current step in the WhatsApp onboarding/confirmation FSM.
  - `:idle`                  — waiting for user to start a flow
  - `:collecting_name`       — asked for the user's name
  - `:collecting_weight`     — asked for weight in kg
  - `:collecting_height`     — asked for height in cm
  - `:collecting_body_fat`   — asked for body fat percentage
  - `:collecting_goal`       — asked for goal (lose/maintain/gain)
  - `:collecting_activity`   — asked for activity level
  - `:awaiting_confirmation`  — presented AI-parsed food items, waiting for yes/no
  """
  @type state ::
          :idle
          | :collecting_name
          | :collecting_weight
          | :collecting_height
          | :collecting_body_fat
          | :collecting_goal
          | :collecting_activity
          | :awaiting_confirmation

  @typedoc "Accumulated conversation data (name, weight, height, food_data, etc.)"
  @type context :: map()

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          state: state(),
          context: context()
        }

  schema "conversation_states" do
    field :state, Ecto.Enum, values: @valid_states, default: :idle
    field :context, :map, default: %{}

    belongs_to :user, DietProject.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a conversation state.

  Casts `state` and `context` fields. `user_id` is set programmatically and
  must not be included in `attrs`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(conversation_state, attrs) do
    conversation_state
    |> cast(attrs, [:state, :context])
    |> validate_required([:state])
  end
end
