# Sprint 2: run.sh dispatch

## Tasks
- Task 5.2: Add `experiments/run.sh`, the single entrypoint with `STACK`/`TRANSPORT` dispatch

## Acceptance criteria
- C1: `experiments/run.sh` exits non-zero with a message naming the accepted `STACK` values when given an unrecognised `STACK`, and exits non-zero with a message naming the accepted `TRANSPORT` values when given an unrecognised `TRANSPORT`, without making any remote call — verify: `( aws() { return 97; }; ssh() { return 97; }; export -f aws ssh; ! o1=$(STACK=quic bash experiments/run.sh 2>&1) && grep -q 0rtt <<< "$o1" && grep -q baseline <<< "$o1" && ! o2=$(TRANSPORT=pigeon bash experiments/run.sh 2>&1) && grep -q ssm <<< "$o2" && grep -q ssh <<< "$o2" )`
- C2: `experiments/run.sh` exists and is marked executable — verify: `test -x experiments/run.sh`

## Out of scope
- Adding the mock-transport pytest suite (sprint 3)
- Writing reports to `reports/<stack>/` (sprint 4)
- Deleting the four runners (sprint 5)
- Updating callers in `.github/workflows/`, `.claude/skills/`, and `CLAUDE.md` (sprint 6)
