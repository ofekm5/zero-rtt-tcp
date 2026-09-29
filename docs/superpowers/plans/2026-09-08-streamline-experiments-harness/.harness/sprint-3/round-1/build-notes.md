# Build notes — sprint 3 round 1

## Changes made
- experiments/tests/test_run_sh.py (new) — adds the mock-transport test for C1 (commit 097c27d).
  - The harness is embedded in the test file and run as `bash -c 'eval "$(cat)"' ../run.sh <stack> <transport>`, so `$0` is the real script path. It stubs `aws`, `ssh` and `sleep`. It wraps `source` so that after each sourced file it replaces whichever primitive layers exist (`remote_run/bg/stdout`, and `ssm_run/bg/stdout` when the transport defines them) with recorders. The recorders trace to fd 9 and send back the answers a healthy chain would give.
  - Node ids are role names on both transports, via the `LAB_*_IP` vars and the `aws` stub. Load knobs are unset so the run doesn't depend on the caller's environment.
  - Pinned sequences for 0rtt+ssm (51 calls, exit 0), 0rtt+ssh (53 calls, exit 1) and baseline+ssm (44 calls, exit 0). Each entry is `<verb> <node> <command prefix>`. Order, count, call kind and target node are compared exactly; long commands are compared by their leading prefix. Whitespace inside a command is collapsed before comparing.
  - A separate test asserts that `STACK=baseline` issues no `meson setup`, `nodes/{client,server}nic.sh` or `*nic-dpdk` call.
  - Bash is invoked by the full path from `shutil.which("bash")`. On Windows a bare `bash` resolves to the System32 WSL launcher, which drops argv[0] and stdin.
- How the pinned lists were recorded: I ran the same harness against `dpdk/run_experiment.sh`, `proxmox/run_experiment.sh` and `baseline-tcp/run_experiment.sh`, and against `run.sh` for the matching STACK/TRANSPORT. Both the normalized call lists and the exit codes were identical in all three pairs (0rtt+ssm 51/51 rc 0/0; 0rtt+ssh 53/53 rc 1/1; baseline+ssm 44/44 rc 0/0).

## Verification commands run
- C1: `pytest experiments/tests/test_run_sh.py -q` — exit 0, "4 passed" (3 parametrized sequence cases + the baseline no-NIC case). Also ran `python -m pytest experiments/tests/test_run_sh.py -q` — 4 passed.
- Recording comparison (one-off python driver calling `_calls()` on old runner vs run.sh) — `equal True` for all three pairs, as listed above.
- `python -m pytest experiments/tests/test_endpoint_sh.py -q` — 13 passed. Run before the work began, to confirm the existing stub pattern works here.
- Negative control: not completed. I moved one baseline entry (`bg server pkill -f loadgen.py`) after `_analyze(...)` and re-ran the test, but the auto-mode permission classifier denied the test run. I reverted the edit with an exact inverse Edit before committing, so the committed file is the one that produced "4 passed". I did not re-run it after the revert, because the same command had just been denied.

## Open concerns
- Three untracked report files, written by the old runners during the one-off recording, are still in the worktree. My `rm` was denied by the permission classifier. They are not committed and need manual removal:
  - `experiments/dpdk/reports/integration-test-report-2026-09-28.md`
  - `experiments/proxmox/reports/` (new dir holding `proxmox-test-report-2026-09-28.md`)
  - `experiments/baseline-tcp/reports/baseline-report-2026-09-28-212336.md`
- Pre-existing bug, pinned as recorded rather than fixed (out of scope: `lib/measure.sh` and the transport shims): `run_ttfb_measurement` calls `ssm_run` directly, and `lib/transport/ssh_lab.sh` does not define it. So on `TRANSPORT=ssh` the client-load step is "command not found" and the run exits 1. The old proxmox runner behaves the same way. As a result, the plan's claim that the two 0-RTT sequences "differ only in REPO_PATH" after the prologue does not hold: the ssh sequence also lacks the load call. The `EXPECTED` entry for 0rtt+ssh documents this. Fixing measure.sh to call `remote_run` means updating that entry (`client_load=False` → default, exit 1 → 0).
- Sprint 4 heads-up: once `run.sh` writes a report under `experiments/reports/<stack>/`, every run of this test will write a report file into the repo. Sprint 4 will need to redirect or stub the report path in the harness.
- The negative control described above was not completed (classifier denial). A grader can reproduce it by swapping or deleting one entry in `EXPECTED` and re-running C1.
