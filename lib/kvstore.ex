defmodule KVStore do
  @moduledoc """
  A distributed key-value store built on OTP with consistent hashing,
  CRDT-based conflict resolution, and Merkle-tree anti-entropy sync.

  ## Public API

      KVStore.put("users:1", %{name: "Alice"})
      KVStore.get("users:1")
      KVStore.delete("users:1")
  """

  alias KVStore.{Ring, Node}

  @doc """
  Stores a value under the given key, replicating to N nodes determined
  by the consistent hash ring.

  ## Options

    * `:w` — write quorum: the number of replica acknowledgements required
      before returning `:ok`. Defaults to a majority of the replication
      factor (`div(rf, 2) + 1`). Returns `{:error, :insufficient_replicas}`
      if fewer than `:w` nodes acknowledge.
    * `:timestamp` — the write timestamp (defaults to the current time).

  Configuring `W` and `R` (see `get/2`) so that `W + R > N` gives
  read-your-write consistency.
  """
  @spec put(String.t(), term(), keyword()) :: :ok | {:error, term()}
  def put(key, value, opts \\ []) do
    nodes = Ring.preference_list(key)
    timestamp = Keyword.get(opts, :timestamp, System.os_time(:microsecond))
    w = Keyword.get(opts, :w, default_quorum())

    acks =
      Enum.count(nodes, fn node_id ->
        match?(:ok, safe_node_put(node_id, key, value, timestamp))
      end)

    if acks >= w do
      :ok
    else
      {:error, :insufficient_replicas}
    end
  end

  # The default majority quorum for the configured replication factor.
  defp default_quorum do
    rf = Application.get_env(:kvstore, :replication_factor, 3)
    div(rf, 2) + 1
  end

  # Per-node put that treats a dead/timed-out replica as a failed ack
  # rather than crashing, so quorum counting stays meaningful.
  defp safe_node_put(node_id, key, value, timestamp) do
    Node.put(node_id, key, value, timestamp)
  catch
    :exit, _reason -> {:error, :node_down}
  end

  @doc """
  Retrieves the value for the given key, resolving conflicts across
  replicas by last-writer-wins.

  ## Options

    * `:r` — read quorum: the number of replicas that must respond
      (whether with a value or `:not_found`) before the read is considered
      valid. Defaults to a majority of the replication factor
      (`div(rf, 2) + 1`). Returns `{:error, :insufficient_replicas}` if
      fewer than `:r` nodes respond.

  Configuring `W` (see `put/3`) and `R` so that `W + R > N` gives
  read-your-write consistency.
  """
  @spec get(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get(key, opts \\ []) do
    nodes = Ring.preference_list(key)
    r = Keyword.get(opts, :r, default_quorum())

    # A replica "responds" if it returns either {:ok, reg} or
    # {:error, :not_found}; only a dead/timed-out node fails to respond.
    responses =
      nodes
      |> Enum.map(fn node_id -> safe_node_get(node_id, key) end)
      |> Enum.reject(&match?({:error, :node_down}, &1))

    cond do
      length(responses) < r ->
        {:error, :insufficient_replicas}

      true ->
        values = Enum.filter(responses, &match?({:ok, _}, &1))

        case values do
          [] ->
            {:error, :not_found}

          values ->
            # Return the value with the highest timestamp (LWW).
            {_ts, value} =
              values
              |> Enum.map(fn {:ok, lww} -> {lww.timestamp, lww.value} end)
              |> Enum.max_by(fn {ts, _v} -> ts end)

            if value == :__tombstone__ do
              {:error, :not_found}
            else
              {:ok, value}
            end
        end
    end
  end

  # Per-node get that treats a dead/timed-out replica as :node_down rather
  # than crashing, so read-quorum counting stays meaningful.
  defp safe_node_get(node_id, key) do
    Node.get(node_id, key)
  catch
    :exit, _reason -> {:error, :node_down}
  end

  @doc """
  Deletes a key by writing a tombstone with the current timestamp.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts \\ []) do
    put(key, :__tombstone__, opts)
  end
end
