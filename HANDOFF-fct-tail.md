# Handoff — Resolve the 0-RTT FCT tail with one `nstat` check

**Created:** 2026-08-08
**Branch:** `fix/measurement-methodology-load-shape`
**Status of the work:** scoped, not started. No stack is deployed.

This item was removed from `roadmap.md` on 2026-08-08 (it was "F1", classified
**Blocking**). It is carried here instead because at PoC scale it does not
justify a roadmap gate — but it does justify ten minutes of work, for one
specific reason stated below.

---

## What the tail is

From the 2026-08-04 baseline-vs-DPDK run pair (2000 conns, 500/s, 4 ports,
1 KB, `NETEM_RTT_MS=100`):

| | baseline | 0-RTT |
|---|---|---|
| `fct` p99 | 202.833 ms | **201.638 ms** (better) |
| `fct` max | 213.254 ms | **536.628 ms** |

The regression is confined to ≤20 of 2000 flows — 335 ms above the 0-RTT
stack's own p99. **2000/2000 connections succeeded on both stacks.** Nothing was
dropped or refused; the affected flows complete, just late.

Already ruled out (do not re-derive):

- **Not the handshake** — `send_unlock` max 2.061 ms vs baseline 112.429 ms.
- **Not the server's response** — `server_gap` max 0.756 ms vs baseline 12.358 ms.
- **Not the ServerNIC flush path** — the captured log has zero
  `flush dropped first c2s data` warnings, the counter that exists to catch
  exactly that. (An earlier session guessed "somewhere in the buffer/flush
  path" and was wrong; the data contradicts it.)

The excess therefore sits between *"first payload leaves"* and *"flow
completes"*.

Full numbers and derivation: `experiments/insights.md` (2026-08-04 entries).
Metric definitions: `experiments/measurement-methodology-review.md`.

---

## The hypothesis, and why one number settles it

One lost segment paying Linux's `TCP_RTO_MIN` (200 ms, `HZ/5` — the hard floor
on the retransmission timeout) plus a ~100 ms retransmit round trip ≈ 300 ms,
against 335 ms observed. The arithmetic fits; nothing proves it.

It is plausible specifically because `endpoint_tune()` disables timestamps, SACK
and window scaling (`experiments/utils/endpoint.sh:57,65`) — the translator does
not rewrite TCP options, so the endpoints must not negotiate them. A 1 KB flow
is one segment, so there are no duplicate ACKs and no fast-retransmit path. The
RTO is the *only* recovery mechanism available.

**The check:** capture retransmission counters on both endpoints around the run.

```sh
# before the load starts, on Client and Server
nstat -n
# after the load completes, on Client and Server
nstat -z | grep -Ei 'retrans|timeout|TCPLoss|TCPTimeouts'
```

Key counters: `TcpRetransSegs`, `TcpExtTCPTimeouts`, `TcpExtTCPSlowStartRetrans`,
`TcpExtTCPLostRetransmit`.

---

## What the user needs to decide — three things, in order

### Decision 1 — when to run it

The stack is terminated, so this needs a redeploy either way. F2 (moving the
emulated WAN to the middle leg) also needs a re-run. Capturing `nstat` during
the F2 run costs nothing extra and answers both questions at once.

**Recommendation: fold this into the F2 run. Do not deploy a stack just for one
counter.**

### Decision 2 — what to do with the number

The two outcomes mean different things and lead to different work. This is the
whole reason the check is worth running.

#### Outcome A — retransmissions are non-zero (≈20, matching the slow-flow count)

Ordinary packet loss recovered by the RTO. **Nothing is wrong with the data
plane.** Decision for the user:

1. Record it in `experiments/insights.md` as resolved and close it out. No code
   change. For a PoC this is a complete answer.
2. Optionally note that the loss source is worth one glance — netem's queue
   (`limit 1000000` is already set in `endpoint.sh:116` to prevent this), the
   ENA ring, or genuine VPC loss. Not required to close the item.

#### Outcome B — retransmissions are zero or near-zero

Then the 335 ms is **not** loss recovery, and the working hypothesis is dead.
That points at the data plane holding or reordering a segment — a real
correctness finding for a PoC whose entire claim is that seq/ack translation is
correct. Decision for the user:

1. Escalate: this becomes a genuine bug hunt, and it *should* re-enter
   `roadmap.md` as blocking.
2. Next steps in that case (all previously identified, all still valid):
   - Use `analyze_metrics.py --detail-out` to name the slow flows, then pull
     only those 4-tuples from the endpoint pcaps rather than reading everything.
   - Read the NIC logs — **blocked on F3**, see below.

### Decision 3 — on Outcome B only, fix F3 first

The 24 KB SSM log cap already blocked this diagnosis once — under 100 of 2000
flows were visible. Chasing a data-plane bug through a truncated log will stall
in exactly the same place. See the blockers section below.

### The one thing not to do

Do not read any FCT number from a server-egress-netem run as a result. Until F2
lands, that metric is measuring the topology, not the design.

---

## Blockers and prerequisites

- **The stack is terminated.** The DPDK stack that produced the 2026-08-04 run
  has been destroyed, and the untruncated NIC logs are gone with it. This needs
  a redeploy — see the `deploy-infra` skill.
- **F3 (NIC log truncation) will obstruct this again.** Both NIC logs hit the
  24 KB SSM cap (24,355 bytes), so any log-derived count covers an arbitrary
  prefix — under 100 of 2000 flows. It already obstructed this diagnosis once.
  If Outcome B happens, fix F3 first or the investigation stalls in the same
  place. Use `grep -c` **on the node** and return only the number, rather than
  cat-ing a prefix back. Tracked in `roadmap.md` under Measurement flaws.
- **F2 is still open and still blocking the FCT claim itself.** Until the
  emulated WAN moves to the ClientNIC↔ServerNIC leg, "0-RTT does not improve
  FCT" is an artifact of netem placement, not a result. Do not draw conclusions
  about FCT from a server-egress-netem run. Details:
  `experiments/measurement-methodology-review.md` §E.

---

## Related context worth knowing

- `roadmap.md` → **Measurement flaws** section holds F2–F16, the classification
  this item was extracted from.
- `experiments/measurement-methodology-review.md` §E was added in this session:
  what the emulated WAN is, `netem`/qdisc mechanics, and the four-placement
  proof that no endpoint-side netem position can show an FCT win.
- The 0-RTT claim as currently measured is *"eliminates one RTT of application
  blocking time"* (`send_unlock` 100.835 → 0.226 ms, proven), **not**
  *"connections complete a round-trip sooner"* (`fct` −0.09 ms). The second is
  expected to become true once F2 lands.

---

## Suggested skills

- **`run-experiment`** — to execute the run and diagnose failures across the
  4-node chain. This is the primary skill for the actual work.
- **`deploy-infra`** — the stack is terminated; this redeploys it. Also covers
  the GitHub Actions path if no local AWS credentials are available.
- **`offline-analysis`** — if the run is executed via the
  `run-experiment.yml` workflow and results land in `experiments/ci-results/`,
  use this to read the bundle rather than re-running anything.
- **`engineering-rigor:systematic-debugging`** — only on Outcome B, where this
  stops being a measurement question and becomes a data-plane bug hunt.
- **`spec-planning:openspec-propose-change`** — only if Outcome B escalates into
  a design change rather than a fix.

Do **not** reach for `openspec-propose-change` on Outcome A. Recording a
resolved observation in `insights.md` is the whole deliverable there.

---

## Uncommitted state on this branch

`roadmap.md`, `CLAUDE.md`, `experiments/measurement-methodology-review.md` and
`open-sessions.txt` all have uncommitted edits from this session. Nothing has
been committed or pushed.
