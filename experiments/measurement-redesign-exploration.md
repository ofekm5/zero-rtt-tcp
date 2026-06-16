# Measurement Redesign — Options & Recommendation

**Status**: Exploration / decision memo (for review — not yet an OpenSpec proposal).
**Last updated**: 2026-06-16
**Mode**: `/ai-workflow-agents:explore` (thinking only — no implementation yet)

> **Purpose of this document**: lay out the proposed measurement mechanism, compare it
> honestly against every alternative considered, and state *which mechanism is better for
> which use case* — so the choice can be reviewed on its merits, not asserted.

---

## 1. Goal — three endpoint-observed metrics

Replace the current incoherent experiment timing with **three metrics, each observed at an
endpoint, on that endpoint's own clock**:

| | Metric | Events | Host |
|---|---|---|---|
| **(a)** | **Flow completion time (FCT)** | first SYN out → last data byte / FIN | Client |
| **(b)** | **Send-unlock** ("0-RTT let the client send early") | first SYN out → first outbound segment with payload > 0 | Client |
| **(c)** | **Server gap** | first SYN-ACK out → first inbound data segment | Server |

The same three metrics must be measured **identically across all available infrastructure**:

1. **AWS EC2 / DPDK** (`infra/dpdk`) — chain: `Client → ClientNIC → ServerNIC → Server` (2 middleboxes).
2. **University Proxmox cluster (real LAN)** — `Client → middlebox/DPU → Server` (1 middlebox).

Measurement must be **tightly coupled to iperf2** — iperf2 is the load generator that fires the
chain of events on both client and server. It stays **completely unmodified**.

---

## 2. Why the current measurement is incoherent

Three different clocks pretend to be one metric, and the metric the report prints doesn't exist:

```
┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
│  Client    │──▶│ ClientNIC  │──▶│ ServerNIC  │──▶│  Server    │
│ iperf2     │   │ DPDK fwd   │   │ DPDK xlate │   │ iperf2     │
└────────────┘   └─────┬──────┘   └─────┬──────┘   └────────────┘
                       │                │
              [METRIC] rdtsc      [METRIC] rdtsc
              SYN-in → 1st        SYN-in → 1st
              s2c data            s2c data
              (middleware-internal, NOT endpoint-observed)
```

1. **The only real timing is NIC-internal** — `rdtsc` deltas inside the DPDK data plane
   (`clientnic/dpdk-forwarder/forwarder.c:39`, `servernic/dpdk/translator.c:40`). Measures what the
   *middleware* does, not what the endpoints experience.
2. **`experiments/utils/measure.sh` greps for `node=client` / `fct node=client`** (lines 136–137) —
   **nobody emits those.** Every baseline report says `no samples found`. Dead code.
3. **iperf's own timing is too coarse** — reports show `0.00–0.01 sec` intervals: 10 ms resolution on a
   sub-ms LAN.

**Architectural decision (agreed):** move measurement **off the NICs and onto the endpoints**. Each
endpoint measures its own metrics on its own clock; the middleboxes get out of the measurement business.

---

## 3. Key property that makes this easy and portable

All three metrics are **single-host intervals** — both bracket events of each metric are observed at
**one tap point on one host**:

```
(a) FCT          = t(last byte)      − t(first SYN)      both on CLIENT
(b) send-unlock  = t(1st data seg out) − t(SYN out)      both on CLIENT
(c) server gap   = t(1st data in)    − t(SYN-ACK out)    both on SERVER
```

Two consequences:

- **No cross-machine clock sync** (no NTP/PTP alignment) is ever required.
- **Systematic timestamp offset cancels in the subtraction.** Whatever fixed latency the capture path
  adds, it adds to *both* bracket events and subtracts out. Only the *jitter difference* survives — far
  smaller than the raw offset. So "most accurate" here does **not** mean "highest-resolution clock"; it
  means *same observation point for both events + remove offload distortion + let the real signal
  dominate the noise floor.*

Because the metrics are observed at the endpoints, **the number of middleboxes is irrelevant** — AWS's
2-middlebox chain and Proxmox's 1-middlebox path reduce to the *same two captures*:

```
   ┌─ CLIENT host ─────────────┐                      ┌─ SERVER host ─────────────┐
   │ iperf2 -c (UNMODIFIED)    │                      │ iperf2 -s (UNMODIFIED)    │
   │ tcpdump on its OWN iface  │   ...middlebox(es)…  │ tcpdump on its OWN iface  │
   │  → client_side.pcap       │   (DPDK / DPU —      │  → server_side.pcap       │
   │  yields (a) + (b)         │    N/A to measuring) │  yields (c)               │
   └───────────────────────────┘                      └───────────────────────────┘
                    │                                          │
                    └──────────► analyze_metrics.py ◄──────────┘
```

---

## 4. The proposal — packet capture to file + offline Python analysis

**Not eBPF. Not a sidecar. Not OpenTelemetry.** The proposed mechanism is the simplest one that fits:

**Step 1 — capture (live, during the flow).** `tcpdump` writes a `.pcap` on the client and on the
server while the iperf2 flow runs. No real-time analysis, no kernel programming — it records packet
headers + timestamps to a file.

**Step 2 — analyze (offline, after the flow).** A Python script reads the `.pcap` files
(`scapy.rdpcap`) and computes (a)/(b)/(c) from packet timestamps. Runs after iperf2 finishes — even on a
laptop.

```
   [start tcpdump on client + server]      ← step 1 begins
   [run iperf2 -c → -s flow]               ← the thing being measured (unmodified)
   [stop tcpdump]                          ← step 1 ends, .pcap files exist
   [copy pcaps, run analyze_metrics.py]    ← step 2: the three numbers come out
```

### Coupling to iperf2 *without touching iperf2*

- **Window:** captures bracket the iperf2 flow (start before connect, stop after).
- **Flow key:** the analyzer locates the flow by 4-tuple (the SYN to `server:8080`). This is
  **generator-agnostic** — it reads the wire, so iperf2's lack of `-J`/JSON is a non-issue, and metric
  (a) comes from the *same* pcap as (b)/(c) (one source of truth).

### Accuracy levers (all inside this mechanism, all portable)

- `tcpdump --time-stamp-precision=nano -j host_hiprec` — nanosecond, high-precision, monotonic-ish stamps.
- **`ethtool -K <if> gro off lro off tso off gso off` on both endpoints** — the single biggest fidelity
  lever: without it, "first segment with payload" is a coalesced (TSO/GRO) lie.
- Pair with **`tc netem`** injected latency so the ~1-RTT 0-RTT saving is legible (see §7).

---

## 5. Honest comparison — which mechanism is better for which use case

The metrics in scope are 3 single-host deltas, demo scale (one short `iperf -n 1M` flow, sequential),
across two infras, triggered by iperf2. Each alternative wins on *some* axis; the question is whether
that axis is exercised by **this** problem.

| Axis | **A. tcpdump + offline Python (PROPOSED)** | **B. eBPF on each host** | **C. C/Rust pcap sidecar** | **D. HW NIC timestamping (PTP)** | **E. iperf telemetry / OTel** |
|---|---|---|---|---|---|
| Timestamp source | libpcap SW ts (AF_PACKET) | `bpf_ktime_get_ns` at kernel hook | libpcap SW ts (same as A) | NIC hardware clock | application-level only |
| Raw precision | ~tens of µs jitter | **sub-µs** | ~tens of µs (= A) | **ns, lowest jitter** | ms (coarse) |
| Precision that *survives* the delta | offset cancels → jitter only | jitter only | jitter only | jitter only | n/a |
| Overhead at line rate | drops at very high pps | **lowest** | low | lowest | n/a |
| Overhead at demo scale (1 short flow) | **negligible** | negligible | low (daemon) | negligible | negligible |
| Can see wire segment (b)/(c)? | **yes** (AF_PACKET egress/ingress) | only with tc-bpf + verifier work (sendmsg ≠ segment) | yes | yes | **no** (app never sees a SYN) |
| Portability across AWS + Proxmox kernels | **zero coupling** | BTF/kernel-version coupling **×2 families** | zero coupling | NIC-dependent (virtio: none) | n/a |
| Code reuse in this repo | **HIGH** — `validate_0rtt_capture.py` already does rdpcap + 4-tuple + SYN timing | PARTIAL — `observability/ebpf/*` exist but for retransmits/state, and are **disabled** | LOW — net-new program | LOW | LOW |
| New host deps | none (tcpdump + scapy already used) | bpftrace/BCC + kernel BTF | Rust/C toolchain | PTP-capable NIC + setup | OTel collector + fork iperf |
| Durable artifact | **`.pcap`** (Wireshark, re-run, diff, attach to report) | ephemeral numbers | ephemeral stream | ephemeral | spans only |
| iperf2 untouched | ✓ | ✓ | ✓ | ✓ | ✗ (would require forking iperf) |
| **Best-fit use case** | **Demo/edu scale, portable, trusted, offline — THIS project now** | Continuous/line-rate telemetry; the Bluefield/DPA move | "live stream" without eBPF — but same data source as A | Absolute cross-host precision on real hardware NICs | Shipping spans someone else already produced |

### Reading the table

- **A wins the axes that bind this problem:** portability (the hard constraint — two kernel families),
  reuse (~80% already written), generator-decoupling (iperf2 has no JSON), and a durable teaching
  artifact. It loses only on axes this problem doesn't exercise.
- **B (eBPF)** is genuinely *better* — but for a *different* problem: always-on, line-rate telemetry, or
  the on-prem Bluefield/DPA move where `observability/` scaffolding and sub-µs precision earn their keep.
  Against this problem it pays a doubled portability tax (AWS AL2023 **and** Proxmox kernels), its sub-µs
  edge rounds away under netem (§7), and the metric it's *weakest* at is exactly (b) — `tcp_sendmsg`
  sees bytes handed to the stack, not on-wire segments (TSO/GSO), so true segment timing needs tc-bpf +
  `bpf_skb_load_bytes` + verifier bounds-fighting to reproduce what `len(pkt[TCP].payload)` gives for free.
- **C (sidecar)** draws from the **identical** libpcap clock as A — it buys *liveness*, not precision,
  at the cost of a daemon to build/deploy/manage. If "live" is ever wanted, B beats it on precision.
  No use case here prefers C.
- **D (HW timestamping)** is the most precise in absolute terms and could matter **later, on the
  Proxmox production-segment hardware NICs (10.13.36.x: Tofino/Bluefield)** — but virtio/ENA VMs don't
  expose it, and mixing HW-ts on Proxmox with SW-ts on AWS breaks "same manner for all infra." Parallel
  to eBPF: a precision *upgrade path*, not a starting point.
- **E (iperf telemetry / OpenTelemetry)** is disqualified by layer, not effort: (b)/(c) are packet-level
  events the application never observes. *OTel is a transport, not an observer* — it ships spans someone
  else produced; it can't capture a SYN. And iperf2 emits no machine-readable per-flow timing anyway.

**Verdict:** for *these 3 metrics, at demo scale, across two infras, triggered by iperf2* — **A is the
most efficient overall.** The alternatives win only on axes this problem doesn't exercise, while losing
on the axis that actually constrains it (portability + reuse). Change the problem — continuous line-rate,
or the Bluefield/DPA move — and **B flips to being the right tool.** That is precisely why B and D are
recorded as the **upgrade path**, not rejected outright.

---

## 6. How it integrates into the existing workflow

The AWS runner already follows this exact two-step shape — the change is *relocation + extension*, not
new runtime tech.

```
experiments/
  utils/
    measure.sh         ← REWRITE: drop dead node=client/fct grep; parse analyzer output
    analyze_metrics.py ← NEW: pcap → (a)(b)(c); generalizes validate_0rtt_capture.py
    ssm.sh             ← AWS transport (exists)
    ssh_lab.sh         ← NEW: run-on-node via runs-gateway jump host + static inventory
  dpdk/run_experiment.sh     ← AWS runner (sources ssm.sh)     + shared core
  proxmox/run_experiment.sh  ← NEW LAN runner (sources ssh_lab.sh) + shared core
```

| Existing step (AWS `run_experiment.sh`) | Change |
|---|---|
| Step 3 starts `tcpdump on eth0` of **ClientNIC** | Move tcpdump onto the **Client host**; add one on the **Server host** |
| Step 5 `pkill tcpdump` | unchanged |
| Step 8 runs `validate_0rtt_capture.py` | Extend → `analyze_metrics.py`, emit (a)/(b)/(c) |
| `measure.sh` greps `[METRIC]` lines (dead) | Replace with: parse analyzer output |

**Common core + 2 transports.** The two runners differ *only* in node discovery (EC2
`describe-instances` vs a static `10.13.37.x` inventory) and exec transport (`ssm_run` vs `ssh_run`
through the gateway). Everything from "start captures on endpoints → run iperf2 → stop → analyze" is
shared. No new runtime stack enters — just `tcpdump` + `scapy`, both already in use.

### Analyzer logic (sketch — generalizes the existing validator)

```
client_side.pcap  (flow keyed by 4-tuple: SYN → server:8080)
   t0  = first SYN out
   t1  = first OUT packet with TCP payload > 0
   t2  = last data packet / FIN
   (a) FCT         = t2 − t0
   (b) send-unlock = t1 − t0

server_side.pcap  (same flow)
   t_sa = first SYN-ACK out
   t_d  = first IN packet with payload > 0
   (c) server gap  = t_d − t_sa
```

---

## 7. Cross-cutting factor — RTT magnitude decides whether precision matters

0-RTT's saving is ~1 RTT.

- **Raw intra-AZ / intra-LAN RTT** ≈ 100–500 µs → pcap jitter (~tens of µs) is a real fraction →
  precision *would* matter.
- **With `tc netem` injected** (50–200 ms, matching CLAUDE.md's "50–200 ms depending on network
  latency") → pcap jitter is the noise floor → tcpdump is more than enough, and eBPF's/HW-ts's precision
  edge rounds away.

A legible 0-RTT result basically *requires* injected latency on **both** infras (a bare LAN's RTT is
sub-ms too). **So `tc netem` is an implied dependency of this redesign**, and it is the reason the
precision-oriented alternatives (B, D) don't pay off in the regime we'll actually measure in.

---

## 8. Decisions still open

1. **NIC `rdtsc [METRIC]` stamps** (`forwarder.c:39`, `translator.c:40`) — now that endpoints own
   measurement: **relabel as middleware-internal diagnostics** (recommended — still useful to show
   *where* the middlebox spends time), remove, or leave?
2. **`tc netem` latency injection** — confirm in-scope for both infras (effectively required for legible
   results; see §7).
3. **iperf2 CSV cross-check** — derive (a) purely from pcap (agreed), but optionally log `iperf -y C`
   alongside to confirm pcap-FCT agrees with iperf2's reported duration? (Defensive, low cost.)

---

## 9. Decisions already made this session

- **Mechanism:** A — tcpdump-to-file + offline Python on the endpoints.
- **Generator:** iperf2 everywhere, unmodified (matches live code; the prior "switch to iperf3" lean was
  stale — the repo reverted iperf3→iperf2).
- **Proxmox topology:** 2-node + 1 middlebox (Client + Server VMs, single DPU/middlebox between).
- **Orchestration:** common pcap+analyzer core, two transports (AWS SSM / Proxmox SSH-gateway).
- **Metric (a) source:** derive from the client pcap (one source of truth for all three).

---

## 10. When this crystallizes → OpenSpec proposal

Slots near `phase-1b-iperf3-stress-testing`. Record:

- **Mechanism:** pcap-on-endpoints + offline analyzer; common core + 2 transports.
- **Alternatives Considered:** eBPF (upgrade path: line-rate / Bluefield-DPA); HW/PTP timestamping
  (Proxmox-only future precision); C/Rust sidecar (same data source as pcap, no advantage here).
- **Non-Goals:** socket-layer eBPF shortcut, OpenTelemetry, forking iperf, cross-host clock sync.
- **In-scope cleanup:** delete dead `node=client`/`fct` grep in `measure.sh`; relabel/keep NIC rdtsc
  stamps; `tc netem` knob.

---

## Reference points (files touched / relevant)

- `experiments/utils/measure.sh` — dead `node=client` / `fct` grep (lines 136–137); `run_ttfb_measurement`.
- `experiments/nodes/client.sh:65` — iperf2 client (`iperf -c … -n 1M -f m`); `server.sh:43` — iperf2 server.
- `experiments/dpdk/run_experiment.sh` — AWS orchestrator (already: tcpdump → validator two-step).
- `clientnic/validate_0rtt_capture.py` — the reusable rdpcap + 4-tuple + SYN-timing analyzer (~80% of §6).
- `clientnic/dpdk-forwarder/forwarder.c:39`, `servernic/dpdk/translator.c:40` — NIC rdtsc `[METRIC]` emit.
- `observability/ebpf/` — disabled bpftrace scaffolding (retransmit/state traces).
- `.claude/skills/runs-lab-connect/SKILL.md` — Proxmox/RUNS-lab access (gateway jump host, no SSM/EC2 API).
