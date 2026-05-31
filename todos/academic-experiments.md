Academic Experiments & Research

## [URGENT] RUNS3 BlueField Reboot {#runs3-bluefield-reboot}
- Perform full reboot of RUNS3 BlueField system
- Needed before proceeding with BF3 testbed preparation and DPDK experiments

## [URGENT] Asymmetric Routing Mitigation {#asymmetric-routing}
- Investigate whether techniques from APNIC post are applicable: https://blog.apnic.net/2026/05/01/react-reflection-attack-mitigation-for-asymmetric-routing/
- Evaluate impact on 0-RTT design and reverse-path validation

## Phase 1b: iperf3 Stress Testing

**Note:** Full spec exists in `openspec/changes/phase-1b-iperf3-stress-testing/`

### Motivation
The simple `client.py`/`server.py` pair is insufficient for stress testing. iperf3 provides parallel streams, bidirectional throughput, UDP/TCP modes, and JSON output — enabling proper load testing through the 0-RTT path.

### Implementation Steps

**1. CDK user data — install iperf3**
- Modify `infra/dpdk/cdk/smartnics_stack.py` and `infra/scapy/cdk/smartnics_stack.py`
- Add to `base_user_data`: `amazon-linux-extras install -y epel` + `yum install -y iperf3`

**2. Node scripts**
- `experiments/zero-rtt-dpdk/nodes/iperf3-server.sh` — starts server on port 5201
- `experiments/zero-rtt-dpdk/nodes/iperf3-client.sh` — usage: `./iperf3-client.sh <server-ip> [flags]`
- Mirror both into `experiments/zero-rtt-clientnic-translate/nodes/`

**3. Orchestrator**
- `experiments/zero-rtt-dpdk/run_iperf3_experiment.sh` — orchestrates full test matrix:
  - Single stream TCP, 10s
  - 4 parallel streams (`-P 4`)
  - Reverse mode (`-R`)
  - Bidirectional (`--bidir`)
  - Collects JSON results + pcaps + report

**4. Verification**
- SSM into Server/Client, verify iperf3 JSON output
- Run with ClientNIC DPDK (`--port=5201`), verify connection + seq translation under load
- Run full orchestrator, verify report generated with throughput metrics

---

## Experiments (General Research)

- QUIC testbed — reference: https://chatgpt.com/share/69efb1eb-e984-83eb-bda0-a9e6df2a9d81
- Prepare testbeds for BF3 and AWS
- Define key metrics: FCT, throughput, TTFB
- Add a baseline for each scenario — both classic TCP and QUIC
- Add more parallel streams — find the threshold where throughput degrades significantly
- Cross-region testing under higher latency conditions
- Start on smaller testbeds, then use `tc` (traffic control) to simulate latency
- TRex vs iperf — compare traffic generators for stress testing
- Address the research hypothesis
- Reference: https://github.com/RC4ML/BenchBF3

## Host Reaction Time Measurement

Goal: measure time from packet arrival to response departure on a single host (no cross-VM clock sync).

### ClientNIC / ServerNIC (DPDK hosts)
- In `packet_processor.c`: record `rte_rdtsc()` at SYN RX and again just before spoofed SYN-ACK TX
- Convert TSC delta to nanoseconds using `rte_get_tsc_hz()`
- Log per-flow reaction time; aggregate min/mean/p99 at shutdown
- Check `RTE_MBUF_F_RX_TIMESTAMP` flag — if ENA PMD sets hardware timestamp on mbuf, use that instead of TSC for higher accuracy

### Client / Server (kernel TCP hosts)
- eBPF pair on the same host: `tracepoint:net:netif_receive_skb` (packet enters kernel) → `tracepoint:net:net_dev_start_xmit` (kernel hands packet to driver)
- Correlate by 5-tuple; compute delta in `nsecs`
- Add to `observability/ebpf/` as `host_reaction_trace.bt`

### Baseline comparison
- Run both normal TCP (no 0-RTT middleware) and 0-RTT mode
- Metric: SYN→SYN-ACK reaction time at ClientNIC (spoofed, ~µs) vs Server (real kernel TCP, ~10s of µs + network RTT)
- This directly quantifies the 0-RTT benefit in the paper

Papers to read:
- https://www.usenix.org/conference/osdi23/presentation/wei-smartnic
- https://arxiv.org/html/2509.21656
- https://www.diva-portal.org/smash/get/diva2:1676162/FULLTEXT01.pdf
- https://www.cs.rice.edu/~eugeneng/papers/SIGCOMM23-Pipeleon.pdf
