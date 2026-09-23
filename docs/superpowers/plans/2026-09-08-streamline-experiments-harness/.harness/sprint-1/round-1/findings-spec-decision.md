# Findings — spec-decision lens — sprint 1 round 1

### C2: exactly one file in experiments/lib/ contains the report header and neither old runner still embeds the report writer inline

**Key:** `spec-decision:C2:baseline-report-not-merged`
**Anchor:** experiments/baseline-tcp/run_experiment.sh:247-304

`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`'s Problem
section names the duplication this task exists to fix explicitly: "The ~100-line
report writer is duplicated between `dpdk/run_experiment.sh:201-286` and
`baseline-tcp/run_experiment.sh`." The round's diff (`git show HEAD`) only routes
`experiments/dpdk/run_experiment.sh` and `experiments/scapy/run_experiment.sh`
through the new `write_integration_report()` in `experiments/lib/report.sh`;
`experiments/baseline-tcp/run_experiment.sh` is byte-identical in its report-writing
block (lines 247-304, `{ ... } > "$REPORT_FILE"`) before and after this round — its
Load Parameters table, Latency Summary block, Client Output block, and Server Log
block, all near-duplicates of what dpdk's report used to contain inline, are still
authored inline rather than through the shared writer. The criterion's transcript
entry is exit 0 only because baseline-tcp's report title was always "Baseline TCP
Report", not "Integration Test Report" — the grep the verify command uses — so the
check passes without the duplication the design doc names as the reason for this
task being eliminated.

