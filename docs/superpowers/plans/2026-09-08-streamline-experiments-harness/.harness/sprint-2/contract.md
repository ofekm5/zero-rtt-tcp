# Sprint 2: Rehome laptop-side and VM-side code

## Tasks
- Task 3: Rehome laptop-side code to lib/ and split the transports out (experiments/utils/ → experiments/lib/; ssm.sh and ssh_lab.sh → experiments/lib/transport/)
- Task 4: Rehome every VM-executed script to nodes/ (dpdk/clientnic.sh, dpdk/servernic.sh, utils/loadgen.py, utils/analyze_metrics.py → experiments/nodes/)

## Acceptance criteria
- C1: lib/core.sh and both transport shims exist and experiments/utils/ is gone — verify: `test -f experiments/lib/core.sh -a -f experiments/lib/transport/ssm.sh -a -f experiments/lib/transport/ssh_lab.sh -a ! -d experiments/utils`
- C2: all six VM-executed scripts are in experiments/nodes/ and no Python files remain in experiments/lib/ — verify: `test -f experiments/nodes/client.sh -a -f experiments/nodes/server.sh -a -f experiments/nodes/clientnic.sh -a -f experiments/nodes/servernic.sh -a -f experiments/nodes/loadgen.py -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"`

## Out of scope
- Writing experiments/run.sh or consolidating entrypoints
- Deleting any run_experiment.sh runner
- Any change to measurement logic in the moved files (endpoint.sh, measure.sh, run_core.sh, loadgen.py, analyze_metrics.py move byte-identical)
- Any change to src/
