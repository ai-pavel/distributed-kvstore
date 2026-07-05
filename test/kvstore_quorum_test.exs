defmodule KVStoreQuorumTest do
  use ExUnit.Case, async: false

  # These tests exercise the configurable read/write quorums on the public
  # KVStore API. The application already starts a 3-node cluster.

  test "put with a satisfiable write quorum succeeds" do
    key = "quorum_ok_#{:erlang.unique_integer([:positive])}"
    assert :ok = KVStore.put(key, "v", w: 1)
    assert :ok = KVStore.put(key, "v2", w: 2)
  end

  test "put with an unsatisfiable write quorum reports insufficient replicas" do
    key = "quorum_toohigh_#{:erlang.unique_integer([:positive])}"
    n = length(KVStore.Ring.preference_list(key))

    # Requiring more acks than there are replicas cannot be satisfied.
    assert {:error, :insufficient_replicas} = KVStore.put(key, "v", w: n + 1)
  end

  test "read quorum returns the written value" do
    key = "quorum_read_#{:erlang.unique_integer([:positive])}"
    :ok = KVStore.put(key, "hello", w: 1)
    assert {:ok, "hello"} = KVStore.get(key, r: 1)
  end

  test "read quorum higher than the number of replicas reports insufficient replicas" do
    key = "quorum_read_high_#{:erlang.unique_integer([:positive])}"
    :ok = KVStore.put(key, "hello", w: 1)
    n = length(KVStore.Ring.preference_list(key))

    assert {:error, :insufficient_replicas} = KVStore.get(key, r: n + 1)
  end

  test "defaults use a majority quorum and still work end-to-end" do
    key = "quorum_default_#{:erlang.unique_integer([:positive])}"
    assert :ok = KVStore.put(key, "def")
    assert {:ok, "def"} = KVStore.get(key)
  end
end
