defmodule DietProjectWeb.UserSessionController do
  use DietProjectWeb, :controller

  alias DietProject.Accounts
  alias DietProjectWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  @doc """
  Validates a magic link token, creates a session, and redirects to the dashboard.

  On invalid or expired tokens, redirects to the login page with an error flash.
  """
  def magic_link(conn, %{"token" => token}) do
    case Accounts.verify_magic_link_token(token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Logged in successfully.")
        |> UserAuth.log_in_user(user, %{})

      {:error, :expired} ->
        conn
        |> put_flash(:error, "The magic link has expired. Please request a new one.")
        |> redirect(to: ~p"/users/log_in")

      {:error, :invalid} ->
        conn
        |> put_flash(:error, "The magic link is invalid.")
        |> redirect(to: ~p"/users/log_in")
    end
  end
end
