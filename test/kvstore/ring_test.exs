defmodule KVStore.RingTest do
  use ExUnit.Case, async: false

  alias KVStore.Ring

  setup do
    # The application supervisor already starts Ring. Instead of stopping and
    # restarting the supervised process (which races with the supervisor's
    # automatic restarts and can crash the application), we clean the ring
    # state by removing all existing nodes before each test.
    # Remember the bootstrapped nodes so we can restore them afterwards —
    # other test modules share this global Ring and rely on those nodes.
    original_nodes = Ring.nodes()

    for node_id <- original_nodes do
      Ring.remove_node(node_id)
    end

    on_exit(fn ->
      for node_id <- Ring.nodes() do
        Ring.remove_node(node_id)
      end

      # Restore the ring to its original bootstrapped state.
      for node_id <- original_nodes do
        Ring.add_node(node_id)
      end
    end)

    :ok
  end

  test "adding a node makes it appear in the node list" do
    assert Ring.nodes() == []
    Ring.add_node(:alpha)
    assert :alpha in Ring.nodes()
  end

  test "adding the same node twice is idempotent" do
    Ring.add_node(:alpha)
    Ring.add_node(:alpha)
    assert Ring.nodes() == [:alpha]
  end

  test "removing a node removes it from the ring" do
    Ring.add_node(:alpha)
    Ring.add_node(:beta)
    Ring.remove_node(:alpha)
    refute :alpha in Ring.nodes()
    assert :beta in Ring.nodes()
  end

  test "preference list returns distinct nodes up to replication factor" do
    Ring.add_node(:n1)
    Ring.add_node(:n2)
    Ring.add_node(:n3)

    pref = Ring.preference_list("some_key")
    assert length(pref) <= Application.get_env(:kvstore, :replication_factor, 3)
    assert pref == Enum.uniq(pref)
  end

  test "preference list is consistent for the same key" do
    Ring.add_node(:n1)
    Ring.add_node(:n2)

    a = Ring.preference_list("test_key")
    b = Ring.preference_list("test_key")
    assert a == b
  end

  test "different keys can map to different primary nodes" do
    Ring.add_node(:n1)
    Ring.add_node(:n2)
    Ring.add_node(:n3)

    # With enough keys, we should see at least two different primary nodes
    primaries =
      for i <- 1..100 do
        [primary | _] = Ring.preference_list("key_#{i}")
        primary
      end
      |> Enum.uniq()

    assert length(primaries) > 1
  end

  test "virtual nodes are created for each physical node" do
    Ring.add_node(:v1)
    vnodes = Application.get_env(:kvstore, :virtual_nodes, 128)
    ring = Ring.ring()
    count = Enum.count(ring, fn {_h, nid} -> nid == :v1 end)
    assert count == vnodes
  end
end
