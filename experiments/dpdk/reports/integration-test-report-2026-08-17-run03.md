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
  Send unlock   : n=2000  min=0.195  mean=0.228  median=0.219  p95=0.284  p99=0.415  max=2.207 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.544  mean=100.651  median=100.614  p95=100.802  p99=100.941  max=102.510 ms
  Server gap    : n=2000  min=0.121  mean=0.224  median=0.199  p95=0.320  p99=0.510  max=2.027 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc6028498 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa33bf647 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4aa44373 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb2a90781 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6130f0c2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5e503d0d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x55e4dc5c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xee0d8ad3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xaa8e8278 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb799b243 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdfe9ef69 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0979177c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6c8dbd8d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x893bbb20 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x91f6fcdb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x98a0ff50 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xddf1bb27 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd1cb6da4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5857e9d7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x79a61672 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf39a64eb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc5b4ffe1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2a4bce4a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe5e93268 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3800aeb5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfb560761 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4ab2b916 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb05ff1bf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb152e130 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x23a4aaea in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfb790d3e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa88f9bf2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1fece529 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe71c228f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7d5513e2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5d453e23 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3a31105e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfca6f844 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x49ef7403 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x391a890e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4ca549c9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4af077e4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5938a70a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd6a8db6a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa8b01a80 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbbabc117 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x145eff63 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9182ecff in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x929c7946 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent,--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: delta=0x1d2f1558, V=0x4b1b1812, real_isn=0x2dec02ba
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x57a582c6
SERVERNIC: SYN-ACK: delta=0x6f90de25, V=0x57a582c6, real_isn=0xe814a4a1
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x7101fede
SERVERNIC: SYN-ACK: delta=0x6a9e8c40, V=0x7101fede, real_isn=0x0663729e
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x3722edf3
SERVERNIC: SYN-ACK: delta=0xac58a9ed, V=0x3722edf3, real_isn=0x8aca4406
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe0712fce
SERVERNIC: SYN-ACK: delta=0x895f9437, V=0xe0712fce, real_isn=0x57119b97
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x7aebda6b
SERVERNIC: SYN-ACK: delta=0x1db3073a, V=0x7aebda6b, real_isn=0x5d38d331
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xd907695d
SERVERNIC: SYN-ACK: delta=0x440a378a, V=0xd907695d, real_isn=0x94fd31d3
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xb529e357
SERVERNIC: SYN-ACK: delta=0x51e52351, V=0xb529e357, real_isn=0x6344c006
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x0acf0dea
SERVERNIC: SYN-ACK: delta=0xb1c26bab, V=0x0acf0dea, real_isn=0x590ca23f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x89aa643d
SERVERNIC: SYN-ACK: delta=0x26cc428b, V=0x89aa643d, real_isn=0x62de21b2
SERVERNIC: SYN: new flow, V=0xd7023775
SERVERNIC--output truncated--
```

## Server Log

```
[1;33m[18:57:21] Killing any leftover load-generator processes...[0m
[1;33m[18:57:22] Open-file limit (ulimit -n): 1048576[0m
[1;33m[18:57:22] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[18:57:23] Server VM IP: 10.1.2.91[0m
[1;33m[18:57:23] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[18:57:23] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 223232 bytes across 218 connections (so far)
Received 1248256 bytes across 1219 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.195 p50_ms=0.219 p95_ms=0.284 p99_ms=0.415 max_ms=2.207 mean_ms=0.228
summary=fct node=client n=2000 min_ms=100.544 p50_ms=100.614 p95_ms=100.802 p99_ms=100.941 max_ms=102.510 mean_ms=100.651
summary=server_gap node=server n=2000 min_ms=0.121 p50_ms=0.199 p95_ms=0.320 p99_ms=0.510 max_ms=2.027 mean_ms=0.224
```
