defmodule DietProject.Repo.Migrations.CreateMacroLogs do
  use Ecto.Migration

  def change do
    create table(:macro_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :calories, :float, null: false, default: 0.0
      add :protein_g, :float, null: false, default: 0.0
      add :carbs_g, :float, null: false, default: 0.0
      add :fat_g, :float, null: false, default: 0.0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:macro_logs, [:user_id, :date])
  end
end
