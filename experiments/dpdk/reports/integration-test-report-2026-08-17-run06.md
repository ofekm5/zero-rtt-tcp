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
  Send unlock   : n=2000  min=0.198  mean=0.239  median=0.224  p95=0.365  p99=0.440  max=2.199 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.517  mean=100.665  median=100.631  p95=100.845  p99=101.007  max=102.497 ms
  Server gap    : n=2000  min=0.101  mean=0.237  median=0.220  p95=0.375  p99=0.521  max=2.141 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 500 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=500 conn/s requested, 500 conn/s achieved over 3.999s
Think: 0 ms between connect() and first write
Transfer complete: 2000/2000 connections ok, 0 failed, duration=4.010s, ~4.1 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd8e0500b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd85bb2d2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x617db5c7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7de1f934 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x95f7b4be in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x061a82aa in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf52c3c00 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xda220d31 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf6ff72b4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x25c805e5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x26c14ff3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x05fcd3be in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcf70137b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xde503c55 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf99ec5aa in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8f1c336c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4330a490 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x53aeeef7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdd865ff5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0c116200 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x026e8c17 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe6d87d5f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x615d7a15 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xef6604b5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf218c622 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x681dc3d0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa135a18a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0e6b09db in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6e29732d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe3f34060 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x47f6e3ad in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7acaa4f6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe4725631 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc2e5a703 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8c15e782 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x78471a56 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb43e58cf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8c3b20ae in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8e669f54 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8d37cb4f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x54981035 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x33879f2d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9d7d8f0f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x767e4b18 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe86ab560 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xaccb3f3a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbbeac21b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb9cf31e1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf6ccea7b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent,--output truncated--
```

## ServerNIC Log

```
SERVERNIC: stats wan_delay: held=48/8192 released=154
SERVERNIC: SYN: new flow, V=0xb0d80d22
SERVERNIC: SYN-ACK: delta=0xa4502f68, V=0xb0d80d22, real_isn=0x0c87ddba
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x297b9ee7
SERVERNIC: SYN-ACK: delta=0x22cd7fa0, V=0x297b9ee7, real_isn=0x06ae1f47
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x0352a4e6
SERVERNIC: SYN-ACK: delta=0x77a5fcae, V=0x0352a4e6, real_isn=0x8baca838
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xb35829f6
SERVERNIC: SYN-ACK: delta=0xc89f1f25, V=0xb35829f6, real_isn=0xeab90ad1
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x0905f8b4
SERVERNIC: SYN-ACK: delta=0x19e092f2, V=0x0905f8b4, real_isn=0xef2565c2
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe1d35e3c
SERVERNIC: SYN-ACK: delta=0xbd04a9ba, V=0xe1d35e3c, real_isn=0x24ceb482
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x49fc53c9
SERVERNIC: SYN-ACK: delta=0xc5614ae7, V=0x49fc53c9, real_isn=0x849b08e2
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe3b97af3
SERVERNIC: SYN-ACK: delta=0x49257c5a, V=0xe3b97af3, real_isn=0x9a93fe99
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x66bbca98
SERVERNIC: SYN-ACK: delta=0xb1cada5b, V=0x66bbca98, real_isn=0xb4f0f03d
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x180e04f7
SERVERNIC:--output truncated--
```

## Server Log

```
[1;33m[19:14:56] Killing any leftover load-generator processes...[0m
[1;33m[19:14:57] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:14:57] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:14:57] Server VM IP: 10.1.2.91[0m
[1;33m[19:14:57] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:14:57] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 273408 bytes across 267 connections (so far)
Received 1297408 bytes across 1267 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.198 p50_ms=0.224 p95_ms=0.365 p99_ms=0.440 max_ms=2.199 mean_ms=0.239
summary=fct node=client n=2000 min_ms=100.517 p50_ms=100.631 p95_ms=100.845 p99_ms=101.007 max_ms=102.497 mean_ms=100.665
summary=server_gap node=server n=2000 min_ms=0.101 p50_ms=0.220 p95_ms=0.375 p99_ms=0.521 max_ms=2.141 mean_ms=0.237
```
