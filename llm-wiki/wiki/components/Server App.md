---
type: Wiki Entry
title: "Server App"
description: "The unmodified TCP server side of the 0-RTT demo, driven by experiments/utils/loadgen.py."
tags: [component, server]
timestamp: 2026-08-04T19:21:32+03:00
---

Source: `src/server-app/README.md`

# Server App

The server side of the 0-RTT demo. Runs `experiments/utils/loadgen.py` in
server mode: one asyncio process listening on `LOAD_PORTS` contiguous ports,
draining each connection until EOF.

The server is **completely unmodified** from the network's perspective — it
speaks standard TCP with no awareness of the 0-RTT optimization.

## Usage

On the Server VM (handles cleanup, git sync and foreground launch):

```bash
experiments/nodes/server.sh
```

Direct:

```bash
python3 experiments/utils/loadgen.py --mode server --port 8080 --port-count 4
```

Start the server **first** — the startup order is
Server → ServerNIC → ClientNIC → Client.

## Why not iperf

iperf2 has been removed; see `src/client-app/README.md` for the reasoning
(thread-per-connection scaling, and no arrival pacing).
