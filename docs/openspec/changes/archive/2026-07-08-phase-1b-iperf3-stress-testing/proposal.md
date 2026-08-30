## Why

The existing `client.py`/`server.py` pair sends a single message and disconnects, which is insufficient for stress testing the 0-RTT path under real load. iperf3 provides parallel TCP streams, bidirectional throughput, and JSON output — enabling proper validation that the DPDK seq-translation pipeline handles concurrent multi-flow connections correctly.

## What Changes

- Install iperf3 on Client and Server VMs via CDK user data (both dpdk and scapy stacks)
- Add `iperf3-server.sh` and `iperf3-client.sh` node scripts for both experiment stacks
- Add `run_iperf3_experiment.sh` orchestrator that runs a 4-scenario test matrix through the 0-RTT DPDK path and writes a structured report

## Capabilities

### New Capabilities
- `iperf3-stress-testing`: iperf3-based stress test orchestration through the 0-RTT path — installs iperf3 on VMs, provides node scripts, runs a multi-scenario test matrix (single stream, parallel streams, reverse, bidirectional), collects JSON results and writes a report

### Modified Capabilities

## Impact

- `infra/dpdk/cdk/smartnics_stack.py` — iperf3 added to base user data
- `infra/scapy/cdk/smartnics_stack.py` — iperf3 added to base user data
- `experiments/zero-rtt-dpdk/nodes/` — two new node scripts
- `experiments/zero-rtt-clientnic-translate/nodes/` — same two node scripts mirrored
- `experiments/zero-rtt-dpdk/run_iperf3_experiment.sh` — new orchestrator
- No changes to ClientNIC, ServerNIC, or core packet processing logic
