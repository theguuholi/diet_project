defmodule DietProject.Repo.Migrations.CreateFoodItems do
  use Ecto.Migration

  def change do
    create table(:food_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :meal_id, references(:meals, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :quantity, :float, null: false
      add :unit, :string, null: false
      add :calories, :float, null: false
      add :protein_g, :float, null: false
      add :carbs_g, :float, null: false
      add :fat_g, :float, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
