# Priority Issues Index

Critical items blocking progress. Each urgent is detailed in one of the category documents below.

## Immediate Action Items

- **T8 ISN passing (SYN ack-num)**: [tech-improvements.md](tech-improvements.md#architecture--implementation) — implement ClientNIC→ServerNIC ISN handoff via SYN ack-num field; shifts seq/ack NAT to ServerNIC
- **RUNS lab connectivity**: [tech-improvements.md](tech-improvements.md#runs-lab-connectivity) — streamline lab connection setup
- **RUNS3 BlueField reinstall**: [tech-improvements.md](tech-improvements.md#runs3-bluefield-reinstall) — restore DPU functionality for DPDK testbed prep
- **ServerNIC forwarding stability**: [tech-improvements.md](tech-improvements.md#servernic-forwarding-stability) — identify stable paths for consistent packet forwarding
- **Asymmetric routing mitigation**: [academic-experiments.md](academic-experiments.md#asymmetric-routing) — evaluate applicability of APNIC reflection attack mitigation techniques

## Phase 1 Initiatives

- **Phase 1a — eBPF observability**: [phase-1a-ebpf-observability.md](phase-1a-ebpf-observability.md) — kernel-level TCP visibility on Client/Server VMs during experiments
- **Phase 1b — iperf3 stress testing**: [phase-1b-iperf3-stress-testing.md](phase-1b-iperf3-stress-testing.md) — parallel streams, bidirectional throughput, load testing
