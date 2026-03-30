## MODIFIED Requirements

### Requirement: SSM-driven DPDK test script exists
The repository SHALL contain `experiments/zero-rtt-dpdk/run_experiment.sh` that orchestrates the full 4-VM DPDK integration test by launching each VM's node script (`nodes/server.sh`, `nodes/servernic.sh`, `nodes/clientnic.sh`) via SSM `send-command`, running the client test via `client.py` directly, collecting per-VM logs, running `validate_0rtt_capture.py`, and saving a report to `experiments/zero-rtt-dpdk/reports/`.

#### Scenario: Script runs successfully when all VMs are up
- **WHEN** the user runs `bash experiments/zero-rtt-dpdk/run_experiment.sh`
- **THEN** the script discovers all 4 instances, starts each VM using its node script in the correct order (Server → ServerNIC → ClientNIC → Client), collects logs, validates the capture, writes a report, and exits 0 if all checks pass

#### Scenario: Script fails fast when a VM is not running
- **WHEN** any required EC2 instance is not in running state
- **THEN** the script prints a clear error and exits non-zero without proceeding

### Requirement: zero-rtt-integration-tester skill documents node-script-driven flow
The `.claude/skills/zero-rtt-integration-tester/SKILL.md` SHALL document that the DPDK integration test is driven by `run_experiment.sh` which delegates to individual node scripts under `experiments/zero-rtt-dpdk/nodes/`, and describe the startup order and GW MAC discovery approach.

#### Scenario: Agent reads skill and knows how to run the DPDK test
- **WHEN** Claude reads the zero-rtt-integration-tester skill
- **THEN** it finds clear instructions for the node-script-driven DPDK flow, including that `clientnic.sh` requires the GW MAC argument and that client runs via `client.py --mode repeated`
