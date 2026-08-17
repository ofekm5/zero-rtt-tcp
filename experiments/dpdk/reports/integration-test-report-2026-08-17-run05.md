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
  Send unlock   : n=2000  min=0.200  mean=0.239  median=0.223  p95=0.410  p99=0.440  max=2.165 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.514  mean=100.639  median=100.600  p95=100.813  p99=100.913  max=102.646 ms
  Server gap    : n=2000  min=0.120  mean=0.211  median=0.187  p95=0.365  p99=0.400  max=2.120 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x10f5636e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x05611204 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1a13bde4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x04bc5930 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x172df5a2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x61801f3a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x20399baa in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbf7ba48e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf7a3e70e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2fc13818 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x26fd4dfb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x222433e1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4c94580f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x654eb7ab in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x55300484 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x003418c4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7aa5ecc8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0ab09b20 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfd7e7bc3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xec74fb98 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa41bf7bf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1029c179 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc4646e56 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xae888e47 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4ef3e777 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x72f8f2fc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe41b8a4f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd34ae054 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3690d9c5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa6072e69 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb03ddcf2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc2bc48f2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x82b72f21 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xef811448 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb4d326ba in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x54ea6b22 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc3bdd435 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x71325db6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2ba1da89 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x532600ec in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd24a5425 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xba6bba6c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8336c1d3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4503c028 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd92c2ed6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb13eae41 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb58a5161 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x275cef9e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2184d57a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8f42f6bf in ack-num--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xafa91cc7
SERVERNIC: SYN-ACK: delta=0x77120933, V=0xafa91cc7, real_isn=0x38971394
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe7639d82
SERVERNIC: SYN-ACK: delta=0x8017a751, V=0xe7639d82, real_isn=0x674bf631
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x44ecc4b9
SERVERNIC: SYN-ACK: delta=0x398eff1d, V=0x44ecc4b9, real_isn=0x0b5dc59c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x61b62bb0
SERVERNIC: SYN-ACK: delta=0xcef68b82, V=0x61b62bb0, real_isn=0x92bfa02e
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x35e40fc7
SERVERNIC: SYN-ACK: delta=0x3f114207, V=0x35e40fc7, real_isn=0xf6d2cdc0
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc8080e3a
SERVERNIC: SYN-ACK: delta=0x96b46263, V=0xc8080e3a, real_isn=0x3153abd7
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xee9cd6a7
SERVERNIC: SYN-ACK: delta=0x3e025408, V=0xee9cd6a7, real_isn=0xb09a829f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf541ad7e
SERVERNIC: SYN-ACK: delta=0x80678e88, V=0xf541ad7e, real_isn=0x74da1ef6
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x4f191836
SERVERNIC: SYN-ACK: delta=0x60e54f35, V=0x4f191836, real_isn=0xee33c901
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x7287a4c6
SERVERNIC--output truncated--
```

## Server Log

```
[1;33m[19:09:09] Killing any leftover load-generator processes...[0m
[1;33m[19:09:10] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:09:10] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:09:10] Server VM IP: 10.1.2.91[0m
[1;33m[19:09:10] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:09:10] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 984064 bytes across 961 connections (so far)
Received 2008064 bytes across 1961 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.200 p50_ms=0.223 p95_ms=0.410 p99_ms=0.440 max_ms=2.165 mean_ms=0.239
summary=fct node=client n=2000 min_ms=100.514 p50_ms=100.600 p95_ms=100.813 p99_ms=100.913 max_ms=102.646 mean_ms=100.639
summary=server_gap node=server n=2000 min_ms=0.120 p50_ms=0.187 p95_ms=0.365 p99_ms=0.400 max_ms=2.120 mean_ms=0.211
```
