# Findings — contract lens — sprint 2 round 0

Definition of done resolved via flat mode: `docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md` → `Spec:` header → `docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`, `## Success Criteria` (lines 75-98).

Sprint 2 contract (`.harness/sprint-2/contract.md`) covers Task 5.2 only (`experiments/run.sh` dispatch).

### C1: unrecognised STACK/TRANSPORT exits non-zero naming accepted values, no remote call

No findings. The verify command actually invokes `experiments/run.sh` (test 2: exercises the script, not a source grep), asserts non-zero exit via `! o1=$(...)` and `! o2=$(...)` (test 1: a plausible bad implementation — no validation — would leave the grep assertions unsatisfied, so the command can fail), and checks the emitted message names both accepted values for each variable. The deliverable is executable and the check runs it (not `grep-not-run`).

### C2: `experiments/run.sh` exists and is marked executable

No findings. The criterion's claim is a static property (existence + executable bit), not runtime behavior, so `test -x experiments/run.sh` is a sufficient and appropriately scoped check — it can fail (missing file or non-executable) and it matches what the criterion actually asserts.

### Executable floor

Sprint has 2 verify-bearing criteria (C1, C2); `totalCriteria > 0` is satisfied.

No findings under this lens.
