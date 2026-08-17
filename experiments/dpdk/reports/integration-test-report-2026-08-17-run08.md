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
  Send unlock   : n=2000  min=0.196  mean=0.230  median=0.222  p95=0.279  p99=0.411  max=2.186 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.510  mean=100.621  median=100.586  p95=100.785  p99=100.869  max=102.518 ms
  Server gap    : n=2000  min=0.105  mean=0.213  median=0.192  p95=0.314  p99=0.384  max=2.131 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x81042577 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3533e078 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4170ecf3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x40492e6e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5661a15e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4c2a15ca in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb8d5423a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe011f83b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5ad5db91 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0d9076d3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbc54e7d8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfa4e2fa1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdbcc587d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x70bbff4f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcd88a244 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x35405e92 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x147db34b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe0094fa6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbb79f7fc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2a8ce9b2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x43dd86ec in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3fc74c20 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe7c921b8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcd0eab38 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6e5dbc4f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x12381614 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe9cab701 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x661dfce1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x22b1849f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb63d91d6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe5a9a907 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc72a6e23 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x65a4cda4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4b07de62 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x995296fd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa95d953c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2467097a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x875b6577 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfb4f3b09 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xad7b5a99 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x039cddef in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa81c50f2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0fc97e92 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8274f02b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5d81ec73 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1b86f051 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd00c38fb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x957d07cd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xce5d2716 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: delta=0x1cfafb18, V=0x5f0fec64, real_isn=0x4214f14c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xab603ef0
SERVERNIC: SYN-ACK: delta=0xbaaf6f2d, V=0xab603ef0, real_isn=0xf0b0cfc3
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x2a2d582e
SERVERNIC: SYN-ACK: delta=0x140e2fce, V=0x2a2d582e, real_isn=0x161f2860
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x1b5f0465
SERVERNIC: SYN-ACK: delta=0xb3b3826a, V=0x1b5f0465, real_isn=0x67ab81fb
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x3b47b7c2
SERVERNIC: SYN-ACK: delta=0x83d62405, V=0x3b47b7c2, real_isn=0xb77193bd
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x07665ce1
SERVERNIC: SYN-ACK: delta=0x82e2eb2a, V=0x07665ce1, real_isn=0x848371b7
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x822318e9
SERVERNIC: SYN-ACK: delta=0x3a065fc5, V=0x822318e9, real_isn=0x481cb924
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xd8a1e2d3
SERVERNIC: SYN-ACK: delta=0x5368996b, V=0xd8a1e2d3, real_isn=0x85394968
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xcb763178
SERVERNIC: SYN-ACK: delta=0x8954b51e, V=0xcb763178, real_isn=0x42217c5a
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xcedb74f0
SERVERNIC: SYN-ACK: delta=0x122f88de, V=0xcedb74f0, real_isn=0xbcabec12
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, --output truncated--
```

## Server Log

```
[1;33m[19:26:39] Killing any leftover load-generator processes...[0m
[1;33m[19:26:40] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:26:40] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:26:41] Server VM IP: 10.1.2.91[0m
[1;33m[19:26:41] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:26:41] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 18432 bytes across 18 connections (so far)
Received 1042432 bytes across 1018 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.196 p50_ms=0.222 p95_ms=0.279 p99_ms=0.411 max_ms=2.186 mean_ms=0.230
summary=fct node=client n=2000 min_ms=100.510 p50_ms=100.586 p95_ms=100.785 p99_ms=100.869 max_ms=102.518 mean_ms=100.621
summary=server_gap node=server n=2000 min_ms=0.105 p50_ms=0.192 p95_ms=0.314 p99_ms=0.384 max_ms=2.131 mean_ms=0.213
```
