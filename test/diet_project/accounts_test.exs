defmodule DietProject.AccountsTest do
  use DietProject.DataCase

  import DietProject.AccountsFixtures

  alias DietProject.Accounts
  alias DietProject.Accounts.User
  alias DietProject.Accounts.UserToken

  doctest DietProject.Accounts, only: [calculate_bmr: 2, calculate_tdee: 2, default_macro_targets: 2]

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      attrs = valid_user_attributes(email: email)
      {:ok, user} = Accounts.register_user(attrs)
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} = Accounts.apply_user_email(user, valid_user_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture()
      password = valid_user_password()

      {:error, changeset} = Accounts.apply_user_email(user, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()
      {:ok, user} = Accounts.apply_user_email(user, valid_user_password(), %{email: email})
      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert Accounts.update_user_email(user, token) == :ok
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at != user.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{password: valid_user_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "get_user_by_phone/1" do
    test "does not return the user if the phone does not exist" do
      refute Accounts.get_user_by_phone("+5511999999999")
    end

    test "returns the user if the phone exists" do
      phone = unique_user_phone()
      %{id: id} = user_fixture(%{phone: phone})
      assert %User{id: ^id} = Accounts.get_user_by_phone(phone)
    end
  end

  describe "user phone validation" do
    test "accepts valid E.164 phone numbers" do
      valid_attrs = valid_user_attributes(%{phone: "+5511999999999"})
      assert {:ok, _user} = Accounts.register_user(valid_attrs)
    end

    test "accepts nil phone (phone is optional)" do
      valid_attrs = valid_user_attributes(%{phone: nil})
      assert {:ok, _user} = Accounts.register_user(valid_attrs)
    end

    test "rejects phone numbers without leading +" do
      attrs = valid_user_attributes(%{phone: "5511999999999"})
      {:error, changeset} = Accounts.register_user(attrs)
      assert "must start with + and contain only digits" in errors_on(changeset).phone
    end

    test "rejects phone numbers with letters" do
      attrs = valid_user_attributes(%{phone: "+551199ABCDEF"})
      {:error, changeset} = Accounts.register_user(attrs)
      assert "must start with + and contain only digits" in errors_on(changeset).phone
    end

    test "enforces uniqueness of phone" do
      phone = unique_user_phone()
      user_fixture(%{phone: phone})
      attrs = valid_user_attributes(%{phone: phone})
      {:error, changeset} = Accounts.register_user(attrs)
      assert "has already been taken" in errors_on(changeset).phone
    end
  end

  describe "calculate_bmr/2" do
    test "calculates BMR correctly for 80kg at 20% body fat" do
      assert Accounts.calculate_bmr(80.0, 20.0) == 1752.4
    end

    test "calculates BMR correctly for 60kg at 15% body fat" do
      assert Accounts.calculate_bmr(60.0, 15.0) == 1471.6
    end

    test "calculates BMR with 0% body fat (all lean mass)" do
      assert Accounts.calculate_bmr(70.0, 0.0) == Float.round(370 + 21.6 * 70.0, 1)
    end
  end

  describe "calculate_tdee/2" do
    test "sedentary multiplier is 1.2" do
      bmr = 1752.4
      assert Accounts.calculate_tdee(bmr, :sedentary) == Float.round(bmr * 1.2, 1)
    end

    test "light multiplier is 1.375" do
      bmr = 1752.4
      assert Accounts.calculate_tdee(bmr, :light) == Float.round(bmr * 1.375, 1)
    end

    test "moderate multiplier is 1.55" do
      bmr = 1752.4
      assert Accounts.calculate_tdee(bmr, :moderate) == Float.round(bmr * 1.55, 1)
    end

    test "very_active multiplier is 1.725" do
      bmr = 1752.4
      assert Accounts.calculate_tdee(bmr, :very_active) == Float.round(bmr * 1.725, 1)
    end

    test "extra_active multiplier is 1.9" do
      bmr = 1752.4
      assert Accounts.calculate_tdee(bmr, :extra_active) == Float.round(bmr * 1.9, 1)
    end
  end

  describe "default_macro_targets/2" do
    test "lose goal splits 35% protein, 35% carbs, 30% fat" do
      targets = Accounts.default_macro_targets(2000, :lose)
      assert targets.protein_g == trunc(round(2000 * 0.35 / 4))
      assert targets.carbs_g == trunc(round(2000 * 0.35 / 4))
      assert targets.fat_g == trunc(round(2000 * 0.30 / 9))
    end

    test "maintain goal splits 30% protein, 40% carbs, 30% fat" do
      targets = Accounts.default_macro_targets(2500, :maintain)
      assert targets.protein_g == trunc(round(2500 * 0.30 / 4))
      assert targets.carbs_g == trunc(round(2500 * 0.40 / 4))
      assert targets.fat_g == trunc(round(2500 * 0.30 / 9))
    end

    test "gain goal splits 30% protein, 45% carbs, 25% fat" do
      targets = Accounts.default_macro_targets(3000, :gain)
      assert targets.protein_g == trunc(round(3000 * 0.30 / 4))
      assert targets.carbs_g == trunc(round(3000 * 0.45 / 4))
      assert targets.fat_g == trunc(round(3000 * 0.25 / 9))
    end

    test "returns a map with calories key equal to the input" do
      targets = Accounts.default_macro_targets(2000, :maintain)
      assert targets.calories == 2000
    end
  end

  describe "create_profile/2" do
    setup do
      %{user: user_fixture()}
    end

    test "creates a profile with valid attributes", %{user: user} do
      attrs = %{
        weight_kg: 80.0,
        height_cm: 175.0,
        body_fat_pct: 20.0,
        activity_level: :moderate,
        goal: :maintain,
        bmr: 1748.8,
        tdee: 2710.6
      }

      assert {:ok, profile} = Accounts.create_profile(user, attrs)
      assert profile.user_id == user.id
      assert profile.weight_kg == 80.0
      assert profile.activity_level == :moderate
      assert profile.goal == :maintain
    end

    test "requires all mandatory fields", %{user: user} do
      {:error, changeset} = Accounts.create_profile(user, %{})

      assert %{
               weight_kg: ["can't be blank"],
               height_cm: ["can't be blank"],
               body_fat_pct: ["can't be blank"],
               activity_level: ["can't be blank"],
               goal: ["can't be blank"],
               bmr: ["can't be blank"],
               tdee: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects non-positive weight_kg", %{user: user} do
      attrs = %{
        weight_kg: -1.0,
        height_cm: 175.0,
        body_fat_pct: 20.0,
        activity_level: :moderate,
        goal: :maintain,
        bmr: 1748.8,
        tdee: 2710.6
      }

      {:error, changeset} = Accounts.create_profile(user, attrs)
      assert "must be greater than 0" in errors_on(changeset).weight_kg
    end

    test "rejects body_fat_pct above 100", %{user: user} do
      attrs = %{
        weight_kg: 80.0,
        height_cm: 175.0,
        body_fat_pct: 101.0,
        activity_level: :moderate,
        goal: :maintain,
        bmr: 1748.8,
        tdee: 2710.6
      }

      {:error, changeset} = Accounts.create_profile(user, attrs)
      assert "must be less than or equal to 100.0" in errors_on(changeset).body_fat_pct
    end

    test "rejects invalid activity_level enum", %{user: user} do
      attrs = %{
        weight_kg: 80.0,
        height_cm: 175.0,
        body_fat_pct: 20.0,
        activity_level: :invalid,
        goal: :maintain,
        bmr: 1748.8,
        tdee: 2710.6
      }

      {:error, changeset} = Accounts.create_profile(user, attrs)
      assert "is invalid" in errors_on(changeset).activity_level
    end

    test "rejects invalid goal enum", %{user: user} do
      attrs = %{
        weight_kg: 80.0,
        height_cm: 175.0,
        body_fat_pct: 20.0,
        activity_level: :moderate,
        goal: :invalid,
        bmr: 1748.8,
        tdee: 2710.6
      }

      {:error, changeset} = Accounts.create_profile(user, attrs)
      assert "is invalid" in errors_on(changeset).goal
    end
  end

  describe "get_profile/1" do
    setup do
      %{user: user_fixture()}
    end

    test "returns nil when user has no profile", %{user: user} do
      assert Accounts.get_profile(user) == nil
    end

    test "returns the profile when it exists", %{user: user} do
      profile = profile_fixture(user)
      fetched = Accounts.get_profile(user)
      assert fetched.id == profile.id
      assert fetched.user_id == user.id
    end
  end

  describe "update_profile/3" do
    setup do
      user = user_fixture()
      profile = profile_fixture(user)
      %{user: user, profile: profile}
    end

    test "updates the profile with valid attributes", %{user: user, profile: profile} do
      {:ok, updated} = Accounts.update_profile(user, profile, %{weight_kg: 75.0, bmr: 1680.0})
      assert updated.weight_kg == 75.0
      assert updated.bmr == 1680.0
    end

    test "returns error changeset for invalid attributes", %{user: user, profile: profile} do
      {:error, changeset} =
        Accounts.update_profile(user, profile, %{weight_kg: -5.0})

      assert "must be greater than 0" in errors_on(changeset).weight_kg
    end
  end

  describe "create_goals/2" do
    setup do
      %{user: user_fixture()}
    end

    test "creates goals with valid attributes", %{user: user} do
      attrs = %{calories: 2000, protein_g: 150, carbs_g: 200, fat_g: 67}
      assert {:ok, goals} = Accounts.create_goals(user, attrs)
      assert goals.user_id == user.id
      assert goals.calories == 2000
      assert goals.protein_g == 150
    end

    test "requires all mandatory fields", %{user: user} do
      {:error, changeset} = Accounts.create_goals(user, %{})

      assert %{
               calories: ["can't be blank"],
               protein_g: ["can't be blank"],
               carbs_g: ["can't be blank"],
               fat_g: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects non-positive calories", %{user: user} do
      attrs = %{calories: -100, protein_g: 150, carbs_g: 200, fat_g: 67}
      {:error, changeset} = Accounts.create_goals(user, attrs)
      assert "must be greater than 0" in errors_on(changeset).calories
    end

    test "rejects non-positive protein_g", %{user: user} do
      attrs = %{calories: 2000, protein_g: 0, carbs_g: 200, fat_g: 67}
      {:error, changeset} = Accounts.create_goals(user, attrs)
      assert "must be greater than 0" in errors_on(changeset).protein_g
    end
  end

  describe "get_goals/1" do
    setup do
      %{user: user_fixture()}
    end

    test "returns nil when user has no goals", %{user: user} do
      assert Accounts.get_goals(user) == nil
    end

    test "returns goals when they exist", %{user: user} do
      goals = goals_fixture(user)
      fetched = Accounts.get_goals(user)
      assert fetched.id == goals.id
      assert fetched.user_id == user.id
    end
  end
end
