defmodule LeaderElection.LeaderPinger do
  @moduledoc """
  A state machine to ping the leader.
  """

  use GenServer
  require Logger

  defstruct node_id: nil, node_pid: nil, status: :idle, wait_retry: 0, active: false

  @t_time Application.get_env(:leader_election, :t_time)

  # Initialization

  @spec start_link(pid(), number(), list()) :: {:error, any()} | {:ok, pid()}
  def start_link(parent_pid, node_id, opts \\ []) do
    GenServer.start_link(__MODULE__, {parent_pid, node_id}, opts)
  end

  @spec init({pid(), number()}) :: {:ok, any()}
  def init({pid, node_id}) do
    LeaderElection.Batch.start_link(%{pid: self(), milliseconds: @t_time})
    state = %__MODULE__{node_pid: pid, node_id: node_id}
    {:ok, state}
  end

  # API

  @spec activate(pid(), Bool.t()) :: :ok
  def activate(pid, activate_pinger), do: GenServer.cast(pid, {:activate, activate_pinger})

  @spec pong_received(pid()) :: :ok
  def pong_received(pid), do: GenServer.cast(pid, :pong_received)

  # Callbacks

  def handle_cast({:activate, activate_pinger}, state) do
    {:noreply, %{state | active: activate_pinger}}
  end

  def handle_cast(:pong_received, state) do
    {:noreply, %{state | status: :idle, wait_retry: 0}}
  end

  def handle_info(:batch, %{active: false} = state) do
    {:noreply, state}
  end

  def handle_info(:batch, %{status: :idle, node_pid: node_pid, node_id: node_id} = state) do
    Logger.debug("Ping leader: pinging")

    state =
      case LeaderElection.Node.get_leader(node_pid) do
        nil ->
          %{state | status: :idle, wait_retry: 0}

        leader ->
          Logger.debug("Pinging leader #{inspect(leader)}")
          LeaderElection.Network.cast(leader.address, {"PING", node_id})
          %{state | status: :wait_for_leader, wait_retry: 0}
      end

    {:noreply, state}
  end

  def handle_info(
        :batch,
        %{status: :wait_for_leader, wait_retry: wait_retry, node_pid: node_pid} = state
      )
      when wait_retry >= 4 do
    Logger.debug("Ping leader timeout")
    LeaderElection.Node.start_election(node_pid)
    {:noreply, %{state | status: :idle, wait_retry: 0}}
  end

  def handle_info(:batch, %{status: :wait_for_leader, wait_retry: wait_retry} = state) do
    state = %{state | status: :wait_for_leader, wait_retry: wait_retry + 1}
    {:noreply, state}
  end

  def handle_info(:batch, state) do
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  # Helpers
end
