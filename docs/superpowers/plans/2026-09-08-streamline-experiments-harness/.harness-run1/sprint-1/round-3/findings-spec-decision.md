# Findings — spec-decision lens — sprint 1 round 3

No findings under this lens.

Round-3's diff (`experiments/lib/report.sh`, `experiments/dpdk/run_experiment.sh:263`,
`experiments/scapy/run_experiment.sh:337`) resolves round-2's
`spec-decision:C2:trailing-blank-line-drift` finding: `report_section` gained an
opt-in `NO_TRAILING_BLANK` 4th arg, applied only to the final `report_section` call
in the dpdk and scapy writers. Verified against the pre-refactor sources
(`git show 2943c54:experiments/dpdk/run_experiment.sh` and
`git show 2943c54:experiments/scapy/run_experiment.sh`): both historically ended the
report file directly after the closing fence with no trailing blank line, which the
new suppressed call now reproduces byte-for-byte. `experiments/baseline-tcp/run_experiment.sh`
was correctly left unchanged — its last `report_section` call (Server Log) is followed
by a manually-written `## Notes` block, and the pre-refactor source
(`git show 2943c54:experiments/baseline-tcp/run_experiment.sh`) shows the blank line
before `## Notes` was already present, so suppressing it there would itself have been
a new textual-equivalence violation. This satisfies the design doc's Task 2 outcome
("Reports produced for a given stack are textually equivalent to what that stack
produced before", `docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md:41`).
