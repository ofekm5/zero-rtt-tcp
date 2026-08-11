---
name: offline-analysis
description: Analyze a saved 0-RTT experiment bundle offline — no live VMs, no AWS, no lab access needed. Use after the `run-experiment` GitHub Actions workflow (.github/workflows/run-experiment.yml) has run an experiment and committed its results to experiments/ci-results/. Triggers on "analyze the last experiment", "investigate the CI run", "read the experiment bundle", "diagnose the saved run", "what went wrong in the experiment", "offline analysis", or when the user points at an experiments/ci-results/ directory. This is the LLM-reasoning half that run-experiment.yml deliberately leaves out.
---

# Offline Analysis — Post-hoc 0-RTT Experiment Investigator

The `run-experiment.yml` workflow runs an experiment on live infra and archives
**everything** it produced, but does **no reasoning**. This skill is that missing
half: it reads the saved bundle from disk and performs the same investigation the
`run-experiment` skill does live (its Steps 3–5) — a result summary, failure
diagnosis, and candidate insights — without touching any VM, AWS, or the lab.

Because all data is already on disk, this works from anywhere: a mobile/web session,
an offline checkout, or a machine with no AWS credentials.

## Step 0 — Locate the bundle

Bundles live under `experiments/ci-results/<STAMP>-<infra>/`. Always `git pull` first
so the newest committed bundle is present.

- **Newest bundle**: read `experiments/ci-results/latest.txt` — its `latest_bundle:`
  line is the path. Use this unless the user names a specific run.
- **A specific stack's newest bundle**: `latest-<infra>.txt` (e.g. `latest-dpdk.txt`,
  `latest-baseline.txt`). A `infra=both` workflow run leaves **two** bundles — one
  baseline, one dpdk — and these pointers are how you find each side of the pair.
- **A specific run**: the user may give a stamp, an infra type, or a GitHub Actions
  run URL. Match it against the directory names; `run-meta.json` inside each bundle
  carries `run_url`, `git_sha`, and `stamp_utc` to disambiguate.
- **A downloaded artifact**: if the user unzipped a `experiment-<infra>-<stamp>`
  artifact somewhere else, point at that directory instead — same layout.

If no bundle exists, say so and tell the user to trigger the workflow
(`gh workflow run run-experiment.yml -f infra=<both|dpdk|baseline|scapy>`) — do
**not** try to run the experiment yourself from here.

**Comparing a baseline/dpdk pair**: before quoting a 0-RTT saving, check that both
bundles' `run-meta.json` `knobs` blocks match. Any difference in `LOAD_*` or
`NETEM_RTT_MS` is a confound; say so instead of reporting a delta.

## Step 1 — Read the bundle

Each bundle contains:

| File | What it holds |
|------|---------------|
| `run-meta.json` | infra, `exit_code` (= failed-check count), `knobs` (resolved load/netem overrides), `repo_ref_on_vms`, git sha, run URL |
| `experiment.log` | **full, untruncated** orchestrator output — the primary source |
| `report.md` | the runner's auto-generated report (latency summary + tailed logs) |
| `reports/` | every file the runner left in `experiments/<dir>/reports/` |
| `node-logs/*.log` | best-effort full `/tmp/*.log` per VM + a pcap inventory (may be absent) |
| `README.md` | file index for the bundle |

Read `run-meta.json` first (the verdict is `exit_code`: 0 = all passed, N = N failed
checks), then `experiment.log` in full, then cross-reference `report.md` and the
`node-logs/`. Prefer `experiment.log`/`node-logs` over `report.md` when they disagree —
the report only tails each log, the full log does not.

**Note on pcaps**: raw captures stay on the VMs (too large to ship through SSM); the
`node-logs` pcap-inventory line lists their paths/sizes. Metric analysis
(`analyze_metrics.py`) already ran on the VM during the experiment, so its `fct=`,
`send_unlock=`, `server_gap=`, and any `missing=` lines are in `experiment.log`. If a
metric is genuinely unresolvable from the saved data, say so — don't invent numbers.

## Step 2 — Summarize the result

Post the same concise summary the live `run-experiment` skill produces (its Step 3),
sourced entirely from the bundle. Lead with the overall verdict and latency numbers,
then the per-check table. For **baseline**, omit ClientNIC/ServerNIC logs and packet
analysis.

---
**Offline Analysis — `<stamp>` (`<infra>`)** · [CI run](<run_url>)

**Overall: ✅ ALL PASSED** / **❌ N FAILURE(S)** (from `run-meta.json` `exit_code`)

**Latency** (from the report's Latency Summary block):
```
<TTFB @ client/clientnic/servernic + FCT + endpoint metrics>
```

| Check | Result |
|-------|--------|
| Build: clientnic-dpdk-forwarder | ✅ / ❌ |  ← DPDK/scapy only
| Build: servernic-dpdk | ✅ / ❌ |          ← DPDK only
| Smoke: forwarder busy-poll | ✅ / ❌ |     ← DPDK only
| Server listening on :8080 | ✅ / ❌ |
| ServerNIC running + IP forwarding | ✅ / ❌ |
| ClientNIC running + IP forwarding | ✅ / ❌ |
| Client: N/N connections succeeded | ✅ / ❌ |
| Server received data | ✅ / ❌ |
| ClientNIC 0-RTT flow activity | ✅ / ❌ | ← 0-RTT modes only
| Endpoint metric analysis | ✅ / ❌ |

**Bundle**: `experiments/ci-results/<stamp>-<infra>/`

---

For each ❌, quote the exact `[FAIL]` line or log excerpt from `experiment.log` /
`node-logs` that caused it.

## Step 3 — Diagnose failures (offline)

For every failed check, work only from the saved data:

1. **Find the first anomaly** — grep `experiment.log` for `[FAIL]`, `ERROR`,
   `FATAL`, `missing=`, `Traceback`. The earliest one usually explains the rest.
2. **Cross-correlate the logs** — ClientNIC + ServerNIC + Server node-logs + the
   endpoint metric lines together tell the full story of a dropped/mistranslated
   flow. State observed-vs-expected for each failed check, with exact lines/timestamps.
3. **Map to known patterns** — check the symptom against
   `.claude/skills/run-experiment/references/troubleshooting.md` (SSM daemon
   detachment, kernel-vs-Scapy race, MAC re-capture loop, swapped SEQ/ACK fields,
   GW-MAC resolution, scapy-dir shadowing, `LOAD_TIMEOUT`/`LOAD_PARALLEL` balance).
   Name the matching pattern and its documented fix.
4. **If the data is insufficient** to reach a root cause (e.g. the relevant log was
   truncated by SSM's cap, or a pcap that only lives on the VM is needed), say
   exactly what additional capture a re-run would need — don't guess a cause. A
   re-run is triggered via the workflow, not from this offline session.

## Step 4 — Propose insights for `experiments/insights.md`

Same rule as the live skill's Step 5: if the run surfaced a **durable insight** — a
confirmed root cause, a bottleneck localized to a specific layer, or a correction to
a documented capacity assumption — draft an entry in the existing
`experiments/insights.md` format (source bundle path, what the run showed, root
cause, "carry forward" takeaway).

**Ask the user before writing** — never append without approval. On confirmation,
append (never reorder prior entries); on decline, discard the draft. Routine
pass/fail results already in the bundle's report don't count.

## What this skill does NOT do

- Run experiments, deploy/destroy stacks, or touch AWS/SSM/the lab — it is read-only
  over saved files. To get fresh data, use the `run-experiment` skill (live) or the
  `run-experiment.yml` workflow (CI).
- Re-fetch pcaps or logs from VMs — if the bundle lacks something, note the gap.
