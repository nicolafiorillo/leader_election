defmodule LeaderElection.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @test Application.get_env(:leader_election, :test) || false

  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LeaderElection.Supervisor]
    children(@test) |> Supervisor.start_link(opts)
  end

  def children(true), do: []

  def children(_) do
    node_port = (System.get_env("PORT") || "4001") |> String.to_integer()
    node_id = (System.get_env("ID") || "4001") |> String.to_integer()
    first_node = System.get_env("FIRST_NODE")

    Logger.debug("Id: #{node_id}")
    Logger.debug("Port: #{node_port}")
    Logger.debug("Connect to: #{first_node}")

    [{LeaderElection.Node, %{id: node_id, port: node_port, first_node: first_node}}]
  end
end
