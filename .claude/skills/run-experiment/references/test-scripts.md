# Experiment Scripts

One entrypoint, `experiments/run.sh`, plus a shared core and a pcap analyzer.
`STACK` and `TRANSPORT` pick the run; it writes its own report to
`experiments/reports/<STACK>/` and exits with the failure count.

| Invocation | Stack | Transport | Analyzer | Report dir |
|------------|-------|-----------|----------|------------|
| `./experiments/run.sh` | DPDK 0-RTT | AWS SSM | `analyze_metrics.py` | `experiments/reports/0rtt/` |
| `TRANSPORT=ssh ./experiments/run.sh` | DPDK 0-RTT | SSH gateway | `analyze_metrics.py` | `experiments/reports/0rtt/` |
| `STACK=baseline ./experiments/run.sh` | plain TCP | AWS SSM | (none) | `experiments/reports/baseline/` |

**Load generator**: `experiments/nodes/loadgen.py` (asyncio, single thread; iperf has
been removed). `LOAD_PARALLEL` (default 100000) total connections per round are spread
round-robin across `LOAD_PORTS` (default 4) contiguous server ports, so a single client
IP can clear the ~28K-per-tuple ephemeral-port ceiling. `LOAD_RATE` (default 2000
conn/s) paces arrivals — without it every flow's latency includes queueing behind the
whole batch; `LOAD_RATE=0` is a capacity run only. `LOAD_BYTES` (default 1024) is one
segment so FCT ≈ handshake + 1 RTT. The DPDK data plane covers the same port range via
`--port-count` (runner passes `LOAD_PORTS`). `CONNECTIONS` = number of rounds
(default 1). Scapy is pinned to single-port/low-parallel.

**Endpoint setup is shared**: `experiments/lib/endpoint.sh` applies sysctls, MTU,
offloads, netem, captures and analysis identically for the DPDK and baseline stacks,
so the two are comparable. Emulated RTT (`NETEM_RTT_MS`, default 100) sits on the **ClientNIC-to-ServerNIC middle leg**, half in each direction: kernel netem on baseline routers, and `--wan-delay-us` on DPDK forwarders. Endpoints stay free of netem; see `experiments/measurement-methodology-review.md` §E.

Shared building blocks — laptop-side under `experiments/lib/`, VM-side under `experiments/nodes/`:
- `lib/core.sh` — transport-agnostic `run_experiment()`; the whole DPDK/Proxmox flow.
- `lib/transport/ssm.sh` — AWS SSM transport (`ssm_run`/`ssm_bg`/`ssm_stdout`, `get_iid`/`get_ip`, `json_idx`).
- `lib/transport/ssh_lab.sh` — RUNS-lab SSH-jump transport (`remote_*` over `runs-gateway`, `get_lab_mac`).
- `lib/measure.sh` — `run_ttfb_measurement`, `summarize_metric`, `report_nic_ttfb`.
- `nodes/analyze_metrics.py` — offline endpoint-pcap analyzer (FCT, send_unlock, server_gap).

---

## experiments/run.sh — `STACK=0rtt` (default)

**DPDK stack** — ClientNIC `dpdk-forwarder` (spoof + stamp V), ServerNIC
`servernic-dpdk` (sole translator). Both transports share `core.sh`; they differ
only in transport, node discovery, MAC resolution, and report filename.

```bash
./experiments/run.sh                                  # AWS, default 1 round
TRANSPORT=ssh CONNECTIONS=10 ./experiments/run.sh     # RUNS lab via gateway
```

### Per-transport head (before core.sh)

| Concern | DPDK (AWS) | Proxmox |
|---------|------------|---------|
| Discovery | `get_iid smartnics-*` (EC2 tags) | ping lab IPs via `runs-gateway` |
| `GW_MAC` (ServerNIC eth1) | EC2 API DeviceIndex==1 | `get_lab_mac SERVERNIC eth1` |
| `CLIENTNIC_ETH1_MAC` | EC2 API DeviceIndex==1 | `get_lab_mac CLIENTNIC eth1` |
| `SERVER_ETH0_MAC` | EC2 API DeviceIndex==0 | `get_lab_mac SERVER eth0` |
| Smoke test | runs forwarder 3s, greps busy-poll | (in shared core) |
| Repo path | `/home/ec2-user/zero-rtt-tcp` | `/home/user/zero-rtt-tcp` |
| Report | `integration-test-report-YYYY-MM-DD.md` | `proxmox-test-report-YYYY-MM-DD.md` |

### Shared core steps (`core.sh::run_experiment`)

| Step | Action | Pass condition |
|------|--------|----------------|
| — | `git pull` on all 4 nodes | (best-effort) |
| — | Disable TCP timestamps/window-scaling/SACK on the ClientNIC-to-ServerNIC middle leg | (accuracy) |
| — | Accuracy knobs: `ethtool -K eth0 gro/lro/tso/gso off` + `tc netem delay 50ms` on the ClientNIC-to-ServerNIC middle leg | (accuracy) |
| — | Cleanup: kill prior binaries/tcpdump, flush iptables, clear DPDK lock | (cleanup) |
| Build | Build `clientnic-dpdk-forwarder` (meson+ninja) | `BUILD_SUCCESS` |
| Build | Build `servernic-dpdk` (meson+ninja) | `BUILD_SUCCESS` |
| 1 | Start Server (`experiments/nodes/server.sh`) | `ss -tlnp` shows `:8080` |
| 2 | Start ServerNIC (`experiments/nodes/servernic.sh`, env MACs) | `pgrep servernic-dpdk` + `ip_forward==1` |
| 3 | Start ClientNIC (`experiments/nodes/clientnic.sh <GW_MAC>`) | `pgrep clientnic-dpdk-forwarder` + `ip_forward==1` |
| 3b | tcpdump on **Client host** + **Server host** (nano ts, `-s 128`) | (capture) |
| 4 | `run_ttfb_measurement` — CONNECTIONS rounds × `LOAD_PARALLEL` parallel iperf2 streams (default 100000) | `Success: N/N` |
| 5 | Stop captures + SIGTERM both DPDK binaries | (always) |
| 6 | Read `/tmp/server.log` | Contains `Received`/`bytes` |
| 7 | Collect ClientNIC + ServerNIC logs | ClientNIC: `flow created`/`spoofed SYN-ACK`/`V=`; ServerNIC warns if no activity |
| — | base64-ship both endpoint pcaps to ClientNIC; run `analyze_metrics.py` | no `missing=` lines |
| — | Aggregate latency: client TTFB/FCT, NIC in-app TTFB, pcap FCT/send_unlock/server_gap | (summary) |

### DPDK/Proxmox-specific details

- **Endpoint captures**: pcaps are taken on the Client and Server hosts, not on ClientNIC. eth1 is `vfio-pci`-bound (invisible to tcpdump); the endpoint model sidesteps that and measures true end-to-end timing. `client_side.pcap` (Client) and `server_side.pcap` (Server) are base64-copied to ClientNIC as `/tmp/client_side_endpoint.pcap` + `/tmp/server_side.pcap`.
- **Gateway MAC** (`--gw-mac`): ServerNIC eth1 (DPDK port) MAC — next L2 hop for the ClientNIC DPDK port. ServerNIC also needs `CLIENTNIC_ETH1_MAC` (`--gw-mac`) and `SERVER_ETH0_MAC` (`--server-gw-mac`).
- **Accuracy knobs**: offloads off + `tc netem delay 50ms` make TTFB/FCT differences measurable on an otherwise sub-ms intra-VPC/LAN path.
- **`[DIAG]` logs**: in-binary diagnostic lines (renamed from `[METRIC]`); authoritative numbers come from `analyze_metrics.py` on the endpoint pcaps.
- **Build time**: DPDK 23.11 is built from source at provision (~15-20 min on AWS). The core rebuilds both binaries each run after `git pull`.

---

## experiments/run.sh — `STACK=baseline`

**Plain TCP** — ClientNIC/ServerNIC are kernel routers (`ip_forward=1` + static
routes from CDK). No DPDK, no Scapy, no build, no pcap analyzer. Default 1
round. Discovers `baseline-*` tagged instances (`infra/baseline` stack).

```bash
STACK=baseline ./experiments/run.sh
STACK=baseline CONNECTIONS=50 ./experiments/run.sh
```

| Step | Action | Pass condition |
|------|--------|----------------|
| 0 | Discover `baseline-*` instances | All 4 IDs resolved |
| 1 | Pre-flight: `ip_forward` + static routes on NIC VMs | forwarding on, routes present (adds if missing) |
| 3 | Start Server | `ss -tlnp` shows `:8080` |
| 4 | `run_ttfb_measurement` (BASELINE_CONNECTIONS) + summarize ttfb/fct | client output captured |
| 5 | Stop server, read `/tmp/server.log` | Contains `Accepted`/`bytes`/`connection` |

Report (`baseline-report-YYYY-MM-DD-HHMMSS.md`) holds Latency Summary, TTFB
measurements, and server log — for comparison against the 0-RTT runs.

---

## src/clientnic/validate_0rtt_capture.py (Scapy only)

Validates 0-RTT from pcaps captured **on ClientNIC** (eth0 client side, eth1 server
side). Runs on the ClientNIC VM. Exit 0 = all passed.

```bash
cp /home/ec2-user/zero-rtt-tcp/src/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py
python3 /tmp/validate_0rtt.py --client-pcap /tmp/client_side.pcap --server-pcap /tmp/server_side.pcap
```

Checks: (A) spoofed SYN-ACK on eth0 with distinct ISN, (B) non-zero ISN delta per
flow, (C) spoofed-before-real timing (informational), (D) no bad IP/TCP checksums.
Copy to `/tmp/` first — running from `src/clientnic/` lets `src/clientnic/scapy/` shadow the
real `scapy` package.

---

## experiments/nodes/analyze_metrics.py (DPDK / Proxmox)

Offline endpoint-pcap analyzer. Computes endpoint-observed metrics from the Client
and Server captures:

- **FCT** — flow completion time (first SYN → last data/FIN) at the client.
- **send_unlock** — time from client SYN to first client data byte (0-RTT proof: the
  client unlocks send before the real handshake completes).
- **server_gap** — gap observed at the server between expected and actual arrival.

```bash
python3 experiments/nodes/analyze_metrics.py \
    --client-pcap /tmp/client_side_endpoint.pcap \
    --server-pcap /tmp/server_side.pcap
```

Output is `key=value` lines consumed by `summarize_metric`. A `missing=` line means
a required metric event was not found in the pcaps → the runner counts it as a
failure. Unit tests: `experiments/tests/test_analyze_metrics.py`.
