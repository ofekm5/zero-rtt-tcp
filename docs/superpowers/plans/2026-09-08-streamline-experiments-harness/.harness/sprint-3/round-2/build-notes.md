# Build notes — sprint 3 round 2

## Changes made
- experiments/tests/test_run_sh.py:12-21 — rewrote the docstring. It now says where the expected sequences come from and how to reproduce them.
- experiments/tests/test_run_sh.py:150-215 — removed the hand-typed `EXPECTED` literal and its builder helpers (`_sync`, `_zero_rtt`, `_baseline`, the prologues and the rest). This addresses `integrity:C1:self-authored-oracle`. In their place:
  - `_OLD_RUNNERS` maps each (stack, transport) to its old runner.
  - `_record()` runs each old runner through the same `_calls` harness and rewrites the RECORDED block with the runner's calls verbatim, whitespace-collapsed, with its exit code.
    - Invocation: `python experiments/tests/test_run_sh.py --record`.
    - Each runner runs from a temp copy with `lib/` beside it. The report the runner writes on exit therefore lands in the temp dir, not the repo.
    - STACK and TRANSPORT are passed empty, which means unset, matching how the old runners were always invoked.
  - `_parse()` reads the block.
  - The parametrized test compares run.sh's calls to the recording exactly. The old version compared only a hand-picked leading prefix of each command, so a change in a command's tail went undetected.
- experiments/tests/test_run_sh.py:216-381 — the generated RECORDED block, written by `--record` and not edited by hand. It holds 0rtt+ssm (51 calls, exit 0), 0rtt+ssh (53, exit 1) and baseline+ssm (44, exit 0), the same counts and exit codes round 1 reported.
- `test_baseline_issues_no_nic_build_or_start` is unchanged.
- This follows plan Task 6 ("expected sequences are recorded from [the old runners] while they still exist … the test carries no separate test that runs the old runners"). The old runners run only in the `--record` generator, never in a pytest test. The pinned block outlives their deletion in sprint 5.

## Verification commands run
- C1: `pytest experiments/tests/test_run_sh.py -q` — exit 0, "4 passed".
- Recording is reproducible from the old runners, run after the commit: `python experiments/tests/test_run_sh.py --record && git diff --exit-code -- experiments/tests/test_run_sh.py` — exit 0, no diff. The same check with `cmp` against a pre-rerun copy also exited 0.
- Negative control, oracle side:
  - Moved the recorded baseline line `bg server pkill -f loadgen.py 2>/dev/null || true` one place later with sed. C1 then exited 1: "1 failed, 3 passed", with `test_remote_call_sequence_matches_the_old_runner[baseline-ssm]` failing.
  - Restored by re-running `--record`. `cmp` against the pre-mutation copy exited 0, and C1 exited 0 with "4 passed".
- Negative control, subject side (scratchpad copy of `experiments/run.sh` + `experiments/lib/`; the repo was not touched):
  - The unmodified copy's calls equal RECORDED for all 3 combinations.
  - I then changed `sleep 2` to `sleep 3` in the NIC-stop command of the copied `lib/core.sh`. 0rtt+ssm and 0rtt+ssh now report DIFFERENT, and baseline+ssm stays equal, since baseline has no NIC stop.
  - The old prefix-based comparison would not have caught this change.
- `python -m pytest experiments/tests -q` — exit 0, "78 passed".
- `--record` created no new files in the repo. `git status` shows only the three pre-existing untracked reports listed below.

## Open concerns
- Three untracked report files left by round 1's one-off recording are still in the worktree. `rm` was denied by the auto-mode classifier again this round. They are not committed and need manual removal:
  - `experiments/baseline-tcp/reports/baseline-report-2026-09-28-212336.md`
  - `experiments/dpdk/reports/integration-test-report-2026-09-28.md`
  - `experiments/proxmox/reports/` (holds `proxmox-test-report-2026-09-28.md`)

  This round's `--record` runs the old runners from a temp copy, so it cannot create more of these.
- Carried over from round 1 (out of scope: `lib/measure.sh` and the transport shims):
  - `run_ttfb_measurement` calls `ssm_run`, which `lib/transport/ssh_lab.sh` does not define. So 0rtt+ssh has no client-load call and exits 1. The old proxmox runner behaves the same way, and the recording captures that.
  - The plan's claim that the two 0-RTT sequences "differ only in REPO_PATH after the prologue" therefore does not hold.
  - Fixing measure.sh means re-running `--record` while the old runners still exist, or editing the block by hand after they are gone.
- Once sprint 5 deletes the old runners, `--record` can no longer regenerate the block. It becomes a frozen artifact, as the plan intends. Any later intended change to a remote command then needs a hand edit of the block.
- Sprint 4 heads-up, unchanged: once `run.sh` writes a report, every run of this test will write a report into the repo. The harness will need to redirect or stub the report path. The temp-copy technique `_record()` uses for the old runners is one option.
