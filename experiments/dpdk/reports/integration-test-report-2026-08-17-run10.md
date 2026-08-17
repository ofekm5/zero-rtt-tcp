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
  Send unlock   : n=2000  min=0.202  mean=0.233  median=0.224  p95=0.265  p99=0.429  max=2.245 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.512  mean=100.629  median=100.596  p95=100.787  p99=100.896  max=102.550 ms
  Server gap    : n=2000  min=0.119  mean=0.218  median=0.194  p95=0.317  p99=0.412  max=2.206 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x50fb9fdc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x74783075 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x96f7a6ff in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x45afd51e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbdf211bc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0c44846a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe148cf24 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8fcefbaf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9de8a69f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x288db95b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x26bff487 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb0ab55df in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x787e3a12 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9087a7c2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x43a7ea5d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x06057a23 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x60c60398 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc08e26a2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x57cd0989 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3d531d61 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2c601336 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xed1feb9c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf5da3f50 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa2da11f2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf425c3c7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6d4be605 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8375510b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x564deb14 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd73a2685 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe8881e38 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3a303052 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4e95f01e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb7ebfdf1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x955b6c34 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa37c8726 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x10950739 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc636c208 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4b272337 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3788124a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9dd70ffc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x066c7c26 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x17daba8e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xae1da0f0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xedc3154e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4830f79d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x192f3f23 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x278c44b9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcc0e8745 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfe5fc71d in ack-num
FORWARDER: SYN: spoofed SYN---output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: delta=0xdd661d81, V=0xb32d82a5, real_isn=0xd5c76524
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf43c28a4
SERVERNIC: SYN-ACK: delta=0x4b4a56cb, V=0xf43c28a4, real_isn=0xa8f1d1d9
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf5fe0010
SERVERNIC: SYN-ACK: delta=0x0291d0b4, V=0xf5fe0010, real_isn=0xf36c2f5c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xe075eb03
SERVERNIC: SYN-ACK: delta=0xdee7e36f, V=0xe075eb03, real_isn=0x018e0794
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x4e78634a
SERVERNIC: SYN-ACK: delta=0xee33e3ea, V=0x4e78634a, real_isn=0x60447f60
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xb468bf83
SERVERNIC: SYN-ACK: delta=0xbf31dc2e, V=0xb468bf83, real_isn=0xf536e355
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x4cdd55d8
SERVERNIC: SYN-ACK: delta=0xfbafd585, V=0x4cdd55d8, real_isn=0x512d8053
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x26d3dc29
SERVERNIC: SYN-ACK: delta=0x91cad899, V=0x26d3dc29, real_isn=0x95090390
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x92817b8e
SERVERNIC: SYN-ACK: delta=0xd01c72eb, V=0x92817b8e, real_isn=0xc26508a3
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x8071dcc6
SERVERNIC: SYN-ACK: delta=0xedf6b6ec, V=0x8071dcc6, real_isn=0x927b25da
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new--output truncated--
```

## Server Log

```
[1;33m[19:38:01] Killing any leftover load-generator processes...[0m
[1;33m[19:38:02] Open-file limit (ulimit -n): 1048576[0m
[1;33m[19:38:02] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[19:38:03] Server VM IP: 10.1.2.91[0m
[1;33m[19:38:03] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[19:38:03] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 928768 bytes across 907 connections (so far)
Received 1953792 bytes across 1908 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.202 p50_ms=0.224 p95_ms=0.265 p99_ms=0.429 max_ms=2.245 mean_ms=0.233
summary=fct node=client n=2000 min_ms=100.512 p50_ms=100.596 p95_ms=100.787 p99_ms=100.896 max_ms=102.550 mean_ms=100.629
summary=server_gap node=server n=2000 min_ms=0.119 p50_ms=0.194 p95_ms=0.317 p99_ms=0.412 max_ms=2.206 mean_ms=0.218
```
