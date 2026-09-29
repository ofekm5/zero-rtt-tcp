# Findings — spec-decision lens — sprint 6 round 1

No findings under this lens.

Checked C1 ("no live caller references `run_experiment.sh`") against the design doc's
(`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`) Success
Criterion 4 (live callers reference only `experiments/run.sh`, scoped away from frozen
historical output) and Key Constraints (transport defaults, `STACK=baseline` has no
data plane, report directories keep the stack split). The round's diff is a
documentation/comment retarget — `.github/workflows/run-experiment.yml`, both skill
docs and their references, `CLAUDE.md`, and four `lib/*.sh` comment headers — and its
content matches those decisions: the workflow drops `scapy` from its infra matrix and
switches to `STACK`/`REPORT_DIR` outputs without ever setting `TRANSPORT` (correct,
since CI is SSM-only and `TRANSPORT` defaults to `ssm`); `CLAUDE.md` and the skill
tables describe the single `run.sh` entrypoint with `STACK`/`TRANSPORT` and the
`experiments/reports/<stack>/` split; the `CONNECTIONS` defaults documented (1 for
every stack/transport combination) match `experiments/run.sh`'s actual
`CONNECTIONS="${CONNECTIONS:-1}"`. No decision or invariant from the design doc is
contradicted by this round's changes.
