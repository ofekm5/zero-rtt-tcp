# Build notes — sprint 5 round 1

## Changes made
- experiments/dpdk/run_experiment.sh, experiments/baseline-tcp/run_experiment.sh, experiments/proxmox/run_experiment.sh — deleted (run.sh is the only orchestrator). `experiments/proxmox/` is now empty and gone.
- experiments/scapy/ (clientnic.sh, servernic.sh, run_experiment.sh) — deleted.
- experiments/run_think_sweep.sh -> experiments/sweeps/think.sh (git mv, mode 755 kept) — the `case "$MODE"` runner pick is replaced by `STACK` (default `0rtt`, validated against `0rtt|baseline`, exported to run.sh); RUNNER is `experiments/run.sh`; REPO_ROOT now `../..`; default SWEEP_OUT moved to `experiments/reports/<stack>/sweep-<ts>`; usage/env comments updated.
- experiments/dpdk/run_stress.sh -> experiments/sweeps/stress.sh (git mv, mode 755 kept) — still exports LOAD_RATE=0 and prints the capacity-run caveat; now `exec "$(dirname "$0")/../run.sh"`; comments retargeted at run.sh.
- experiments/lib/core.sh:483, experiments/lib/measure.sh:133 — comment-only path fixes pointing at the moved sweep files.
- C3 and C4 already held at the start of the round (one `log()` in lib/output.sh, one report writer in lib/report.sh; nodes/ complete, no lib/*.py); no change needed for them.

## Verification commands run
- C1: `test -z "$(find experiments -name run_experiment.sh)" && test ! -d experiments/scapy && test -f experiments/sweeps/think.sh -a -f experiments/sweeps/stress.sh` — exit 0
- C2: `test -x experiments/run.sh && test -z "$(find experiments -name run_experiment.sh)"` — exit 0
- C3: `[ "$(grep -rl '^log()' experiments/lib/ | wc -l)" -eq 1 ] && [ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ]` — exit 0
- C4: `test -f experiments/nodes/{client,server,clientnic,servernic}.sh ... loadgen.py ... analyze_metrics.py && test -z "$(ls experiments/lib/*.py)"` — exit 0
- `python -m pytest experiments/tests -q` — 85 passed (includes test_path_refs.py: all scripts parse under `bash -n`, sourced paths resolve)
- `bash experiments/sweeps/stress.sh` — printed the caveat, exec'd run.sh, reached "Step 0: Discovering 0rtt nodes over ssm...", exited 1 at "could not find running node" (no stack deployed); no "No such file" error.
- `THINK_SWEEP=0 bash experiments/sweeps/think.sh` — reached run.sh node discovery for the 0rtt stack, point recorded as failed (no stack), curve.md written; no "No such file" error.
- `STACK=dpdk bash experiments/sweeps/think.sh` — exit 2, "accepted values: 0rtt, baseline".

## Open concerns
- The two sweep smoke runs above were meant to hit a stub `aws` placed first on PATH, but discovery printed `None` for the instance IDs and the stub's stderr marker never showed up. So the real AWS CLI probably ran read-only `ec2 describe-instances` calls through run.sh's SSM transport. That is network access the sandbox screen doesn't see, because it happens inside a script. I did not re-run it.
- `python experiments/tests/test_run_sh.py --record` can no longer regenerate its oracle, because it copies the deleted runners. The pinned RECORDED block and the tests that use it are unaffected (85 passed). Its docstrings and `_OLD_RUNNERS` still name the deleted runners as provenance. I left them as-is and did not delete `_record()`.
- Out-of-scope callers still point at deleted paths and are left for sprint 6: `.github/workflows/run-experiment.yml:215-217` (`experiments/$EXP_DIR/run_experiment.sh`), `.claude/skills/`, `CLAUDE.md`, `experiments/README.md`. Header comments in `experiments/lib/output.sh:2`, `experiments/lib/report.sh:2-3`, `experiments/lib/endpoint.sh:5`, `experiments/lib/core.sh:152,397` and `experiments/tests/test_endpoint_sh.py:4` also still mention `run_experiment.sh`. Sprint 6's verify greps `experiments/lib/` for that string.
- The stress sweep used to be DPDK-only. It now honours `STACK` and `TRANSPORT` via run.sh and defaults to `0rtt`/`ssm`, so it matches the old behaviour by default.
