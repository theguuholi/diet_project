defmodule DietProject.Accounts do
  @moduledoc """
  The Accounts context.

  Manages user registration, authentication, and user profiles. This context
  is the single source of truth for user identity, physical profile data, and
  daily macro targets. It exposes a public API consumed by Oban workers,
  LiveView, and the WhatsApp bot onboarding flow.
  """

  import Ecto.Query, warn: false
  alias DietProject.Repo

  alias DietProject.Accounts.Goals
  alias DietProject.Accounts.MagicToken
  alias DietProject.Accounts.Profile
  alias DietProject.Accounts.User
  alias DietProject.Accounts.UserNotifier
  alias DietProject.Accounts.UserToken

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by phone number (E.164 format).

  ## Examples

      iex> DietProject.Accounts.get_user_by_phone("+5511999999999")
      nil

  """
  @spec get_user_by_phone(phone :: String.t()) :: User.t() | nil
  def get_user_by_phone(phone) when is_binary(phone) do
    Repo.get_by(User, phone: phone)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         multi = user_email_multi(user, email, context),
         {:ok, _} <- Repo.transaction(multi) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    token
    |> UserToken.by_token_and_context_query("session")
    |> Repo.delete_all()

    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- user |> confirm_user_multi() |> Repo.transaction() do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Profile & Goals

  @doc """
  Calculates the Basal Metabolic Rate using the Katch-McArdle formula.

  BMR = 370 + (21.6 × lean_body_mass_kg)
  where lean_body_mass_kg = weight_kg × (1 - body_fat_pct / 100)

  ## Parameters

  - `weight_kg`    — total body weight in kilograms
  - `body_fat_pct` — body fat percentage (0.0–100.0)

  ## Examples

      iex> DietProject.Accounts.calculate_bmr(80.0, 20.0)
      1752.4

      iex> DietProject.Accounts.calculate_bmr(60.0, 15.0)
      1471.6

  """
  @spec calculate_bmr(weight_kg :: float(), body_fat_pct :: float()) :: float()
  def calculate_bmr(weight_kg, body_fat_pct) do
    lean_mass = weight_kg * (1 - body_fat_pct / 100)
    Float.round(370 + 21.6 * lean_mass, 1)
  end

  @doc """
  Calculates the Total Daily Energy Expenditure by multiplying BMR by an
  activity multiplier.

  Multipliers:
  - `:sedentary`    — 1.2
  - `:light`        — 1.375
  - `:moderate`     — 1.55
  - `:very_active`  — 1.725
  - `:extra_active` — 1.9

  ## Parameters

  - `bmr`            — the user's Basal Metabolic Rate in kcal/day
  - `activity_level` — one of the activity level atoms above

  ## Examples

      iex> DietProject.Accounts.calculate_tdee(1752.4, :moderate)
      2716.2

      iex> DietProject.Accounts.calculate_tdee(1752.4, :sedentary)
      2102.9

  """
  @spec calculate_tdee(bmr :: float(), activity_level :: atom()) :: float()
  def calculate_tdee(bmr, activity_level) do
    multiplier = activity_multiplier(activity_level)
    Float.round(bmr * multiplier, 1)
  end

  defp activity_multiplier(:sedentary), do: 1.2
  defp activity_multiplier(:light), do: 1.375
  defp activity_multiplier(:moderate), do: 1.55
  defp activity_multiplier(:very_active), do: 1.725
  defp activity_multiplier(:extra_active), do: 1.9

  @doc """
  Returns the default daily macro targets (protein, carbs, fat) in grams
  based on total calories and the user's dietary goal.

  Caloric splits by goal:
  - `:lose`     — protein 35 %, carbs 35 %, fat 30 %
  - `:maintain` — protein 30 %, carbs 40 %, fat 30 %
  - `:gain`     — protein 30 %, carbs 45 %, fat 25 %

  Energy density: protein 4 kcal/g, carbs 4 kcal/g, fat 9 kcal/g.

  ## Parameters

  - `calories` — the total daily calorie target
  - `goal`     — `:lose`, `:maintain`, or `:gain`

  ## Examples

      iex> DietProject.Accounts.default_macro_targets(2000, :maintain)
      %{calories: 2000, protein_g: 150, carbs_g: 200, fat_g: 67}

      iex> DietProject.Accounts.default_macro_targets(2000, :lose)
      %{calories: 2000, protein_g: 175, carbs_g: 175, fat_g: 67}

  """
  @spec default_macro_targets(calories :: integer(), goal :: atom()) :: map()
  def default_macro_targets(calories, goal) do
    {protein_pct, carbs_pct, fat_pct} = macro_split(goal)

    %{
      calories: calories,
      protein_g: trunc(round(calories * protein_pct / 4)),
      carbs_g: trunc(round(calories * carbs_pct / 4)),
      fat_g: trunc(round(calories * fat_pct / 9))
    }
  end

  defp macro_split(:lose), do: {0.35, 0.35, 0.30}
  defp macro_split(:maintain), do: {0.30, 0.40, 0.30}
  defp macro_split(:gain), do: {0.30, 0.45, 0.25}

  @doc """
  Creates a physical profile for a user.

  The `user_id` is taken from the user struct and set directly — it must not
  appear in the `attrs` map.

  Returns `{:ok, profile}` on success or `{:error, changeset}` on validation
  failure.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "some-uuid"}
      iex> match?({:error, %Ecto.Changeset{}}, DietProject.Accounts.create_profile(user, %{}))
      true

  """
  @spec create_profile(user :: User.t(), attrs :: map()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def create_profile(user, attrs) do
    %Profile{user_id: user.id}
    |> Profile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the profile for the given user, or `nil` if none exists.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "no-profile-uuid"}
      iex> DietProject.Accounts.get_profile(user)
      nil

  """
  @spec get_profile(user :: User.t()) :: Profile.t() | nil
  def get_profile(user) do
    Repo.get_by(Profile, user_id: user.id)
  end

  @doc """
  Updates an existing profile with the given attributes.

  Returns `{:ok, profile}` on success or `{:error, changeset}` on failure.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "some-uuid"}
      iex> match?({:error, %Ecto.Changeset{}}, DietProject.Accounts.update_profile(user, %DietProject.Accounts.Profile{}, %{weight_kg: -1.0}))
      true

  """
  @spec update_profile(user :: User.t(), profile :: Profile.t(), attrs :: map()) ::
          {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(_user, profile, attrs) do
    profile
    |> Profile.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates daily macro targets for a user.

  The `user_id` is taken from the user struct and set directly — it must not
  appear in the `attrs` map.

  Returns `{:ok, goals}` on success or `{:error, changeset}` on failure.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "some-uuid"}
      iex> match?({:error, %Ecto.Changeset{}}, DietProject.Accounts.create_goals(user, %{}))
      true

  """
  @spec create_goals(user :: User.t(), attrs :: map()) ::
          {:ok, Goals.t()} | {:error, Ecto.Changeset.t()}
  def create_goals(user, attrs) do
    %Goals{user_id: user.id}
    |> Goals.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the daily macro targets for the given user, or `nil` if none exist.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "no-goals-uuid"}
      iex> DietProject.Accounts.get_goals(user)
      nil

  """
  @spec get_goals(user :: User.t()) :: Goals.t() | nil
  def get_goals(user) do
    Repo.get_by(Goals, user_id: user.id)
  end

  ## Magic Link Auth

  @doc """
  Generates a magic link token for the given user and returns the raw token
  string to embed in the login URL.

  The hashed token is stored in the database with a 15-minute expiry.

  ## Examples

      iex> user = %DietProject.Accounts.User{id: "some-uuid"}
      iex> token = DietProject.Accounts.generate_magic_link_token(user)
      iex> is_binary(token)
      true

  """
  @spec generate_magic_link_token(user :: User.t()) :: String.t()
  def generate_magic_link_token(user) do
    {raw_token, changeset} = MagicToken.build(user)
    Repo.insert!(changeset)
    raw_token
  end

  @doc """
  Verifies a magic link token, deletes it from the DB if valid, and returns
  the associated user.

  Returns `{:ok, user}` on success, or `{:error, :invalid}` / `{:error, :expired}`
  on failure.

  ## Examples

      iex> DietProject.Accounts.verify_magic_link_token("nonexistent-token")
      {:error, :invalid}

  """
  @spec verify_magic_link_token(raw_token :: String.t()) ::
          {:ok, User.t()} | {:error, :invalid | :expired}
  def verify_magic_link_token(raw_token) do
    hash = MagicToken.hash(raw_token)

    case Repo.get_by(MagicToken, token_hash: hash) do
      nil ->
        {:error, :invalid}

      token ->
        Repo.delete!(token)

        if DateTime.compare(token.expires_at, DateTime.utc_now()) == :gt do
          {:ok, Repo.get!(User, token.user_id)}
        else
          {:error, :expired}
        end
    end
  end
end
