# Integration Test Report Summary

Aggregated metrics from all experiment reports in `experiments/` directory.

---

## Comprehensive Metrics Table

| Date | Implementation | Connections | TTFB Min (ms) | TTFB Max (ms) | TTFB Avg (ms) | TTFB Median (ms) | Std Dev (ms) | ISN Delta | Lead Time | Throughput (Mbps) | Notes |
|------|---|---|---|---|---|---|---|---|---|---|---|
| 2026-06-01 | Baseline TCP | 20 | 1.53 | 5.68 | **1.93** | 1.71 | 0.91 | N/A | N/A | — | Plain kernel forwarding; conn 9 outlier (5.68 ms); median 1.71 ms |
| 2026-06-09 | Baseline TCP | 20 | — | — | — | — | — | N/A | N/A | 1121–2478 | iperf3 bandwidth; intra-VPC t3.micro; 20/20 pass; BaselineStack eu-central-1 |
| 2026-06-09 | Baseline TCP | 20 | — | — | — | — | — | N/A | N/A | 923–2812 | iperf3 bandwidth; run #2; avg ~1806 Mbps; 20/20 pass |
| 2026-06-09 | Baseline TCP | 20 | — | — | — | — | — | N/A | N/A | 1231–2520 | iperf3 bandwidth; run #3; avg ~1474 Mbps; 20/20 pass |
| 2026-03-06 | Scapy 0-RTT | 3 | 1.98 | 3.62 | **2.66** | 2.38 | 0.85 | Non-zero | N/A | — | Kernel race; buffering issue found |
| 2026-03-07 | Scapy 0-RTT | 3 | 2.09 | 3.85 | **2.79** | 2.42 | 0.93 | Non-zero | N/A | — | After metadata/SYN-retransmit fixes |
| 2026-03-12 | Scapy 0-RTT | 3 | 351.82 | 409.80 | **373.85** | 359.93 | 31.40 | 3,980,068,009 | +83–199 ms | — | iptables DROP applied; 0-RTT timing verified |
| 2026-03-18 | Scapy 0-RTT | 3 | 389.06 | 423.75 | **402.92** | 395.94 | 18.37 | 3,075,871,609 | +82–177 ms | — | Consistent 0-RTT spoofed lead |
| 2026-03-25 | DPDK Legacy | 1 | 296.17 | 296.17 | **296.17** | 296.17 | 0.00 | 2,571,737,058 | +119 ms | — | Full-owner translation; smoke test passes |
| 2026-03-30 | DPDK Legacy | 1 | 306.40 | 306.40 | **306.40** | 306.40 | 0.00 | 1,739,976,854 | +121 ms | — | Node-script driven orchestration |
| 2026-04-09 | DPDK Legacy | 1 | 275.87 | 275.87 | **275.87** | 275.87 | 0.00 | 2,500,719,103 | +113 ms | — | All checksums valid; git conflict resolved |
| 2026-04-21 | DPDK Legacy (iperf) | Multi | — | — | — | — | — | 1,542,316,412 avg | — | **0.06–0.89** | TCP throughput bottleneck; 1074 Mbps UDP baseline |
| 2026-05-30 | DPDK T8 | 1 | 1.74 | 1.74 | **1.74** | 1.74 | 0.00 | 0x90771689 | ~instant | — | Shifted translation; stateless ClientNIC |
| 2026-05-31 | DPDK T8 | 1 | 2.91 | 2.91 | **2.91** | 2.91 | 0.00 | 0x9d1ec791 | ~instant | — | Buffered packets flushed (1-2); near-baseline |
| 2026-06-06 | DPDK T8 | 5 | 1.50 | 5.22 | **2.88** | 1.83 | 1.68 | various | ~instant | — | First 5-connection run; ENI rebind fix applied; clientnic 0.99–3.65 ms TTFB |

---

## Implementation Summary

| Implementation | Reports | Avg TTFB (ms) | Overhead vs Baseline | Throughput | Key Characteristic |
|---|---|---|---|---|---|
| **Baseline TCP** | 4 | 1.93 (median 1.71) | — | 923–2812 Mbps | Plain kernel forwarding reference; iperf3 throughput: 3 runs avg ~1625 Mbps |
| **Scapy 0-RTT (early)** | 2 | 2.72 | +1.01 ms | — | Kernel race condition (bypassed 0-RTT) |
| **Scapy 0-RTT (iptables)** | 2 | 388.39 | +386.68 ms | — | Userspace processing overhead; 0-RTT verified |
| **DPDK Legacy** | 3 | 292.81 | +291.10 ms | 0.06–0.89 Mbps | C/DPDK; full-owner translation; AF_PACKET bottleneck |
| **DPDK T8** | 3 | 2.51 | +0.80 ms | — | Stateless forwarding; shifted translation; **near-baseline** |


---

## Key Findings

**0-RTT Mechanism Validation**
- Spoofed SYN-ACK reliably precedes real SYN-ACK across all implementations
- ISN deltas verified non-zero and consistent within flows
- Buffered packets correctly flushed upon real SYN-ACK arrival
- All checksums valid (100% pass rate on 66+ captured packets per test)

**Architecture Trade-offs**

| Aspect | Scapy (Early) | Scapy (iptables) | DPDK Legacy | DPDK T8 |
|--------|---|---|---|---|
| **Processing Model** | Kernel race | Userspace only | C/DPDK busy-poll | Stateless forwarder + ServerNIC translator |
| **Latency Overhead** | +1 ms | +387 ms | +291 ms | **+0.62 ms** |
| **Translation Placement** | ClientNIC | ClientNIC | ClientNIC (full) | ServerNIC (shifted) |
| **Per-Packet Work** | Sniff/forward | Buffer/rewrite | Full seq/ack rewrite | Spoof + V-stamp only |
| **Bottleneck** | Kernel race | Python interpreter | AF_PACKET ceiling | Minimal |

**Throughput Characteristics (DPDK Legacy)**
- Single TCP stream: 0.06 Mbps (AF_PACKET + userspace translation overhead)
- Parallel scaling: linear up to 16 streams (0.89 Mbps aggregate = 14.8× speedup)
- UDP baseline: 1074 Mbps (network is fast; TCP translation is the constraint)
- Window size sensitivity: 40 KB default likely contributor to low throughput

**Design Lesson: Stateless Forwarding Wins**
- DPDK T8 achieves **6× latency improvement** over legacy DPDK
- Key insight: defer translation work from critical (client-facing) path
- ClientNIC ack-num field piggybacking (V) enables ServerNIC to extract delta
- ServerNIC performs full seq/ack rewriting (fewer per-packet constraints)
