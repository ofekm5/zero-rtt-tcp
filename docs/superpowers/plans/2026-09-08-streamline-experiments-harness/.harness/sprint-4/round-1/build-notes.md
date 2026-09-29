# Build notes — sprint 4 round 1

Commit: `cc84fcf harness(sprint-4): write run.sh's report under experiments/reports/<stack>/`

## Changes made
- experiments/lib/report.sh:48-194 — new `write_run_report STACK TRANSPORT` plus `_report_0rtt_ssm` / `_report_0rtt_ssh` / `_report_baseline`. Bodies copied from `dpdk/`, `proxmox/` and `baseline-tcp/run_experiment.sh`. Filenames keep each runner's convention: `integration-test-report-<date>.md`, `proxmox-test-report-<date>.md` and `baseline-report-<date-time>.md`. The writer resolves `experiments/reports/<stack>/` from its own location (`BASH_SOURCE`), so the output path does not depend on the caller's cwd. It reads `CORE_*`, `CLIENT_STDOUT`, `FAILURES`, `CONNECTIONS`, the `LOAD_*`/`NETEM_RTT_MS` knobs and `LAB_GATEWAY` (ssh only).
- experiments/run.sh:169-170, 211-213 — sources `lib/report.sh` and calls `write_run_report "$STACK" "$TRANSPORT"` after the summary banner, before `exit "$FAILURES"`. The old runners wrote their reports at the same point.
- experiments/reports/0rtt/.gitkeep, experiments/reports/baseline/.gitkeep (new) — the two report directories, tracked.
- experiments/tests/test_report_path.py (new) — copies `lib/{output,report}.sh` into a temp `experiments/` tree and calls `write_run_report` under `set -u` with stubbed `CORE_*` values, once for each of 0rtt/ssm, 0rtt/ssh, baseline/ssm and baseline/ssh. It asserts that exactly one file appears outside `lib/`, at `experiments/reports/<stack>/<convention>`, and that the file starts with that stack's title and contains the stubbed metrics.
- experiments/tests/test_run_sh.py:200-233 — a new module fixture `run_sh` runs `run.sh` from a temp copy (`run.sh` + `lib/`), because `run.sh` now writes a report and otherwise every pytest run would leave report files under the repo's `experiments/reports/`. The two existing tests take the fixture; their assertions and the RECORDED block are unchanged. New `test_run_sh_writes_its_report_under_reports_stack` checks that `run.sh` itself writes to the right `reports/<stack>/` file prefix for each of the three combos.
- experiments/README.md:8-13 — new "Reports" note: `run.sh` writes under `experiments/reports/<stack>/`, and `experiments/dpdk/reports/` and `experiments/baseline-tcp/reports/` are frozen historical output.

## Verification commands run
- C1: `pytest experiments/tests/test_report_path.py -q && test -d experiments/reports/0rtt -a -d experiments/reports/baseline` — exit 0, 4 passed; both directories exist.
- `python -m pytest experiments/tests -q` — exit 0, 85 passed. Afterwards `git status --untracked-files=all` showed no stray report files in the repo.
- `python -m pytest experiments/tests/test_run_sh.py -q` — exit 0, 7 passed (the 4 existing tests plus the 3 new ones).
- `bash -n experiments/run.sh experiments/lib/report.sh` — exit 0.
- Negative control (not a contract repair; the verify command is untouched). With the writer changed to write to `reports/` instead of `reports/$stack`, `test_report_path.py` exited 1 (`AssertionError: experiments/reports/integration-test-report-2026-09-28.md`). With `run.sh`'s `write_run_report` call no-op'd, `test_run_sh.py`'s new test exited non-zero (`assert False`). Both files were restored and re-run green: C1 exit 0, test_run_sh 7 passed.
- Body parity check (one-off scratch script, not committed): ran each old runner and `run.sh` under test_run_sh's mock harness in one temp tree and diffed the reports. The only differences are timestamps and the path repoints listed below.

## Open concerns
- I changed some path strings from the old runner bodies. Everything else is verbatim. Each change repoints a path invalidated by this change set; the plan's Global Constraints allow and require this:
  - 0rtt/ssm and 0rtt/ssh: `**Experiment script**` now names `experiments/run.sh`, not `experiments/{dpdk,proxmox}/run_experiment.sh`.
  - 0rtt/ssm: the `LOAD_RATE=0` capacity-run note now says "use `run.sh`".
  - 0rtt/ssm: `**Node scripts**` now says `experiments/nodes/` for all four. It was stale since Task 4 moved clientnic/servernic.sh.
  - The cross-stack comparison pointers now name `experiments/reports/baseline/` and `experiments/reports/0rtt/`, not the frozen `experiments/baseline-tcp/reports/` and `experiments/dpdk/reports/`.
  - Leaving the old text would also have planted `run_experiment.sh` strings in `lib/` that sprint 6's grep verify has to remove.
- `STACK=baseline TRANSPORT=ssh` has no old runner to copy from. It writes the SSM baseline body, marked with a `ponytail:` comment, whose `**Infra**` line names the `infra/baseline` CDK stack — inaccurate for the lab. No test or contract criterion covers that combo's body, only its path.
- 0rtt over ssh keeps the proxmox runner's filename (`proxmox-test-report-<date>.md`) inside `reports/0rtt/`. I read "that stack's filename convention" as per matching runner. If one 0rtt name was meant, that is a one-line change in `write_run_report`.
- The 0rtt/ssm and 0rtt/ssh filenames are date-only, as before, so two runs on the same day overwrite each other. This was already true of the old runners and I left it unchanged.
- `lib/report.sh`'s header comment still says "used by ... run_experiment.sh". I left it for sprint 6, whose grep verify covers `experiments/lib/`.
