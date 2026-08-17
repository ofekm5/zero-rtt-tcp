# Integration Test Report — 2026-08-17

**Implementation**: DPDK (ISN ack-num translation shift)
**ClientNIC binary**: `src/clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `src/servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: 1 FAILURE(S)

## Load Parameters

Must match the baseline run being compared against — see
`experiments/baseline-tcp/reports/`.

| Parameter | Value |
|---|---|
| Rounds | 1 |
| `LOAD_PARALLEL` | 100000 |
| `LOAD_PORTS` | 4 |
| `LOAD_BYTES` | 1024 |
| `LOAD_RATE` | 2000 conn/s |
| `LOAD_CONCURRENCY` | 2000 |
| `NETEM_RTT_MS` | 100 (Server egress only) |

## Latency Summary

`Send unlock` is the primary result: first SYN out → first payload out,
which is exactly what the spoofed SYN-ACK unblocks. Compare it against the
baseline's `Send unlock`; the expected saving is one `NETEM_RTT_MS`.

```
  ── Primary: time-to-first-byte the client actually experiences ──
  Send unlock   : n=87073  min=0.178  mean=793.060  median=0.444  p95=1016.975  p99=31656.071  max=31842.579 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=87073  min=100.499  mean=2253.220  median=100.905  p95=3152.039  p99=59311.440  max=89807.632 ms
  Server gap    : n=85158  min=0.098  mean=18.339  median=0.417  p95=165.337  p99=227.033  max=435.955 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 100000 total connections, 1024 bytes/conn, 2000 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=2000 conn/s requested, 2000 conn/s achieved over 50.000s
Think: 0 ms between connect() and first write
Transfer complete: 87073/100000 connections ok, 12927 failed, duration=985.027s, ~0.7 Mbits/sec
Success: 87073/100000
Success: 0/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa472baa3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x438e34b1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6a5dfaec in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9439e76f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8f3a3fdf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdf89052b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc664c670 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf087e9bc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf18078a5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc0309a80 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9eccb25c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x41bd0f42 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x90281f23 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x07a2812c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc5265cb7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc97a5931 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9dc8d042 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2b350c56 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8f08b1a2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7fd04e7b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf589d514 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe4fb4a6d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x69ea7684 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xda9a51a2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8ed9da60 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbab6bb3d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x424eb04c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1d227ea3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x00ef2580 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa7c40076 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x21ca244d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe8f13c37 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x229782a8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf99678d4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x00ec6f21 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1d2699f8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7f8fb540 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9c198bcd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcc2746f9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe5f7467d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x61c205be in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5373778a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc5b9b3ad in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0a11c78b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x215a81cd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x37507176 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6890ebd1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4ec7d238 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x330d9a18 in ack-num
FORWARDER: SYN--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: delta=0x42d26936, V=0xe294ecd1, real_isn=0x9fc2839b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xd2c91a7c
SERVERNIC: SYN: new flow, V=0x830e1880
SERVERNIC: SYN-ACK: delta=0x18c9ada0, V=0xd2c91a7c, real_isn=0xb9ff6cdc
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x3cfb4c87
SERVERNIC: SYN-ACK: delta=0xc801f627, V=0x830e1880, real_isn=0xbb0c2259
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x1003a928, V=0x3cfb4c87, real_isn=0x2cf7a35f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x2a86844e
SERVERNIC: SYN-ACK: delta=0xe4e74570, V=0x2a86844e, real_isn=0x459f3ede
SERVERNIC: SYN: new flow, V=0x4fc13377
SERVERNIC: SYN-ACK: delta=0xcc83ec4c, V=0x4fc13377, real_isn=0x833d472b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x26db05c8
SERVERNIC: SYN-ACK: delta=0x5aa9380f, V=0x26db05c8, real_isn=0xcc31cdb9
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x81f9d3dd
SERVERNIC: SYN: new flow, V=0xcd7e6ef2
SERVERNIC: SYN-ACK: delta=0x5432bb3e, V=0x81f9d3dd, real_isn=0x2dc7189f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x96502dbb, V=0xcd7e6ef2, real_isn=0x372e4137
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf13518c6
SERVERNIC: SYN-ACK: delta=0x54e0e12e, V=0xf13518c6, real_isn=0x9c543798
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x7995b73f
SERVERNIC: SYN-ACK: delta=0--output truncated--
```

## Server Log

```
Received 84225024 bytes across 82251 connections (so far)
Received 84346880 bytes across 82370 connections (so far)
Received 84589568 bytes across 82607 connections (so far)
Received 84814848 bytes across 82827 connections (so far)
Received 84926464 bytes across 82936 connections (so far)
Received 84935680 bytes across 82945 connections (so far)
Received 85339136 bytes across 83339 connections (so far)
Received 85498880 bytes across 83495 connections (so far)
Received 85679104 bytes across 83671 connections (so far)
Received 85868544 bytes across 83856 connections (so far)
Received 85956608 bytes across 83942 connections (so far)
Received 85966848 bytes across 83952 connections (so far)
Received 86116352 bytes across 84098 connections (so far)
Received 86190080 bytes across 84170 connections (so far)
Received 86321152 bytes across 84298 connections (so far)
Received 86502400 bytes across 84475 connections (so far)
Received 86577152 bytes across 84548 connections (so far)
Received 86580224 bytes across 84551 connections (so far)
Received 87063552 bytes across 85023 connections (so far)
Received 87189504 bytes across 85146 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=87073 min_ms=0.178 p50_ms=0.444 p95_ms=1016.975 p99_ms=31656.071 max_ms=31842.579 mean_ms=793.060
summary=fct node=client n=87073 min_ms=100.499 p50_ms=100.905 p95_ms=3152.039 p99_ms=59311.440 max_ms=89807.632 mean_ms=2253.220
summary=server_gap node=server n=85158 min_ms=0.098 p50_ms=0.417 p95_ms=165.337 p99_ms=227.033 max_ms=435.955 mean_ms=18.339
missing=first_inbound_payload node=server count=171
```
