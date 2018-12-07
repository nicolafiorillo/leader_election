defmodule LeaderElection.NodeCoords do
  defstruct id: nil, address: nil

  @spec new(number(), binary()) :: any()
  def new(id, address), do: %__MODULE__{id: id, address: address}

  @spec split_address(binary()) :: {charlist(), number()}
  def split_address(address) do
    %{"addr" => addr, "port" => port} =
      Regex.named_captures(~r/(?<addr>.+):(?<port>\d+)/, address)

    {port, _} = Integer.parse(port)
    addr = addr |> String.to_charlist()

    {addr, port}
  end
end
