# Measurement Redesign — Specification

**Status**: Pre-proposal spec (decision made; ready to slot into OpenSpec — see §10).
**Last updated**: 2026-06-20
**Mechanism (decided)**: `tcpdump` capture-to-file on the endpoints + offline Python analysis.

> **Purpose**: specify the endpoint-based measurement mechanism precisely enough to implement
> and verify. Alternatives were compared and settled (§7, condensed); this document is about the
> chosen design, not the choice.

---

## 1. Goal — three endpoint-observed metrics

Replace the current incoherent experiment timing with **three metrics, each observed at an
endpoint, on that endpoint's own clock**:

| | Metric | Interval (both events on one host) | Host |
|---|---|---|---|
| **(a)** | **Flow completion time (FCT)** | first SYN out → last data byte / FIN | Client |
| **(b)** | **Send-unlock** ("0-RTT let the client send early") | first SYN out → first outbound segment with payload > 0 | Client |
| **(c)** | **Server gap** | first SYN-ACK out → first inbound data segment | Server |

The mechanism must satisfy:

- **R1 — Identical across infra.** The same captures + same analyzer produce all three metrics on
  both target infrastructures:
  1. **AWS EC2 / DPDK** (`infra/dpdk`) — `Client → ClientNIC → ServerNIC → Server` (2 middleboxes).
  2. **University Proxmox cluster (real LAN)** — `Client → middlebox/DPU → Server` (1 middlebox).
- **R2 — iperf2 unmodified.** iperf2 is the load generator that fires the chain of events on both
  client and server. It stays **completely unmodified**; coupling is by capture window + on-wire
  flow key, never by patching the generator.

---

## 2. Motivation — why the current measurement is incoherent

Three different clocks pretend to be one metric, and the metric the report prints doesn't exist:

```
┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
│  Client    │──▶│ ClientNIC  │──▶│ ServerNIC  │──▶│  Server    │
│ iperf2     │   │ DPDK fwd   │   │ DPDK xlate │   │ iperf2     │
└────────────┘   └─────┬──────┘   └─────┬──────┘   └────────────┘
                       │                │
              [METRIC] rdtsc      [METRIC] rdtsc
              (middleware-internal, NOT endpoint-observed)
```

1. **The only real timing is NIC-internal** — `rdtsc` deltas inside the DPDK data plane
   (`clientnic/dpdk-forwarder/forwarder.c:39`, `servernic/dpdk/translator.c:40`). Measures what the
   *middleware* does, not what the endpoints experience.
2. **`experiments/utils/measure.sh` greps for `node=client` / `fct node=client`** (lines 136–137) —
   **nobody emits those.** Every baseline report says `no samples found`. Dead code.
3. **iperf's own timing is too coarse** — reports show `0.00–0.01 sec` intervals: 10 ms resolution on
   a sub-ms LAN.

**Decision:** move measurement **off the NICs and onto the endpoints**. Each endpoint measures its
own metrics on its own clock; the middleboxes get out of the measurement business.

---

## 3. Design principle — single-host intervals

All three metrics are **single-host intervals** — both bracket events of each metric are observed at
**one tap point on one host**:

```
(a) FCT          = t(last byte)       − t(first SYN)     both on CLIENT
(b) send-unlock  = t(1st data seg out) − t(SYN out)      both on CLIENT
(c) server gap   = t(1st data in)     − t(SYN-ACK out)   both on SERVER
```

This is the property the whole spec leans on:

- **No cross-machine clock sync** (no NTP/PTP alignment) is ever required.
- **Systematic timestamp offset cancels in the subtraction.** Whatever fixed latency the capture path
  adds, it adds to *both* bracket events and subtracts out; only the *jitter difference* survives. So
  "accurate" here means *same observation point for both events + remove offload distortion + let the
  real signal dominate the noise floor* — not "highest-resolution clock."
- **Middlebox count is irrelevant.** AWS's 2-middlebox chain and Proxmox's 1-middlebox path reduce to
  the *same two captures*:

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

## 4. Specification

The mechanism is two steps: **capture** (live, during the flow) and **analyze** (offline, after).
No eBPF, no sidecar, no OpenTelemetry, no kernel programming.

```
   [start tcpdump on client + server]      ← capture begins
   [run iperf2 -c → -s flow]               ← the thing being measured (unmodified)
   [stop tcpdump]                          ← capture ends, .pcap files exist
   [copy pcaps, run analyze_metrics.py]    ← analysis: the three numbers come out
```

### 4.1 Capture requirements

- **C1 — Tap point.** On each endpoint, `tcpdump` captures on the host's **own** data interface
  (the iface carrying the iperf2 flow), writing a `.pcap` to disk. Client → `client_side.pcap`;
  Server → `server_side.pcap`.
- **C2 — Window.** Captures bracket the iperf2 flow: started **before** the client connects, stopped
  **after** the flow completes. The flow's SYN and last byte must both fall inside the window.
- **C3 — Filter.** Capture is restricted to the flow's TCP traffic (`tcp and host <peer> and port
  <server-port>`) to keep pcaps small; it must not filter so tightly that the SYN / SYN-ACK / FIN are
  excluded.
- **C4 — Timestamp quality.** Capture with
  `tcpdump --time-stamp-precision=nano -j host_hiprec` — nanosecond, high-precision, monotonic-ish
  stamps where the kernel/NIC supports it; fall back gracefully if a flag is unsupported.

### 4.2 Analyzer requirements (`analyze_metrics.py`)

Generalizes the existing `clientnic/validate_0rtt_capture.py` (rdpcap + 4-tuple + SYN-timing).

- **A1 — Input.** Reads one or both pcaps via `scapy.rdpcap`. Runs offline, anywhere (laptop OK).
  Copy out of any `scapy/`-shadowing directory before running (`/tmp/`), per existing validator note.
- **A2 — Flow identification.** Locates the flow by 4-tuple, anchored on the SYN to
  `server:<port>`. **Generator-agnostic** — it reads the wire, so iperf2's lack of JSON is a
  non-issue, and metric (a) comes from the *same* pcap as (b), giving one source of truth.
- **A3 — Metric extraction.**

  ```
  client_side.pcap  (flow keyed by 4-tuple: SYN → server:<port>)
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

- **A4 — Output.** Emits the three metrics in a machine-parseable form that `measure.sh` consumes
  (replacing the dead `[METRIC]` grep). Format to be fixed in the proposal (e.g. `metric=fct
  value_ms=… node=client`).
- **A5 — Validation guardrails.** Reject/flag a flow where required events are missing (no SYN, no
  payload segment, truncated capture) rather than emitting a wrong number — the current failure mode
  was silent "no samples found."

### 4.3 Accuracy requirements (host setup before capture)

- **X1 — Disable offload** on both endpoints' capture interfaces:
  `ethtool -K <if> gro off lro off tso off gso off`. This is the **single biggest fidelity lever** —
  without it, "first segment with payload" is a coalesced (TSO/GRO) lie, corrupting (b) and (c).
- **X2 — Inject latency** with `tc netem` so the ~1-RTT 0-RTT saving is legible against the capture
  noise floor (see §6). Effectively a hard dependency of the redesign, not optional polish.

---

## 5. Workflow integration

The AWS runner already follows this two-step shape — the change is *relocation + extension*, not new
runtime tech.

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
| `measure.sh` greps `[METRIC]` lines (dead) | Replace with: parse analyzer output (A4) |

**Common core + 2 transports.** The two runners differ *only* in node discovery (EC2
`describe-instances` vs a static `10.13.37.x` inventory) and exec transport (`ssm_run` vs `ssh_run`
through the gateway). Everything from "start captures on endpoints → run iperf2 → stop → analyze" is
shared. No new runtime stack enters — just `tcpdump` + `scapy`, both already in use.

---

## 6. Cross-cutting dependency — RTT magnitude decides legibility

0-RTT's saving is ~1 RTT. Whether that saving is visible above the capture noise depends on RTT:

- **Raw intra-AZ / intra-LAN RTT** ≈ 100–500 µs → pcap jitter (~tens of µs) is a real fraction.
- **With `tc netem` injected** (50–200 ms, matching CLAUDE.md's "50–200 ms depending on network
  latency") → pcap jitter is the noise floor → tcpdump's software timestamps are more than enough.

A legible 0-RTT result on either infra basically *requires* injected latency (a bare LAN's RTT is
sub-ms too). This is why **`tc netem` is requirement X2**, and why higher-precision alternatives (§7
B, D) don't pay off in the regime we actually measure in — their edge rounds away under netem.

---

## 7. Alternatives Considered

Compared honestly and settled. The constraints that bind *this* problem — three single-host deltas,
demo scale (one short `iperf -n 1M` flow), two kernel families, iperf2-triggered — favor the chosen
mechanism on portability and reuse, the two axes the problem actually exercises.

| Option | One-line tradeoff | Verdict |
|---|---|---|
| **A. tcpdump + offline Python** *(chosen)* | SW timestamps; offset cancels in the delta; ~80% reuse of `validate_0rtt_capture.py`; durable `.pcap` artifact; zero kernel coupling | **Chosen** — wins portability + reuse; loses only on axes this problem doesn't exercise |
| **B. eBPF on each host** | Sub-µs precision, lowest overhead — but BTF/kernel coupling **×2 families**, and `tcp_sendmsg` sees bytes-to-stack, not on-wire segments, so metric (b) needs tc-bpf + verifier work | **Upgrade path** — right tool for continuous/line-rate telemetry or the Bluefield/DPA move, not for this |
| **C. C/Rust pcap sidecar** | Draws from the **identical** libpcap clock as A — buys *liveness*, not precision, at the cost of a daemon to build/deploy | **Rejected** — no use case here prefers it; if "live" is ever wanted, B beats it on precision |
| **D. HW NIC timestamping (PTP)** | Most precise absolute clock — but virtio/ENA VMs don't expose it; mixing HW-ts (Proxmox) with SW-ts (AWS) breaks R1 | **Upgrade path** — matters later on Proxmox production-segment NICs (Tofino/Bluefield, 10.13.36.x) |
| **E. iperf telemetry / OpenTelemetry** | Disqualified by *layer*: (b)/(c) are packet events the app never sees; OTel ships spans, can't capture a SYN; iperf2 emits no machine-readable per-flow timing | **Rejected** — wrong layer, and would require forking iperf (violates R2) |

**Why B/D are recorded as upgrade path, not rejected:** change the problem to continuous line-rate
measurement, or move to the Bluefield/DPA on-prem hardware, and B (then D) become the right tool. They
lose *here*, not everywhere.

---

## 8. Open decisions

1. **NIC `rdtsc [METRIC]` stamps** (`forwarder.c:39`, `translator.c:40`) — now that endpoints own
   measurement: **relabel as middleware-internal diagnostics** (recommended — still shows *where* the
   middlebox spends time), remove, or leave?
2. **`tc netem` parameters** — confirm the injected-latency value(s) and that injection is applied
   consistently on both infras (the mechanism requires it per X2; the exact ms is open).
3. **iperf2 CSV cross-check** — derive (a) purely from pcap (agreed), but optionally log `iperf -y C`
   alongside to confirm pcap-FCT agrees with iperf2's reported duration? (Defensive, low cost.)
4. **A4 output format** — fix the exact analyzer output line that `measure.sh` parses.

---

## 9. Decisions already made

- **Mechanism:** A — tcpdump-to-file + offline Python on the endpoints.
- **Generator:** iperf2 everywhere, unmodified (the prior "switch to iperf3" lean was stale — the repo
  reverted iperf3→iperf2).
- **Proxmox topology:** 2-node + 1 middlebox (Client + Server VMs, single DPU/middlebox between).
- **Orchestration:** common pcap+analyzer core, two transports (AWS SSM / Proxmox SSH-gateway).
- **Metric (a) source:** derive from the client pcap (one source of truth for all three).

---

## 10. When this crystallizes → OpenSpec proposal

Slots near `phase-1b-iperf3-stress-testing`. Maps to OpenSpec artifacts as:

- **Capability / `proposal.md` "What Changes":** pcap-on-endpoints capture + `analyze_metrics.py`;
  common runner core + 2 transports; rewrite `measure.sh` to parse analyzer output.
- **`design.md` "Decisions":** §3 single-host principle; §4.1–4.3 capture/analyzer/accuracy specs.
- **`design.md` "Alternatives Considered":** §7 table — B (line-rate / Bluefield-DPA upgrade), D
  (Proxmox HW/PTP future precision), C (same data source as pcap, no advantage here).
- **`proposal.md` "Non-Goals":** socket-layer eBPF shortcut, OpenTelemetry, forking iperf, cross-host
  clock sync, C/Rust sidecar.
- **`tasks.md` in-scope cleanup:** delete dead `node=client`/`fct` grep in `measure.sh`; relabel/keep
  NIC rdtsc stamps; add `tc netem` + `ethtool -K` offload-off knobs.

---

## Reference points (files touched / relevant)

- `experiments/utils/measure.sh` — dead `node=client` / `fct` grep (lines 136–137); `run_ttfb_measurement`.
- `experiments/nodes/client.sh:65` — iperf2 client (`iperf -c … -n 1M -f m`); `server.sh:43` — iperf2 server.
- `experiments/dpdk/run_experiment.sh` — AWS orchestrator (already: tcpdump → validator two-step).
- `clientnic/validate_0rtt_capture.py` — the reusable rdpcap + 4-tuple + SYN-timing analyzer (~80% of §4.2).
- `clientnic/dpdk-forwarder/forwarder.c:39`, `servernic/dpdk/translator.c:40` — NIC rdtsc `[METRIC]` emit.
- `observability/ebpf/` — disabled bpftrace scaffolding (retransmit/state traces).
- `.claude/skills/runs-lab-connect/SKILL.md` — Proxmox/RUNS-lab access (gateway jump host, no SSM/EC2 API).
</content>
</invoke>
