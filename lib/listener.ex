defmodule LeaderElection.Listener do
  @moduledoc """
  A node listener for TCP connection.
  """

  require Logger

  # API
  @spec run(number(), pid(), list()) :: {:error, any()} | {:ok, pid()}
  def run(port, parent_pid, _opts \\ []) do
    {:ok, _} =
      :ranch.start_listener(make_ref(), :ranch_tcp, [{:port, port}], __MODULE__, [parent_pid])
  end

  # Initialization

  @spec start_link(any(), any(), any(), any()) :: {:ok, pid()}
  def start_link(ref, socket, transport, [parent_pid]) do
    pid = :proc_lib.spawn_link(__MODULE__, :init, [ref, socket, transport, parent_pid])
    {:ok, pid}
  end

  @spec init(any(), any(), atom(), pid()) :: any()
  def init(ref, socket, transport, parent_pid) do
    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, [{:active, true}])

    :gen_server.enter_loop(__MODULE__, [], %{
      socket: socket,
      transport: transport,
      parent_pid: parent_pid
    })
  end

  # Callbacks

  def handle_info(
        {:tcp, socket, data},
        state = %{socket: socket, transport: transport, parent_pid: parent_pid}
      ) do
    data = data |> :erlang.binary_to_term()
    Logger.debug("#{inspect(self())} received #{inspect(data)}")

    from = from_ip(socket)
    tcp_replay = incoming_message(data, parent_pid, from)

    transport.send(socket, tcp_replay |> :erlang.term_to_binary())
    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, state = %{socket: socket, transport: transport}) do
    transport.close(socket)
    {:stop, :normal, state}
  end

  # Helpers

  defp from_ip(socket) do
    case :inet.peername(socket) do
      {:ok, {ip, _port}} -> :inet_parse.ntoa(ip)
      _ -> nil
    end
  end

  defp incoming_message({"MYID", id, port}, parent_pid, from) do
    addr = "#{from}:#{port}"
    LeaderElection.Node.add_node(parent_pid, id, addr)
  end

  defp incoming_message("HEREIAM", parent_pid, _from) do
    nodes = LeaderElection.Node.nodes(parent_pid)
    id = LeaderElection.Node.id(parent_pid)
    {id, nodes}
  end

  defp incoming_message({"IAMTHEKING", id}, parent_pid, _from) do
    LeaderElection.Node.set_leader(parent_pid, id)
  end

  defp incoming_message({"ALIVE?", id}, parent_pid, _from) do
    LeaderElection.Node.send_finethanks(parent_pid, id)
    LeaderElection.Node.check_if_possible_leader(parent_pid)
  end

  defp incoming_message("FINETHANKS", parent_pid, _from) do
    LeaderElection.Node.wait_for_iamtheking(parent_pid)
  end

  defp incoming_message({"PING", id}, parent_pid, _from) do
    Logger.info("Ping from #{id}")
    LeaderElection.Node.send_pong(parent_pid, id)
  end

  defp incoming_message("PONG", parent_pid, _from) do
    Logger.info("Pong arrived")
    LeaderElection.Node.pong_received(parent_pid)
  end
end
