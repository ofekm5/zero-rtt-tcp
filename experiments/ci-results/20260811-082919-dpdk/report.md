# Integration Test Report — 2026-08-11

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
  Send unlock   : n=84143  min=0.286  mean=766.158  median=0.562  p95=110.535  p99=31618.471  max=31755.087 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=84143  min=101.181  mean=1682.956  median=101.674  p95=332.833  p99=53487.684  max=113927.790 ms
  Server gap    : n=83040  min=0.315  mean=13.928  median=0.545  p95=99.774  p99=228.336  max=608.808 ms
  ── Data-plane internal (in-app rdtsc, not client-observed) ──
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 100000 total connections, 1024 bytes/conn, 2000 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=2000 conn/s requested, 2000 conn/s achieved over 50.000s
Think: 0 ms between connect() and first write
Transfer complete: 84143/100000 connections ok, 15857 failed, duration=1115.292s, ~0.6 Mbits/sec
Success: 84143/100000
Success: 0/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcd86bcf0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xca036a3b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4b9837f8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb9f98fed in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5e162fb9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd883e34 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xed504e57 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x69b5285c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6ee88a1e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x66532fda in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x91d1efd5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcb95404c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc52a9f97 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x76783f2b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe479a152 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1d75620b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc031efbd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd0090461 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x77b8125a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe3ecd3a5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x26f56ec9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd35b9b07 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x16024fa2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb5a13efe in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xdf151f08 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x950ff5b1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8c7c2436 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa4bd1545 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x24db087c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8653c2da in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfc04bf47 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4ce7758b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x80a49e2c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2fe1f756 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd87078e5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x173db401 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xae61bcb0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xac4d9666 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x99bfe9b0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd06c5d83 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbbe43172 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4338949f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0d8eb1fd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x210349f7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4f3c633b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7492b807 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0346a40c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1fd3f756 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9de343d3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forw--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x9c1e9377
SERVERNIC: SYN-ACK: delta=0xf1589292, V=0x9c1e9377, real_isn=0xaac600e5
SERVERNIC: SYN: new flow, V=0x12beed7f
SERVERNIC: SYN-ACK: delta=0x94e2ea85, V=0x12beed7f, real_isn=0x7ddc02fa
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf73684be
SERVERNIC: SYN-ACK: delta=0x8e50d9e6, V=0xf73684be, real_isn=0x68e5aad8
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xeef1f30b
SERVERNIC: SYN-ACK: delta=0xe81071ef, V=0xeef1f30b, real_isn=0x06e1811c
SERVERNIC: SYN: new flow, V=0x17d31acf
SERVERNIC: SYN-ACK: delta=0x1cbaab4c, V=0x17d31acf, real_isn=0xfb186f83
SERVERNIC: SYN: new flow, V=0xa1613151
SERVERNIC: SYN-ACK: delta=0xf460f770, V=0xa1613151, real_isn=0xad0039e1
SERVERNIC: SYN: new flow, V=0xfcdbf60b
SERVERNIC: SYN: new flow, V=0x1df8a1ac
SERVERNIC: SYN-ACK: delta=0xc86c5f0b, V=0xfcdbf60b, real_isn=0x346f9700
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x268d2ae4, V=0x1df8a1ac, real_isn=0xf76b76c8
SERVERNIC: SYN-ACK: flushed 3 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x49c9c340
SERVERNIC: SYN-ACK: delta=0x2e0f48e7, V=0x49c9c340, real_isn=0x1bba7a59
SERVERNIC: SYN: new flow, V=0x7a2d2de8
SERVERNIC: SYN-ACK: delta=0x25897cf3, V=0x7a2d2de8, real_isn=0x54a3b0f5
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x1cecb5be
SERVERNIC: SYN-ACK: delta=0x94f657a3, V=0x1cecb5be, real_isn=0x87f65e1b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xa--output truncated--
```

## Server Log

```
Received 78173184 bytes across 76341 connections (so far)
Received 78619648 bytes across 76777 connections (so far)
Received 78674944 bytes across 76831 connections (so far)
Received 78675968 bytes across 76832 connections (so far)
Received 79220736 bytes across 77364 connections (so far)
Received 79961088 bytes across 78087 connections (so far)
Received 80023552 bytes across 78148 connections (so far)
Received 80756736 bytes across 78864 connections (so far)
Received 81355776 bytes across 79449 connections (so far)
Received 81401856 bytes across 79494 connections (so far)
Received 81812480 bytes across 79895 connections (so far)
Received 81926144 bytes across 80006 connections (so far)
Received 82478080 bytes across 80545 connections (so far)
Received 82479104 bytes across 80546 connections (so far)
Received 82873344 bytes across 80931 connections (so far)
Received 83342336 bytes across 81389 connections (so far)
Received 83389440 bytes across 81435 connections (so far)
Received 83880960 bytes across 81915 connections (so far)
Received 84568064 bytes across 82586 connections (so far)
Received 85016576 bytes across 83024 connections (so far)
```

## Packet Analysis

```
summary=send_unlock node=client n=84143 min_ms=0.286 p50_ms=0.562 p95_ms=110.535 p99_ms=31618.471 max_ms=31755.087 mean_ms=766.158
summary=fct node=client n=84143 min_ms=101.181 p50_ms=101.674 p95_ms=332.833 p99_ms=53487.684 max_ms=113927.790 mean_ms=1682.956
summary=server_gap node=server n=83040 min_ms=0.315 p50_ms=0.545 p95_ms=99.774 p99_ms=228.336 max_ms=608.808 mean_ms=13.928
missing=first_inbound_payload node=server count=166
```
