# Integration Test Report — 2026-10-03

**Implementation**: DPDK (ISN ack-num translation shift)
**ClientNIC binary**: `src/clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `src/servernic/dpdk/` (full translator)
**Experiment script**: `experiments/run.sh`
**Node scripts**: `experiments/nodes/` (clientnic/servernic/client/server)
**Overall result**: ALL PASSED

## Load Parameters

Must match the baseline run being compared against — see
`experiments/reports/baseline/`.

| Parameter | Value |
|---|---|
| Rounds | 1 |
| `LOAD_PARALLEL` | 2000 |
| `LOAD_PORTS` | 4 |
| `LOAD_BYTES` | 1024 |
| `LOAD_RATE` | 100 conn/s |
| `LOAD_CONCURRENCY` | 2000 |
| `NETEM_RTT_MS` | 100 (ClientNIC↔ServerNIC leg, half per direction) |

## Latency Summary

`Send unlock` is the primary result: first SYN out → first payload out,
which is exactly what the spoofed SYN-ACK unblocks. Compare it against the
baseline's `Send unlock`; the expected saving is one `NETEM_RTT_MS`.

```
  ── Primary: time-to-first-byte the client actually experiences ──
  Send unlock   : n=2000  min=0.305  mean=0.343  median=0.338  p95=0.364  p99=0.420  max=3.106 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.788  mean=100.928  median=100.892  p95=101.072  p99=101.154  max=103.624 ms
  Server gap    : n=2000  min=0.088  mean=0.308  median=0.278  p95=0.498  p99=0.514  max=2.057 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 100 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=100 conn/s requested, 100 conn/s achieved over 19.991s
Think: 0 ms between connect() and first write
Transfer complete: 2000/2000 connections ok, 0 failed, duration=20.002s, ~0.8 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xad2e1cb2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfcd26f37 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe5d939b5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x192a409e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6754a2d9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xccdcd16e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc6f36288 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfef0a67d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x717969a5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0dbd10c0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc0e2f9c1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x89fcf4ed in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe60c246d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4fa0543b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x941709d8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcbaa808d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x54c20519 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5c7f0e28 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x69769e6e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6f55b668 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2209e7b2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xba1ffaec in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x29b70661 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x12424d49 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x232d1a03 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x21ddd782 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdf874965 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x51e5a5ca in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6e17eca4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7dfca4eb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xabbaf7b9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1f8105f4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe502426a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x296f362e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb903bebf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8e49eccb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x54e4e990 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x01ce8d22 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcaf06db4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6b04389d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x033ec469 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x98610545 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd6d47f43 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc3da9322 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf5f11148 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1b603923 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8ef593bb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x755c1134 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x693bb4f4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded wi--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: delta=0x12f7803e, V=0x7269455e, real_isn=0x5f71c520
SERVERNIC: SYN: new flow, V=0xeeb18915
SERVERNIC: SYN-ACK: delta=0x52317e41, V=0xeeb18915, real_isn=0x9c800ad4
SERVERNIC: SYN: new flow, V=0x3a0f0390
SERVERNIC: SYN-ACK: delta=0x6c202d02, V=0x3a0f0390, real_isn=0xcdeed68e
SERVERNIC: SYN: new flow, V=0x9eaa6d65
SERVERNIC: SYN-ACK: delta=0xf7f4d790, V=0x9eaa6d65, real_isn=0xa6b595d5
SERVERNIC: SYN: new flow, V=0x879dcad5
SERVERNIC: SYN-ACK: delta=0x971ede49, V=0x879dcad5, real_isn=0xf07eec8c
SERVERNIC: SYN: new flow, V=0x2d0d822f
SERVERNIC: SYN-ACK: delta=0x7c6ceb13, V=0x2d0d822f, real_isn=0xb0a0971c
SERVERNIC: SYN: new flow, V=0x415542d1
SERVERNIC: SYN-ACK: delta=0xbfdff6d1, V=0x415542d1, real_isn=0x81754c00
SERVERNIC: SYN: new flow, V=0x465e701c
SERVERNIC: SYN-ACK: delta=0x7cddc6da, V=0x465e701c, real_isn=0xc980a942
SERVERNIC: SYN: new flow, V=0x9e4393be
SERVERNIC: SYN-ACK: delta=0x467662be, V=0x9e4393be, real_isn=0x57cd3100
SERVERNIC: SYN: new flow, V=0x1cb90c3a
SERVERNIC: SYN-ACK: delta=0xf27ce6db, V=0x1cb90c3a, real_isn=0x2a3c255f
SERVERNIC: SYN: new flow, V=0xf31b230e
SERVERNIC: SYN-ACK: delta=0x41a12720, V=0xf31b230e, real_isn=0xb179fbee
SERVERNIC: SYN: new flow, V=0x15a376c3
SERVERNIC: SYN-ACK: delta=0x271946e7, V=0x15a376c3, real_isn=0xee8a2fdc
SERVERNIC: SYN: new flow, V=0xb7cb0b32
SERVERNIC: SYN-ACK: delta=0x47e61138, V=0xb7cb0b32, real_isn=0x6fe4f9fa
SERVERNIC: SYN: new flow, V=0x1534fc9d
SERVERNIC: SYN-ACK: delta=0xd781a861, V=0x1534fc9d, real_isn=0x3db3543c
SERVERNIC: SYN: new flow, V=0x9fcdf0ff
SERVERNIC: SYN-ACK: delta=0x5e3e8044, V=0x9fcdf0ff, real_isn=0x418f70bb
SERVERNIC: stats ClientNIC-facing (port 0): rx=860 tx=339 imissed=0 rx_nombuf=0 ierrors=0--output truncated--
```

## Server Log

```
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            experiments/quic-comparison-2026-10-03 -> FETCH_HEAD
HEAD is now at e0b28dd ci: experiment baseline bundle 20261003-145040 [skip ci]
[1;33m[14:53:12] Server VM IP: 10.1.2.204[0m
[1;33m[14:53:12] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[14:53:12] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 72704 bytes across 71 connections (so far)
Received 276480 bytes across 270 connections (so far)
Received 482304 bytes across 471 connections (so far)
Received 686080 bytes across 670 connections (so far)
Received 891904 bytes across 871 connections (so far)
Received 1096704 bytes across 1071 connections (so far)
Received 1301504 bytes across 1271 connections (so far)
Received 1506304 bytes across 1471 connections (so far)
Received 1711104 bytes across 1671 connections (so far)
Received 1915904 bytes across 1871 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.305 p50_ms=0.338 p95_ms=0.364 p99_ms=0.420 max_ms=3.106 mean_ms=0.343
summary=fct node=client n=2000 min_ms=100.788 p50_ms=100.892 p95_ms=101.072 p99_ms=101.154 max_ms=103.624 mean_ms=100.928
summary=server_gap node=server n=2000 min_ms=0.088 p50_ms=0.278 p95_ms=0.498 p99_ms=0.514 max_ms=2.057 mean_ms=0.308
```
