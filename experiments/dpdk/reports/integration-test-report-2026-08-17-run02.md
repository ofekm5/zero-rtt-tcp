# Integration Test Report — 2026-08-17

**Implementation**: DPDK (ISN ack-num translation shift)
**ClientNIC binary**: `src/clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `src/servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: ALL PASSED

## Load Parameters

Must match the baseline run being compared against — see
`experiments/baseline-tcp/reports/`.

| Parameter | Value |
|---|---|
| Rounds | 1 |
| `LOAD_PARALLEL` | 2000 |
| `LOAD_PORTS` | 4 |
| `LOAD_BYTES` | 1024 |
| `LOAD_RATE` | 500 conn/s |
| `LOAD_CONCURRENCY` | 2000 |
| `NETEM_RTT_MS` | 100 (Server egress only) |

## Latency Summary

`Send unlock` is the primary result: first SYN out → first payload out,
which is exactly what the spoofed SYN-ACK unblocks. Compare it against the
baseline's `Send unlock`; the expected saving is one `NETEM_RTT_MS`.

```
  ── Primary: time-to-first-byte the client actually experiences ──
  Send unlock   : n=2000  min=0.200  mean=0.252  median=0.225  p95=0.424  p99=0.449  max=2.266 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.529  mean=100.649  median=100.612  p95=100.876  p99=100.921  max=102.575 ms
  Server gap    : n=2000  min=0.106  mean=0.214  median=0.185  p95=0.380  p99=0.409  max=2.215 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 500 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=500 conn/s requested, 500 conn/s achieved over 3.999s
Think: 0 ms between connect() and first write
Transfer complete: 2000/2000 connections ok, 0 failed, duration=4.011s, ~4.1 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf723b6de in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcb105ad3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x676ca03c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb55e8d5d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x831dff61 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6442d4b6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5f0ff171 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1e52e82f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2a5e985c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdeb58b9a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x750757a1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x16dac3cf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe956555c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2e18dc33 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x22c66edb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x509c247d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc7f09a45 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2eca64b5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x456ef5d8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0b826f04 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x508ec3d7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6840e82e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd69d4507 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8c7f7a6d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd0bcb87c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc222e90f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcbec8628 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcaf855ab in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xacd03fb3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x24ca553d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe4c2f03d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x046839a0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0309c46e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x90e78868 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x62aa7640 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x96e1a3a4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcbbf7efc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x02c2c828 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0a63970b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0b4dda80 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb35c7281 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x25bc9965 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1d4e3e91 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x84f23b95 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb5035e88 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbb79c669 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb872425f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbad9d5e7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x53395bc3 in ack-num
FORW--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xbc41d44a
SERVERNIC: SYN-ACK: delta=0xb2953630, V=0xbc41d44a, real_isn=0x09ac9e1a
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc5cb8e97
SERVERNIC: SYN-ACK: delta=0x3d3f7e1d, V=0xc5cb8e97, real_isn=0x888c107a
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x07339a2e
SERVERNIC: SYN-ACK: delta=0xa1fa7fcd, V=0x07339a2e, real_isn=0x65391a61
SERVERNIC: SYN: new flow, V=0x69957ee0
SERVERNIC: SYN-ACK: delta=0x40614400, V=0x69957ee0, real_isn=0x29343ae0
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x0d5330c2
SERVERNIC: SYN-ACK: delta=0xe119182f, V=0x0d5330c2, real_isn=0x2c3a1893
SERVERNIC: SYN: new flow, V=0x781a691b
SERVERNIC: SYN-ACK: delta=0xd919a97d, V=0x781a691b, real_isn=0x9f00bf9e
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x6f28e0ea
SERVERNIC: SYN-ACK: delta=0xe95f0735, V=0x6f28e0ea, real_isn=0x85c9d9b5
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xec087e9b
SERVERNIC: SYN-ACK: delta=0xcdb63359, V=0xec087e9b, real_isn=0x1e524b42
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x6a36c724
SERVERNIC: SYN-ACK: delta=0x6d13fb3e, V=0x6a36c724, real_isn=0xfd22cbe6
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xcf72b11e
SERVERNIC: SYN-ACK: delta=0x50584a90, V=0xcf72b11e, real_isn=0x7f1a668e
SERVERNIC: SYN: new flow, V=0x1b4f986a
SERVERNIC: SYN---output truncated--
```

## Server Log

```
[1;33m[18:51:07] Killing any leftover load-generator processes...[0m
[1;33m[18:51:08] Open-file limit (ulimit -n): 1048576[0m
[1;33m[18:51:08] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[18:51:08] Server VM IP: 10.1.2.91[0m
[1;33m[18:51:08] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[18:51:08] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 630784 bytes across 616 connections (so far)
Received 1654784 bytes across 1616 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.200 p50_ms=0.225 p95_ms=0.424 p99_ms=0.449 max_ms=2.266 mean_ms=0.252
summary=fct node=client n=2000 min_ms=100.529 p50_ms=100.612 p95_ms=100.876 p99_ms=100.921 max_ms=102.575 mean_ms=100.649
summary=server_gap node=server n=2000 min_ms=0.106 p50_ms=0.185 p95_ms=0.380 p99_ms=0.409 max_ms=2.215 mean_ms=0.214
```
