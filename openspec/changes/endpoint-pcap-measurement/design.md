## Context

The 0-RTT demo runs a 4-VM chain on AWS (`Client → ClientNIC → ServerNIC → Server`) and a 3-node Proxmox LAN path (`Client → middlebox/DPU → Server`). Today the only real timing is NIC-internal `rdtsc` (measures the middlebox, not the endpoints); `experiments/utils/measure.sh` greps `[METRIC] … node=… ttfb|fct` lines that no component emits (every report: "no samples found"); and iperf2's 10 ms resolution is useless on a sub-ms LAN. iperf2 is the unmodified load generator on both infras (R2). The existing `clientnic/validate_0rtt_capture.py` already does rdpcap + 4-tuple + SYN-timing on a client pcap — ~80% of the analyzer we need.

The key insight is that all three target metrics are **single-host intervals**: both bracket events of each metric are observed at one tap point on one host. This removes any need for cross-machine clock sync — a fixed capture-path offset adds to both bracket events and cancels in the subtraction; only the jitter *difference* survives.

## Goals / Non-Goals

**Goals:**
- One mechanism, identical captures + identical analyzer, producing the three metrics on both AWS and Proxmox (R1).
- iperf2 stays completely unmodified; coupling only via capture window + on-wire 4-tuple (R2).
- Reuse `validate_0rtt_capture.py` machinery rather than introduce new runtime tech.
- Make the ~1-RTT 0-RTT saving legible above the capture noise floor.

**Non-Goals:**
- Sub-µs precision, line-rate/continuous telemetry, cross-host clock alignment (NTP/PTP), or any kernel programming (eBPF/tc-bpf). See proposal `## Non-Goals`.
- Changing the DPDK 0-RTT data-plane behavior (only the diagnostic log tag changes).

## Decisions

### D1 — Two captures, one analyzer, regardless of middlebox count
Both infra topologies reduce to the *same two captures*: `client_side.pcap` (yields FCT + send-unlock) and `server_side.pcap` (yields server-gap). The middleboxes (2 on AWS, 1 on Proxmox) are irrelevant to measurement — they sit between the two tap points and cancel out of every single-host delta. This is what makes R1 achievable with one analyzer.

### D2 — tcpdump-to-file + offline Python (mechanism A)
Capture is live tcpdump to `.pcap`; analysis is offline `analyze_metrics.py` (scapy `rdpcap`). Software timestamps suffice because offset cancels in the delta and the netem-injected RTT dominates the noise floor (see D5). Durable `.pcap` is a re-analyzable artifact; zero kernel coupling keeps it portable across the two kernel families. Rationale over alternatives in `## Alternatives Considered`.

### D3 — Analyzer generalizes `validate_0rtt_capture.py`; key=value output
`analyze_metrics.py` reuses the existing rdpcap + 4-tuple + SYN-anchor logic and adds payload-bearing-segment and last-byte/FIN detection. It anchors the flow on the SYN to `server:<port>`, is generator-agnostic (reads the wire, so iperf2's lack of JSON is a non-issue), and derives FCT from the *same* client pcap as send-unlock (one source of truth). Output is greppable key=value lines:
```
metric=fct          value_ms=<v> node=client flow=<srcip:sport-dstip:dport>
metric=send_unlock  value_ms=<v> node=client flow=<...>
metric=server_gap   value_ms=<v> node=server flow=<...>
```
This format was chosen over JSON so `measure.sh` parses with the same shell idiom it already uses (no `jq`/python parser dependency); metrics are flat, so nested structure buys nothing.

### D4 — Shared core + 2 thin transports
The runners differ *only* in node discovery (EC2 `describe-instances` vs static `10.13.37.x` inventory) and exec transport (`ssm_run` vs `ssh_run` through the runs-gateway jump host). Everything from "start captures on endpoints → run iperf2 → stop → copy pcaps → analyze" is factored into a shared core sourced by both `experiments/dpdk/run_experiment.sh` (AWS) and the new `experiments/proxmox/run_experiment.sh`. A new `experiments/utils/ssh_lab.sh` provides the SSH-gateway transport mirroring `ssm.sh`.

### D5 — Accuracy knobs are hard dependencies, not polish
- **Disable offload** (`ethtool -K <if> gro off lro off tso off gso off`) on both capture interfaces — without it, "first segment with payload" is a coalesced TSO/GRO lie that corrupts send-unlock and server-gap. Single biggest fidelity lever.
- **Inject `tc netem delay 50ms`** on each endpoint (~100 ms RTT). On a bare LAN/intra-AZ path RTT is sub-ms, so the ~1-RTT saving would round into pcap jitter. 50ms/side puts the saving (~100 ms) two orders of magnitude above tens-of-µs jitter, and is the bottom of CLAUDE.md's stated 50–200 ms band.

### D6 — Validation guardrails + defensive cross-check
The analyzer rejects/flags a flow missing required events (no SYN, no payload segment, truncated capture) rather than emitting a wrong number — the current silent-"no samples found" failure mode is unacceptable. Additionally, `iperf -y C` CSV is logged alongside the flow; the analyzer/runner warns if pcap-derived FCT diverges from iperf2's reported duration by >10 ms. The CSV is advisory only — pcap stays the source of truth.

### D7 — NIC rdtsc stamps relabeled `[METRIC]` → `[DIAG]`
The DPDK data planes keep their `rdtsc` instrumentation (still answers "where does the middlebox spend time?") but the log tag changes to `[DIAG]` in `forwarder.c` / `translator.c` so it no longer masquerades as the experiment metric and is not parsed by `measure.sh`. No data-plane behavior change.

## Alternatives Considered

### A. tcpdump + offline Python — **CHOSEN**
SW timestamps; offset cancels in each single-host delta; ~80% reuse of `validate_0rtt_capture.py`; durable `.pcap` artifact; zero kernel coupling. **Verdict: chosen** — wins on the two axes this problem exercises (portability across two kernel families + reuse) and loses only on precision/liveness, which the netem regime makes irrelevant.

### B. eBPF on each host
Sub-µs precision and lowest overhead, but BTF/kernel coupling ×2 families, and `tcp_sendmsg` sees bytes-to-stack not on-wire segments, so send-unlock would need tc-bpf + verifier work. **Verdict: on-the-shelf upgrade path** — right tool for continuous/line-rate telemetry or the Bluefield/DPA move, not for a single short demo flow.

### C. C/Rust libpcap sidecar
Draws from the *identical* libpcap clock as A, so it buys liveness, not precision, at the cost of a daemon to build and deploy on both infras. **Verdict: rejected** — no use case here prefers it; if "live" is ever wanted, B beats it on precision.

### D. HW NIC timestamping (PTP)
Most precise absolute clock, but virtio/ENA VMs don't expose it, and mixing HW-ts (Proxmox) with SW-ts (AWS) breaks R1. **Verdict: on-the-shelf upgrade path** — matters later on Proxmox production-segment NICs (Tofino/Bluefield).

### E. iperf telemetry / OpenTelemetry
Disqualified by layer: send-unlock/server-gap are packet events the app never sees; OTel ships spans and can't capture a SYN; iperf2 emits no machine-readable per-flow timing. **Verdict: rejected** — wrong layer, and would require forking iperf2 (violates R2).

## Risks / Trade-offs

- **Offload left on corrupts (b)/(c)** → X1 makes `ethtool -K … off` a mandatory pre-capture step; the runner asserts/logs the offload state before starting the flow.
- **Capture window misses SYN or last byte** → C2 starts tcpdump before connect and stops after completion; A5 guardrails flag truncated/missing-event captures instead of scoring them; iperf CSV cross-check (D6) catches window mistakes.
- **Sub-ms LAN makes the saving invisible** → X2/tc netem is a hard dependency, not optional (D5).
- **Proxmox transport depends on lab gateway access** → SSH-gateway transport isolated in `ssh_lab.sh`; AWS runner is unaffected and remains the primary verifiable path. Proxmox criterion is manual-review until lab access is available.
- **`scapy/`-dir shadowing** → analyzer must be run from outside any `scapy/`-named directory (copy to `/tmp/`), per the existing validator note (A1).
- **tcpdump high-precision flags unsupported on some kernels** → C4 requires graceful fallback if `--time-stamp-precision=nano` or `-j host_hiprec` is rejected.
