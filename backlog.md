# Backlog

## Urgent

- [ ] **RUNS3 BlueField BFB Reinstall** — DPU offline; reinstall BFB image via BMC at 10.13.36.233. Refs: `infra/bluefield/docs/`, `infra/bluefield/deployment/`
- [ ] **RUNS Lab Connectivity** — streamline VPN setup, Proxmox access, SSM commands; improve lab onboarding docs and automation
- [ ] **RUNS3 BlueField Reboot** — full reboot before BF3 testbed prep and DPDK experiments
- [ ] **Asymmetric Routing Mitigation** — investigate applicability of [APNIC REACT techniques](https://blog.apnic.net/2026/05/01/react-reflection-attack-mitigation-for-asymmetric-routing/) to 0-RTT design and reverse-path validation

## Architecture & Implementation

- [ ] Shift sequence number translation responsibility between sides
- [ ] BlueField-3 architecture: eSwitch for translation, DPA for connection setup and ISN generation, ARM core for DPDK setup
- [ ] RSS-based flow sharding
- [ ] Buffer ingress packets before handshake completes
- [ ] Explore [Corundum](https://github.com/corundum/corundum)
- [ ] QUIC-style Connection ID — widen ISN-passing channel (T3 or T6; T8's 4 bytes too narrow) to carry `{version, backend_id, tenant_id, flow_nonce, auth_tag}`; enables stateless ServerNIC routing and multi-backend fan-out. Only needed when fan-out > 1.

## Phase 1b: iperf3 Stress Testing

Full spec in `openspec/changes/phase-1b-iperf3-stress-testing/`

- [ ] Add `iperf3` install to CDK user data in `infra/dpdk/cdk/smartnics_stack.py` and `infra/scapy/cdk/smartnics_stack.py`
- [ ] Create `iperf3-server.sh` and `iperf3-client.sh` in `experiments/zero-rtt-dpdk/nodes/` and `experiments/zero-rtt-clientnic-translate/nodes/`
- [ ] Build `run_iperf3_experiment.sh` orchestrator: single-stream TCP, 4 parallel streams, reverse, bidirectional, JSON + pcap output
- [ ] Verify iperf3 JSON output via SSM; test with ClientNIC DPDK (`--port=5201`) under load

## Experiments & Research

- [ ] QUIC testbed — [reference](https://chatgpt.com/share/69efb1eb-e984-83eb-bda0-a9e6df2a9d81)
- [ ] Prepare testbeds for BF3 and AWS
- [ ] Define key metrics: FCT, throughput, TTFB
- [ ] Multi-region AWS CDK experiment — deploy across two regions (e.g. eu-central-1 + us-east-1) to measure 0-RTT TTFB benefit under real WAN latency (~90–120 ms RTT); compare against baseline TCP
- [ ] Find throughput degradation threshold — add parallel streams until performance breaks
- [ ] Use `tc` to simulate latency on smaller testbeds before scaling up
- [ ] TRex vs iperf — compare traffic generators for stress testing
- [ ] Address the research hypothesis
- [ ] Host reaction time measurement — DPDK: `rte_rdtsc()` at SYN RX and spoofed SYN-ACK TX in `packet_processor.c`; kernel: eBPF `netif_receive_skb` → `net_dev_start_xmit` pair in `observability/ebpf/host_reaction_trace.bt`
- [ ] Read [BenchBF3](https://github.com/RC4ML/BenchBF3)

## Papers to Read

- https://www.usenix.org/conference/osdi23/presentation/wei-smartnic
- https://arxiv.org/html/2509.21656
- https://www.diva-portal.org/smash/get/diva2:1676162/FULLTEXT01.pdf
- https://www.cs.rice.edu/~eugeneng/papers/SIGCOMM23-Pipeleon.pdf
