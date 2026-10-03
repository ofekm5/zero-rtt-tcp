---
name: run-experiment
description: Run or diagnose live 0-RTT TCP, plain TCP, and QUIC experiments on AWS EC2 or the RUNS lab, preserving matched load settings and recording reports and artifacts. Use for live measurements and four-node packet-flow checks, not offline unit tests.
---

# Run Experiment — 0-RTT Integration Tester

Each experiment is a self-contained orchestrator script that discovers nodes, pulls
code, starts services in order, runs the client, captures packets, analyzes metrics,
**and writes its own report**. Your job: pick the mode, run the script, summarize the
result in chat, and investigate any failures.

## Step 0 — Choose experiment mode

Infer the mode from the request and existing session authorization. Ask only when the target is unspecified:

> "Which experiment should I run?
> 1. **DPDK** (AWS) — 0-RTT, C/DPDK forwarder + translator (`./experiments/run.sh`)
> 2. **Proxmox** — 0-RTT DPDK on the RUNS lab via SSH gateway (`TRANSPORT=ssh ./experiments/run.sh`)
> 3. **Baseline** (AWS) — plain TCP, kernel forwarding, no middleware (`STACK=baseline ./experiments/run.sh`)"

Set variables based on the answer:

A comparison request ("dpdk vs baseline", "does 0-RTT actually win") is **not** a
mode choice — it is `infra=both` in one dispatch (Step 1). Don't run the two stacks
as separate dispatches with hand-matched knobs.

| Variable | DPDK (AWS) | Proxmox | Baseline |
|----------|------------|---------|----------|
| Workflow `infra` input | `dpdk` | *(not available in CI)* | `baseline` |
| `RUN_ENV` (prefix to `./experiments/run.sh`) | *(none — defaults `STACK=0rtt TRANSPORT=ssm`)* | `TRANSPORT=ssh` | `STACK=baseline` |
| `REPORT_DIR` | `experiments/reports/0rtt/` | `experiments/reports/0rtt/` | `experiments/reports/baseline/` |
| Report filename | `integration-test-report-YYYY-MM-DD.md` | `proxmox-test-report-YYYY-MM-DD.md` | `baseline-report-YYYY-MM-DD-HHMMSS.md` |
| `IMPL_NAME` | `dpdk` | `proxmox` | `baseline` |
| Transport | AWS SSM | SSH gateway | AWS SSM |
| Node discovery | `smartnics-*` tags | lab IPs (10.13.37.x) | `baseline-*` tags |
| Default `CONNECTIONS` | 1 | 1 | 1 |
| Infra stack | `infra/dpdk` | RUNS Proxmox lab | `infra/baseline` |
| Endpoint analyzer | `analyze_metrics.py` | `analyze_metrics.py` | `analyze_metrics.py` (TCP); none (QUIC) |

## Step 1 — Run it (GitHub Actions is the default path)

**Dispatch `.github/workflows/run-experiment.yml`** unless the mode is Proxmox or
the user asks for a local run. It drives the same orchestrators over SSM, but also
archives every artifact and commits a results bundle — which is what Step 6 reads.

The workflow commits bundles to its dispatch ref. If main requires pull requests,
dispatch with `--ref` set to a writable experiment branch and pass `repo_ref`
explicitly; do not weaken repository rules to save results. If publication fails,
download the Actions artifact and analyze its recorded `exit_code` separately
from the workflow commit-step failure.

> ⛔ **Never dispatch without `load_parallel` and `load_rate`.** Omitting them
> silently selects 100000 @ 2000 conn/s — a capacity setting that saturates the
> t3.micro endpoints and fails the run. See "Load knobs are mandatory" below
> before you copy anything here.

```bash
# Latency run — the comparable operating point. This is the default invocation.
gh workflow run run-experiment.yml -f infra=both \
    -f load_parallel=2000 -f load_rate=500

# One stack only, same knobs.
gh workflow run run-experiment.yml -f infra=dpdk \
    -f load_parallel=2000 -f load_rate=500

gh run watch "$(gh run list --workflow=run-experiment.yml -L1 --json databaseId -q '.[0].databaseId')"
```

| Input | Maps to | Default if omitted |
|-------|---------|--------------------|
| `infra` | `both` \| `dpdk` \| `baseline` | `both` |
| `repo_ref` | branch the VMs hard-reset to | the workflow's own ref |
| `rounds` | `CONNECTIONS` | 1 |
| `load_parallel` | `LOAD_PARALLEL` | 100000 ⛔ never omit |
| `load_rate` | `LOAD_RATE` conn/s | 2000 ⛔ never omit |
| `load_ports` | `LOAD_PORTS` | 4 |
| `load_timeout` | `LOAD_TIMEOUT` | 1800 |
| `netem_rtt_ms` | `NETEM_RTT_MS` | 100 |
| `extra_env` | `KEY=VALUE ...` (`LOAD_BYTES`, `LOAD_CONCURRENCY`, …) | — |

Why this path is preferred:

- **`infra=both` is the only way to get a comparable pair** — one dispatch applies
  identical knobs to baseline and dpdk, serialised, so neither side can drift. Both
  jobs must go green for the comparison to count.
- Needs no local AWS credentials, and survives the workstation going away.
- Saves a full bundle per run to `experiments/ci-results/<stamp>-<infra>/`
  (`run-meta.json`, untruncated `experiment.log`, `report.md`, `node-logs/`) **and**
  copies the report into `experiments/reports/<stack>/`, then commits both.
- The workflow does **zero reasoning** on purpose. Step 6 supplies it.

**Repeat runs / sweeps**: dispatch once per repetition (the `aws-ops` concurrency
group serialises them; the stacks cannot be shared anyway). Each dispatch produces
its own timestamped bundle, so nothing overwrites — unlike the local DPDK runner,
whose report filename is date-only and self-overwrites within a day.

### Load knobs are mandatory — the workflow's defaults will fail the run

The workflow only exports a knob that was **explicitly passed**; anything omitted
falls through to the runner default in `experiments/lib/measure.sh`, which is
**`LOAD_PARALLEL=100000`, `LOAD_RATE=2000`**. That is a *capacity* setting, not a
latency setting, and on the t3.micro endpoints it fails:

| Stack | Observed at 100k @ 2000/s (2026-08-17) |
|---|---|
| Baseline | 272/100000 connections failed, 326 `missing=` metric events, p95 send_unlock **64 s** |
| DPDK | 171 `missing=` server events, p95 send_unlock **1.0 s**, p99 **31.7 s** |

Both exit non-zero on `Endpoint analysis: N missing metric event(s)`. The numbers
are not a 0-RTT result — the queueing dominates the path — and this ceiling is
already recorded in `docs/index.html` (a prior 100k attempt completed 84143/100000
on the 0-RTT side).

**Rule**: every dispatch passes `load_parallel` and `load_rate` explicitly.
Use **`load_parallel=2000`, `load_rate=500`** — the operating point every
committed report since 2026-08-08 was taken at — unless the user asks for
something else, and always match the reports you intend to compare against.

**Deliberately running at capacity?** Then say so in the summary and read only
establishment-success and throughput from it. `missing=` events and multi-second
percentiles are expected there, not a regression — and never quote its latency as
a 0-RTT saving. Pair it with `-f load_timeout=3600`, since 100k @ 2000/s needs
~50 s of spawn plus several minutes of drain per round.

### QUIC four-arm comparison

Use the Task 3 rate spike to choose `min(sustained_rate / 2, 500)` on the client,
then confirm endpoint CPU headroom. Match all load settings across plain TCP,
DPDK 0-RTT TCP, QUIC cold, and QUIC resumed; check endpoint VM types as well.
Run the TCP pair with `infra=both`. QUIC uses `infra=baseline`, with
`extra_env` containing `PROTO=quic QUIC_RESUME=0` for cold or
`PROTO=quic QUIC_RESUME=1` for resumed. Pass explicit count and rate to each.
Wait for each workflow dispatch to finish before submitting the next: GitHub's
concurrency group allows only one pending run, so a third dispatch can cancel
an already pending one even with `cancel-in-progress: false`.
Read the actual reports and `quic_summary` lines; require every resumed flow's
early data to be accepted. Record handshake timing and evaluate the design's
A2 triggers. State plaintext-vs-encrypted, one-ticket reuse, and data-plane
caveats in the comparison. QUIC reports application timing, not pcap timing.

### Step 1b — Local orchestrator (fallback)

Required for **Proxmox** (the GitHub runner cannot reach the lab: F5 VPN + SSH
gateway), and for iterating with uncommitted local changes.

```bash
LOAD_PARALLEL=2000 LOAD_RATE=500 <RUN_ENV> ./experiments/run.sh
```

The same rule applies here — a bare `./experiments/run.sh` inherits the identical
100000 @ 2000 conn/s default and fails the same way. `CONNECTIONS=N` adds
measurement rounds and is optional.

Exit code = number of failed checks (0 = all passed). The script handles node
discovery, code pull, service startup, packet capture, client test, log checks,
metric analysis, **and report writing** automatically. Local runs produce no
ci-results bundle, so Steps 3–5 are done against the inline output instead of
Step 6's offline handoff.

See `references/test-scripts.md` for the full step-by-step breakdown and expected
output of each script.

### Shared architecture (DPDK + Proxmox)

Every mode runs through **`experiments/run.sh`**; all per-step orchestration
lives in **`experiments/lib/core.sh`**. `run.sh` only sources the transport
(`TRANSPORT`), does node discovery + MAC resolution, then calls `run_experiment`:

| Concern | DPDK (AWS) | Proxmox |
|---------|------------|---------|
| Transport layer | `experiments/lib/transport/ssm.sh` | `experiments/lib/transport/ssh_lab.sh` |
| Shims | `remote_run`/`remote_bg`/`remote_stdout` → SSM | → SSH jump host (`runs-gateway`) |
| Node discovery | EC2 `describe-instances` by tag | ping lab IPs via gateway |
| MAC resolution | EC2 API (DeviceIndex query) | `get_lab_mac` reads `/sys/class/net/<if>/address` |
| Repo path on node | `/home/ec2-user/zero-rtt-tcp` | `/home/user/zero-rtt-tcp` |

Both build **two** binaries each run: `clientnic-dpdk-forwarder` (spoof + stamp V)
and `servernic-dpdk` (sole translator). Proxmox prerequisites: F5 VPN (HAIFA)
active + `~/.ssh/config` entry `runs-gateway → 132.75.121.140` (see the
`runs-lab-connect` skill).

### Node-script delegation (DPDK + Proxmox)

Per-node startup is delegated to scripts via the transport. All node scripts live in
`experiments/nodes/`:

| Node | Node script | Notes |
|------|-------------|-------|
| Server | `experiments/nodes/server.sh` | |
| ServerNIC | `experiments/nodes/servernic.sh` | env: `CLIENTNIC_GW_MAC`, `SERVER_GW_MAC`, `MIDDLE_ENI_MAC`, `SKIP_BUILD=1` |
| ClientNIC | `experiments/nodes/clientnic.sh <GW_MAC>` | `$1` = ServerNIC eth1 MAC; `SKIP_BUILD=1` (core builds explicitly) |
| Client | `loadgen.py --mode client` via `run_ttfb_measurement` (`measure.sh`) | `experiments/nodes/client.sh` has an interactive `read` loop — never used for automation |

**Load generator: `experiments/nodes/loadgen.py`** — a single-thread asyncio
(epoll-driven) TCP generator. iperf has been removed; it was thread-per-connection
and had no arrival pacing. Knobs (defined in `measure.sh`, override via env):
- **`LOAD_PARALLEL`** (default 100000) — total TCP connections per round.
- **`LOAD_PORTS`** (default 4) — contiguous server ports `[8080 .. 8080+N-1]` the
  load is spread across, round-robin. One asyncio process serves all of them.
- **`LOAD_RATE`** (default 2000 conn/s) — **arrival pacing**. Connections are
  spawned on a schedule rather than all at once, so per-connection latency reflects
  the network path instead of queueing behind the batch. `LOAD_RATE=0` restores the
  burst; that is a capacity run, not a latency run (see `experiments/sweeps/stress.sh`).
- **`LOAD_BYTES`** (default 1024) — payload per connection. One segment, so flow
  completion time is dominated by the handshake 0-RTT shortens, not by transfer.
- **`LOAD_CONCURRENCY`** (default 2000) — in-flight connection ceiling.

`LOAD_RATE` sets a wall-clock floor of `LOAD_PARALLEL / LOAD_RATE` seconds per round
that `LOAD_TIMEOUT` must clear; `run_ttfb_measurement` warns when it does not.

Spreading across multiple destination ports is what makes 100000 connections from a
single client IP actually openable: each `(dst-ip, dst-port)` tuple has its own ~28K
usable ephemeral-port space, so 4 ports × 25000 clears the per-port ceiling. The
0-RTT data plane must cover the same range — both DPDK binaries take **`--port-count`**
(default 1; the runner passes `LOAD_PORTS`), and iptables/tcpdump filters use the
port range. `CONNECTIONS` controls how many sequential rounds run (default 1, since
one round already opens 100000). Scapy is pinned to single-port/low-parallel (legacy
Python data plane can't sustain this).

### Endpoint pcap measurement (TCP: DPDK, Proxmox, baseline)

The new measurement model captures at the **endpoints**, not on ClientNIC:
- `tcpdump` runs on the **Client host** (`/tmp/client_side.pcap`) and **Server host** (`/tmp/server_side.pcap`), using nanosecond timestamps where supported.
- Accuracy knobs applied before the run: GRO/LRO/TSO/GSO **off** + `tc qdisc netem delay 50ms` on the middle ClientNIC-to-ServerNIC leg; TCP timestamps/window-scaling/SACK disabled.
- Each pcap is analyzed on its own endpoint host by `experiments/nodes/analyze_metrics.py`, computing endpoint-observed metrics: **FCT**, **send_unlock** (client), **server_gap** (server). A `missing=` line in its output = a metric event was not found → counts as a failure.
- In-binary `[DIAG]` log lines (formerly `[METRIC]`) on ClientNIC/ServerNIC are diagnostic only — the authoritative latency numbers come from the endpoint pcaps.

**DPDK build note**: the CDK user data builds DPDK 23.11 from source at provision
time (~15-20 min after deploy). The runner rebuilds both binaries from source each
run (after syncing to the requested ref). If a build fails, wait for user data to finish or check the
meson/ninja output the script prints inline.

**Baseline note**: no DPDK, no Scapy, no build. ClientNIC/ServerNIC are plain kernel
routers (`ip_forward=1` + static routes from CDK user data). Deploy `infra/baseline`
first with `infra/baseline/deploy.ps1` from PowerShell. Use the matching `destroy.ps1` for teardown. Plain TCP measures endpoint `send_unlock`, FCT and `server_gap`, with no
spoofing. QUIC measures app-side `send_unlock` and skips pcap analysis.

## Step 2 — Report is written automatically

**The script writes the report itself** to `<REPORT_DIR><filename>` before exiting.
Do **not** hand-author a duplicate. A workflow run commits that same report to
`<REPORT_DIR>` *and* copies it into its bundle as `report.md`. After the run:

1. Confirm the report file exists and read it back to verify it captured the run.
2. If a section is empty because a step failed (e.g. empty ClientNIC log), note that
   in your chat summary — don't silently overwrite the auto-generated file.

The DPDK/Proxmox report contains: Latency Summary (TTFB @ 3 points + FCT), Client
Output, ClientNIC/ServerNIC/Server logs, and endpoint Packet Analysis. The Scapy
report adds `validate_0rtt_capture.py` output. Baseline TCP includes endpoint
metrics; baseline QUIC includes `quic_summary`.

## Step 3 — Report results to the user in chat

After the run, post a concise summary. Lead with the overall result and the latency
numbers, then relevant checks. For **baseline**, omit middleware activity;
retain endpoint analysis for TCP and `quic_summary` for QUIC.

---
**Experiment Run — `<timestamp>`** (`<IMPL_NAME>`)

**Overall: ✅ ALL PASSED** / **❌ N FAILURE(S)**

**Latency** (from script's Latency Summary block):
```
<TTFB @ client/clientnic/servernic + FCT + endpoint metrics>
```

| Check | Result |
|-------|--------|
| Build: clientnic-dpdk-forwarder | ✅ / ❌ |  ← DPDK/Proxmox only
| Build: servernic-dpdk | ✅ / ❌ |          ← DPDK/Proxmox only
| Smoke: forwarder busy-poll | ✅ / ❌ |     ← DPDK/Proxmox only
| Server listening on :8080 | ✅ / ❌ |
| ServerNIC running + IP forwarding | ✅ / ❌ |
| ClientNIC running + IP forwarding | ✅ / ❌ |
| Client: N/N connections succeeded | ✅ / ❌ |
| Server received data | ✅ / ❌ |
| ClientNIC 0-RTT flow activity | ✅ / ❌ |
| Endpoint metric analysis | ✅ / ❌ |

**Report saved**: `<REPORT_DIR><filename>`

---

For each ❌, quote the exact log line or output that caused the failure.

## Step 4 — Investigate any failures

1. **Read the logs** — the script prints them inline; look for the first anomaly.
2. **Reach the relevant node** (SSM for AWS, SSH gateway for Proxmox) and run the
   manual diagnostics below.
3. **Cross-correlate**: ClientNIC log + ServerNIC log + endpoint pcaps + server log
   together tell the full story.
4. **Report observed vs expected** for each failed check with exact lines/timestamps.

Common failure patterns and fixes: `references/troubleshooting.md`.

## Step 5 — Propose insights for `experiments/insights.md`

After reporting results (Step 3) and investigating any failures (Step 4), check
whether this run surfaced a **durable insight** — a confirmed root cause, a
bottleneck localized to a specific layer (endpoint / SmartNIC / kernel / config),
or a correction to a documented capacity assumption. Not every run produces one;
don't force it, and routine pass/fail results already in the auto-generated
report don't count.

If it does:

1. Draft the entry in the same format as existing entries in
   `experiments/insights.md` (source report/log, what the run showed, root
   cause, "carry forward" takeaway).
2. **Ask the user to confirm before writing** — never append to
   `experiments/insights.md` without approval:
   > "This run surfaced an insight: `<one-line summary>`. Add it to
   > `experiments/insights.md`?"
3. On confirmation, append the entry (never overwrite or reorder prior
   entries). On decline, discard the draft — don't save it elsewhere.

## Step 6 — Close with the `offline-analysis` skill (CI runs)

**Every workflow-dispatched run ends here.** `run-experiment.yml` archives the
data but deliberately does no reasoning; `offline-analysis` is that missing half,
and it is the closing step of this skill — not an optional follow-up.

```bash
git pull --ff-only                         # only when local changes permit; otherwise download the Actions artifact
cat experiments/ci-results/latest.txt      # latest_bundle: -> the path
```

Then invoke the **`offline-analysis`** skill against the bundle. It performs
Steps 3–5 (summary, failure diagnosis, candidate insights) from
`run-meta.json` + the untruncated `experiment.log` + `node-logs/`, which is
strictly more data than the inline output a local run leaves behind — SSM
caps fetched node logs at 24 KB; bundle node logs can also contain truncation
markers. The orchestrator's `experiment.log` remains the full local output.

- **`infra=both`**: analyze **both** bundles — `latest-baseline.txt` and
  `latest-dpdk.txt` — and confirm their `run-meta.json` `knobs` blocks match
  before quoting any 0-RTT saving. Mismatched knobs = confound, not a result.
- **Sweeps**: run it over every bundle in the sweep, then report cross-run
  spread (mean-of-means, min/max per metric). A single run's mean says nothing
  about run-to-run variance.
- **Local runs (Step 1b)**: no bundle exists — do Steps 3–5 inline instead and
  skip this step.

---

## Manual / Interactive Testing

Use these when the script fails partway, or to run individual checks in isolation.

### Node access

**AWS (SSM, no SSH key):**
```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=smartnics-*" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],InstanceId,PublicIpAddress,PrivateIpAddress]" \
  --output table --region eu-central-1
aws ssm start-session --target <instance-id> --region eu-central-1
```

**Proxmox lab (SSH via gateway):** requires F5 VPN + `runs-gateway` host. See the
`runs-lab-connect` skill. Default lab IPs: Client `10.13.37.10`, ClientNIC `.11`,
ServerNIC `.12`, Server `.13` (override via `LAB_*_IP` env vars).

**Note**: AWS instance IPs change on restart — always query fresh.

### Startup order

Always: **Server → ServerNIC → ClientNIC → Client**

```bash
# 1. Server
setsid bash experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &

# 2. ServerNIC — DPDK translator
CLIENTNIC_GW_MAC=<cnic-eth1-mac> SERVER_GW_MAC=<server-eth0-mac> MIDDLE_ENI_MAC=<snic-eth1-mac> \
    SKIP_BUILD=1 setsid bash experiments/nodes/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &

# 3. ClientNIC — DPDK forwarder (GW_MAC = ServerNIC eth1 MAC)
SKIP_BUILD=1 setsid bash experiments/nodes/clientnic.sh <GW_MAC> < /dev/null >> /tmp/clientnic.log 2>&1 &

# 4. Client — 100000 conns across 4 ports, paced at 2000/s, 1 KB each
ulimit -n 1048576
python3 experiments/nodes/loadgen.py --mode client --host <server-ip> \
    --port 8080 --port-count 4 --parallel 100000 --bytes 1024 \
    --rate 2000 --concurrency-limit 2000
```

### Pre-flight checks

**All modes — IP forwarding on NIC nodes:**
```bash
cat /proc/sys/net/ipv4/ip_forward      # must be 1
```

**DPDK (ClientNIC + ServerNIC):**
```bash
dpdk-devbind.py --status | grep -E "(vfio|eth1)"     # eth1 bound to vfio-pci
grep HugePages_Total /proc/meminfo                    # expect 512
# Build (both binaries)
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
cd src/clientnic/dpdk-forwarder && meson setup builddir && ninja -C builddir   # clientnic-dpdk-forwarder
cd src/servernic/dpdk          && meson setup builddir && ninja -C builddir    # servernic-dpdk
```

### Packet capture (endpoint model — DPDK/Proxmox)

Capture on the **Client host** and **Server host**, not on ClientNIC:
```bash
# On Client host
tcpdump --time-stamp-precision=nano -i eth0 -nn -s 128 'tcp port 8080' -w /tmp/client_side.pcap &
# On Server host
tcpdump --time-stamp-precision=nano -i eth0 -nn -s 128 'tcp port 8080' -w /tmp/server_side.pcap &
```

### Running the analyzer

**TCP: DPDK, Proxmox, baseline** — analyze on each endpoint host:
```bash
# On Client
python3 experiments/nodes/analyze_metrics.py --client-pcap /tmp/client_side.pcap
# On Server
python3 experiments/nodes/analyze_metrics.py --server-pcap /tmp/server_side.pcap
# Output lines: fct=, send_unlock=, server_gap=  (a "missing=" line = failure)
```

## Known Issues

See `references/troubleshooting.md`:
- SSM daemon detachment (`setsid`, not `nohup ... &`)
- Scapy `sendp()` vs `send()` / `iface=` ignored on L3 send
- Kernel forwarding races Scapy (fix: iptables FORWARD DROP)
- Packet re-capture loop on ServerNIC (fix: MAC filter)
- Swapped SEQ/ACK rewrite fields
- GW-MAC EC2 API fails from VM (fix: pass MAC as argument)
- `scapy/` dir shadowing when running the validator from `src/clientnic/` (fix: copy to `/tmp/`)
