# Sprint 3: Write single run.sh entrypoint

## Tasks
- Task 5: Write experiments/run.sh with STACK/TRANSPORT dispatch; absorb shared flow into experiments/lib/core.sh

## Acceptance criteria
- C1: run.sh is executable and exits non-zero for an unrecognised STACK value — verify: `test -x experiments/run.sh && { remote_run(){ :; }; remote_bg(){ :; }; remote_stdout(){ :; }; export -f remote_run remote_bg remote_stdout; STACK=__invalid__ TRANSPORT=ssm bash experiments/run.sh 2>/dev/null; [ "$?" -ne 0 ]; }`
- C2: STACK=baseline correctly skips NIC build, NIC start, and NIC log-collection steps and STACK=0rtt issues those steps for both transports — manual review (confirmed by the mock-transport test suite in Sprint 4)

## Out of scope
- Writing the mock-transport test (Sprint 4)
- Deleting old run_experiment.sh runners (Sprint 4)
- Updating .github/workflows/, skill docs, or CLAUDE.md (Sprint 5)
- Changing measurement semantics or metric definitions
- Any change to src/
