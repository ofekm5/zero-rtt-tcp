# Findings — integrity lens — sprint 2 round 1

No findings under this lens.

Notes (not findings):
- C1's verify command runs `experiments/run.sh` twice with bad `STACK`/`TRANSPORT` values, asserts nonzero exit, and greps the captured output for the literal accepted-value tokens (`0rtt`, `baseline`, `ssm`, `ssh`). These tokens are hardcoded in the contract's verify line, which is untouched by this round's diff (`git diff HEAD~1 HEAD --stat` shows only `experiments/run.sh` added) — oracle independent of the subject. `aws`/`ssh` are stubbed only as a guard; run.sh's validation `case` statements run before anything is sourced, so the stubs are never invoked on the bad-input paths, consistent with the "without making any remote call" clause.
- C2 (`test -x experiments/run.sh`) is a presence/mode check, but the criterion itself only asks for existence + executable bit, so a presence check is the correct instrument here, not a test-2 failure.
- No `## Contract repairs` section in build-notes.md — nothing to audit there.
- Round diff is a single new file (`experiments/run.sh`, 209 insertions, no other file touched), so no oracle file was co-edited with the subject.
