defmodule DietProject.Repo.Migrations.AddPhoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :phone, :string, null: true
    end

    create unique_index(:users, [:phone], where: "phone IS NOT NULL")
  end
end
