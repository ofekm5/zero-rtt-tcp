# Baseline TCP Report — 2026-08-17-212656

**Mode**: Plain TCP (no 0-RTT middleware)
**Infra**: `infra/baseline` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding
**Overall result**: 1 FAILURE(S) ❌

## Load Parameters

These must match the 0-RTT run being compared against, or the comparison
is confounded. Both stacks read them from `experiments/utils/measure.sh`
and configure endpoints via `experiments/utils/endpoint.sh`.

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

```
  ── Primary: time-to-first-byte the client actually experiences ──
  Send unlock   : n=75932  min=100.947  mean=4018.311  median=357.358  p95=64105.749  p99=65695.463  max=140185.727 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=75932  min=201.879  mean=41266.905  median=555.464  p95=212526.486  p99=220443.147  max=228119.634 ms
  Server gap    : n=75932  min=100.934  mean=307.271  median=336.862  p95=704.386  p99=797.903  max=75686.082 ms
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 100000 total connections, 1024 bytes/conn, 2000 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=2000 conn/s requested, 2000 conn/s achieved over 50.000s
Think: 0 ms between connect() and first write
Transfer complete: 99728/100000 connections ok, 272 failed, duration=291.773s, ~2.8 Mbits/sec
Success: 99728/100000
Success: 0/1
```

## Endpoint Packet Analysis

```
summary=send_unlock node=client n=75932 min_ms=100.947 p50_ms=357.358 p95_ms=64105.749 p99_ms=65695.463 max_ms=140185.727 mean_ms=4018.311
summary=fct node=client n=75932 min_ms=201.879 p50_ms=555.464 p95_ms=212526.486 p99_ms=220443.147 max_ms=228119.634 mean_ms=41266.905
missing=first_outbound_payload node=client count=147
missing=last_data_or_FIN node=client count=147
summary=server_gap node=server n=75932 min_ms=100.934 p50_ms=336.862 p95_ms=704.386 p99_ms=797.903 max_ms=75686.082 mean_ms=307.271
missing=first_inbound_payload node=server count=32
```

## Server Log

```
Received 42294272 bytes across 41303 connections (so far)
Received 47358976 bytes across 46249 connections (so far)
Received 52401152 bytes across 51173 connections (so far)
Received 52420608 bytes across 51192 connections (so far)
Received 57675776 bytes across 56324 connections (so far)
Received 61995008 bytes across 60542 connections (so far)
Received 67709952 bytes across 66123 connections (so far)
Received 73302016 bytes across 71584 connections (so far)
Received 78211072 bytes across 76378 connections (so far)
Received 78296064 bytes across 76461 connections (so far)
Received 79267840 bytes across 77410 connections (so far)
Received 83580928 bytes across 81622 connections (so far)
Received 87970816 bytes across 85909 connections (so far)
Received 92323840 bytes across 90160 connections (so far)
Received 96164864 bytes across 93911 connections (so far)
Received 101888000 bytes across 99500 connections (so far)
Received 101888000 bytes across 99500 connections (final)
_GatheringFuture exception was never retrieved
future: <_GatheringFuture finished exception=CancelledError()>
concurrent.futures._base.CancelledError
```

## Notes

- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server
- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1
- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0
- Emulated RTT is applied entirely on the Server VM's egress, so the leg
  0-RTT short-circuits carries the full `NETEM_RTT_MS`. See endpoint.sh.
- **Compare `Send unlock` against `experiments/dpdk/reports/`** — that is
  the metric the 0-RTT mechanism acts on. FCT and server gap are
  throughput-bound and move with payload size and loss.
