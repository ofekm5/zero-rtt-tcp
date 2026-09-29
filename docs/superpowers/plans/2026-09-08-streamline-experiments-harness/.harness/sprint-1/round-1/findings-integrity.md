# Findings — integrity lens — sprint 1 round 1

No findings under this lens.

Notes (not findings): all four criteria (C1, C2, C4 structural test -f/grep checks;
C3 pytest run) can fail on a plausible bad implementation, and each asserts the
directory-layout/dedup fact the criterion actually names rather than standing in
for unrelated behavior — C1/C2/C4 are inherently structural criteria (file
placement, single-definition), so a presence/grep check is not a stand-in here.
Verified experiments/lib/output.sh and experiments/lib/report.sh (C4's oracle
matches) are untouched by this round's diff — prior-sprint work, not gamed.
For C3, the round's diff touches experiments/tests/test_*.py, but only import/path
constants (confirmed via `git diff -M` against the prior commit) — no assertion or
expected-value lines changed, so the oracle (test logic) remains independent of
the subject (moved lib/nodes scripts) per the verify-feasibility carve-out for
renamed-but-unmodified oracles. No `## Contract repairs` section exists in
build-notes.md, so no repair-guard check applies.
