# Findings — spec-decision lens — sprint 1 round 1

No findings under this lens.

Checked design decisions from `docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`
(resolved via `plan_path`'s `Spec:` header, flat mode) against this round's diff
(commit bb6f803, Tasks 3 and 4):

- Byte-identity constraint ("moves byte-identical... repointing a path string is
  explicitly exempt and required"): every changed line in `run_core.sh`→`lib/core.sh`,
  `endpoint.sh`, `measure.sh`, `ssm.sh`, `client.sh`, `server.sh`, `clientnic.sh`, and
  the four `run_experiment.sh` callers is a `source`/comment/remote-command path
  repoint from `utils/`→`lib/`(`/transport/`) or `dpdk/`→`nodes/`; no other lines
  changed.
- Task 3 outcome ("every source path resolves... moved pytest files import their
  targets at the new paths"): confirmed no `utils/` references remain anywhere
  under `experiments/lib/`, `experiments/nodes/`, or the four runners; test files
  (`test_endpoint_sh.py`, `test_loadgen.py`, `test_analyze_metrics.py`,
  `test_measure_sh.py`) resolve their targets at `../lib/` and `../nodes/`.
- Task 4 outcome ("every remote command string that names one of them... uses the
  new path"): `lib/core.sh` invokes `nodes/servernic.sh` and `nodes/clientnic.sh`;
  `lib/endpoint.sh` and `lib/measure.sh` invoke `nodes/analyze_metrics.py` and
  `nodes/loadgen.py`; `nodes/client.sh`/`nodes/server.sh` invoke `nodes/loadgen.py`.
- C2 second clause ("no Python files remain in experiments/lib/"): confirmed via
  transcript and `find`.
- Prior-sprint invariant (C4 — single `log()`, single report writer): still holds
  after the move (`experiments/lib/output.sh`, `experiments/lib/report.sh`).

Task 5 (run.sh dispatch, `REPO_PATH` derivation from transport, `STACK=baseline`
skip logic) is out of scope for this sprint's contract and was not built this
round, so its design decisions are not gradeable yet.
