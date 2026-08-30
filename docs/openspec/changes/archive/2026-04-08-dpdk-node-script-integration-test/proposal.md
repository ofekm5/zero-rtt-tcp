## Why

The zero-rtt-integration-tester skill drives the DPDK stack test via `run_experiment.sh`, a monolithic orchestrator. The individual node scripts under `experiments/zero-rtt-dpdk/nodes/` exist but are unused in automation — using them directly gives finer-grained control, clearer per-VM logs, and makes it easier to restart individual nodes without re-running the full experiment.

## What Changes

- `experiments/zero-rtt-dpdk/run_experiment.sh` is updated (or a new script is added) to drive each VM via its node script through SSM `send-command` instead of a single monolithic orchestrator
- `nodes/client.sh` interactive `read` loop is bypassed by calling `client.py` directly for automation
- GW MAC discovery falls back to reading `/sys/class/net/eth0/address` on ServerNIC via SSM when EC2 API fails due to IAM permissions
- Git safe.directory is configured before running any node script as root
- The zero-rtt-integration-tester skill is updated to document the node-script-driven flow

## Capabilities

### New Capabilities
- `dpdk-node-script-runner`: SSM-driven per-VM test orchestration using individual node scripts (`nodes/server.sh`, `nodes/servernic.sh`, `nodes/clientnic.sh`, `nodes/client.sh`) with per-VM log capture to `/tmp/*.log`

### Modified Capabilities
- `dpdk-ssm-test-runner`: Existing requirement that "SSM-driven DPDK test script exists" now applies to the node-script-driven flow; the orchestration approach changes from monolithic to per-node

## Impact

- `experiments/zero-rtt-dpdk/run_experiment.sh` — primary change target
- `experiments/zero-rtt-dpdk/nodes/client.sh` — may need non-interactive mode
- `.claude/skills/zero-rtt-integration-tester/SKILL.md` — updated to reference node-script flow
- No changes to `clientnic/dpdk/` source or build system
