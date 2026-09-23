# Build notes — sprint 1 round 1

## Changes made
- experiments/lib/output.sh (new) — hoisted the byte-identical `RED/GREEN/YELLOW/NC` colors and `log()/pass()/fail()/warn()` definitions that were duplicated verbatim across all four `run_experiment.sh` runners.
- experiments/lib/report.sh (new) — `write_integration_report()`, a parameterised writer covering the shared "# Integration Test Report" shape (title, Client Output / ClientNIC Log / ServerNIC Log / Server Log / Packet Analysis sections, same `tail -50/-30/-20`) that dpdk and scapy both emitted inline; parameterised on implementation-info lines, overall result, an optional extra-body block (dpdk's Load Parameters/Latency Summary/capacity banner; empty for scapy), and the four log/analysis blobs.
- experiments/dpdk/run_experiment.sh — sources `lib/output.sh` and `lib/report.sh`; replaced the inline color/log block and the inline report-writer `{ ... } > "$REPORT_FILE"` with calls into the two shared helpers.
- experiments/scapy/run_experiment.sh — same hoist; report block now builds `IMPL_INFO` + fetches `SERVERNIC_LOG` via `ssm_stdout` first, then calls `write_integration_report` with `EXTRA_BODY=""`.
- experiments/baseline-tcp/run_experiment.sh, experiments/proxmox/run_experiment.sh — sources `lib/output.sh` only (Task 1 scope); their report writers were not touched (Task 2 only asked to merge "the two duplicated" writers — dpdk and scapy share the literal `Integration Test Report` header and identical tail structure; baseline-tcp and proxmox each have distinct headers/fields — `# Baseline TCP Report`, `# Proxmox 0-RTT Test Report` — and merging those would have changed output formatting/metric layout, which is out of scope).

## Verification commands run
- C1: `test -f experiments/lib/output.sh && ! grep -qE '^log\(\)' experiments/dpdk/run_experiment.sh experiments/baseline-tcp/run_experiment.sh experiments/proxmox/run_experiment.sh experiments/scapy/run_experiment.sh` — exit 0.
- C2: `[ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ] && ! grep -q 'Integration Test Report' experiments/dpdk/run_experiment.sh && ! grep -q 'Integration Test Report' experiments/baseline-tcp/run_experiment.sh` — exit 0.
- `bash -n` on all six touched/added files — exit 0 each (no syntax errors).
- Functional-equivalence check (not part of the contract, extra diligence given "no change to output formatting" is out of scope): reconstructed the pre-refactor inline report-writer bodies for both dpdk and scapy in throwaway scripts under a scratch temp dir, ran them against the same synthetic inputs as the new `lib/report.sh`-based versions (including the dpdk `LOAD_RATE=0` capacity-banner branch), and `diff`'d old vs new output — all three comparisons (dpdk normal, dpdk capacity run, scapy) came back byte-identical. Scratch files removed after the check; nothing under the repo was left behind.

## Open concerns
(none)
