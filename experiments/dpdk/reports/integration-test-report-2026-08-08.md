# Integration Test Report — 2026-08-08

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
  Send unlock   : n=2000  min=0.224  mean=0.263  median=0.251  p95=0.374  p99=0.433  max=2.136 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.830  mean=101.067  median=101.055  p95=101.277  p99=101.407  max=102.928 ms
  Server gap    : n=2000  min=0.170  mean=0.259  median=0.238  p95=0.398  p99=0.549  max=2.075 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 500 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=500 conn/s requested, 500 conn/s achieved over 3.998s
Think: 0 ms between connect() and first write
Transfer complete: 2000/2000 connections ok, 0 failed, duration=4.009s, ~4.1 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0edcc61e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x75df4753 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x36628c5e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1e0fc17e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3ccca834 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x31ac0a77 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1b45d9c0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0e292917 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x53b3319b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1cb39ed8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2790e077 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xab77faae in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa570257f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0c10725a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfc5393a6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0c2d145d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfe4d8148 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x60cd5dd2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x543dbbf0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9d72f277 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x603444bc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x71a24751 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7b710df1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf6bb948a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x172372a3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1c44420a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbf31b2dd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd4f1e1f4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x610bd85e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x64ab4d0c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa33858ee in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf712d016 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x62642378 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x14bff65a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xac4b9387 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xae7d53d6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdb4f6c62 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6424e952 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x53cba6c0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5f19e4ae in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb44e3ec9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9d844e06 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0505c513 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9e0018bc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x45989554 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x80b718ca in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe821a8c1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x40bc5771 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x62369da2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xae874fc1 in ac--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc3950af8
SERVERNIC: SYN-ACK: delta=0xf14acd34, V=0xc3950af8, real_isn=0xd24a3dc4
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x1b94654e
SERVERNIC: SYN-ACK: delta=0x6f649f4c, V=0x1b94654e, real_isn=0xac2fc602
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe9fd0756
SERVERNIC: SYN-ACK: delta=0xce42951b, V=0xe9fd0756, real_isn=0x1bba723b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x4882ab81
SERVERNIC: SYN-ACK: delta=0x4a6373f0, V=0x4882ab81, real_isn=0xfe1f3791
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x6572496f
SERVERNIC: SYN-ACK: delta=0x5e84a86b, V=0x6572496f, real_isn=0x06eda104
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x4932639e
SERVERNIC: SYN-ACK: delta=0x5a972b3b, V=0x4932639e, real_isn=0xee9b3863
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x2f1b5267
SERVERNIC: SYN-ACK: delta=0x450ffd55, V=0x2f1b5267, real_isn=0xea0b5512
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xeeae1358
SERVERNIC: SYN-ACK: delta=0x1620b340, V=0xeeae1358, real_isn=0xd88d6018
SERVERNIC: SYN-ACK: flushed 2 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x25fe0e07
SERVERNIC: SYN-ACK: delta=0x7c7b6d88, V=0x25fe0e07, real_isn=0xa982a07f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xdc2f6aba
SERVERNIC: S--output truncated--
```

## Server Log

```
[1;33m[18:26:16] Killing any leftover load-generator processes...[0m
[1;33m[18:26:17] Open-file limit (ulimit -n): 1048576[0m
[1;33m[18:26:17] Syncing code to origin/fix/measurement-methodology-load-shape (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            fix/measurement-methodology-load-shape -> FETCH_HEAD
HEAD is now at cc26b6a fix(experiments): move the emulated WAN to the middle leg, add think-time sweep
[1;33m[18:26:18] Server VM IP: 10.1.2.205[0m
[1;33m[18:26:18] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[18:26:18] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 441344 bytes across 431 connections (so far)
Received 1465344 bytes across 1431 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.224 p50_ms=0.251 p95_ms=0.374 p99_ms=0.433 max_ms=2.136 mean_ms=0.263
summary=fct node=client n=2000 min_ms=100.830 p50_ms=101.055 p95_ms=101.277 p99_ms=101.407 max_ms=102.928 mean_ms=101.067
summary=server_gap node=server n=2000 min_ms=0.170 p50_ms=0.238 p95_ms=0.398 p99_ms=0.549 max_ms=2.075 mean_ms=0.259
```
