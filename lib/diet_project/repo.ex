defmodule DietProject.Repo do
  use Ecto.Repo,
    otp_app: :diet_project,
    adapter: Ecto.Adapters.Postgres
end
