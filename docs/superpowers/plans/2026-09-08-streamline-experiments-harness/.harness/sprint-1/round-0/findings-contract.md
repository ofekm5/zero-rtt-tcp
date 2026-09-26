# Findings — contract lens — sprint 1 round 0

Definition of done resolved via flat mode: `plan_path` header points to
`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`
(bolded as `**Spec:**` in the plan, not a literal `^Spec:` line, but
unambiguous from context — one design doc referenced). Its `## Success
Criteria` section matches this sprint's scope (Tasks 3 and 4: rehoming
laptop-side code to `lib/` and VM-side scripts to `nodes/`).

Sprint 1 contract has 4 verify-bearing criteria (C1-C4), no `manual review`
entries.

- C1 (`experiments/utils/` deleted, `lib/` + `lib/transport/` populated):
  `test -f ... -a ! -d experiments/utils` can fail on a bad implementation
  (missing file or surviving `utils/` dir) and asserts a purely structural
  claim the criterion itself makes (where code lives) — a presence check is
  the correct proof for a location claim, not a stand-in for behavior.
- C2 (VM-executed scripts in `experiments/nodes/`, no `.py` left in `lib/`):
  same shape as C1 — structural existence/absence check matching a
  structural criterion.
- C3 (tests pass at new location): `pytest experiments/tests/ -q` actually
  executes the moved test suite; can fail on import errors or assertion
  failures.
- C4 (helpers/report-writer each defined exactly once): the `grep -rl ... |
  wc -l -eq 1` pattern can fail (0 or >1 matches, or an empty/missing
  `experiments/lib/` collapses to 0) and asserts the exact-once-definition
  claim the criterion makes, which is inherently a location-count property —
  same technique the design doc's own Success Criteria use for the identical
  claim.

No `true`/bare-echo/`|| true` commands, no `grep -qv` absence traps, no
grep-for-interface-name standing in for a runnable check, and no prose
deliverable handed a `verify:` line. Contract has more than zero
verify-bearing criteria.

No findings under this lens.
