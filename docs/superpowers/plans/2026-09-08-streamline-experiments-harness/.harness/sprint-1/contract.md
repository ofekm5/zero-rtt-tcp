# Sprint 1: Extract shared output and report helpers

## Tasks
- Task 1: Hoist the duplicated output helpers into a single shared file (`experiments/lib/output.sh`)
- Task 2: Merge the two duplicated report writers into one parameterised writer (`experiments/lib/report.sh`)

## Acceptance criteria
- C1: experiments/lib/output.sh exists and none of the four runner files still define log() inline — verify: `test -f experiments/lib/output.sh && ! grep -qE '^log\(\)' experiments/dpdk/run_experiment.sh experiments/baseline-tcp/run_experiment.sh experiments/proxmox/run_experiment.sh experiments/scapy/run_experiment.sh`
- C2: exactly one file in experiments/lib/ contains the report header and neither old runner still embeds the report writer inline — verify: `[ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ] && ! grep -q 'Integration Test Report' experiments/dpdk/run_experiment.sh && ! grep -q 'Integration Test Report' experiments/baseline-tcp/run_experiment.sh`

## Out of scope
- Moving any file to a new directory (lib/ receives only the two new shared files)
- Writing run.sh or changing the number of entrypoints
- Changing measurement semantics, output formatting, or metric definitions
- Any change to src/
