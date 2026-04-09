defmodule DietProject.Repo.Migrations.CreateGoals do
  use Ecto.Migration

  def change do
    create table(:goals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :calories, :integer, null: false
      add :protein_g, :integer, null: false
      add :carbs_g, :integer, null: false
      add :fat_g, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:goals, [:user_id])
  end
end
