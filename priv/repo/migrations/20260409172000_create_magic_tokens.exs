defmodule DietProject.Repo.Migrations.CreateMagicTokens do
  use Ecto.Migration

  def change do
    create table(:magic_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:magic_tokens, [:token_hash])
    create index(:magic_tokens, [:user_id])
  end
end
