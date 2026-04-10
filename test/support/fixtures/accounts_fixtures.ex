defmodule DietProject.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `DietProject.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def unique_user_phone do
    n = :rand.uniform(9_999_999)
    suffix = n |> Integer.to_string() |> String.pad_leading(7, "0")
    "+551199#{suffix}"
  end

  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> DietProject.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def profile_fixture(user, attrs \\ %{}) do
    {:ok, profile} =
      attrs
      |> Enum.into(%{
        weight_kg: 80.0,
        height_cm: 175.0,
        body_fat_pct: 20.0,
        activity_level: :moderate,
        goal: :maintain,
        bmr: 1752.4,
        tdee: 2716.2
      })
      |> then(&DietProject.Accounts.create_profile(user, &1))

    profile
  end

  def goals_fixture(user, attrs \\ %{}) do
    {:ok, goals} =
      attrs
      |> Enum.into(%{calories: 2000, protein_g: 150, carbs_g: 200, fat_g: 67})
      |> then(&DietProject.Accounts.create_goals(user, &1))

    goals
  end
end
