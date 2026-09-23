# Findings — integrity lens — sprint 1 round 2

No findings under this lens.

Notes (not findings): C1 and C2 both have a real failure branch (build-notes.md documents C2 actually failing exit 1 mid-round until the literal title text was moved into `report_header`'s default), their oracles are the literal grep patterns/strings hard-coded in `contract.md`, which this round's diff does not touch (`git diff c6ac688..080db25 --name-only` = `experiments/{baseline-tcp,dpdk,lib,scapy}/run_experiment.sh` + `experiments/lib/report.sh` only), and inspection of the diff shows a genuine parameterized refactor (`report_header`/`report_section`) rather than a hand-planted value or a grep pattern gamed to match. No `## Contract repairs` section exists in build-notes.md, so no contract-repair check applies.
