defmodule DietProjectWeb.MagicLinkTest do
  use DietProjectWeb.ConnCase, async: true

  import DietProject.AccountsFixtures

  alias DietProject.Accounts

  describe "GET /auth/:token" do
    test "logs the user in with a valid token" do
      user = user_fixture()
      token = Accounts.generate_magic_link_token(user)

      conn = get(build_conn(), ~p"/auth/#{token}")

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login with error for invalid token" do
      conn = get(build_conn(), ~p"/auth/invalid-token-here")

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "redirects to login with error for expired token" do
      user = user_fixture()
      token = Accounts.generate_magic_link_token(user)

      # Manually expire the token
      import Ecto.Query

      expired_at = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      query = from(t in DietProject.Accounts.MagicToken, where: t.user_id == ^user.id)
      DietProject.Repo.update_all(query, set: [expires_at: expired_at])

      conn = get(build_conn(), ~p"/auth/#{token}")

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "token is single-use — second use fails" do
      user = user_fixture()
      token = Accounts.generate_magic_link_token(user)

      get(build_conn(), ~p"/auth/#{token}")

      conn2 = get(build_conn(), ~p"/auth/#{token}")
      refute get_session(conn2, :user_token)
      assert redirected_to(conn2) == ~p"/users/log_in"
    end
  end
end
