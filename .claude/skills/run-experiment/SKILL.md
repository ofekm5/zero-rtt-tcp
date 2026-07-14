---
name: run-experiment
description: End-to-end integration testing for the 0-RTT TCP demo across all 4 nodes (Client, ClientNIC, ServerNIC, Server) on AWS EC2 or the RUNS Proxmox lab. Use when running experiments, validating 0-RTT behavior, measuring TTFB/FCT, diagnosing packet flow issues, verifying sequence number translation, or troubleshooting the 4-VM chain. Triggers on phrases like "run experiment", "run integration tests", "test 0-RTT", "measure latency", "check the VMs", "verify packet flow", "debug the demo", or "validate the setup".
---

# Run Experiment — 0-RTT Integration Tester

Each experiment is a self-contained orchestrator script that discovers nodes, pulls
code, starts services in order, runs the client, captures packets, analyzes metrics,
**and writes its own report**. Your job: pick the mode, run the script, summarize the
result in chat, and investigate any failures.

## Step 0 — Choose experiment mode

**Always ask the user** which mode they want before doing anything:

> "Which experiment should I run?
> 1. **Scapy** (AWS) — 0-RTT, Python/Scapy AF_PACKET (`experiments/scapy/run_experiment.sh`)
> 2. **DPDK** (AWS) — 0-RTT T8, C/DPDK forwarder + translator (`experiments/dpdk/run_experiment.sh`)
> 3. **Proxmox** — 0-RTT T8 DPDK on the RUNS lab via SSH gateway (`experiments/proxmox/run_experiment.sh`)
> 4. **Baseline** (AWS) — plain TCP, kernel forwarding, no middleware (`experiments/baseline-tcp/run_experiment.sh`)"

Set variables based on the answer:

| Variable | Scapy | DPDK (AWS) | Proxmox | Baseline |
|----------|-------|------------|---------|----------|
| `EXPERIMENT_SCRIPT` | `experiments/scapy/run_experiment.sh` | `experiments/dpdk/run_experiment.sh` | `experiments/proxmox/run_experiment.sh` | `experiments/baseline-tcp/run_experiment.sh` |
| `REPORT_DIR` | `experiments/scapy/reports/` | `experiments/dpdk/reports/` | `experiments/proxmox/reports/` | `experiments/baseline-tcp/reports/` |
| Report filename | `integration-test-report-YYYY-MM-DD.md` | `integration-test-report-YYYY-MM-DD.md` | `proxmox-test-report-YYYY-MM-DD.md` | `baseline-report-YYYY-MM-DD-HHMMSS.md` |
| `IMPL_NAME` | `scapy` | `dpdk` | `proxmox` | `baseline` |
| Transport | AWS SSM | AWS SSM | SSH gateway | AWS SSM |
| Node discovery | `smartnics-*` tags | `smartnics-*` tags | lab IPs (10.13.37.x) | `baseline-*` tags |
| Default `CONNECTIONS` | 3 | 5 | 5 | 20 |
| Infra stack | `infra/scapy` | `infra/dpdk` | RUNS Proxmox lab | `infra/baseline` |
| Pcap validator | `validate_0rtt_capture.py` | `analyze_metrics.py` | `analyze_metrics.py` | (none) |

## Step 1 — Run the automated script

```bash
CONNECTIONS=5 ./<EXPERIMENT_SCRIPT>      # CONNECTIONS env var is optional
```

Exit code = number of failed checks (0 = all passed). The script handles node
discovery, code pull, service startup, packet capture, client test, log checks,
metric analysis, **and report writing** automatically.

See `references/test-scripts.md` for the full step-by-step breakdown and expected
output of each script.

### Shared architecture (DPDK + Proxmox)

The DPDK (AWS) and Proxmox runners share **`experiments/utils/run_core.sh`** —
all per-step orchestration lives there. The thin per-mode runner only does node
discovery + MAC resolution, defines transport shims, then calls `run_experiment`:

| Concern | DPDK (AWS) | Proxmox |
|---------|------------|---------|
| Transport layer | `experiments/utils/ssm.sh` | `experiments/utils/ssh_lab.sh` |
| Shims | `remote_run`/`remote_bg`/`remote_stdout` → SSM | → SSH jump host (`runs-gateway`) |
| Node discovery | EC2 `describe-instances` by tag | ping lab IPs via gateway |
| MAC resolution | EC2 API (DeviceIndex query) | `get_lab_mac` reads `/sys/class/net/<if>/address` |
| Repo path on node | `/home/ec2-user/zero-rtt-tcp` | `/home/user/zero-rtt-tcp` |

Both build **two** binaries each run: `clientnic-dpdk-forwarder` (spoof + stamp V)
and `servernic-dpdk` (sole translator). Proxmox prerequisites: F5 VPN (HAIFA)
active + `~/.ssh/config` entry `runs-gateway → 132.75.121.140` (see the
`runs-lab-connect` skill).

### Node-script delegation (DPDK + Proxmox)

Per-node startup is delegated to scripts via the transport. Shared scripts live in
`experiments/nodes/`; NIC-specific scripts in `experiments/dpdk/`:

| Node | Node script | Notes |
|------|-------------|-------|
| Server | `experiments/nodes/server.sh` | |
| ServerNIC | `experiments/dpdk/servernic.sh` | env: `CLIENTNIC_GW_MAC`, `SERVER_GW_MAC`, `MIDDLE_ENI_MAC`, `SKIP_BUILD=1` |
| ClientNIC | `experiments/dpdk/clientnic.sh <GW_MAC>` | `$1` = ServerNIC eth1 MAC; `SKIP_BUILD=1` (core builds explicitly) |
| Client | `iperf2 -c` via `run_ttfb_measurement` (`measure.sh`) | `experiments/nodes/client.sh` has an interactive `read` loop — never used for automation |

**Load generator: iperf2 only.** An `iperf3` binary shadowing `iperf` is rejected by
an explicit guard on client and server. Two knobs (defined in `measure.sh`, override
via env):
- **`IPERF_PARALLEL`** (default 100000) — total parallel TCP connections per round.
- **`IPERF_PORTS`** (default 4) — contiguous server ports `[8080 .. 8080+N-1]` the
  load is spread across. The server runs one `iperf -s` per port; the client runs one
  `iperf -c -p <port> -P <IPERF_PARALLEL/IPERF_PORTS>` per port, concurrently.

Spreading across multiple destination ports is what makes 100000 connections from a
single client IP actually openable: each `(dst-ip, dst-port)` tuple has its own ~28K
usable ephemeral-port space, so 4 ports × 25000 clears the per-port ceiling. The
0-RTT data plane must cover the same range — both DPDK binaries take **`--port-count`**
(default 1; the runner passes `IPERF_PORTS`), and iptables/tcpdump filters use the
port range. `CONNECTIONS` controls how many sequential rounds run (default 1, since
one round already opens 100000). Scapy is pinned to single-port/low-parallel (legacy
Python data plane can't sustain this).

### Endpoint pcap measurement (DPDK + Proxmox)

The new measurement model captures at the **endpoints**, not on ClientNIC:
- `tcpdump` runs on the **Client host** (`/tmp/client_side.pcap`) and **Server host** (`/tmp/server_side.pcap`), using nanosecond timestamps where supported.
- Accuracy knobs applied before the run: GRO/LRO/TSO/GSO **off** + `tc qdisc netem delay 50ms` on Client and Server egress; TCP timestamps/window-scaling/SACK disabled.
- Both pcaps are base64-shipped to ClientNIC, where `experiments/utils/analyze_metrics.py` computes endpoint-observed metrics: **FCT**, **send_unlock** (client), **server_gap** (server). A `missing=` line in its output = a metric event was not found → counts as a failure.
- In-binary `[DIAG]` log lines (formerly `[METRIC]`) on ClientNIC/ServerNIC are diagnostic only — the authoritative latency numbers come from the endpoint pcaps.

**DPDK build note**: the CDK user data builds DPDK 23.11 from source at provision
time (~15-20 min after deploy). The runner rebuilds both binaries from source each
run (after `git pull`). If a build fails, wait for user data to finish or check the
meson/ninja output the script prints inline.

**Baseline note**: no DPDK, no Scapy, no build. ClientNIC/ServerNIC are plain kernel
routers (`ip_forward=1` + static routes from CDK user data). Deploy `infra/baseline`
first (`cd infra/baseline && .\deploy.ps1`). Measures plain-TCP TTFB/FCT only — no
spoofing, no pcap validator.

## Step 2 — Report is written automatically

**The script writes the report itself** to `<REPORT_DIR><filename>` before exiting.
Do **not** hand-author a duplicate. After the run:

1. Confirm the report file exists and read it back to verify it captured the run.
2. If a section is empty because a step failed (e.g. empty ClientNIC log), note that
   in your chat summary — don't silently overwrite the auto-generated file.

The DPDK/Proxmox report contains: Latency Summary (TTFB @ 3 points + FCT), Client
Output, ClientNIC/ServerNIC/Server logs, and endpoint Packet Analysis. The Scapy
report adds `validate_0rtt_capture.py` output; the Baseline report is TTFB/FCT only.

## Step 3 — Report results to the user in chat

After the run, post a concise summary. Lead with the overall result and the latency
numbers, then the per-check table. For **baseline**, omit ClientNIC/ServerNIC logs
and packet analysis.

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

# 2a. ServerNIC — Scapy (deprecated — feasibility PoC only, not used in the live DPDK path)
setsid python3 src/servernic/scapy/main.py --client-iface eth0 --server-iface eth1 \
    < /dev/null >> /tmp/servernic.log 2>&1 &
# 2b. ServerNIC — DPDK T8 translator
CLIENTNIC_GW_MAC=<cnic-eth1-mac> SERVER_GW_MAC=<server-eth0-mac> MIDDLE_ENI_MAC=<snic-eth1-mac> \
    SKIP_BUILD=1 setsid bash experiments/dpdk/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &

# 3a. ClientNIC — Scapy (deprecated — feasibility PoC only, not used in the live DPDK path)
setsid python3 src/clientnic/scapy/main.py < /dev/null >> /tmp/clientnic.log 2>&1 &
# 3b. ClientNIC — DPDK T8 forwarder (GW_MAC = ServerNIC eth1 MAC)
SKIP_BUILD=1 setsid bash experiments/dpdk/clientnic.sh <GW_MAC> < /dev/null >> /tmp/clientnic.log 2>&1 &

# 4. Client — iperf2, 100000 parallel conns spread across 4 ports (25000 each), 1M
ulimit -n 1048576
for p in 8080 8081 8082 8083; do
    iperf -c <server-ip> -p "$p" -P 25000 -n 1M -f m &
done; wait
```

### Pre-flight checks

**All modes — IP forwarding on NIC nodes:**
```bash
cat /proc/sys/net/ipv4/ip_forward      # must be 1
```

**Scapy — block kernel forwarding so userspace wins the race:**
```bash
iptables -A FORWARD -p tcp --dport 8080 -j DROP
iptables -A FORWARD -p tcp --sport 8080 -j DROP
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

**Scapy** uses the legacy on-ClientNIC capture instead (eth0 + eth1):
```bash
tcpdump -i eth0 -nn -tttt 'tcp port 8080' -w /tmp/client_side.pcap &
tcpdump -i eth1 -nn -tttt 'tcp port 8080' -w /tmp/server_side.pcap &
```

### Running the analyzer

**DPDK / Proxmox** — `analyze_metrics.py` on ClientNIC against both endpoint pcaps:
```bash
python3 experiments/utils/analyze_metrics.py \
    --client-pcap /tmp/client_side_endpoint.pcap \
    --server-pcap /tmp/server_side.pcap
# Output lines: fct=, send_unlock=, server_gap=  (a "missing=" line = failure)
```

**Scapy** (deprecated — feasibility PoC only) — `validate_0rtt_capture.py` (copy to `/tmp/` first so `src/clientnic/scapy/`
doesn't shadow the `scapy` package):
```bash
cp src/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py
python3 /tmp/validate_0rtt.py --client-pcap /tmp/client_side.pcap --server-pcap /tmp/server_side.pcap
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
