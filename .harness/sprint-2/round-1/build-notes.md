# Build notes — sprint 2 round 1

## Changes made
- experiments/utils/measure.sh:(new rewrite) — replaced [METRIC]-pattern summarize_metric with analyzer-output parser using metric=/value_ms= fields; removed all [METRIC] grep references
- clientnic/dpdk-forwarder/forwarder.c:39 — relabeled [METRIC] to [DIAG] in log_ttfb LOG_INFO call
- servernic/dpdk/translator.c:40 — relabeled [METRIC] to [DIAG] in log_ttfb LOG_INFO call

## Verification commands run
- C1: `bash -n experiments/utils/measure.sh && ! grep -q '\[METRIC\]' experiments/utils/measure.sh` — exit 0, syntax valid, no [METRIC] in file
- C2: `grep -q '\[DIAG\]' clientnic/dpdk-forwarder/forwarder.c && ! grep -q '\[METRIC\]' clientnic/dpdk-forwarder/forwarder.c` — exit 0, [DIAG] present, no [METRIC]
- C3: `grep -q '\[DIAG\]' servernic/dpdk/translator.c && ! grep -q '\[METRIC\]' servernic/dpdk/translator.c` — exit 0, [DIAG] present, no [METRIC]
- C4: `grep -q 'value_ms' experiments/utils/measure.sh` — exit 0, value_ms parsing present

## Open concerns
- (none)
