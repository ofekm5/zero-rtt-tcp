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
  Send unlock   : n=2000  min=0.199  mean=0.230  median=0.221  p95=0.293  p99=0.422  max=2.219 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.532  mean=100.633  median=100.602  p95=100.790  p99=100.907  max=102.526 ms
  Server gap    : n=2000  min=0.119  mean=0.212  median=0.188  p95=0.315  p99=0.388  max=2.181 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x346cc11a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x88a1c6db in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9080a8c4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xaac408b4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x61cf2ce4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x97fa77bb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xecb45507 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x730fdf68 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x474e4982 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x439a6d92 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2e619931 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd2ad9220 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9cdf9257 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2c2146fb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4e163f39 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x42194dde in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x706f01db in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2b9994f6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x773521fb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb572564a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf7067a63 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf86afd44 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfa832d9d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x288e8371 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x633bf1d4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf0258497 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x062a63ac in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc5c9c788 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbae4af31 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2b772193 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb9173826 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe47ecb26 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3e493b28 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc7f1ca38 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1b8620af in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x745e9454 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2e372100 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xeb25895c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x631da320 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdbd239ad in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4189df53 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2c9a9cb9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x43f8c811 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd8a08734 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x63c6ba1d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc84d2ff2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbb376cf5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc364294b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1c36ef7a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent,--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN: new flow, V=0xa18bae24
SERVERNIC: SYN-ACK: delta=0xf0fb605d, V=0xa18bae24, real_isn=0xb0904dc7
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc89ed23e
SERVERNIC: SYN-ACK: delta=0xbd5ed7c7, V=0xc89ed23e, real_isn=0x0b3ffa77
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: stats ClientNIC-facing (port 0): rx=441 tx=146 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats Server-facing (port 1): rx=295 tx=440 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=13797/16383 low-water=13786
SERVERNIC: stats buffered: bytes=0/1073741824 (capacity-model ?7)
SERVERNIC: stats cycles_per_packet: 23939.2 (tsc_hz=3000000000, packets=736, capacity-model ?9/?12)
SERVERNIC: stats wan_delay: held=50/8192 released=146
SERVERNIC: SYN: new flow, V=0x300d3318
SERVERNIC: SYN-ACK: delta=0x898846a1, V=0x300d3318, real_isn=0xa684ec77
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x9340ba1b
SERVERNIC: SYN-ACK: delta=0xa2a60bcc, V=0x9340ba1b, real_isn=0xf09aae4f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x0de8aa85
SERVERNIC: SYN-ACK: delta=0xa816a08e, V=0x0de8aa85, real_isn=0x65d209f7
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x51d9de3a
SERVERNIC: SYN-ACK: delta=0xef42e3ce, V=0x51d9de3a, real_isn=0x6296fa6c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x90a1e0a2
SERVERNIC: SYN-ACK: delta=0xb384f675, V=0x90a1e0a2, real_isn=0xdd1cea2d
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xcc86ce43
SERVERNIC: SYN-ACK: delta=0xd4d81b97, V=0xcc86ce43, real_isn=0xf7aeb2ac
SERVERNIC: SYN-ACK: flushed 1 --output truncated--
```

## Server Log

```
[1;33m[19:20:53] Killing any leftover load-generator processes...[0m
[1;33m[19:20:54] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:20:54] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:20:55] Server VM IP: 10.1.2.91[0m
[1;33m[19:20:55] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:20:55] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 574464 bytes across 561 connections (so far)
Received 1598464 bytes across 1561 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.199 p50_ms=0.221 p95_ms=0.293 p99_ms=0.422 max_ms=2.219 mean_ms=0.230
summary=fct node=client n=2000 min_ms=100.532 p50_ms=100.602 p95_ms=100.790 p99_ms=100.907 max_ms=102.526 mean_ms=100.633
summary=server_gap node=server n=2000 min_ms=0.119 p50_ms=0.188 p95_ms=0.315 p99_ms=0.388 max_ms=2.181 mean_ms=0.212
```
