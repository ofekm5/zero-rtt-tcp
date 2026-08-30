---
type: Raw Source
title: "Integration Test Report — 2026-08-04"
description: "Implementation: DPDK (T8 ISN ack-num translation shift)"
tags: [experiments, integration-test, dpdk]
timestamp: 2026-08-04T20:27:24+03:00
---

# Integration Test Report — 2026-08-04

**Implementation**: DPDK (T8 ISN ack-num translation shift)
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
  Send unlock   : n=2000  min=0.190  mean=0.226  median=0.215  p95=0.292  p99=0.421  max=2.061 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=201.266  mean=201.546  median=201.368  p95=201.468  p99=201.638  max=536.628 ms
  Server gap    : n=2000  min=0.329  mean=0.359  median=0.354  p95=0.388  p99=0.487  max=0.756 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 500 conn/s arrival, max 2000 in flight ---
Arrival: rate=500 conn/s requested, 500 conn/s achieved over 3.998s
Transfer complete: 2000/2000 connections ok, 0 failed, duration=4.010s, ~4.1 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xea2cfbbb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe9d923ab in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x55e03520 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1824a47c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2ea7c696 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7a57830a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9d05cba6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x145d568d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x44ac57e0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x68bb2b43 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2e1af745 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf4096229 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf09dbafb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfe9f8a39 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9151b685 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe46870ee in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf95d1c43 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa3649510 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf7f6a226 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb90ec7f7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x00f5b406 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x79677c0c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3aed2ee5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2dda8647 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x926df45b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd9981c16 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd98708bb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x23f5431b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x506a6836 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x102f1e22 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xac1a96ae in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3d1a89c7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xaef3c0a7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x63d49916 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x84fd7e7c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9eb03bad in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf9cad8eb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb6daaa52 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5bf9fcc7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8712941f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9529d423 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x272591fd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0be77c07 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x39561262 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0187d087 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x083f71b3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9193a31d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0140f071 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x35421418 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: delta=0x4693a082, V=0xc393a1bd, real_isn=0x7d00013b
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x1f9479c5
SERVERNIC: SYN: new flow, V=0x33e14d58
SERVERNIC: SYN-ACK: delta=0x9510044d, V=0xf4590149, real_isn=0x5f48fcfc
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x07a0efdb, V=0x68a72589, real_isn=0x610635ae
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x9a414472
SERVERNIC: SYN: new flow, V=0xdb2f2e29
SERVERNIC: SYN-ACK: delta=0x223afcc2, V=0xdb1a4636, real_isn=0xb8df4974
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x8dd88a8d, V=0xa7ae4fdf, real_isn=0x19d5c552
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x923836b0
SERVERNIC: SYN: new flow, V=0xca9994c7
SERVERNIC: SYN-ACK: delta=0x593e4235, V=0x9d742889, real_isn=0x4435e654
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x51f2f58a, V=0xeaa12932, real_isn=0x98ae33a8
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x4de66f64
SERVERNIC: SYN: new flow, V=0x98e97d8d
SERVERNIC: SYN-ACK: delta=0x84c5bd8f, V=0xcfed05a8, real_isn=0x4b274819
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x9d6a2a3e, V=0xa735a80b, real_isn=0x09cb7dcd
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc6a46b89
SERVERNIC: SYN: new flow, V=0x483d34b4
SERVERNIC: SYN-ACK: delta=0xc6df3efd, V=0xa9043bc0, real_isn=0xe224fcc3
SERVERNIC: SYN-ACK: flushed 3 buffered c2s pac--output truncated--
```

## Server Log

```
[1;33m[17:20:01] Killing any leftover load-generator processes...[0m
[1;33m[17:20:02] Open-file limit (ulimit -n): 1048576[0m
[1;33m[17:20:02] Syncing code to origin/fix/measurement-methodology-load-shape (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            fix/measurement-methodology-load-shape -> FETCH_HEAD
HEAD is now at d426c6c fix(infra/baseline): grant the instance role Secrets Manager read access
[1;33m[17:20:03] Server VM IP: 10.1.2.156[0m
[1;33m[17:20:03] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[17:20:03] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 238592 bytes across 233 connections (so far)
Received 1263616 bytes across 1234 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.190 p50_ms=0.215 p95_ms=0.292 p99_ms=0.421 max_ms=2.061 mean_ms=0.226
summary=fct node=client n=2000 min_ms=201.266 p50_ms=201.368 p95_ms=201.468 p99_ms=201.638 max_ms=536.628 mean_ms=201.546
summary=server_gap node=server n=2000 min_ms=0.329 p50_ms=0.354 p95_ms=0.388 p99_ms=0.487 max_ms=0.756 mean_ms=0.359
```
