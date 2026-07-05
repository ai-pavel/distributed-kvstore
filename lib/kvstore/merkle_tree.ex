defmodule KVStore.MerkleTree do
  @moduledoc """
  A simple binary Merkle tree for comparing data sets between replicas.

  The tree is built from a sorted list of `{key, hash}` leaf pairs.
  Internal nodes store the SHA-256 hash of their children's concatenated
  hashes. Two replicas can compare root hashes and then drill down to
  find exactly which keys differ.
  """

  defstruct [:root]

  @type hash :: binary()
  @type leaf :: {String.t(), hash()}
  @type tree_node ::
          {:leaf, String.t(), hash()}
          | {:node, hash(), tree_node(), tree_node()}
          | :empty

  @type t :: %__MODULE__{root: tree_node()}

  @doc "Builds a Merkle tree from a sorted list of {key, hash} pairs."
  @spec build([leaf()]) :: t()
  def build([]), do: %__MODULE__{root: :empty}

  def build(leaves) do
    nodes = Enum.map(leaves, fn {key, hash} -> {:leaf, key, hash} end)
    %__MODULE__{root: build_tree(nodes)}
  end

  @doc "Returns the root hash of the tree."
  @spec root_hash(t() | nil) :: hash()
  def root_hash(nil), do: <<0::256>>
  def root_hash(%__MODULE__{root: :empty}), do: <<0::256>>
  def root_hash(%__MODULE__{root: root}), do: node_hash(root)

  @doc """
  Compares two Merkle trees and returns the list of keys that differ
  (present in one but not the other, or with different hashes).

  The two trees may have been built from different key *sets* (the common
  case that triggers anti-entropy sync), which means their internal shapes
  differ and a structural node-by-node walk would compare unrelated
  subtrees. Instead we collect each tree's `{key, hash}` leaves into a map
  and return exactly the keys whose hashes differ or that appear in only
  one tree. Callers should still compare `root_hash/1` first as a cheap
  equality fast-path before calling `diff/2`.
  """
  @spec diff(t(), t()) :: [String.t()]
  def diff(%__MODULE__{root: a}, %__MODULE__{root: b}) do
    leaves_a = leaves(a)
    leaves_b = leaves(b)

    keys = MapSet.union(MapSet.new(Map.keys(leaves_a)), MapSet.new(Map.keys(leaves_b)))

    keys
    |> Enum.filter(fn key ->
      Map.get(leaves_a, key) != Map.get(leaves_b, key)
    end)
    |> Enum.sort()
  end

  ## Internal

  # Collects every {key, hash} leaf in the tree into a map keyed by key.
  @spec leaves(tree_node()) :: %{String.t() => hash()}
  defp leaves(:empty), do: %{}
  defp leaves({:leaf, key, hash}), do: %{key => hash}

  defp leaves({:node, _hash, left, right}) do
    Map.merge(leaves(left), leaves(right))
  end

  defp build_tree([single]), do: single

  defp build_tree(nodes) do
    nodes
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [left, right] ->
        h = hash_pair(node_hash(left), node_hash(right))
        {:node, h, left, right}

      [left] ->
        left
    end)
    |> build_tree()
  end

  defp node_hash({:leaf, _key, hash}), do: hash
  defp node_hash({:node, hash, _l, _r}), do: hash
  defp node_hash(:empty), do: <<0::256>>

  defp hash_pair(a, b) do
    :crypto.hash(:sha256, a <> b)
  end
end
