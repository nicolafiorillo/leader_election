defmodule LeaderElectionTest do
  use ExUnit.Case

  test "one node alone become leader" do
    {:ok, node_pid} = LeaderElection.Node.start_link(%{id: 4001, port: 4001, first_node: nil})
    wait(600)

    state = process_state(node_pid)
    assert state.id == state.leader
    assert state.status == :idle
  end

  test "one node alone wait for finethanks" do
    {:ok, node_pid} = LeaderElection.Node.start_link(%{id: 4002, port: 4002, first_node: nil})

    state = process_state(node_pid)
    assert is_nil(state.leader)
    assert state.status == :waiting_for_finethanks
  end

  test "two node and verify leader" do
    {:ok, node1_pid} = LeaderElection.Node.start_link(%{id: 4003, port: 4003, first_node: nil})

    {:ok, node2_pid} =
      LeaderElection.Node.start_link(%{id: 4004, port: 4004, first_node: "localhost:4003"})

    wait(600)

    node1_state = process_state(node1_pid)
    node2_state = process_state(node2_pid)

    assert node1_state.leader == 4004
    assert node2_state.leader == 4004
  end

  defp process_state(pid), do: :sys.get_state(pid)

  defp wait(millisec), do: Process.sleep(millisec)
end
