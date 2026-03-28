## Why

The ClientNIC DPDK binary targets AWS ENA hardware and requires Linux kernel features unavailable locally on Windows. Running tests in Docker with virtual PMDs (`net_null`, `net_ring`) was unreliable and diverged from the real execution environment. The ClientNIC VM already has DPDK installed, hugepages configured, and is the actual target — tests should run there.

## What Changes

- **Remove** `clientnic/dpdk/tests/Dockerfile` and `clientnic/dpdk/tests/run_tests_docker.sh` (Docker-based test approach)
- **Add** `experiments/zero-rtt-clientnic-translate/run_dpdk_tests_ssm.sh` — discovers the ClientNIC EC2 instance, SSMs into it, builds the DPDK binary, and runs `run_dpdk_tests.sh`
- **Add** `.claude/skills/zero-rtt-integration-tester/references/dpdk-tests.md` — documents DPDK test flow as a skill reference
- **Update** `.claude/skills/zero-rtt-integration-tester/SKILL.md` — link the new reference
- **Update** `clientnic/dpdk/tests/README.md` — reflect SSM-based execution instead of Docker

## Capabilities

### New Capabilities

- `dpdk-ssm-test-runner`: SSM-driven script that builds and runs DPDK smoke tests on the ClientNIC VM, reusing the existing `run_dpdk_tests.sh` test cases

### Modified Capabilities

_(none — no existing specs to change)_

## Impact

- `experiments/zero-rtt-clientnic-translate/`: new script added alongside `run_experiment.sh`
- `clientnic/dpdk/tests/`: Dockerfile and Docker wrapper removed; README updated
- `.claude/skills/zero-rtt-integration-tester/`: new reference doc + SKILL.md index update
- Requires AWS CLI + SSM access (same prereqs as `run_experiment.sh`)
