## Requirements

### Requirement: SSM-driven DPDK test script exists
The repository SHALL contain `experiments/zero-rtt-clientnic-translate/run_dpdk_tests_ssm.sh` that orchestrates DPDK smoke tests on the ClientNIC VM via AWS SSM.

#### Scenario: Script runs successfully when VM is up
- **WHEN** the user runs `bash experiments/zero-rtt-clientnic-translate/run_dpdk_tests_ssm.sh`
- **THEN** the script discovers the ClientNIC instance, builds the binary via SSM, runs `run_dpdk_tests.sh` on the VM, prints its output, and exits 0 if all tests pass

#### Scenario: Script fails fast when VM is not running
- **WHEN** no running EC2 instance with tag `Name=smartnics-clientnic` exists
- **THEN** the script prints a clear error and exits non-zero without attempting SSM commands

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
