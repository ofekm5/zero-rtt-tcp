# Sprint 1: Reorganize directory layout

## Tasks
- Task 3: Rehome laptop-side code to `lib/` and split the transports out
- Task 4: Rehome every VM-executed script to `nodes/`

## Acceptance criteria
- C1: `experiments/utils/` is deleted and laptop-side code lives in `lib/` with transports split into `lib/transport/` — verify: `test -f experiments/lib/core.sh -a -f experiments/lib/transport/ssm.sh -a -f experiments/lib/transport/ssh_lab.sh -a ! -d experiments/utils`
- C2: All VM-executed scripts live in `experiments/nodes/` and no Python files remain in `experiments/lib/` — verify: `test -f experiments/nodes/client.sh -a -f experiments/nodes/server.sh -a -f experiments/nodes/clientnic.sh -a -f experiments/nodes/servernic.sh -a -f experiments/nodes/loadgen.py -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"`
- C3: Existing tests pass at their new location with import paths updated to the new module locations — verify: `pytest experiments/tests/ -q`
- C4: The shared output helpers and report writer are each defined exactly once in `experiments/lib/` (prior sprint work remains intact) — verify: `[ "$(grep -rl '^log()' experiments/lib/ | wc -l)" -eq 1 ] && [ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ]`

## Out of scope
- Writing `experiments/run.sh` or `experiments/lib/core.sh` DPDK/baseline dispatch logic — that is Sprint 2
- Deleting the four `run_experiment.sh` files — that is Sprint 3
- Deleting `experiments/scapy/` — that is Sprint 3
- Any change to `src/` or to measurement logic in the moved scripts
- Historical reports under `experiments/dpdk/reports/` and `experiments/baseline-tcp/reports/`
