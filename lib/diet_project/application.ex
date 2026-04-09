defmodule DietProject.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DietProjectWeb.Telemetry,
      DietProject.Repo,
      {DNSCluster, query: Application.get_env(:diet_project, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: DietProject.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: DietProject.Finch},
      {Oban, Application.fetch_env!(:diet_project, Oban)},
      DietProjectWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: DietProject.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DietProjectWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
