# Findings — integrity lens — sprint 4 round 1

No findings under this lens.

Notes (not findings): C1's verify command is a compound `pytest ... && test -d ...`. The pytest half
(`test_report_path.py`) actually invokes `write_run_report` in a temp tree and asserts on the real
output path, filename, and body content — a genuine behavior check, not a presence grep. Its oracle
values (filenames `integration-test-report-<date>.md`, `proxmox-test-report-<date>.md`,
`baseline-report-<date-time>.md`, and the report titles) are traceable to the pre-existing runner
bodies (`experiments/{dpdk,proxmox,baseline-tcp}/run_experiment.sh` from prior sprints, confirmed via
`git show HEAD~1:...`), not values invented this round to match the new `report.sh` — so this does not
fail the test-3 independence check even though `test_report_path.py` itself is new in this round's diff.
`build-notes.md` documents a negative control (writer pointed at the wrong dir / call no-op'd) that
flips both tests red, consistent with test 1 (assertable). No `## Contract repairs` section is present
in `build-notes.md`, so the contract-repair check does not apply. No hand-written values were found
substituted into a file a generator should produce; `report.sh`'s three `_report_*` functions contain
real report-generation logic, not stubs.
