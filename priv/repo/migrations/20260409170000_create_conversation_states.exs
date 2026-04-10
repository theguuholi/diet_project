defmodule DietProject.Repo.Migrations.CreateConversationStates do
  use Ecto.Migration

  def change do
    create table(:conversation_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :state, :string, null: false, default: "idle"
      add :context, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_states, [:user_id])
  end
end
