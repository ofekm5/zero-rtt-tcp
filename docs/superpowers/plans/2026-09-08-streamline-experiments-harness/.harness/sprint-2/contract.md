# Sprint 2: Rehome laptop-side and VM-side code

> **Re-planned after a `scope-violation` on the first attempt.** Two defects in the
> original contract, both fixed below:
> 1. `touches[]` listed only `experiments/dpdk` among the runner directories, but
>    moving `experiments/utils/*` breaks the `source` lines in **all four** runners.
>    The builder had to edit `baseline-tcp`, `proxmox` and `scapy` to leave the tree
>    working, and the sandbox correctly rejected it.
> 2. "Out of scope: the moved files move byte-identical" contradicted Task 4's own
>    Outcome, which requires every remote command string naming a moved script to be
>    repointed — and those strings live inside `run_core.sh`, `endpoint.sh` and
>    `measure.sh`. Obeying the contract meant shipping a harness that cannot find
>    `clientnic.sh`/`servernic.sh`/`loadgen.py`/`analyze_metrics.py` on the VMs. The
>    builder flagged this rather than silently patching; the contract was wrong.
>
> C3 is new and exists to make defect 2 impossible to pass.

## Tasks
- Task 3: Rehome laptop-side code to lib/ and split the transports out (experiments/utils/ → experiments/lib/; ssm.sh and ssh_lab.sh → experiments/lib/transport/)
- Task 4: Rehome every VM-executed script to nodes/ (dpdk/clientnic.sh, dpdk/servernic.sh, utils/loadgen.py, utils/analyze_metrics.py → experiments/nodes/)

## Acceptance criteria
- C1: lib/core.sh and both transport shims exist and experiments/utils/ is gone — verify: `test -f experiments/lib/core.sh -a -f experiments/lib/transport/ssm.sh -a -f experiments/lib/transport/ssh_lab.sh -a ! -d experiments/utils`
- C2: all six VM-executed scripts are in experiments/nodes/ and no Python files remain in experiments/lib/ — verify: `test -f experiments/nodes/client.sh -a -f experiments/nodes/server.sh -a -f experiments/nodes/clientnic.sh -a -f experiments/nodes/servernic.sh -a -f experiments/nodes/loadgen.py -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"`
- C3: no shell or Python file under experiments/ still names a pre-move path, so no remote command string can point at a script that is no longer there — verify: `! grep -rn -e 'experiments/utils/' -e 'experiments/dpdk/clientnic\.sh' -e 'experiments/dpdk/servernic\.sh' experiments/ --include='*.sh' --include='*.py'`
- C4: the moved code still behaves identically — verify: `python3 -m pytest experiments/tests/ -q`

### C3 covers these seven functional call sites
Repointing each is **required**, not out of scope. Paths are as of `origin/main`:
- `experiments/utils/run_core.sh:250` — `setsid bash $REPO_PATH/experiments/dpdk/servernic.sh`
- `experiments/utils/run_core.sh:288` — `setsid bash $REPO_PATH/experiments/dpdk/clientnic.sh`
- `experiments/utils/endpoint.sh:260` — `python3 $repo/experiments/utils/analyze_metrics.py`
- `experiments/utils/endpoint.sh:271` — `python3 $repo/experiments/utils/analyze_metrics.py`
- `experiments/utils/measure.sh:161` — `python3 $repo/experiments/utils/loadgen.py`
- `experiments/nodes/client.sh:99` — `python3 "$REPO_PATH/experiments/utils/loadgen.py"`
- `experiments/nodes/server.sh:60` — `exec python3 "$REPO_PATH/experiments/utils/loadgen.py"`

C3 also sweeps the cosmetic mentions (comments, module docstrings, the two
`baseline-tcp` report strings, three `proxmox` ones, `dpdk/run_stress.sh:26`).
Fixing them is in scope: a stale path in a comment is the debt this change exists
to remove, and leaving it forces a second pass in Sprint 5.

## In scope (explicitly, because the first attempt was rejected for it)
- Repointing `source` lines in all four `experiments/*/run_experiment.sh`. These are
  path-only edits; no runner gains or loses a step.
- Repointing the remote command strings listed under C3, including the ones inside
  `run_core.sh`, `endpoint.sh` and `measure.sh`.
- Repointing `_UTILS_DIR`, `_ENDPOINT_SH`, `_LOADGEN_PATH`, `_MEASURE_SH` and the
  harness argument in the moved `experiments/tests/` files.

## Out of scope
- Writing experiments/run.sh or consolidating entrypoints
- Deleting any run_experiment.sh runner
- Changing measurement **semantics** in the moved files: the logic, metric
  definitions and emitted formats of `endpoint.sh`, `measure.sh`, `core.sh`,
  `loadgen.py` and `analyze_metrics.py` stay as they are. Path strings are the only
  permitted edit; a diff of a moved file must contain nothing else.
- `CLAUDE.md`, `roadmap.md`, `docs/`, `.claude/skills/`, `.github/workflows/` — the
  reference sweep outside experiments/ is Sprint 5's job
- Frozen historical output: `experiments/*/reports/`, `experiments/ci-results/`
- Any change to src/
