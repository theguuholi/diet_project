defmodule DietProject.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  def change do
    create table(:profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :weight_kg, :float, null: false
      add :height_cm, :float, null: false
      add :body_fat_pct, :float, null: false
      add :activity_level, :string, null: false
      add :goal, :string, null: false
      add :bmr, :float, null: false
      add :tdee, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profiles, [:user_id])
  end
end
