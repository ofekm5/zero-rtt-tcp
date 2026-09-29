# Findings — spec-decision lens — sprint 4 round 1

No findings under this lens.

Checked C1 ("Write run.sh's report under reports/{0rtt,baseline}/") against the
decisions in docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md:

- "Report directories keep the stack split... New runs write to
  experiments/reports/0rtt/ and experiments/reports/baseline/" — `write_run_report`
  in experiments/lib/report.sh resolves `dir=.../reports/$stack` (stack only, not
  transport), matching exactly; baseline/ssm and baseline/ssh both land under
  reports/baseline/.
- "experiments/dpdk/reports/ and experiments/baseline-tcp/reports/ are never moved,
  renamed, or deleted" (Non-Goal) — git diff for this round touches no files under
  those paths; only experiments/reports/{0rtt,baseline}/.gitkeep are added.
- Task 8 outcome: "the body the matching runner writes today" — compared
  _report_0rtt_ssm/_report_0rtt_ssh/_report_baseline against
  experiments/dpdk/run_experiment.sh, experiments/proxmox/run_experiment.sh and
  experiments/baseline-tcp/run_experiment.sh (still present pre-Task-7): section
  order, headings, table rows and filename conventions
  (integration-test-report-<date>.md, proxmox-test-report-<date>.md,
  baseline-report-<date-time>.md) all match. The only textual deltas are path
  repoints required by earlier sprints' moves (run_experiment.sh -> run.sh,
  experiments/dpdk/ + experiments/nodes/ -> experiments/nodes/ for node scripts,
  experiments/dpdk/reports/ -> experiments/reports/0rtt/ in the cross-reference
  notes) — explicitly permitted by plan.md's Global Constraints ("repointing a path
  string... is explicitly exempt and is required wherever a move invalidates it").
- README.md gained the required note that the two historical report directories
  are frozen, per Task 8's outcome text.

No design/spec decision or invariant is violated by this round's diff.
