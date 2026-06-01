# Backlog

## Ops — Lab & Hardware

Blocking access to the RUNS testbed; address before running BF3 experiments.

- [ ] **RUNS3 BFB Reinstall** — DPU is offline; reinstall BFB image via BMC console at `10.13.36.233`. Refs: `infra/bluefield/docs/`, `infra/bluefield/deployment/`
- [ ] **RUNS3 Full Reboot** — Required before BF3 testbed prep and DPDK experiments; do after BFB reinstall
- [ ] **RUNS Lab Connectivity** — Streamline VPN setup, Proxmox access, and SSM commands; improve onboarding docs and automation

## Active: Phase 1b — iperf3 Stress Testing

Full spec in `openspec/changes/phase-1b-iperf3-stress-testing/`

- [ ] Add `iperf3` install to CDK user data in `infra/dpdk/cdk/smartnics_stack.py` and `infra/scapy/cdk/smartnics_stack.py`
- [ ] Add `iperf3-server.sh` / `iperf3-client.sh` to `experiments/zero-rtt-dpdk/nodes/` and `experiments/zero-rtt-clientnic-translate/nodes/`
- [ ] Build `run_iperf3_experiment.sh` orchestrator: single-stream, 4 parallel streams, reverse, bidirectional; output JSON + pcap
- [ ] Validate via SSM: confirm JSON output, test under load with ClientNIC DPDK on port 5201

## Architecture & Design

Design decisions and future platform work.

- [ ] **BlueField-3 Data Plane Roles** — Assign per-component responsibilities: eSwitch for per-packet translation, DPA for connection setup and ISN generation, ARM cores for DPDK control plane
- [ ] **RSS Flow Sharding** — Distribute flows across cores via RSS to enable parallel packet processing without cross-core state sharing
- [ ] **Pre-Handshake Packet Buffering** — Buffer ingress client data that arrives before the real SYN-ACK; flush once delta is established. Currently missing from the DPDK path
- [ ] **QUIC-style Connection ID** — Widen ISN-passing channel (T3 or T6; T8's 4 bytes too narrow) to carry `{version, backend_id, tenant_id, flow_nonce, auth_tag}`; enables stateless ServerNIC routing and multi-backend fan-out. Only needed when fan-out > 1
- [ ] **Explore Corundum** — Assess open-source FPGA NIC ([corundum/corundum](https://github.com/corundum/corundum)) as a potential hardware platform alternative to BF3

## Experiments

Concrete measurement and validation tasks. Requires testbeds to be up first.

- [ ] **Multi-Region AWS Experiment** — Deploy CDK stack across two regions (e.g. `eu-central-1` + `us-east-1`) to measure 0-RTT TTFB benefit under real WAN latency (~90–120 ms RTT); compare against baseline TCP
- [ ] **Throughput Degradation Threshold** — Increase parallel iperf3 streams until throughput or latency degrades; identify the breaking point
- [ ] **Host Reaction Time** — Measure NIC-side latency from SYN RX to spoofed SYN-ACK TX:
  - DPDK path: `rte_rdtsc()` at SYN RX and spoofed SYN-ACK TX in `packet_processor.c`
  - Kernel path: eBPF `netif_receive_skb` → `net_dev_start_xmit` pair in `observability/ebpf/host_reaction_trace.bt`
- [ ] **Latency Simulation on Small Testbeds** — Use `tc netem` to inject artificial RTT before scaling to multi-region
- [ ] **QUIC Testbed** — Set up a QUIC comparison testbed; [reference conversation](https://chatgpt.com/share/69efb1eb-e984-83eb-bda0-a9e6df2a9d81)
- [ ] **Research Hypothesis Validation** — Quantify 0-RTT TTFB reduction across testbeds; document measured benefit vs. RTT baseline
- [ ] **Asymmetric Routing Investigation** — Assess applicability of [APNIC REACT techniques](https://blog.apnic.net/2026/05/01/react-reflection-attack-mitigation-for-asymmetric-routing/) to 0-RTT reverse-path validation

## Methodology & Tooling

Prerequisites and tooling decisions that gate multiple experiments.

- [ ] **Define Key Metrics** — Formally specify FCT, TTFB, and throughput measurement methodology before running comparative experiments
- [ ] **TRex vs iperf3** — Compare traffic generators for stress testing; determine which produces more realistic load for the 0-RTT use case
- [ ] **BF3 Testbed Bring-Up** — Configure DOCA + DPDK environment on RUNS3 after hardware ops above complete
- [ ] **Read BenchBF3** — Review [BenchBF3](https://github.com/RC4ML/BenchBF3) benchmarking methodology for BF3

## Papers to Read

- [SmartNIC-as-a-Service — Wei et al. (OSDI '23)](https://www.usenix.org/conference/osdi23/presentation/wei-smartnic)
- [arXiv 2509.21656](https://arxiv.org/html/2509.21656)
- [FPGA SmartNIC thesis (DiVA)](https://www.diva-portal.org/smash/get/diva2:1676162/FULLTEXT01.pdf)
- [Pipeleon — Ng et al. (SIGCOMM '23)](https://www.cs.rice.edu/~eugeneng/papers/SIGCOMM23-Pipeleon.pdf)
