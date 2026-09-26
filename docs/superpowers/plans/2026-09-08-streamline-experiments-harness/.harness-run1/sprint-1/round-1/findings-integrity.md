# Findings — integrity lens — sprint 1 round 1

### C2: exactly one file in experiments/lib/ contains the report header and neither old runner still embeds the report writer inline

**Key:** `integrity:C2:unchecked-duplicate`
**Anchor:** .harness/sprint-1/contract.md:9

The verify command is `[ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ] && ! grep -q 'Integration Test Report' experiments/dpdk/run_experiment.sh && ! grep -q 'Integration Test Report' experiments/baseline-tcp/run_experiment.sh`. Task 2 and this round's own build-notes.md identify the two duplicated report writers being merged as **dpdk and scapy** (byte-identical "Integration Test Report" header/tail; baseline-tcp/proxmox have distinct headers and were explicitly left untouched as out of scope). The command's second `grep -q` checks `experiments/baseline-tcp/run_experiment.sh` — a file that never contained the string and was never part of the merge — instead of `experiments/scapy/run_experiment.sh`, the file that actually needed to lose its inline duplicate. A bad implementation that hoisted `lib/report.sh` but left the report-writer block duplicated inline in `experiments/scapy/run_experiment.sh` would still pass this command: `grep -rl` over `experiments/lib/` still finds exactly one match (report.sh), and neither of the two files the command actually checks (dpdk, baseline-tcp) would contain the string. So the command cannot fail on the one bad-implementation case its own criterion text is about (scapy left unmerged) — it fails test 1's "zero only on the success case" for that failure mode.

By inspection of this round's diff, `experiments/scapy/run_experiment.sh` was in fact correctly hoisted (its inline "Integration Test Report" block was removed and replaced with a call to `write_integration_report` from the newly sourced `lib/report.sh`), so this round's actual C2 outcome is correct — but the command as written would not have caught a failure to do so, which is the defect being flagged, not this round's result.

