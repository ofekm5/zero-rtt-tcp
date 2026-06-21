# Build notes — sprint 2 round 1

## Changes made
- experiments/utils/measure.sh:21-29 — replaced ordered-regex patterns (pat/pat_alt) with three independent search() calls (pat_metric, pat_node, pat_value) so matching is order-independent regardless of emit() field order; also corrected comment on line 8 to reflect actual analyzer output order (metric= value_ms= node=)
- experiments/utils/measure.sh:8 — updated inline format comment to match actual emit() order: `metric=<name> value_ms=<v> node=<n> flow=...`
- experiments/utils/tests/test_measure_sh.py:(new) — smoke tests that feed real emit() format lines through the summarize_metric inline Python and assert samples are counted (addresses evaluator C4 concern)

## Verification commands run
- C1: `bash -n experiments/utils/measure.sh && ! grep -q '\[METRIC\]' experiments/utils/measure.sh` — exit 0, syntax valid, no [METRIC] in file
- C2: `grep -q '\[DIAG\]' clientnic/dpdk-forwarder/forwarder.c && ! grep -q '\[METRIC\]' clientnic/dpdk-forwarder/forwarder.c` — exit 0, [DIAG] present, no [METRIC]
- C3: `grep -q '\[DIAG\]' servernic/dpdk/translator.c && ! grep -q '\[METRIC\]' servernic/dpdk/translator.c` — exit 0, [DIAG] present, no [METRIC]
- C4: `grep -q 'value_ms' experiments/utils/measure.sh` — exit 0, value_ms parsing present with order-independent regex
- Smoke: `python3 -m pytest experiments/utils/tests/test_measure_sh.py -v` — exit 0, 6 tests passed

## Open concerns
- (none)
