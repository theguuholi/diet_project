defmodule DietProject.Repo.Migrations.CreateMeals do
  use Ecto.Migration

  def change do
    create table(:meals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :logged_at, :utc_datetime, null: false
      add :input_type, :string, null: false
      add :raw_input, :text
      add :confirmed, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:meals, [:user_id, :logged_at])
  end
end
