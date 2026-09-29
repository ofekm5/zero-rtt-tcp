# Findings — contract lens — sprint 1 round 0

No findings under this lens.

Context checked:
- `.harness/sprint-1/contract.md` has one criterion (C1) with a `verify:` command; no `manual review` criteria present.
- C1's verify command shims `remote_run`/`remote_bg`/`remote_stdout`/`ssm_run` to append their arguments to a log file, sources the real `experiments/lib/core.sh` and `experiments/lib/measure.sh`, invokes the real `run_experiment` function under both `STACK=baseline` and unset `STACK`, and asserts on the resulting call-sequence log via `grep -qF`/`! grep -qE`. This actually exercises `run_experiment`'s control flow (test 2: behavior, not text presence) and can fail on a plausible bad implementation — e.g. an implementation that ignores `STACK` would cause the `! grep -qE 'meson setup|nodes/(client|server)nic\.sh|...'` branch to fail for the baseline case (test 1: assertable by exit code).
- The negative-assertion form used is `! grep -qE 'pattern' <<< "$b"` (fails only if some line matches), not the `grep -qv` trap (which would incorrectly pass whenever any single line lacks the pattern) — correct usage.
- The grep checks run against a runtime-generated log of shimmed remote calls, not against contract.md/core.sh source text, so this is not the "grep-not-run" trap (checking an interface's name in a doc/source instead of invoking it) — the interface is actually invoked.
- No prose/narrative criteria in this contract to misuse a verify line on.
- Contract has exactly 1 executable (`verify:`-bearing) criterion, so the executable floor (`totalCriteria > 0`) is satisfied.
- Oracle independence (verify-feasibility test 3) is out of scope for this lens per the round-0 carve-out and was not evaluated.
- Success-Criteria coverage against the plan's design doc (`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`, resolved via `plan_path`'s `**Spec:**` header) is out of scope for a lane-scoped grader and was not evaluated.
