# Priority Issues Index

Critical items blocking progress. Each urgent is detailed in one of the category documents below.

## Immediate Action Items

- **RUNS lab connectivity**: [tech-improvements.md](tech-improvements.md#runs-lab-connectivity) — streamline lab connection setup
- **RUNS3 BlueField reinstall**: [tech-improvements.md](tech-improvements.md#runs3-bluefield-reinstall) — restore DPU functionality for DPDK testbed prep
- **ServerNIC forwarding stability**: [tech-improvements.md](tech-improvements.md#servernic-forwarding-stability) — identify stable paths for consistent packet forwarding
- **Asymmetric routing mitigation**: [academic-experiments.md](academic-experiments.md#asymmetric-routing) — evaluate applicability of APNIC reflection attack mitigation techniques

## Phase 1 Initiatives

- **Phase 1a — eBPF observability**: [phase-1a-ebpf-observability.md](phase-1a-ebpf-observability.md) — kernel-level TCP visibility on Client/Server VMs during experiments
- **Phase 1b — iperf3 stress testing**: [phase-1b-iperf3-stress-testing.md](phase-1b-iperf3-stress-testing.md) — parallel streams, bidirectional throughput, load testing

## Experiment Measurements

### Integration Test Results Summary

| Date | Implementation | Connections | Success Rate | TTFB Min (ms) | TTFB Avg (ms) | TTFB Max (ms) | Result | Notes |
|------|----------------|-------------|--------------|---------------|---------------|---------------|--------|-------|
| 2026-05-31 | DPDK T8 (forwarder) | 1 | 100% | 2.91 | 2.91 | 2.91 | ✅ PASS | Single connection, spoofed SYN-ACK validated |
| 2026-05-30 | DPDK T8 (forwarder) | 1 | 100% | 1.74 | 1.74 | 1.74 | ✅ PASS | Single connection, buffered packets flushed |
| 2026-05-31 | Baseline TCP (kernel) | 20 | 0% | — | — | — | ❌ FAIL | No connectivity via kernel forwarding |
| 2026-04-21 | DPDK (full-owner) + iperf | Multi | 100% | — | 0.06–0.89 Mbps | — | ⚠️ PARTIAL | 0-RTT working; TCP throughput bottleneck (~60–110 Kbps) |
| 2026-03-25 | DPDK (full-owner) | 1 | 100% | 296.17 | 296.17 | 296.17 | ✅ PASS | Run 1: all checks passed; Run 2: same (SSM timeout not functional issue) |
| 2026-03-18 | Scapy | 3 | 100% | 389.06 | 402.92 | 423.75 | ✅ PASS | Lead time: spoofed SYN-ACK ±177ms, ±82ms, ±114ms before real |
| 2026-03-12 | Scapy | 1 | 100% | — | — | — | ✅ PASS | Single connection, delta non-zero |
| 2026-03-07 | Scapy | 1 | 100% | — | — | — | ✅ PASS | Single connection, delta non-zero |
| 2026-03-06 | Scapy | 1 | 100% | — | — | — | ✅ PASS | Single connection, delta non-zero |

### Key Metrics Trends

**TTFB Improvement (DPDK T8 forwarder):**
- Recent (2026-05-30/31): 1.74–2.91 ms (lowest latency observed)
- Earlier DPDK: 274–296 ms
- Scapy: 389–423 ms
- **Improvement ratio:** T8 forwarder ~100–170× faster than legacy Scapy

**Success Indicators:**
- All Scapy and DPDK integration tests: 100% success on 0-RTT mechanism
- Spoofed SYN-ACK consistently delivered before real SYN-ACK
- Packet checksums valid across all reports
- Baseline kernel forwarding: 0% (connectivity issue, not 0-RTT logic failure)

**Throughput Notes (iperf data from 2026-04-21):**
- TCP: 0.06–0.89 Mbps (limited by AF_PACKET socket and per-packet rewriting overhead)
- UDP (bypass): 1074 Mbps (confirms network path is not bottleneck)
- Recommendation: Profile busy-poll loop or test with larger TCP window (256K+)
