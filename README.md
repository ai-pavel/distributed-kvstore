# Distributed KV Store

[![CI](https://github.com/ai-pavel/distributed-kvstore/actions/workflows/ci.yml/badge.svg)](https://github.com/ai-pavel/distributed-kvstore/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/ai-pavel/distributed-kvstore/branch/main/graph/badge.svg)](https://codecov.io/gh/ai-pavel/distributed-kvstore)

An Elixir/OTP distributed key-value store using consistent hashing, CRDTs, and Merkle tree-based anti-entropy sync.

## Features

- **Consistent Hashing** with virtual nodes for key partitioning
- **CRDTs**: LWW-Register and G-Counter for conflict-free replication
- **Anti-entropy sync** via periodic Merkle tree comparison
- **Tunable consistency**: configurable read/write quorums (`R`/`W`)
- **HTTP API** via Plug

## Consistency (R/W/N quorums)

Each key is replicated to `N` nodes (`:replication_factor`, default 3).
`KVStore.put/3` and `KVStore.get/2` accept `:w` and `:r` options controlling
how many replicas must acknowledge a write / respond to a read. Both default
to a majority (`div(N, 2) + 1`), and `put` returns `{:error,
:insufficient_replicas}` if fewer than `W` replicas acknowledge.

Choosing `W + R > N` guarantees read-your-write consistency (a read quorum
always overlaps the last write quorum); smaller values trade consistency for
lower latency and higher availability. The previous behaviour was effectively
`W = 1` (returned `:ok` on the first acknowledgement), which could silently
lose an acknowledged write if the sole acknowledging node died before
anti-entropy sync.

```elixir
KVStore.put("k", "v", w: 2)
KVStore.get("k", r: 2)
```

## API Endpoints

- `PUT /kv/:key` — store a value
- `GET /kv/:key` — retrieve a value
- `DELETE /kv/:key` — delete a key
- `GET /status` — cluster status

## Running

```bash
mix deps.get
mix compile
mix run --no-halt
```

## Testing

```bash
mix test
```
