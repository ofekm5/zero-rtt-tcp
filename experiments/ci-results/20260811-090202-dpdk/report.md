# Integration Test Report — 2026-08-11

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
  Send unlock   : n=2000  min=0.297  mean=0.443  median=0.443  p95=0.596  p99=0.655  max=2.107 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=101.223  mean=101.571  median=101.550  p95=101.878  p99=102.017  max=103.182 ms
  Server gap    : n=2000  min=0.317  mean=0.437  median=0.419  p95=0.593  p99=0.681  max=2.094 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 500 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=500 conn/s requested, 500 conn/s achieved over 3.998s
Think: 0 ms between connect() and first write
Transfer complete: 2000/2000 connections ok, 0 failed, duration=4.010s, ~4.1 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x40a3095f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1b663461 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x613a97e5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0420e3b9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xccb79008 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xae93932e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x07e14a9f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8a314e13 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x49dfc5bc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa0c1020f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xeb2e1056 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe7d7b261 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xedf2628d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6a7578c2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd57ff22 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x610a2a3a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd9288818 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6afb7c96 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf56b20a7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x71215a7d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6b696025 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x425cfe60 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x076afc30 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfd38ba80 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x90a608a1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x55d8731e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3bbffa95 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x297cc992 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1503e000 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x71327e38 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x962def18 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x558743cf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x89a91ad4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9dd5b148 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x882650d3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x41b24b8d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4bbd3d10 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x802735f2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7b752ed7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3c8c22a3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x79a3ba50 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcca0f148 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9a0fcb05 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdfd2752d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x92ea6cc2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8b078bb7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x666b3b36 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9dc0366d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9f288cab in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forw--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x53722525
SERVERNIC: SYN-ACK: delta=0x6cfadd54, V=0x53722525, real_isn=0xe67747d1
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x918d53a9
SERVERNIC: SYN-ACK: delta=0x9afae14d, V=0x918d53a9, real_isn=0xf692725c
SERVERNIC: SYN: new flow, V=0xaaebda37
SERVERNIC: SYN-ACK: delta=0x75f81721, V=0xaaebda37, real_isn=0x34f3c316
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xaf35d08f
SERVERNIC: SYN-ACK: delta=0xeaead566, V=0xaf35d08f, real_isn=0xc44afb29
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc86c6641
SERVERNIC: SYN-ACK: delta=0x47f30750, V=0xc86c6641, real_isn=0x80795ef1
SERVERNIC: SYN: new flow, V=0xfabfff3d
SERVERNIC: SYN-ACK: delta=0xacd78540, V=0xfabfff3d, real_isn=0x4de879fd
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x023635da
SERVERNIC: SYN-ACK: delta=0x70331308, V=0x023635da, real_isn=0x920322d2
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xd0524051
SERVERNIC: SYN-ACK: delta=0x09f9427f, V=0xd0524051, real_isn=0xc658fdd2
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x30317e68
SERVERNIC: SYN-ACK: delta=0x284e0289, V=0x30317e68, real_isn=0x07e37bdf
SERVERNIC: SYN: new flow, V=0x06b26f4e
SERVERNIC: SYN-ACK: delta=0x9444d0c3, V=0x06b26f4e, real_isn=0x726d9e8b
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xaf47a91b
SERVERNIC: SYN-ACK: delta=0x496c6ab1, V=0xaf47--output truncated--
```

## Server Log

```
[1;33m[08:59:39] Killing any leftover load-generator processes...[0m
[1;33m[08:59:40] Open-file limit (ulimit -n): 1048576[0m
[1;33m[08:59:40] Syncing code to origin/fix/secret-rename (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            fix/secret-rename -> FETCH_HEAD
HEAD is now at 7313ced ci: experiment baseline bundle 20260811-085652 [skip ci]
[1;33m[08:59:41] Server VM IP: 10.1.2.50[0m
[1;33m[08:59:41] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[08:59:41] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 423936 bytes across 414 connections (so far)
Received 1447936 bytes across 1414 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.297 p50_ms=0.443 p95_ms=0.596 p99_ms=0.655 max_ms=2.107 mean_ms=0.443
summary=fct node=client n=2000 min_ms=101.223 p50_ms=101.550 p95_ms=101.878 p99_ms=102.017 max_ms=103.182 mean_ms=101.571
summary=server_gap node=server n=2000 min_ms=0.317 p50_ms=0.419 p95_ms=0.593 p99_ms=0.681 max_ms=2.094 mean_ms=0.437
```
