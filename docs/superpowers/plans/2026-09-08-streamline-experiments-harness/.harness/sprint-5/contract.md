# Sprint 5: delete the runners, move the sweeps

## Tasks
- Task 7: Delete the four runners and the Scapy stack; move the sweeps

## Acceptance criteria
- C1: No `run_experiment.sh` remains under `experiments/`, `experiments/scapy/` is deleted, and both sweep scripts exist at their new paths — verify: `test -z "$(find experiments -name run_experiment.sh)" && test ! -d experiments/scapy && test -f experiments/sweeps/think.sh -a -f experiments/sweeps/stress.sh`
- C2: `experiments/run.sh` is executable and no `run_experiment.sh` exists anywhere under `experiments/` — verify: `test -x experiments/run.sh && test -z "$(find experiments -name run_experiment.sh)"`
- C3: The four output helpers and the report writer each have exactly one definition among the shared laptop-side library files in `experiments/lib/` — verify: `[ "$(grep -rl '^log()' experiments/lib/ | wc -l)" -eq 1 ] && [ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ]`
- C4: All VM-executed scripts live in `experiments/nodes/` and no Python files remain directly in `experiments/lib/` — verify: `test -f experiments/nodes/client.sh -a -f experiments/nodes/server.sh -a -f experiments/nodes/clientnic.sh -a -f experiments/nodes/servernic.sh -a -f experiments/nodes/loadgen.py -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"`

## Out of scope
- Updating callers in `.github/workflows/`, `.claude/skills/`, `CLAUDE.md`, and `experiments/README.md` (sprint 6)
- Moving or deleting historical reports under `experiments/dpdk/reports/` or `experiments/baseline-tcp/reports/`
- Any change to `experiments/dpdk/probes/`
- Any change to `src/`
