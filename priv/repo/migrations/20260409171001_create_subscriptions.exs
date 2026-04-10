defmodule DietProject.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false
      add :current_period_end, :utc_datetime
      add :external_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:subscriptions, [:user_id, :status])
    create index(:subscriptions, [:external_id])
  end
end
