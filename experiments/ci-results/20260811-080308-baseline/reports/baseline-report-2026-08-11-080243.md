# Baseline TCP Report — 2026-08-11-080243

**Mode**: Plain TCP (no 0-RTT middleware)
**Infra**: `infra/baseline` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding
**Overall result**: ALL PASSED ✅

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
  Send unlock   : n=74569  min=100.876  mean=4467.436  median=464.566  p95=64658.220  p99=66500.261  max=67382.001 ms
  ── Secondary (throughput-bound; not evidence about the handshake) ──
  Pcap FCT      : n=74569  min=201.840  mean=46003.253  median=790.212  p95=228137.031  p99=237074.801  max=242673.713 ms
  Server gap    : n=74569  min=100.875  mean=438.465  median=459.439  p95=809.957  p99=1706.900  max=2098.473 ms
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 100000 total connections, 1024 bytes/conn, 2000 conn/s arrival, 0ms think, max 2000 in flight ---
Arrival: rate=2000 conn/s requested, 2000 conn/s achieved over 50.000s
Think: 0 ms between connect() and first write
Transfer complete: 100000/100000 connections ok, 0 failed, duration=242.812s, ~3.4 Mbits/sec
Success: 100000/100000
Success: 1/1
```

## Endpoint Packet Analysis

```
summary=send_unlock node=client n=74569 min_ms=100.876 p50_ms=464.566 p95_ms=64658.220 p99_ms=66500.261 max_ms=67382.001 mean_ms=4467.436
summary=fct node=client n=74569 min_ms=201.840 p50_ms=790.212 p95_ms=228137.031 p99_ms=237074.801 max_ms=242673.713 mean_ms=46003.253
summary=server_gap node=server n=74569 min_ms=100.875 p50_ms=459.439 p95_ms=809.957 p99_ms=1706.900 max_ms=2098.473 mean_ms=438.465
```

## Server Log

```
Received 49154048 bytes across 48002 connections (so far)
Received 52420608 bytes across 51192 connections (so far)
Received 53801984 bytes across 52541 connections (so far)
Received 56398848 bytes across 55077 connections (so far)
Received 60386304 bytes across 58971 connections (so far)
Received 62491648 bytes across 61027 connections (so far)
Received 66588672 bytes across 65028 connections (so far)
Received 72053760 bytes across 70365 connections (so far)
Received 76621824 bytes across 74826 connections (so far)
Received 78669824 bytes across 76826 connections (so far)
Received 80650240 bytes across 78760 connections (so far)
Received 85826560 bytes across 83815 connections (so far)
Received 90445824 bytes across 88326 connections (so far)
Received 95493120 bytes across 93255 connections (so far)
Received 100201472 bytes across 97853 connections (so far)
Received 102282240 bytes across 99885 connections (so far)
Received 102282240 bytes across 99885 connections (final)
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
