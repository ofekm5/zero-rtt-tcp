## Requirements

### Requirement: SSM-driven DPDK test script exists
The repository SHALL contain `experiments/zero-rtt-dpdk/run_experiment.sh` that orchestrates the full 4-VM DPDK integration test by launching each VM's node script (`nodes/server.sh`, `nodes/servernic.sh`, `nodes/clientnic.sh`) via SSM `send-command`, running the client test via `client.py` directly, collecting per-VM logs, running `validate_0rtt_capture.py`, and saving a report to `experiments/zero-rtt-dpdk/reports/`.

#### Scenario: Script runs successfully when all VMs are up
- **WHEN** the user runs `bash experiments/zero-rtt-dpdk/run_experiment.sh`
- **THEN** the script discovers all 4 instances, starts each VM using its node script in the correct order (Server → ServerNIC → ClientNIC → Client), collects logs, validates the capture, writes a report, and exits 0 if all checks pass

#### Scenario: Script fails fast when a VM is not running
- **WHEN** any required EC2 instance is not in running state
- **THEN** the script prints a clear error and exits non-zero without proceeding

### Requirement: DPDK binary is built on the VM before tests run
The script SHALL run `meson setup builddir && ninja -C builddir` in `~/zero-rtt-demo/clientnic/dpdk/` on the ClientNIC VM via SSM before invoking the test script.

#### Scenario: Build succeeds
- **WHEN** the VM has DPDK dev packages installed and the source is present
- **THEN** the binary `builddir/clientnic-dpdk` is produced and the test step proceeds

#### Scenario: Build fails
- **WHEN** the meson/ninja build exits non-zero
- **THEN** the script prints the build stderr and exits non-zero without running tests

### Requirement: Test output is captured and forwarded
The script SHALL print the full stdout of `run_dpdk_tests.sh` (pass/fail/skip lines and summary) and exit with a non-zero code if any test fails.

#### Scenario: All tests pass
- **WHEN** `run_dpdk_tests.sh` exits 0 on the VM
- **THEN** the script exits 0

#### Scenario: One or more tests fail
- **WHEN** `run_dpdk_tests.sh` exits non-zero on the VM
- **THEN** the script exits non-zero and the failure output is visible in the caller's terminal

### Requirement: Docker-based test files are removed
The files `clientnic/dpdk/tests/Dockerfile` and `clientnic/dpdk/tests/run_tests_docker.sh` SHALL be deleted from the repository.

#### Scenario: Docker files absent
- **WHEN** a developer clones the repo
- **THEN** `clientnic/dpdk/tests/` contains only `run_dpdk_tests.sh` and `README.md`

### Requirement: Skill and README document SSM-based test execution
The `.claude/skills/zero-rtt-integration-tester/` skill and `clientnic/dpdk/tests/README.md` SHALL document that DPDK tests run on the ClientNIC VM via `run_dpdk_tests_ssm.sh`.

#### Scenario: Developer reads README
- **WHEN** a developer reads `clientnic/dpdk/tests/README.md`
- **THEN** they find instructions to run `run_dpdk_tests_ssm.sh` (not Docker) with prereqs listed

#### Scenario: Agent reads skill
- **WHEN** Claude reads the zero-rtt-integration-tester skill
- **THEN** it finds a reference to the DPDK test flow alongside the Scapy integration test flow

### Requirement: zero-rtt-integration-tester skill documents node-script-driven flow
The `.claude/skills/zero-rtt-integration-tester/SKILL.md` SHALL document that the DPDK integration test is driven by `run_experiment.sh` which delegates to individual node scripts under `experiments/zero-rtt-dpdk/nodes/`, and describe the startup order and GW MAC discovery approach.

#### Scenario: Agent reads skill and knows how to run the DPDK test
- **WHEN** Claude reads the zero-rtt-integration-tester skill
- **THEN** it finds clear instructions for the node-script-driven DPDK flow, including that `clientnic.sh` requires the GW MAC argument and that client runs via `client.py --mode repeated`
