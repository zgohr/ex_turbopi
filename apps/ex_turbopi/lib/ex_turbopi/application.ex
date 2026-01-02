defmodule ExTurbopi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DNSCluster, query: Application.get_env(:ex_turbopi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ExTurbopi.PubSub}
      # Start a worker by calling: ExTurbopi.Worker.start_link(arg)
      # {ExTurbopi.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExTurbopi.Supervisor)
  end
end
