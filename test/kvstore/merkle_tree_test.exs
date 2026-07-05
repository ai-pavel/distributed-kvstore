defmodule KVStore.MerkleTreeTest do
  use ExUnit.Case, async: true

  alias KVStore.MerkleTree

  test "empty tree has a zero root hash" do
    tree = MerkleTree.build([])
    assert MerkleTree.root_hash(tree) == <<0::256>>
  end

  test "single leaf tree has root equal to that leaf's hash" do
    hash = :crypto.hash(:sha256, "value1")
    tree = MerkleTree.build([{"key1", hash}])
    assert MerkleTree.root_hash(tree) == hash
  end

  test "identical data produces identical root hashes" do
    leaves = [
      {"a", :crypto.hash(:sha256, "1")},
      {"b", :crypto.hash(:sha256, "2")},
      {"c", :crypto.hash(:sha256, "3")}
    ]

    tree1 = MerkleTree.build(leaves)
    tree2 = MerkleTree.build(leaves)
    assert MerkleTree.root_hash(tree1) == MerkleTree.root_hash(tree2)
  end

  test "different data produces different root hashes" do
    leaves_a = [
      {"a", :crypto.hash(:sha256, "1")},
      {"b", :crypto.hash(:sha256, "2")}
    ]

    leaves_b = [
      {"a", :crypto.hash(:sha256, "1")},
      {"b", :crypto.hash(:sha256, "CHANGED")}
    ]

    tree_a = MerkleTree.build(leaves_a)
    tree_b = MerkleTree.build(leaves_b)
    assert MerkleTree.root_hash(tree_a) != MerkleTree.root_hash(tree_b)
  end

  test "diff of identical trees returns empty list" do
    leaves = [{"a", :crypto.hash(:sha256, "1")}, {"b", :crypto.hash(:sha256, "2")}]
    tree = MerkleTree.build(leaves)
    assert MerkleTree.diff(tree, tree) == []
  end

  test "diff finds changed keys" do
    tree_a =
      MerkleTree.build([
        {"a", :crypto.hash(:sha256, "1")},
        {"b", :crypto.hash(:sha256, "2")}
      ])

    tree_b =
      MerkleTree.build([
        {"a", :crypto.hash(:sha256, "1")},
        {"b", :crypto.hash(:sha256, "CHANGED")}
      ])

    assert "b" in MerkleTree.diff(tree_a, tree_b)
  end

  test "diff of empty vs non-empty returns all keys" do
    tree_a = MerkleTree.build([])

    tree_b =
      MerkleTree.build([
        {"x", :crypto.hash(:sha256, "1")},
        {"y", :crypto.hash(:sha256, "2")}
      ])

    diff = MerkleTree.diff(tree_a, tree_b)
    assert "x" in diff
    assert "y" in diff
  end

  defp leaf(key, value), do: {key, :crypto.hash(:sha256, value)}

  test "diff detects fully disjoint key sets" do
    tree_a = MerkleTree.build([leaf("a", "1"), leaf("b", "2")])
    tree_b = MerkleTree.build([leaf("c", "3"), leaf("d", "4")])

    assert MerkleTree.diff(tree_a, tree_b) == ["a", "b", "c", "d"]
  end

  test "diff detects one-sided insertions" do
    # tree_b has every key tree_a has, plus two extra.
    tree_a = MerkleTree.build([leaf("a", "1"), leaf("c", "3")])
    tree_b = MerkleTree.build([leaf("a", "1"), leaf("b", "2"), leaf("c", "3"), leaf("d", "4")])

    assert MerkleTree.diff(tree_a, tree_b) == ["b", "d"]
  end

  test "diff detects differences across interleaved key sets" do
    # Interleaved keys: shared-but-changed key ("c") plus disjoint tails.
    tree_a = MerkleTree.build([leaf("a", "1"), leaf("c", "old"), leaf("e", "5")])
    tree_b = MerkleTree.build([leaf("b", "2"), leaf("c", "new"), leaf("d", "4")])

    assert MerkleTree.diff(tree_a, tree_b) == ["a", "b", "c", "d", "e"]
  end

  test "diff ignores keys whose hashes match even when other keys differ" do
    tree_a = MerkleTree.build([leaf("a", "same"), leaf("b", "old")])
    tree_b = MerkleTree.build([leaf("a", "same"), leaf("b", "new"), leaf("z", "z")])

    diff = MerkleTree.diff(tree_a, tree_b)
    refute "a" in diff
    assert "b" in diff
    assert "z" in diff
  end
end
