---
type: Wiki Entry
title: "Experiment Insights"
description: "Running log of durable insights from experiment runs — confirmed root causes,"
tags: [experiments, findings]
timestamp: 2026-08-04T20:56:36+03:00
---

Source: `experiments/insights.md`

# Experiment Insights

Running log of durable insights from experiment runs — confirmed root causes,
localized bottlenecks, and corrections to prior assumptions. This is **not** a
report archive (see `<mode>/reports/` for that) — only things worth carrying
into future runs and design decisions. Newest entries at the bottom.

Each entry: what the run showed, the confirmed root cause, and a "carry
forward" takeaway for future runs.

---

## 2026-06-27 — 10k-connection DPDK run: bottleneck is the t3.micro endpoints, not the SmartNIC data plane

**Source:** `experiments/dpdk/reports/integration-test-report-2026-06-27.md` (`run-10k.log`, `IPERF_PARALLEL=10000`)

At 10k parallel connections, the 0-RTT data plane itself worked correctly for
every flow it saw — `ClientNIC dpdk-forwarder: 0-RTT flow table activity
confirmed` and `ServerNIC dpdk: translation activity confirmed` both passed.
The failures were downstream: 484 flows never logged a
`first_outbound_payload`/`first_inbound_payload` metric event, and flows that
did complete had FCT of 30–64s and `server_gap` of 47–74s — orders of
magnitude above expected. The server log showed a wall of `recvn abort
failed` lines: thousands of failed/aborted iperf2 connect attempts queuing up
behind the ones that eventually succeeded.

**Root cause:** the Client/Server `t3.micro` endpoints, not the SmartNICs.
iperf2 is thread-per-connection; a t3.micro's 1 GiB RAM + burstable 2 vCPU
cannot service a synchronized burst of 10k connection attempts. Per
`docs/capacity-model.md` §10, a t3.micro realistically holds "~20–30k
connections at minimum buffers, realistically fewer" — 10k is already
straining it, not comfortably inside margin.

**Carry forward:** at scale, don't default to SmartNIC/DPDK explanations
(mbuf pool, flow table sizing, cycles/packet) for symptoms like stalled FCT
or missing payload events — check endpoint capacity first.
`docs/capacity-model.md` §11 orders the investigation "outside-in" for this
exact reason: endpoint RAM/socket count is ceiling #1, SmartNIC CPU is #6.

---

## 2026-06-27 — The `full-dpdk-endpoint-interfaces` 3rd ENI does not address endpoint (Client/Server) scaling

**Source:** `openspec/changes/full-dpdk-endpoint-interfaces/proposal.md` ("Why" + Non-Goals section), cross-checked against the 10k-run root cause above

Each SmartNIC now provisions a 3rd ENI (1 kernel/SSM management + 2 vfio-pci
data ENIs), which reads like a capacity upgrade but isn't one. It fixes a
different, SmartNIC-internal problem: the AF_PACKET endpoint-facing kernel
sockets on ClientNIC/ServerNIC themselves were the source of egress
backpressure and RX tail-drop (kernel `sndbuf`/qdisc filling, a `sendto`/
`recvfrom` syscall per packet). Moving those ports to the DPDK ENA PMD
removes that kernel queue structurally. The extra ENI is just a side effect
of vfio-pci binding taking over an entire NIC — a separate, always-kernel-
bound management ENI is required to keep SSM reachable.

**Carry forward:** the proposal explicitly lists "Not re-tuning flow-table
sizing or the 100k sysctls" as a non-goal. Don't expect this change to move
the needle on the t3.micro endpoint bottleneck above — that's tracked
separately under issue #20 (endpoint upsizing + load generator). These are
two distinct bottlenecks in two distinct layers (SmartNIC I/O vs. endpoint
capacity), and fixing one says nothing about the other.

---

## 2026-06-28 — A run where *every* metric reads "no samples found" is a harness failure, not a data-plane result

**Source:** `experiments/dpdk/reports/integration-test-report-2026-06-28.md` (5 FAILURES)

The report is scored as five data-plane failures, but nothing in it is
evidence about the data plane. The ClientNIC log goes straight from
`Entering busy-poll loop...` to `Shutting down...` with zero
`SYN: spoofed SYN-ACK sent` lines; ServerNIC likewise logs no flows. Client
Output, Server Log, and Packet Analysis are all empty blocks. Both NICs
initialized cleanly (ENA PMD probed, ports up, correct gateway MACs) — no
traffic ever reached them. Two things in the log are worth noting as
suspects: the run hard-reset to `bfc942c`
("perf(dpdk): cap tx retries at 8 to avoid head-of-line collapse under
load") **and** ran with `SKIP_BUILD=1`, so the binary that executed was
whatever was already on disk, not the commit under test.

**Carry forward:** before reading a failing report as a data-plane finding,
check whether the forwarder logged *any* SYN. If it didn't, the failure is
upstream (client never ran, iperf timed out, routing/ARP, or the run never
started). Separately: `SKIP_BUILD=1` combined with a git hard-reset is a
silent lie — the report claims to test a commit whose code was never
compiled. Only use `SKIP_BUILD=1` when the tree hasn't moved since the last
build, and treat "which binary actually ran" as something the report should
state.

---

## 2026-07-14 (retrospective, all DPDK + baseline runs) — TTFB, the metric this project exists to improve, has never once been measured

**Source:** the Latency Summary block of every report in
`experiments/dpdk/reports/` and `experiments/baseline-tcp/reports/`

In all four DPDK reports — including the fully-passing 2026-06-23 run — four
of the seven latency lines are identical:

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
```

The three baseline reports (2026-06-09 ×3) are the same story:
`Client TTFB: no samples found`, `Client FCT: no samples found`. The only
numbers ever produced come from the pcap side (`Pcap FCT`, `Send unlock`,
`Server gap`). The one head-to-head TTFB table that exists
(`archive/baseline-report-2026-06-01.md`) was built from an older,
now-replaced TTFB script — those 1.53/1.74/2.91 ms figures cannot be
reproduced by the current harness on either stack.

**Carry forward:** we cannot currently state the project's headline claim
("0-RTT saves ~1 RTT of TTFB") from our own data, and no amount of further
data-plane work changes that. Fixing the in-app TTFB/FCT emitters (client
and both NICs) is the highest-leverage measurement task open, ahead of any
scale or throughput tuning. Until then, don't report TTFB numbers, and
treat any report whose Latency Summary is mostly "no samples found" as
having measured the *mechanism* but not the *benefit*.

---

## 2026-07-14 (retrospective) — `send_unlock` is the metric that actually demonstrates 0-RTT, and it works

**Source:** `experiments/dpdk/reports/integration-test-report-2026-06-23.md`
(n=100, ALL PASSED) and `-2026-06-22.md` (n=5)

With TTFB dark, `send_unlock` — time from the client's SYN to its first
payload byte on the wire — is the one metric that directly proves the
spoofed SYN-ACK unblocks the application early. It is healthy and stable:
n=100, min 0.27 ms, median 10.3 ms, max 30.1 ms (2026-06-23); n=5, min
0.39 ms, median 0.95 ms (2026-06-22). The client is sending data ~1–30 ms
after SYN, without ever having waited for the real server SYN-ACK — which
`Server gap` (median 213 ms on the same run) shows arrives far later.

**Carry forward:** `send_unlock` vs `server_gap` on the same flow is the
cleanest 0-RTT evidence we have and should be the primary chart in any
write-up. It is also the check to watch for regressions — if a data-plane
change breaks the spoof, `send_unlock` collapses toward `server_gap` long
before FCT or pass/fail counts notice.

---

## 2026-07-14 (retrospective) — Per-flow throughput through the 0-RTT path is ~100× below the kernel baseline, and nobody has measured this on purpose

**Source:** `integration-test-report-2026-06-23.md` (iperf2, 100 conns) vs
`baseline-tcp/reports/baseline-report-2026-06-09*.md` (iperf3, 20 sequential)

Baseline kernel forwarding moves 640–896 KB per connection at
**735–1051 Mbit/s** receiver-side, completing in ~10 ms. The passing DPDK
0-RTT run moves 1 MB per connection at **0.23–1.6 Mbit/s** per stream,
~6 Mbit/s aggregate, with per-connection times of 5–37 s. The comparison is
not apples-to-apples (iperf3 sequential single-stream vs iperf2 25-way
parallel; different transfer sizes; the 0-RTT run's aggregate is split 25
ways) — but a 2-orders-of-magnitude gap is far too large to be explained by
those differences alone. The long tail is the tell: within a single 25-way
port group, flows range from 1.62 Mbit/s down to 0.24 Mbit/s and FCT from
5.3 s to 38.5 s. That spread is the signature of drops plus TCP RTO
back-off, not of a clean bandwidth ceiling being shared fairly.

**Carry forward:** run one deliberate throughput comparison — same iperf
version, same stream count, same transfer size, baseline stack vs DPDK stack
— before drawing any conclusion. But plan for the answer to be bad: a
single-core busy-poll loop with one leg still on AF_PACKET is the obvious
suspect, which makes this the first hard number the
`full-dpdk-endpoint-interfaces` change should be judged against. 0-RTT that
costs 100× throughput is not a win, and right now we cannot prove it doesn't.

---

## 2026-07-14 (retrospective) — Intra-VPC RTT is too small for 0-RTT to show a benefit; the demo needs emulated WAN latency

**Source:** `archive/baseline-report-2026-06-01.md` (Comparison section),
corroborated by `archive/integration-test-report-2026-03-12.md`

Baseline TTFB inside the VPC is 1.53–1.93 ms. One RTT — the entire thing
0-RTT eliminates — is a fraction of that. The saving the README claims
(50–200 ms) is a WAN-scale number and is structurally unobservable on this
topology: even a perfect implementation would land inside the baseline's own
1.5–5.7 ms jitter. The Scapy-era runs "showed" a 83–199 ms 0-RTT lead only
because userspace Python added 100–200 ms of its own processing delay
(`2026-03-12`, Check 3 note) — i.e. the lead was an artifact of the
middlebox being slow, not of the network being far.

**Carry forward:** any TTFB benefit claim needs injected latency (`tc netem
delay 50ms` on the Middle subnet legs, or a genuinely distant endpoint).
Without it, the correct headline is "0-RTT adds no measurable TTFB cost
intra-VPC and the mechanism is proven correct" — which is honest, and is not
the same claim as "saves 1 RTT". Build the netem knob into
`experiments/dpdk/run_experiment.sh` so latency is a run parameter, not a
manual step.

---

## 2026-07-14 (retrospective) — Two recurring harness traps: kernel-vs-datapath races, and validator failures that aren't data-plane failures

**Source:** `archive/integration-test-report-2026-03-07.md` (kernel race),
`archive/baseline-report-2026-05-31.md` (0/20), and
`dpdk/reports/integration-test-report-2026-06-22.md` (`missing=SYN-ACK`)

Three failures across the history share a shape — the harness, not the code,
produced the result:

1. **Kernel forwarding raced and beat the data plane.** With `ip_forward=1`
   and no block, the kernel forwarded SYN and real SYN-ACK at line rate
   while Scapy was still parsing the SYN. Connections *succeeded* — via the
   kernel — and the 0-RTT path was never exercised; the spoofed SYN-ACK
   arrived 58–373 ms *late*. It took `iptables FORWARD DROP` on port 8080 to
   force traffic through the pipeline (`2026-03-12` was then the first true
   pass). The DPDK/vfio-pci design kills this class of bug by construction —
   the kernel cannot see the port at all — which is a real, underrated
   argument for full-DPDK on BlueField, beyond raw speed.
2. **Rebinding NICs to run the baseline broke the baseline.** The 2026-05-31
   baseline scored 0/20 because it ran on the DPDK stack with eth1 flipped
   vfio-pci → ena → vfio-pci around the run. The dedicated `infra/baseline`
   stack (used from 2026-06-01) passes every time. Never measure baseline by
   un-binding the DPDK stack.
3. **The validator reports failures the data plane didn't cause.** The
   2026-06-22 run is scored "1 FAILURE" on the strength of a single
   `missing=SYN-ACK flow=unknown` line — while all 5 flows spoofed, stamped,
   translated, and completed correctly. A validator finding it cannot
   attribute to a flow is a parse gap, not a defect.

**Carry forward:** read the failure count as a *pointer*, never as the
finding. Confirm any failure against the forwarder/translator logs before
touching data-plane code, and consider teaching the validator to separate
"data-plane defect" from "I could not parse this" in its output.

---

## 2026-08-04 — First valid baseline-vs-0-RTT comparison: send_unlock drops a full RTT, FCT does not move

**Source:** `experiments/baseline-tcp/reports/baseline-report-2026-08-04-200506.md`
and the matching DPDK run, both at `LOAD_PARALLEL=2000 LOAD_RATE=500
LOAD_PORTS=4 LOAD_BYTES=1024 NETEM_RTT_MS=100`, both 2000/2000 connections OK.
First run using the shared `experiments/utils/endpoint.sh` setup, so the two
stacks were configured by identical code.

| Metric (mean) | Baseline | 0-RTT DPDK | Delta |
|---|---|---|---|
| `send_unlock` | 100.835 ms | **0.226 ms** | **-100.61 ms** |
| `send_unlock` p99 | 101.354 ms | 0.421 ms | -100.93 ms |
| `fct` | 201.636 ms | 201.546 ms | -0.09 ms |
| `fct` max | 213.254 ms | 536.628 ms | +323 ms |
| `server_gap` | 0.818 ms | 0.359 ms | -0.46 ms |

**The mechanism works, exactly as specified.** `send_unlock` — first SYN out to
first payload out — falls from one full emulated RTT to effectively zero. The
spoofed SYN-ACK unblocks the client's `connect()` immediately; the saving is
100.6 ms against a modelled 100 ms RTT, across 2000 flows with a p99 of 0.42 ms.

**But flow completion time is unchanged**, and that is not a measurement
artifact. `src/servernic/dpdk/syn_handler.c` buffers client→server packets in a
PENDING flow entry and only flushes them once the *real* SYN-ACK arrives and the
delta is known (the run logged 97 `buffered` / 79 `flushed`). The real SYN-ACK
is delayed by the full server-egress RTT, so the client's data still cannot
reach the server before t≈100 ms. 0-RTT does not remove the wait — **it relocates
it from the client application to the ServerNIC.**

That distinction is invisible unless `send_unlock` and `fct` are reported
separately, which is why the metric split matters and why FCT alone was never
going to show this.

**Carry forward:**
- The honest headline is "0-RTT eliminates one RTT of *application* blocking
  time", not "0-RTT makes connections complete a round-trip sooner". Both are
  now measured; only the first is true.
- Whether the second is achievable is a real design question: it needs the
  ServerNIC to forward client data before it knows the real ISN, which the
  ISN-ack-num translation scheme does not currently allow.
- The FCT tail regressed sharply (max 537 ms vs 213 ms baseline) while p99 did
  not. Cause not established — see the dedicated entry below. Do not run at
  100k scale before it is understood.

---

## 2026-08-04 — `tc` was never installed, so no experiment in this repo's history ran with emulated latency

**Source:** the same pair of runs; found by the netem post-condition check added
to `endpoint_tune()`.

`tc` lives in the `iproute-tc` package, which neither CDK stack installs. Every
netem command the harness has ever issued failed with `tc: command not found`
and was swallowed by its own `2>/dev/null || true`. Every prior run labelled
"50ms netem" actually measured the intra-VPC RTT of ~1.5 ms.

This is the precise condition the 2026-07-14 retrospective predicted would make
a 0-RTT benefit structurally unobservable — and it had been silently true the
whole time. `endpoint_tune()` now installs the package and then *verifies* the
qdisc on both endpoints, failing the run if the server lacks netem or the client
has it.

**Carry forward:** a knob that is applied with `|| true` and never read back is
not a knob, it is a comment. Any environment setting a measurement depends on
must be asserted after it is applied, not assumed from the fact that the command
was issued.

---

## 2026-08-04 — Open: 0-RTT FCT tail reaches 537 ms while p99 sits at 201.6 ms; cause NOT established

**Source:** the 2026-08-04 DPDK run
(`experiments/dpdk/reports/integration-test-report-2026-08-04-smoke.log`),
2000 flows, `NETEM_RTT_MS=100`.

| `fct` | Baseline | 0-RTT DPDK |
|---|---|---|
| p50 | 201.571 ms | 201.368 ms |
| p99 | 202.833 ms | 201.638 ms |
| max | **213.254 ms** | **536.628 ms** |
| max − p99 | 10.4 ms | **335.0 ms** |

More than 99% of 0-RTT flows complete in ~201.5 ms — *tighter* than baseline at
p99. The regression is confined to the top 1% (≤20 of 2000 flows), at least one
of which takes 2.7× the median.

**What the data rules out.** The tail is not in the parts of the path the other
two metrics cover: `send_unlock` max is 2.061 ms (baseline: 112.429 ms) and
`server_gap` max is 0.756 ms (baseline: 12.358 ms). Both 0-RTT tails are tighter
than baseline's. So the excess is neither in the spoofed handshake nor in the
server's own response latency — it is between "client's first payload leaves"
and "flow completes".

**Working hypothesis (UNCONFIRMED): a lost segment paying a retransmission
timeout.** With timestamps, SACK and window scaling all disabled, a single loss
falls back to an RTO, and Linux's `TCP_RTO_MIN` is 200 ms. 200 ms RTO plus one
~100 ms round trip for the retransmission lands at ~300 ms of excess, against
the 335 ms observed. The arithmetic fits; nothing yet proves it.

**Explicitly NOT supported by evidence.** An earlier note in this file guessed
the buffer/flush path in `syn_handler.c`. The captured log contains **zero**
`flush dropped first c2s data` warnings — the counter that exists precisely to
catch that case. It is not ruled out either: the fetched log was **truncated at
the SSM 24 KB cap** (24,355 bytes) and covers only 97 `buffered` / 79 `flushed`
lines, i.e. a prefix spanning well under 100 of the 2000 flows. Treat the
buffer-overflow theory as untested, not disproven.

**The stack has since been terminated**, so the untruncated `/tmp/servernic.log`
is gone. Re-testing requires a redeploy.

**How to resolve it, next run:**
1. Fetch the NIC logs by running `grep -c` **on the node** and returning only
   counts, instead of `cat`-ing a 24 KB prefix — the same fix `--summary`
   already applies to analyzer output.
2. Capture `nstat`/`netstat -s` retransmission counters on both endpoints
   around the run. A non-zero `TcpRetransSegs` confirms or kills the RTO theory
   in one number.
3. Have `analyze_metrics.py --detail-out` identify the specific slow flows, then
   pull just those 4-tuples out of the endpoint pcaps.

---

## Open follow-ups as of 2026-08-04

Tracked here because they came out of a run; `roadmap.md` remains the repo's
source of truth for what is scheduled.

- [ ] **Resolve the FCT tail** (entry above) before any 100k-connection run.
      Blocking, because a tail that is 1% of flows at 2k scale is 1000 flows at
      100k and would dominate any aggregate.
- [ ] **Run both stacks at full scale** (`LOAD_PARALLEL=100000`,
      `LOAD_RATE=2000`, identical on both). Only the 2000-connection smoke has
      been run. Note the port-space and pacing-floor guards both pass at that
      size; the untested part is endpoint capacity under sustained arrival.
- [ ] **Fix NIC-log retrieval past the 24 KB SSM cap.** Both `clientnic.log` and
      `servernic.log` hit it in this run, so every count and grep the harness
      reports over them is scoped to an arbitrary prefix. This actively
      obstructed the FCT-tail diagnosis above.
- [ ] **Restore NIC in-app TTFB instrumentation.** Both `clientnic TTFB` and
      `servernic TTFB` reported "no samples found"; the harness warns that the
      binary may predate the instrumentation. The internal rdtsc view is the
      only thing that can localize latency *inside* the data plane.
- [ ] **Decide whether FCT can be improved at all.** 0-RTT currently relocates
      the RTT wait to the ServerNIC rather than removing it, because the
      translator cannot forward client data before it knows the real ISN. If
      end-to-end completion time is a goal, that is a design change, not a
      tuning one — and it should be specced before more measurement work.
- [ ] **Fix the baseline CDK user-data clone.** The IAM grant added on
      2026-08-04 lets the orchestrator self-heal at run time, but the boot-time
      clone still fails on the expired legacy SSM-parameter token. Changing the
      user-data forces instance replacement, which is why it was left alone.
- [ ] **Consider installing `iproute-tc` in both CDK stacks' user-data.**
      `endpoint_tune()` installs it per-run, which costs ~25 s and needs the VM
      to have package-repo access at run time.
- [ ] **Retire `analyze_metrics.py --iperf-csv`.** Dead since iperf was removed;
      still carries 6 tests.
