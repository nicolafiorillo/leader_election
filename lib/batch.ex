defmodule LeaderElection.Batch do
  use GenServer
  require Logger

  @moduledoc false

  @spec start_link(%{pid: pid(), milliseconds: number()}) ::
          :ignore | {:error, any()} | {:ok, pid()}
  def start_link(scheduler) do
    GenServer.start_link(__MODULE__, scheduler, [])
  end

  @spec init(%{pid: pid(), milliseconds: number()}) ::
          {:ok, %{pid: pid(), milliseconds: number()}}
  def init(scheduler = %{pid: _, milliseconds: milliseconds}) do
    schedule_job(milliseconds)
    {:ok, scheduler}
  end

  def handle_info(:work, scheduler = %{pid: pid, milliseconds: milliseconds}) do
    send(pid, :batch)

    schedule_job(milliseconds)
    {:noreply, scheduler}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp schedule_job(milliseconds) do
    Process.send_after(self(), :work, milliseconds)
  end
end
