## Context

The 0-RTT DPDK stack is functionally verified with a single-connection `client.py`/`server.py` exchange. The next validation step is multi-flow stress testing: proving that the flow table handles concurrent streams, that seq-translation is correct under load, and that throughput is measurable. iperf3 is the standard tool for this — it supports parallel TCP streams, reverse mode, and JSON output.

The design touches three layers: VM provisioning (CDK user data), per-VM node scripts, and the experiment orchestrator.

## Goals / Non-Goals

**Goals:**
- Install iperf3 on Client and Server VMs at launch time via CDK user data
- Provide simple node scripts (`iperf3-server.sh`, `iperf3-client.sh`) usable standalone or from an orchestrator
- Provide `run_iperf3_experiment.sh` that runs a 4-scenario matrix through the live DPDK 0-RTT path and writes a report
- Mirror node scripts into both the dpdk and scapy experiment directories

**Non-Goals:**
- UDP testing (iperf3 `-u`) — DPDK ClientNIC only handles TCP
- Performance tuning or optimization of throughput
- Automated CI/CD integration of the iperf3 tests
- Changes to ClientNIC, ServerNIC, or any packet-processing code

## Decisions

### Decision 1: Single configurable port (`--port=5201`)
iperf3 uses port 5201 by default. The DPDK ClientNIC binary is port-specific (it intercepts SYN packets on a configured port). Rather than hardcoding, the orchestrator starts the binary with `--port=5201`. This keeps the binary general and makes the port obvious in the script.

*Alternative considered*: Intercept all ports — requires flow table changes outside scope.

### Decision 2: Node scripts are thin wrappers, not orchestrators
`iperf3-server.sh` and `iperf3-client.sh` do one thing each. The orchestrator is responsible for sequencing, SSM dispatch, and result collection. This keeps node scripts reusable standalone (e.g., manual SSM session) without pulling in orchestration logic.

### Decision 3: Mirror node scripts into both stacks
`experiments/zero-rtt-dpdk/nodes/` and `experiments/zero-rtt-clientnic-translate/nodes/` share the same iperf3 scripts (identical content). Keeping them co-located with each stack avoids cross-directory references in orchestrators.

### Decision 4: JSON output piped to report
iperf3's `-J` flag emits structured JSON. The orchestrator captures this via SSM command output and embeds key metrics (throughput, retransmits, streams) directly in the markdown report. No separate parser script needed at this stage.

### Decision 5: SSM runtime fallback for iperf3 install
If iperf3 is absent (e.g., older AMI or CDK change not yet deployed), the orchestrator installs it via SSM before running tests. This prevents test failures due to missing binary.

## Risks / Trade-offs

- **Port 5201 conflict with existing services** → Mitigation: orchestrator kills any existing iperf3 server before starting a new one (`pkill -f iperf3 || true`)
- **DPDK binary not built yet** → Mitigation: orchestrator checks for binary existence and prints a clear error; points to DPDK build instructions
- **Parallel streams (-P 4) stress flow table** → This is intentional; failure here is diagnostic signal, not a blocker for the script
- **iperf3 JSON output truncated by SSM response limits** → Mitigation: write JSON to `/tmp/iperf3_result.json` on Client VM and retrieve via SSM `cat` as a separate step
