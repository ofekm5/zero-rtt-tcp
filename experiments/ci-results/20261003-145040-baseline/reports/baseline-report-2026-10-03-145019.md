# Baseline TCP Report — 2026-10-03-145019

**Mode**: Plain TCP (no 0-RTT middleware)
**Infra**: `infra/baseline` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding
**Overall result**: ALL PASSED ✅

## Load Parameters

These must match the 0-RTT run being compared against, or the comparison
is confounded. Both stacks read them from `experiments/lib/measure.sh`
and configure endpoints via `experiments/lib/endpoint.sh`.

| Parameter | Value |
|---|---|
| Rounds | 1 |
| `LOAD_PARALLEL` | 2000 |
| `LOAD_PORTS` | 4 |
| `LOAD_BYTES` | 1024 |
| `LOAD_RATE` | 100 conn/s |
| `LOAD_CONCURRENCY` | 2000 |
| `NETEM_RTT_MS` | 100 (ClientNIC↔ServerNIC leg, half per direction) |

## Latency Summary

```
  ── Primary: time-to-first-byte the client actually experiences ──
  Send unlock   : n=2000  min=100.644  mean=101.056  median=100.918  p95=101.328  p99=101.497  max=152.134 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=2000  min=201.328  mean=201.816  median=201.692  p95=202.086  p99=202.543  max=253.047 ms
  Server gap    : n=2000  min=100.572  mean=100.877  median=100.809  p95=101.225  p99=101.375  max=111.145 ms
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 100 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=100 conn/s requested, 100 conn/s achieved over 19.990s
Think: 0 ms between connect() and first write
Transfer complete: 2000/2000 connections ok, 0 failed, duration=20.102s, ~0.8 Mbits/sec
Success: 2000/2000
Success: 1/1
```

## Endpoint Packet Analysis

```
summary=send_unlock node=client n=2000 min_ms=100.644 p50_ms=100.918 p95_ms=101.328 p99_ms=101.497 max_ms=152.134 mean_ms=101.056
summary=fct node=client n=2000 min_ms=201.328 p50_ms=201.692 p95_ms=202.086 p99_ms=202.543 max_ms=253.047 mean_ms=201.816
summary=server_gap node=server n=2000 min_ms=100.572 p50_ms=100.809 p95_ms=101.225 p99_ms=101.375 max_ms=111.145 mean_ms=100.877
```

## Server Log

```
[1;33m[14:49:02] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[14:49:02] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 171008 bytes across 167 connections (so far)
Received 376832 bytes across 368 connections (so far)
Received 581632 bytes across 568 connections (so far)
Received 786432 bytes across 768 connections (so far)
Received 991232 bytes across 968 connections (so far)
Received 1196032 bytes across 1168 connections (so far)
Received 1400832 bytes across 1368 connections (so far)
Received 1605632 bytes across 1568 connections (so far)
Received 1810432 bytes across 1768 connections (so far)
Received 2015232 bytes across 1968 connections (so far)
Received 2048000 bytes across 2000 connections (so far)
Received 2048000 bytes across 2000 connections (final)
_GatheringFuture exception was never retrieved
future: <_GatheringFuture finished exception=CancelledError()>
concurrent.futures._base.CancelledError
```

## Notes

- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server
- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1
- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0
- Emulated RTT sits on the ClientNIC↔ServerNIC leg (netem, half per
  direction), the leg 0-RTT short-circuits. See endpoint.sh and
  measurement-methodology-review.md §E.
- **Compare `Send unlock` against `experiments/reports/0rtt/`** — that is
  the metric the 0-RTT mechanism acts on. FCT and server gap are
  throughput-bound and move with payload size and loss.
