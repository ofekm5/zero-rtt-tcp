# Experiments

End-to-end orchestrators and node scripts for the 0-RTT TCP demo. Sub-directory
map is in the repo root `CLAUDE.md`; this file covers the **client and server
endpoints**, which have no source of their own — both are just
`experiments/utils/loadgen.py` in different modes.

## Client and server apps

`loadgen.py` is an asyncio (epoll-driven, single-thread) TCP load generator. It
*is* the client app and the server app — there is no `src/client-app/` or
`src/server-app/` code. Both endpoints are **completely unmodified** from the
network's perspective: standard TCP flows with no awareness of the 0-RTT
optimization happening in the network layer.

### Server (start first)

Startup order is **Server → ServerNIC → ClientNIC → Client**.

On the Server VM (handles cleanup, git sync, foreground launch):

```bash
experiments/nodes/server.sh
```

Direct:

```bash
python3 experiments/utils/loadgen.py --mode server --port 8080 --port-count 4
```

One process listens on `LOAD_PORTS` contiguous ports and drains each connection
until EOF.

### Client

Interactive, on the Client VM:

```bash
experiments/nodes/client.sh <server-ip>     # press Enter to fire a flow
```

Direct:

```bash
python3 experiments/utils/loadgen.py --mode client \
    --host <server-ip> --port 8080 --port-count 4 \
    --parallel 100000 --bytes 1024 --rate 2000 --concurrency-limit 2000
```

Under the orchestrators every knob comes from `experiments/utils/measure.sh`
(`LOAD_PARALLEL`, `LOAD_PORTS`, `LOAD_BYTES`, `LOAD_RATE`, `LOAD_CONCURRENCY`).

## Why not iperf

iperf2 was the original generator and has been removed:

- **Thread-per-connection.** `-P N` spawns N OS threads in one process; at this
  project's target scale (100k connections across 4 ports = 25k threads per
  process) that is not viable at any instance size. See
  `docs/kb/wiki/Capacity Model.md`.
- **No arrival pacing.** Every connection started at once, so per-connection
  latency measured queueing behind the batch rather than the round-trip 0-RTT
  removes. `loadgen.py --rate` fixes this — see
  `experiments/measurement-methodology-review.md`.
