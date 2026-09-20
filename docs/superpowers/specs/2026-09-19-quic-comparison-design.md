# QUIC comparison — design

## Problem

The 0-RTT TCP claim is currently measured against one reference, plain TCP. A reader
will ask how it compares with QUIC, the protocol that removed the handshake round trip
by leaving TCP. Today the repo has no UDP endpoint and no way to answer.

Facts from the codebase that shape the fix:

- The headline metric is `send_unlock`: time from connect start until the client
  application is allowed to write (`docs/kb/wiki/Measurement Methodology.md`, B2). It is
  taken on the client alone, so it needs no cross-VM clock sync. QUIC has the same
  event, so the definition carries over unchanged.
- `fct`, `server_gap` and the pcap `send_unlock` parse TCP segments from `tcpdump -r`
  text. QUIC payloads are encrypted, so none of that applies to a QUIC flow.
- The baseline stack (kernel-routed NIC VMs) has no DPDK data plane, so QUIC needs no
  `src/` change. Its security group allows all traffic from `10.1.0.0/16`
  (`infra/baseline/cdk/smartnics_stack.py:159`), and the emulated WAN is a
  `tc qdisc ... root netem delay` on the interface, which delays UDP as it does TCP
  (`experiments/utils/endpoint.sh`).
- `loadgen.py` is an asyncio TCP client/server with paced arrivals. It emits no
  `metric=` lines today; metrics come from pcap.

## Non-Goals

- **A TCP+TLS1.3 arm.** Rejected in framing: the claim is about the handshake, not
  about encryption parity. Recorded so the plaintext-vs-TLS asymmetry is stated in the
  report, not silently ignored.
- **`fct`, `server_gap` and any congestion-control or loss comparison.** QUIC's edge
  there depends on loss handling, which is roadmap "Packet-loss handling", not built.
- **Wire-level (pcap) verification of QUIC 0-RTT.** Deferred, not rejected: it is the
  escalation path (A2) described under Key Constraints.
- **Any change to `src/`, to the DPDK stack, or to how the 0-RTT and TCP arms measure.**
- **Anti-replay handling for QUIC 0-RTT.** The server accepts replayed tickets; this is
  a measurement rig, not a service.

## Goal

Add QUIC as two more arms (cold and resumed) on the baseline stack and report one
comparable number per arm — client-side `send_unlock` — so the write-up can say how
0-RTT TCP's time-to-first-write compares with QUIC cold (1-RTT) and QUIC resumed
(0-RTT). Four arms, four separate runs at identical parameters: TCP baseline, 0-RTT TCP
(DPDK stack), QUIC cold, QUIC resumed.

## Success Criteria

*Proposed — awaiting approval.*

- [ ] The QUIC client reports `send_unlock` for a cold connection and for a resumed one,
      plus whether the server accepted early data — measured by:
      `pytest experiments/tests/test_loadgen_quic.py -q`
- [ ] Offline, on loopback with no netem, a resumed connection's `send_unlock` is
      smaller than the cold one's and early data is reported accepted — measured by:
      the same pytest command
- [ ] `loadgen.py` is byte-identical to `main` — measured by:
      `git diff --exit-code main -- experiments/utils/loadgen.py`
- [ ] Four reports exist at identical `NETEM_RTT_MS`, connection count and arrival rate
      (the rate chosen by the loopback spike): TCP baseline, 0-RTT TCP, QUIC cold, QUIC
      resumed — measured by: the four files under `experiments/baseline-tcp/reports/`
      and `experiments/dpdk/reports/` (manual, needs AWS)

## Architecture Impact

```
Client VM ── ClientNIC VM ═(netem RTT)═ ServerNIC VM ── Server VM     (baseline stack)
 loadgen.py | _quic.py     kernel routing                               loadgen.py | _quic.py
 (PROTO=tcp|quic)        UDP passes like TCP                          (PROTO=tcp|quic)
```

```diff
 experiments/utils/loadgen.py
   (unchanged)
+experiments/utils/loadgen_quic.py     # new: aioquic client/server, per-conn send_unlock
 experiments/nodes/{client,server}.sh
+  PROTO=quic runs loadgen_quic.py; openssl cert, pip aioquic          # modified
 experiments/run.sh  (STACK=baseline)
+  PROTO=quic|tcp, QUIC_RESUME=0|1, report rows                        # modified
```

| Component | Path | Change | Responsibility after |
| --- | --- | --- | --- |
| QUIC load generator | `experiments/utils/loadgen_quic.py` | new | QUIC client/server with the same paced-arrival shape as `loadgen.py`; prints `send_unlock` percentiles and early-data acceptance |
| QUIC test | `experiments/tests/test_loadgen_quic.py` | new | Loopback cold-vs-resumed check |
| Node scripts | `experiments/nodes/client.sh`, `server.sh` | modified | Install `aioquic`, make a self-signed cert, pass the flags |
| Orchestrator | `experiments/run.sh` | modified | Runs the QUIC arm on the baseline stack, adds report rows |

**Dependencies and data flow.** New dependency `aioquic` (pure Python + `cryptography`),
installed on the two endpoint VMs only. Data flow: the client prints its metric lines to
stdout; the orchestrator already captures client stdout.

**Contracts and boundaries.** `loadgen.py` is untouched. `loadgen_quic.py` has its own
flags (`--resume`, `--cert`, `--key`) and prints a `quic_summary` line.

**Blast radius.** The TCP path cannot regress because its file is not edited. No NIC VM,
CDK stack or `src/` file changes. The arrival rate for all four arms drops below the
500/s of past reports, so these runs are not comparable to earlier numbers.

**Depends on** `streamline-experiments-harness` (single `experiments/run.sh`,
`experiments/nodes/`). Paths above assume it has landed.

## Alternatives Considered

### 1. App-side `send_unlock` in `loadgen_quic.py` — **chosen (A1)**

Timestamp in the client, from connect start until the first write is permitted. Same
definition as the existing headline metric, single clock, no pcap work. Costs: it trusts
the library's report of 0-RTT rather than the wire. Verdict: chosen, because it is the
smallest thing that answers the question.

### 2. A1 plus wire cross-check from QUIC header bits (A2)

Long-header type "0-RTT" and the first short-header packet are unencrypted, so the
client pcap can show whether early data really left. It also catches silent fallback to
1-RTT. Costs: new parsing in `analyze_metrics.py`. Verdict: **deferred — do this if the
A1 results do not look good** (triggers below).

### 3. QUIC mode as a `--proto` flag inside `loadgen.py`

One tool and shared pacing, but every TCP run on both stacks would share a file with new
QUIC code. Verdict: rejected; a separate file costs ~50 duplicated pacing lines and
removes the regression risk.

### 4. TCP+TLS1.3 versus QUIC on equal cryptographic footing

More rigorous on encryption, but adds a TLS arm and moves the story from the handshake
to the crypto stack. Verdict: rejected for this change.

## Key Constraints

- **Escalate to A2 when the A1 numbers look wrong.** Concretely, any of: QUIC cold
  `send_unlock` is not close to `NETEM_RTT_MS`; QUIC resumed is not clearly below cold;
  early data is reported accepted on fewer than all resumed connections; resumed
  `handshake_ms` (kept as a diagnostic) equals cold, which means resumption silently
  fell back. Any one of these means the library's own report cannot be trusted alone.
- **Every `verify:` runs offline** — no AWS, no live VMs, no Docker. The QUIC test uses
  loopback.
- **State the asymmetry in the report.** The TCP and 0-RTT arms are plaintext; QUIC
  always encrypts.
- **Same `NETEM_RTT_MS`, connection count and arrival rate** across all four runs, or
  the comparison is meaningless.
- **Lower arrival rate.** `aioquic` is pure Python and does a TLS handshake per
  connection; at 500/s client CPU could inflate `send_unlock` with event-loop queueing,
  biasing against QUIC. A loopback spike finds the highest sustained cold-handshake rate
  and the runs use about half of it. The TCP baseline and the DPDK 0-RTT arm rerun at
  that rate.
- **One ticket, reused.** One priming connection per client process; every flow resumes
  from it. Flows are therefore all "returning users", which is stated in the report.
- **Comparison by hand.** The four `send_unlock` numbers are pasted into
  `docs/index.html`; no merge script.

## Not yet specified

- The arrival rate value itself: fixed by the Task 3 spike, then recorded here.
