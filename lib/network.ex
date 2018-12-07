defmodule LeaderElection.Network do
  @moduledoc """
  The communication layer.
  """

  require Logger

  @spec call([any()], any()) :: :ok
  def call(nodes, message) when is_list(nodes) do
    nodes |> Enum.each(fn node -> Task.async(fn -> _call(node.address, message) end) end)
  end

  @spec call(binary(), any()) :: any()
  def call(address, message), do: _call(address, message)

  @spec cast([any()], any()) :: :ok
  def cast(nodes, message) when is_list(nodes) do
    nodes |> Enum.each(fn node -> Task.async(fn -> _cast(node.address, message) end) end)
  end

  @spec cast(binary(), any()) :: :ok
  def cast(address, message), do: _cast(address, message)

  # Helper

  defp _call(address, message) do
    Logger.debug("#{inspect(self())} send call #{inspect(message)} to #{address}")

    {addr, port} = LeaderElection.NodeCoords.split_address(address)

    {:ok, socket} = :gen_tcp.connect(addr, port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, message |> :erlang.term_to_binary())
    {:ok, data} = :gen_tcp.recv(socket, 0)
    :ok = :gen_tcp.close(socket)

    data |> :erlang.binary_to_term()
  end

  defp _cast(address, message) do
    Logger.debug("#{inspect(self())} send cast #{inspect(message)} to #{address}")

    {addr, port} = LeaderElection.NodeCoords.split_address(address)

    with {:ok, socket} <- :gen_tcp.connect(addr, port, [:binary, active: false]),
         :ok <- :gen_tcp.send(socket, message |> :erlang.term_to_binary()),
         :ok <- :gen_tcp.close(socket) do
      :ok
    else
      {:error, err} -> Logger.info("#{inspect(addr)}:#{port} seems down (#{inspect(err)})")
    end
  end
end
