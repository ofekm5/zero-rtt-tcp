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
  Send unlock   : n=2000  min=0.197  mean=0.329  median=0.391  p95=0.438  p99=0.464  max=2.253 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=100.532  mean=100.723  median=100.715  p95=100.934  p99=101.033  max=102.747 ms
  Server gap    : n=2000  min=0.108  mean=0.301  median=0.311  p95=0.502  p99=0.577  max=2.199 ms
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
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xaaff0b42 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb71907e6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9001ab6e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4222cdc8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb4f87be8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbe542300 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcef3d85b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4c924186 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xba86c4a0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8921a4f1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd13d5c8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x23fa9fb5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcfc2cb9c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe6bdd92c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa391f3f2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa541e4fe in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x273d5ad9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1825e00e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x556ca155 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc1c54608 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x37d75c85 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1851beb1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x21ac7d52 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa536302f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7d0437d0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x123f3918 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x54e54f8b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5dda0cc0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x07b469a0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x02f80489 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe4d4dedf in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5999d96b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8a7be59d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x31a22fc8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x95f6edc1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa199f5ff in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcc39a0b2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x97143d22 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5732177f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1bf9407c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd6e66eb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xaa7b4b0f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2ef55420 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0d3f7330 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7d566eec in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x763d800f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x65860945 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5cb4333d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x83bcdf27 in ack-num
FORWARDER: SYN: spoofed--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN: new flow, V=0x9abd2ec2
SERVERNIC: SYN-ACK: delta=0xbfb596d8, V=0x9abd2ec2, real_isn=0xdb0797ea
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x8fba04fe
SERVERNIC: SYN-ACK: delta=0x93336f67, V=0x8fba04fe, real_isn=0xfc869597
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xc1f2ddd3
SERVERNIC: SYN-ACK: delta=0xb2d37860, V=0xc1f2ddd3, real_isn=0x0f1f6573
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xeb432d1e
SERVERNIC: SYN-ACK: delta=0x68152006, V=0xeb432d1e, real_isn=0x832e0d18
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x8bc0bb1d
SERVERNIC: SYN-ACK: delta=0x91ee552d, V=0x8bc0bb1d, real_isn=0xf9d265f0
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xeb260ae3
SERVERNIC: SYN-ACK: delta=0x3f543d2d, V=0xeb260ae3, real_isn=0xabd1cdb6
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x5467708c
SERVERNIC: SYN-ACK: delta=0x78364bfa, V=0x5467708c, real_isn=0xdc312492
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xcd29695f
SERVERNIC: SYN-ACK: delta=0xc3157e9a, V=0xcd29695f, real_isn=0x0a13eac5
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x56e82395
SERVERNIC: SYN-ACK: delta=0xf0597170, V=0x56e82395, real_isn=0x668eb225
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x42688c1e
SERVERNIC: SYN-ACK: delta=0xf4711570, V=0x42688c1e, real_isn=0x4df776ae
SERVERNIC: SYN-ACK: flushed 1 buffered--output truncated--
```

## Server Log

```
[1;33m[18:44:43] Killing any leftover load-generator processes...[0m
[1;33m[18:44:44] Open-file limit (ulimit -n): 1048576[0m
[1;33m[18:44:44] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at fad594b Merge pull request #30 from ofekm5/fix/secret-rename
[1;33m[18:44:44] Server VM IP: 10.1.2.91[0m
[1;33m[18:44:44] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[18:44:44] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 472064 bytes across 461 connections (so far)
Received 1496064 bytes across 1461 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=0.197 p50_ms=0.391 p95_ms=0.438 p99_ms=0.464 max_ms=2.253 mean_ms=0.329
summary=fct node=client n=2000 min_ms=100.532 p50_ms=100.715 p95_ms=100.934 p99_ms=101.033 max_ms=102.747 mean_ms=100.723
summary=server_gap node=server n=2000 min_ms=0.108 p50_ms=0.311 p95_ms=0.502 p99_ms=0.577 max_ms=2.199 mean_ms=0.301
```
