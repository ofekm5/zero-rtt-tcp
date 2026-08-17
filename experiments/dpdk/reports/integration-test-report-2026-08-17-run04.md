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
  Send unlock   : n=2000  min=0.198  mean=0.235  median=0.223  p95=0.299  p99=0.423  max=2.266 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.521  mean=100.665  median=100.624  p95=100.834  p99=101.033  max=102.571 ms
  Server gap    : n=2000  min=0.113  mean=0.231  median=0.216  p95=0.330  p99=0.518  max=2.202 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x751d9724 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa6ea0231 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x78c46802 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x733d45af in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xda1b3e8c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1a4d2941 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdb0205cd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8a85ec6c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfc13fe7d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe8c2737d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6d804da8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9fd767be in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa4113452 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xeefa9426 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x454a1bbe in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x84737bbb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x72383847 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd54e72d0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa9bde213 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xffb94909 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x26c61067 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcacd370c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7dd97aed in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x553b7f6d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x308757e7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xda4d0c54 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9259f545 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x27337114 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7af5f4d9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9b52a9f1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb92e2704 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf344b532 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x016536f0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9e3cd324 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa480f1cc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x542ed2e7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7e713524 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb0fe042c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5f174d9d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7288dbed in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x73ef6a91 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9b0110b0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x634fb632 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x88c35420 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdbb34ad0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb5e017a5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x01f05603 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2848e613 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf7fab1c0 in ack-num
FORWAR--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x2fa69c78
SERVERNIC: SYN-ACK: delta=0x47ed4b0d, V=0x2fa69c78, real_isn=0xe7b9516b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xb71fe1f4
SERVERNIC: SYN-ACK: delta=0xe38c6a8a, V=0xb71fe1f4, real_isn=0xd393776a
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x0ad7d059
SERVERNIC: SYN-ACK: delta=0x9a815d5c, V=0x0ad7d059, real_isn=0x705672fd
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf1070bd9
SERVERNIC: SYN-ACK: delta=0x0233fb7d, V=0xf1070bd9, real_isn=0xeed3105c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x1999c63a
SERVERNIC: SYN-ACK: delta=0x3a8b84dc, V=0x1999c63a, real_isn=0xdf0e415e
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf9a4805b
SERVERNIC: SYN-ACK: delta=0x1da83c8c, V=0xf9a4805b, real_isn=0xdbfc43cf
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x3efef693
SERVERNIC: SYN-ACK: delta=0xb4e0dd1f, V=0x3efef693, real_isn=0x8a1e1974
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x8799ecc2
SERVERNIC: SYN-ACK: delta=0x016705f3, V=0x8799ecc2, real_isn=0x8632e6cf
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x8678fe51
SERVERNIC: SYN-ACK: delta=0xcf11abf6, V=0x8678fe51, real_isn=0xb767525b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x77e1ecda
SERVERNIC: SYN-ACK: delta=0x765fffcf, V=0x77e1ecda, real_isn=0--output truncated--
```

## Server Log

```
[1;33m[19:03:20] Killing any leftover load-generator processes...[0m
[1;33m[19:03:21] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:03:21] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:03:21] Server VM IP: 10.1.2.91[0m
[1;33m[19:03:21] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:03:21] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 168960 bytes across 165 connections (so far)
Received 1192960 bytes across 1165 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.198 p50_ms=0.223 p95_ms=0.299 p99_ms=0.423 max_ms=2.266 mean_ms=0.235
summary=fct node=client n=2000 min_ms=100.521 p50_ms=100.624 p95_ms=100.834 p99_ms=101.033 max_ms=102.571 mean_ms=100.665
summary=server_gap node=server n=2000 min_ms=0.113 p50_ms=0.216 p95_ms=0.330 p99_ms=0.518 max_ms=2.202 mean_ms=0.231
```
