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
  Send unlock   : n=2000  min=0.197  mean=0.230  median=0.220  p95=0.287  p99=0.414  max=2.200 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.511  mean=100.627  median=100.596  p95=100.786  p99=100.884  max=102.552 ms
  Server gap    : n=2000  min=0.117  mean=0.214  median=0.190  p95=0.318  p99=0.380  max=2.152 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8175d23b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc3a7e1a4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6f4a1f0e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7eac2c88 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0a852110 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0526828e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc0b8576f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x75031694 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x655ee0e1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x07f63598 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1cca8a8d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbeef92ff in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x222785a0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcbcb5555 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x42cd6dcd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc95e6223 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5dfda787 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x77ded082 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8e01b40e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4fff51e4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd00efc35 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x847399a8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x39e0b842 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb43474c8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6ba13183 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x20879ccd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x53ada7b8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9440a232 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x28272651 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x84725bb1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3f8c1398 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3476cb9b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6e5d71b1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbb7066f0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb3867527 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x223b248f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf9ea828b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd9aa207e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbafde0bd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa031d87c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1703254b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd849e840 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd972444 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x65311ef2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8ce491c0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe5303100 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3378be13 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x96df3f87 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x657f44f7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent,--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x430c238e
SERVERNIC: SYN-ACK: delta=0xca2d12a1, V=0x430c238e, real_isn=0x78df10ed
SERVERNIC: SYN: new flow, V=0x941fa242
SERVERNIC: SYN-ACK: delta=0x73917966, V=0x941fa242, real_isn=0x208e28dc
SERVERNIC: SYN: new flow, V=0xb0073796
SERVERNIC: SYN-ACK: delta=0xfe0eb0b9, V=0xb0073796, real_isn=0xb1f886dd
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc0a6da90
SERVERNIC: SYN-ACK: delta=0xfc10b466, V=0xc0a6da90, real_isn=0xc496262a
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe24077ca
SERVERNIC: SYN-ACK: delta=0xa504ee1b, V=0xe24077ca, real_isn=0x3d3b89af
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xa4e520b1
SERVERNIC: SYN-ACK: delta=0x142fa8bd, V=0xa4e520b1, real_isn=0x90b577f4
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x23b7f56a
SERVERNIC: SYN-ACK: delta=0xb6e69458, V=0x23b7f56a, real_isn=0x6cd16112
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xbdfe2df1
SERVERNIC: SYN-ACK: delta=0xbbdd72ee, V=0xbdfe2df1, real_isn=0x0220bb03
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x7a05e95e
SERVERNIC: SYN-ACK: delta=0xb246e0f6, V=0x7a05e95e, real_isn=0xc7bf0868
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf8a41287
SERVERNIC: SYN-ACK: delta=0xaded4b43, V=0xf8a41287, real_isn=0x4ab6c744
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
--output truncated--
```

## Server Log

```
[1;33m[19:32:22] Killing any leftover load-generator processes...[0m
[1;33m[19:32:23] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:32:23] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:32:24] Server VM IP: 10.1.2.91[0m
[1;33m[19:32:24] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:32:24] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 830464 bytes across 811 connections (so far)
Received 1854464 bytes across 1811 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.197 p50_ms=0.220 p95_ms=0.287 p99_ms=0.414 max_ms=2.200 mean_ms=0.230
summary=fct node=client n=2000 min_ms=100.511 p50_ms=100.596 p95_ms=100.786 p99_ms=100.884 max_ms=102.552 mean_ms=100.627
summary=server_gap node=server n=2000 min_ms=0.117 p50_ms=0.190 p95_ms=0.318 p99_ms=0.380 max_ms=2.152 mean_ms=0.214
```
