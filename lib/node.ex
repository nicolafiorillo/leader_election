defmodule LeaderElection.Node do
  @moduledoc """
  The node implementation.
  """

  use GenServer
  alias LeaderElection.Network
  require Logger

  defstruct id: nil, nodes: [], status: :idle, leader: nil, pinger_pid: nil

  @t_time Application.get_env(:leader_election, :t_time)

  # Initialization

  @spec start_link(any(), list()) :: {:error, any()} | {:ok, pid()}
  def start_link(data, opts \\ []) do
    GenServer.start_link(__MODULE__, data, opts)
  end

  @spec init(any()) :: {:ok, any()}
  def init(%{id: node_id, port: port, first_node: first_node}) do
    LeaderElection.Listener.run(port, self())
    {:ok, pinger_pid} = LeaderElection.LeaderPinger.start_link(self(), node_id)

    {first_node_id, nodes} = ask_peers(first_node)
    nodes = add_first_node(nodes, first_node_id, first_node)

    Network.call(nodes, {"MYID", node_id, port})

    Logger.info("Here is node #{node_id}, listening on port #{port}.")

    status = _start_election(node_id, nodes)

    {:ok, %__MODULE__{id: node_id, nodes: nodes, status: status, pinger_pid: pinger_pid}}
  end

  # API

  @spec nodes(pid()) :: [any()]
  def nodes(pid), do: GenServer.call(pid, :nodes)

  @spec id(pid()) :: [any()]
  def id(pid), do: GenServer.call(pid, :id)

  @spec add_node(pid(), number(), binary()) :: :ok
  def add_node(pid, id, addr), do: GenServer.call(pid, {:add_node, id, addr})

  @spec set_leader(pid(), number()) :: any()
  def set_leader(pid, id), do: GenServer.cast(pid, {:set_leader, id})

  @spec get_leader(pid()) :: any()
  def get_leader(pid), do: GenServer.call(pid, :get_leader)

  @spec start_election(pid()) :: any()
  def start_election(pid), do: GenServer.cast(pid, :start_election)

  @spec stop_election(pid()) :: any()
  def stop_election(pid), do: GenServer.cast(pid, :stop_election)

  @spec check_if_possible_leader(pid()) :: any()
  def check_if_possible_leader(pid), do: GenServer.cast(pid, :possible_leader)

  @spec i_am_the_king(pid()) :: any()
  def i_am_the_king(pid), do: GenServer.cast(pid, :i_am_the_king)

  @spec send_finethanks(pid(), number()) :: any()
  def send_finethanks(pid, id), do: GenServer.cast(pid, {:send_finethanks, id})

  @spec send_pong(pid(), number()) :: any()
  def send_pong(pid, id), do: GenServer.cast(pid, {:send_pong, id})

  @spec pong_received(pid()) :: any()
  def pong_received(pid), do: GenServer.cast(pid, :pong_received)

  @spec wait_for_iamtheking(pid()) :: any()
  def wait_for_iamtheking(pid), do: GenServer.cast(pid, :wait_for_iamtheking)

  # Callbacks

  def handle_call(:nodes, _from, %{nodes: nodes} = state), do: {:reply, nodes, state}

  def handle_call(:id, _from, %{id: id} = state), do: {:reply, id, state}

  def handle_call({:add_node, id, addr}, _from, %{nodes: nodes} = state) do
    nodes = [LeaderElection.NodeCoords.new(id, addr) | nodes]
    {:reply, :ok, %{state | nodes: nodes}}
  end

  def handle_call(:get_leader, _from, %{id: me, leader: me} = state) do
    {:reply, nil, state}
  end

  def handle_call(:get_leader, _from, %{leader: nil} = state), do: {:reply, nil, state}

  def handle_call(:get_leader, _from, %{leader: leader, nodes: nodes} = state) do
    leader = nodes |> Enum.find(nil, fn n -> n.id == leader end)
    {:reply, leader, state}
  end

  def handle_cast({:send_finethanks, dest_id}, %{nodes: nodes} = state) do
    case find_node_by_id(nodes, dest_id) do
      nil -> nil
      n -> Network.cast(n.address, "FINETHANKS")
    end

    {:noreply, state}
  end

  def handle_cast(:possible_leader, %{nodes: nodes} = state) do
    max_node = nodes |> Enum.max_by(fn %{id: id} -> id end, fn -> 0 end)

    case state.id > max_node do
      true -> LeaderElection.Node.i_am_the_king(self())
      _ -> LeaderElection.Node.start_election(self())
    end

    {:noreply, state}
  end

  def handle_cast({:send_pong, dest_id}, %{nodes: nodes} = state) do
    case find_node_by_id(nodes, dest_id) do
      nil -> nil
      n -> Network.cast(n.address, "PONG")
    end

    {:noreply, state}
  end

  def handle_cast(:pong_received, state) do
    LeaderElection.LeaderPinger.pong_received(state.pinger_pid)
    {:noreply, state}
  end

  def handle_cast(:stop_election, state), do: {:noreply, %{state | status: :idle}}

  def handle_cast(:start_election, %{status: :waiting_for_finethanks} = state), do: {:noreply, state}
  def handle_cast(:start_election, %{id: id, nodes: nodes} = state) do
    status = _start_election(id, nodes)
    {:noreply, %{state | status: status, leader: nil}}
  end

  def handle_cast({:set_leader, leader_id}, %{id: id} = state) do
    Logger.info("The king is #{leader_id}")
    Logger.debug("Active pinger: #{leader_id != id}")
    LeaderElection.LeaderPinger.activate(state.pinger_pid, leader_id != id)
    {:noreply, %{state | leader: leader_id}}
  end

  def handle_cast(:wait_for_iamtheking, state) do
    time = length(state.nodes) * @t_time
    Process.send_after(self(), :wait_for_iamtheking_timeout, time)
    {:noreply, %{state | status: :waiting_for_iamtheking}}
  end

  def handle_info(
        :wait_for_iamtheking_timeout,
        %{id: id, nodes: nodes, status: :waiting_for_iamtheking} = state
      ) do
    status = _start_election(id, nodes)
    {:noreply, %{state | status: status, leader: nil}}
  end

  def handle_info(:wait_for_iamtheking_timeout, state), do: {:noreply, state}

  def handle_info(:election_timeout, %{status: :waiting_for_finethanks} = state) do
    i_am_the_king(state.nodes, state.id, state.pinger_pid)
    {:noreply, %{state | leader: state.id, status: :idle}}
  end

  def handle_info(:election_timeout, state), do: {:noreply, state}

  def handle_info(:i_am_the_king, %{status: :waiting_for_finethanks} = state) do
    i_am_the_king(state.nodes, state.id, state.pinger_id)
    {:noreply, %{state | leader: state.id, status: :idle}}
  end

  def handle_info(_, state), do: {:noreply, state}

  # Helpers

  defp i_am_the_king(nodes, id, pinger_pid) do
    Logger.info("I am the king.")
    Network.cast(nodes, {"IAMTHEKING", id})
    LeaderElection.LeaderPinger.activate(pinger_pid, false)
  end

  defp _start_election(id, nodes) do
    Logger.info("Starting election...")
    nodes_greater_than_me =
      nodes |> Enum.filter(fn %LeaderElection.NodeCoords{id: node_id} -> node_id > id end)

    Network.cast(nodes_greater_than_me, {"ALIVE?", id})

    Process.send_after(self(), :election_timeout, @t_time)

    :waiting_for_finethanks
  end

  defp ask_peers(nil), do: {nil, []}

  defp ask_peers(address) do
    {id, nodes} = Network.call(address, "HEREIAM")
    {id, nodes |> Enum.map(fn n -> LeaderElection.NodeCoords.new(n.id, n.address) end)}
  end

  defp add_first_node(nodes, nil, nil), do: nodes

  defp add_first_node(nodes, id, address),
    do: [LeaderElection.NodeCoords.new(id, address) | nodes]

  defp find_node_by_id(nodes, id) do
    nodes |> Enum.find(nil, fn %LeaderElection.NodeCoords{id: node_id} -> node_id == id end)
  end
end
