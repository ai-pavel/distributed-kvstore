defmodule KVStore.SyncTest do
  use ExUnit.Case, async: false

  alias KVStore.{Ring, Node, Sync}

  setup do
    # The application supervisor already starts Ring, Sync, and the NodeRegistry.
    # Instead of stopping/restarting supervised processes (which races with the
    # supervisor's automatic restarts), we clean up the existing Ring state and
    # add fresh test nodes.

    # Remove all existing nodes from the ring so each test starts clean.
    # Remember them so we can restore the ring afterwards — other test
    # modules share this global Ring and rely on the bootstrapped nodes.
    original_nodes = Ring.nodes()

    for node_id <- original_nodes do
      Ring.remove_node(node_id)
    end

    # Start two test nodes
    node_a = :"sync_a_#{:erlang.unique_integer([:positive])}"
    node_b = :"sync_b_#{:erlang.unique_integer([:positive])}"

    {:ok, pid_a} = Node.start_link(node_a)
    {:ok, pid_b} = Node.start_link(node_b)

    Ring.add_node(node_a)
    Ring.add_node(node_b)

    on_exit(fn ->
      # GenServer.stop/1 races with the process exiting on test teardown
      # (nodes are linked to the test process), so tolerate an already-dead
      # process instead of crashing the on_exit callback.
      for pid <- [pid_a, pid_b] do
        try do
          if Process.alive?(pid), do: GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end

      # Clean up test nodes from the ring
      Ring.remove_node(node_a)
      Ring.remove_node(node_b)

      # Restore the nodes the application bootstrapped so subsequent test
      # modules see the ring in its original state.
      for node_id <- original_nodes do
        Ring.add_node(node_id)
      end
    end)

    {:ok, node_a: node_a, node_b: node_b}
  end

  test "sync propagates data between nodes", %{node_a: node_a, node_b: node_b} do
    # Write to node_a only
    :ok = Node.put(node_a, "sync_key", "sync_val", 1000)

    # node_b should not have it yet
    assert {:error, :not_found} = Node.get(node_b, "sync_key")

    # Trigger sync
    Sync.sync_now()

    # Now node_b should have the data
    {:ok, reg} = Node.get(node_b, "sync_key")
    assert reg.value == "sync_val"
  end

  test "sync resolves conflicts using LWW merge", %{node_a: node_a, node_b: node_b} do
    # Write different values to same key on both nodes
    :ok = Node.put(node_a, "conflict", "old_a", 100)
    :ok = Node.put(node_b, "conflict", "new_b", 200)

    Sync.sync_now()

    # Both should now have the newer value
    {:ok, reg_a} = Node.get(node_a, "conflict")
    {:ok, reg_b} = Node.get(node_b, "conflict")

    assert reg_a.value == "new_b"
    assert reg_b.value == "new_b"
  end

  test "sync is idempotent", %{node_a: node_a, node_b: node_b} do
    :ok = Node.put(node_a, "idem", "val", 100)
    Sync.sync_now()
    Sync.sync_now()
    Sync.sync_now()

    {:ok, reg} = Node.get(node_b, "idem")
    assert reg.value == "val"
  end
end
