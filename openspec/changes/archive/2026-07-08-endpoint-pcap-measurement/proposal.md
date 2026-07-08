## Why

The current experiment timing is incoherent: the only real measurements are NIC-internal `rdtsc` deltas (`clientnic/dpdk-forwarder/forwarder.c`, `servernic/dpdk/translator.c`) that measure what the *middleware* does, not what the endpoints experience; `experiments/utils/measure.sh` greps for `[METRIC] … node=…` lines that **nobody emits**, so every report says "no samples found"; and iperf2's own timing is 10 ms-resolution on a sub-ms LAN. We need three endpoint-observed metrics, each measured on one host's own clock, with one portable mechanism that works identically on AWS EC2/DPDK and the Proxmox LAN.

## Non-Goals

- **Socket-layer eBPF / tc-bpf** — sub-µs precision and kernel coupling are unnecessary in the netem-injected regime we measure in; recorded as an upgrade path for line-rate/Bluefield-DPA work, not built here.
- **OpenTelemetry / span-based telemetry** — wrong layer; metrics (b)/(c) are packet events (SYN, first segment) the application never sees.
- **Forking or patching iperf2** — R2 requires the generator stay completely unmodified; coupling is by capture window + on-wire flow key only.
- **Cross-host clock sync (NTP/PTP alignment)** — every metric is a single-host interval, so systematic offset cancels in the subtraction; no alignment is ever needed.
- **C/Rust pcap sidecar daemon** — draws from the identical libpcap clock as tcpdump; buys liveness we don't need at the cost of a daemon to build/deploy.
- **HW NIC / PTP timestamping** — virtio/ENA VMs don't expose it, and mixing HW-ts (Proxmox) with SW-ts (AWS) would break R1; upgrade path for Proxmox production-segment NICs later.
- **Changing the 0-RTT data-plane logic** — this change only relocates measurement; the spoof/translate behavior of the DPDK NICs is untouched (apart from relabeling their internal diagnostic log tag).

## What Changes

- **NEW `experiments/utils/analyze_metrics.py`** — offline pcap analyzer (generalizes `clientnic/validate_0rtt_capture.py`: rdpcap + 4-tuple + SYN anchor). From `client_side.pcap` it computes **(a) FCT** (`first SYN out → last data byte/FIN`) and **(b) send-unlock** (`first SYN out → first outbound segment with payload > 0`); from `server_side.pcap` it computes **(c) server gap** (`first SYN-ACK out → first inbound data segment`). Emits greppable `metric=<name> value_ms=<v> node=<n> flow=<key>` lines. Flags (rather than silently mis-scores) captures missing a required event.
- **Relocate capture onto the endpoints** — tcpdump runs on the **Client** and **Server** hosts' own data interface (not on ClientNIC's eth0), with `--time-stamp-precision=nano -j host_hiprec` and graceful fallback, writing `client_side.pcap` / `server_side.pcap`.
- **REWRITE `experiments/utils/measure.sh`** — remove the dead `[METRIC] … node=… ttfb|fct` grep (`summarize_metric`); parse the analyzer's `metric=… value_ms=…` output instead, and report the three endpoint metrics.
- **Shared runner core + 2 transports** — factor the AWS runner's "start captures → run iperf2 → stop → copy pcaps → analyze" steps into a shared core; add a **NEW `experiments/proxmox/run_experiment.sh`** that reuses the core with an SSH-gateway transport (static `10.13.37.x` inventory) alongside the existing AWS SSM transport.
- **Host accuracy knobs** — disable offload on both capture interfaces (`ethtool -K <if> gro off lro off tso off gso off`) and inject `tc netem delay 50ms` on each endpoint (~100 ms RTT) so the ~1-RTT 0-RTT saving clears the capture noise floor.
- **iperf2 stays unmodified**; optionally log `iperf -y C` (CSV) as a defensive cross-check that pcap-derived FCT agrees with iperf2's reported duration.
- **Relabel DPDK NIC `rdtsc` stamps** from `[METRIC]` to `[DIAG]` in `forwarder.c` / `translator.c` — kept as middlebox-internal diagnostics, no longer masquerading as the experiment metric.

## Success Criteria

- [ ] `analyze_metrics.py` emits all three metrics as `metric=… value_ms=… node=…` key=value lines from the two pcaps — measured by: `python3 experiments/utils/analyze_metrics.py --client-pcap c.pcap --server-pcap s.pcap` prints exactly three `metric=` lines (`fct`, `send_unlock`, `server_gap`) on a known-good capture.
- [ ] `measure.sh` reports the three endpoint metrics with no "no samples found", parsed from the analyzer output — measured by: a `run_experiment.sh` run's report shows non-empty `fct` / `send_unlock` / `server_gap` values.
- [ ] The same analyzer + capture step is shared across the AWS (SSM) and Proxmox (SSH-gateway) runners, satisfying R1 — measured by: manual review confirming both `run_experiment.sh` scripts source the same core and produce the three metrics (Proxmox run requires lab access).
- [ ] Under `tc netem delay 50ms`/side (~100 ms RTT) with offload disabled, send-unlock ≪ FCT, demonstrating the ~1-RTT 0-RTT saving above the noise floor — measured by: analyzer output on a netem run shows `send_unlock` value_ms an order of magnitude below the ~100 ms RTT.
- [ ] Captures missing a required event are flagged, not silently scored (A5), and the iperf `-y C` cross-check warns on >10 ms FCT divergence — measured by: `analyze_metrics.py` on a truncated pcap exits non-zero / prints a flag line.

## Capabilities

### New Capabilities
- `endpoint-pcap-measurement`: pcap-on-endpoints capture + offline `analyze_metrics.py` yielding the three single-host metrics (FCT, send-unlock, server-gap); shared runner core with AWS-SSM and Proxmox-SSH transports; host accuracy knobs (offload-off + tc netem); `measure.sh` analyzer-output parsing.

### Modified Capabilities
- (none; no existing spec's requirements change — the NIC `[METRIC]`→`[DIAG]` relabel is an implementation-detail log change, not a requirement change.)

## Impact

- **New files**: `experiments/utils/analyze_metrics.py`, `experiments/proxmox/run_experiment.sh`, `experiments/utils/ssh_lab.sh` (SSH-gateway transport), a shared runner-core helper sourced by both runners.
- **Modified files**: `experiments/utils/measure.sh` (drop dead grep, parse analyzer output), `experiments/dpdk/run_experiment.sh` (relocate tcpdump to endpoints, add server capture, call analyzer, host knobs), `clientnic/dpdk-forwarder/forwarder.c` + `servernic/dpdk/translator.c` (`[METRIC]`→`[DIAG]` relabel).
- **Dependencies**: only `tcpdump` + `scapy`, both already in use; no new runtime stack, no kernel programming. Proxmox transport depends on `.claude/skills/runs-lab-connect/SKILL.md` gateway access.
- **Behavioral**: experiment reports stop emitting "no samples found" and start reporting real endpoint metrics; the 0-RTT data plane is functionally unchanged.
