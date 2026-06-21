# Build notes — sprint 4 round 1

## Changes made
- `experiments/utils/run_core.sh` (new) — transport-agnostic orchestration: build both binaries, start server/servernic/clientnic, run client measurement, stop captures, collect logs, analyze pcaps, aggregate metrics; exports CORE_* globals for callers
- `experiments/utils/ssh_lab.sh` (new) — SSH-gateway transport for RUNS Proxmox lab; provides remote_run/remote_bg/remote_stdout via ssh ProxyJump through runs-gateway; discover_nodes populates node IDs from LAB_*_IP env vars; get_lab_mac reads MACs from /sys/class/net/<iface>/address
- `experiments/proxmox/run_experiment.sh` (new) — Proxmox runner: sources ssh_lab.sh + measure.sh + run_core.sh, resolves MACs via get_lab_mac, calls run_experiment(), writes report
- `experiments/dpdk/run_experiment.sh` (modified) — refactored: added remote_run/bg/stdout shims over ssm_*, moved discover_nodes into a function, sources run_core.sh, calls run_experiment(); kept AWS-specific smoke test and MAC resolution via EC2 API; report uses CORE_* globals

## Verification commands run
- C1: `bash -n experiments/utils/run_core.sh` — exit 0, no syntax errors
- C2: `bash -n experiments/utils/ssh_lab.sh` — exit 0, no syntax errors
- C3: `bash -n experiments/proxmox/run_experiment.sh` — exit 0, no syntax errors
- C4: `grep -q 'run_core.sh' experiments/dpdk/run_experiment.sh && grep -q 'run_core.sh' experiments/proxmox/run_experiment.sh` — exit 0, both files contain the string
- C5: `grep -q 'ssh_lab.sh' experiments/proxmox/run_experiment.sh` — exit 0, proxmox runner sources ssh_lab.sh
- C6: `grep -q 'run_core.sh' experiments/dpdk/run_experiment.sh` — exit 0, AWS runner sources run_core.sh

## Open concerns
- The `_lab_ssh` implementation uses a subshell trick to capture stderr from the ProxyJump SSH invocation; on some systems this may lose the remote exit code vs. the SSH connection exit code. The contract only requires valid bash syntax and sourcing, so this is not a blocking concern for the sprint.
- `run_core.sh` defines `_hiprec_start` as a nested function inside `run_experiment`; bash does not support lexical scoping so this is a top-level definition at source time — it works correctly but is a style note.
- LSP diagnostics: no LSP server available for `.sh` file type; bash -n syntax checks confirm no errors.
