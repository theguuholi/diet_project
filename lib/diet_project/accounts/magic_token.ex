defmodule DietProject.Accounts.MagicToken do
  @moduledoc """
  Represents a single-use magic link token for passwordless dashboard login.

  When a user requests a magic link, a token is generated, hashed, and stored
  here. The raw token is embedded in the login URL sent to the user. On click,
  the URL token is hashed and looked up; if found and unexpired, the token
  record is deleted and the user is logged in.

  Tokens expire after 15 minutes to limit the attack window.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @token_ttl_minutes 15

  @typedoc "Internal UUID primary key"
  @type id :: Ecto.UUID.t()

  @typedoc "Foreign key to the user this token belongs to"
  @type user_id :: Ecto.UUID.t()

  @typedoc "SHA-256 hash of the raw URL token — what is stored in the DB"
  @type token_hash :: String.t()

  @typedoc "UTC datetime after which the token is no longer valid"
  @type expires_at :: DateTime.t()

  @type t :: %__MODULE__{
          id: id(),
          user_id: user_id(),
          token_hash: token_hash(),
          expires_at: expires_at()
        }

  schema "magic_tokens" do
    field :token_hash, :string
    field :expires_at, :utc_datetime

    belongs_to :user, DietProject.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a raw token string and returns a changeset to insert the hashed record.

  Returns `{raw_token, changeset}` where `raw_token` is embedded in the URL
  and `changeset` is ready to be inserted into the DB.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "some-uuid"}
      iex> {token, changeset} = DietProject.Accounts.MagicToken.build(user)
      iex> is_binary(token) and changeset.valid?
      true

  """
  @spec build(user :: DietProject.Accounts.User.t()) :: {String.t(), Ecto.Changeset.t()}
  def build(user) do
    raw_bytes = :crypto.strong_rand_bytes(32)
    raw_token = Base.url_encode64(raw_bytes, padding: false)
    token_hash = hash(raw_token)
    ttl_seconds = @token_ttl_minutes * 60

    expires_at =
      DateTime.utc_now() |> DateTime.add(ttl_seconds, :second) |> DateTime.truncate(:second)

    changeset =
      %__MODULE__{user_id: user.id}
      |> cast(%{token_hash: token_hash, expires_at: expires_at}, [:token_hash, :expires_at])
      |> validate_required([:token_hash, :expires_at])

    {raw_token, changeset}
  end

  @doc """
  Hashes a raw token string using SHA-256 for storage or lookup.

  ## Examples

      iex> is_binary(DietProject.Accounts.MagicToken.hash("some-token"))
      true

  """
  @spec hash(raw_token :: String.t()) :: String.t()
  def hash(raw_token) do
    hash_bytes = :crypto.hash(:sha256, raw_token)
    Base.encode16(hash_bytes, case: :lower)
  end
end
