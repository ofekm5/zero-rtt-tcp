# Baseline TCP Report — 2026-06-01

**Mode**: Plain TCP (no 0-RTT middleware)
**Infra**: `infra/baseline` CDK stack — 4× t3.micro, kernel forwarding
**Connections**: 20 sequential
**Overall result**: ALL PASSED ✅

## Check Results

| Step | Check | Result |
|------|-------|--------|
| 1 | ClientNIC + ServerNIC IP forwarding enabled | ✅ PASS |
| 2 | Static routes present on NIC VMs | ✅ PASS |
| 3 | Server listening on :8080 | ✅ PASS |
| 4 | Client: 20/20 connections succeeded | ✅ PASS |
| 5 | Server received data | ✅ PASS |

## TTFB Measurements

```
=== Repeated Connection Test (20 connections) ===
Server: 10.1.2.16:8080

  Connection 1: 2.42 ms
  Connection 2: 1.72 ms
  Connection 3: 1.55 ms
  Connection 4: 1.80 ms
  Connection 5: 1.79 ms
  Connection 6: 1.65 ms
  Connection 7: 1.78 ms
  Connection 8: 1.53 ms
  Connection 9: 5.68 ms
  Connection 10: 1.69 ms
  Connection 11: 1.60 ms
  Connection 12: 1.57 ms
  Connection 13: 1.95 ms
  Connection 14: 1.57 ms
  Connection 15: 1.61 ms
  Connection 16: 1.89 ms
  Connection 17: 1.84 ms
  Connection 18: 1.77 ms
  Connection 19: 1.54 ms
  Connection 20: 1.63 ms

Results:
  Success: 20/20 (100%)
  TTFB Statistics:
    Min:     1.53 ms
    Max:     5.68 ms
    Average: 1.93 ms
    Median:  1.71 ms
    Std Dev: 0.91 ms
```

## Failures / Notes

None.

- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server
- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1
- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0
- Connection 9 spike (5.68 ms) is an outlier; median 1.71 ms is a more representative baseline.

## Comparison

DPDK T8 figures are from single-connection runs (2026-05-30/31); baseline is 20 sequential connections.

| Metric | Baseline (today, 20 conn) | 0-RTT DPDK T8 (2026-05-30) | 0-RTT DPDK T8 (2026-05-31) |
|--------|--------------------------|----------------------------|----------------------------|
| TTFB min (ms) | 1.53 | 1.74 | 2.91 |
| TTFB avg (ms) | 1.93 | 1.74 | 2.91 |
| TTFB max (ms) | 5.68 | 1.74 | 2.91 |

**Observation**: baseline TTFB (intra-VPC kernel forwarding) is already sub-2 ms, putting it in the same range as the 0-RTT DPDK T8 single-connection results. The 0-RTT benefit will only show meaningfully in higher-latency networks (WAN-scale RTT). Next step: run 0-RTT DPDK T8 with `CONNECTIONS=20` to get a fair multi-connection comparison on the same infra.
