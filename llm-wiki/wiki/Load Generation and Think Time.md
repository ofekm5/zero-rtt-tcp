---
type: Wiki Entry
title: "Load Generation and Think Time"
description: "Why loadgen.py beats iperf2 for this topology, what iperf2 is still the right tool for, and why a client think-time sweep must follow the netem fix rather than replace it."
tags: [experiments, methodology, loadgen, iperf]
timestamp: 2026-08-08T18:53:12+03:00
---

Analysis, 2026-08-08. Not mirrored from any repo doc — this entry is the only
home for it. Derived from [[raw/2026-08-08-telemetry-review-artifact]] plus
direct reading of `experiments/utils/loadgen.py`,
`experiments/utils/analyze_metrics.py` and `experiments/utils/endpoint.sh`.
Companion: [[wiki/Measurement Methodology]].

# Load Generation and Think Time

## Neither tool generates packets

`loadgen.py` and iperf2 both hand bytes to the Linux TCP stack, which builds the
segments. The packet path is identical. The difference is entirely in the
userspace half:

| | iperf2 | `loadgen.py` |
|---|---|---|
| Concurrency model | thread per stream | coroutine per connection, one thread |
| Cost per connection | ~8 MB stack + scheduler slot | a few KB |
| Practical ceiling | ~thousands of streams | ~100k connections |
| Per-syscall CPU | native C | interpreter overhead (~100×) |
| Good at | sustained bytes on few flows | many short flows, paced arrivals |

## Verdict for this topology

**`loadgen.py` is the correct tool.** The experiment's subject is *many short
connections* — 100k of them at the target scale — and iperf2's thread-per-stream
model cannot hold that many. Asyncio coroutines can.

The obvious objection — that a Python event loop is a poor instrument — does not
bite here, for two reasons:

1. **The metrics do not come from the generator.** `send_unlock`, `fct` and
   `server_gap` are all derived by `analyze_metrics.py` streaming `tcpdump -r`
   over endpoint pcaps, keyed on SYN 4-tuples. The analyzer is tool-agnostic:
   point it at an iperf2 run and the numbers come out the same way.
2. **The residual overhead is negligible against the signal.** The one place
   Python can contaminate a measurement is the gap between `connect()` returning
   and `send()` being called, which lands inside `send_unlock`. Measured p99 is
   0.42 ms against a 100 ms modelled RTT — roughly 240× smaller than the effect.

At the current profile (500 conn/s × 1 KB) that is ~500 syscalls per second.
Python is nowhere near its limit.

**iperf2 remains the right tool for exactly one thing:** sustained bytes on few
flows. That is the unmeasured throughput question (roadmap flaw F8, and the
unresolved 2026-07-14 "~100× slower" finding). Keep it for that and nothing
else. Two tools, two jobs — do not nest them; spawning iperf under `loadgen.py`
gives thread-scaling limits on a connection-count workload with no measurement
benefit, since the pcaps already do the measuring.

Related: `loadgen.py`'s self-reported timings are roadmap flaw **F6** (bound them
by comparing against pcap `send_unlock` before any 100k run); its pacing being a
ceiling rather than a guarantee is **F7**.

## Client think time (`T`) — a real axis, not a repair

`loadgen.py`'s `_client_conn()` currently does `connect()` → `write(1 KB)` →
`write_eof()` → `close()`, with zero think time. Adding a `T` ms pause between
connect and write changes the arithmetic, keeping the *current* server-egress
netem placement:

- Baseline: connect returns ≈101.5 ms, wait `T`, write, response returns →
  **FCT ≈ 203 + T**
- 0-RTT: connect returns ≈0.2 ms, wait `T`, write → ServerNIC buffers until the
  ISN is known at 101.5 ms → **FCT ≈ max(0.2 + T, 101.5) + 100**

| `T` | baseline FCT | 0-RTT FCT | gain |
|---|---|---|---|
| 0 ms (today) | 203 ms | 201.5 ms | ~0 |
| 25 ms | 228 ms | 201.5 ms | 26 ms |
| 50 ms | 253 ms | 201.5 ms | 51 ms |
| 100 ms | 303 ms | 201.5 ms | **101 ms (full RTT)** |
| 200 ms | 403 ms | 300 ms | ~103 ms |

Once `T ≥ RTT`, the ServerNIC's buffer wait is entirely hidden behind the
client's own think time, and 0-RTT recovers a full RTT of FCT **without touching
netem placement**. Implementation cost is one `asyncio.sleep()` — roughly three
lines — against F2's DPDK TX FIFO.

### Why that is not a shortcut

**Order decides whether this is realism or number-fixing.**

- **Think-time sweep *instead of* fixing F2** → fixing results. The apparent gain
  exists only because a measurement artifact interacts favourably with a workload
  knob chosen for that purpose.
- **Think-time sweep *after* fixing F2** → legitimate characterisation. At `T=0`
  the corrected topology already yields a full-RTT FCT win; the sweep then shows
  the gain is *robust across* think times rather than *dependent on* them.

Two points that settle it:

- **`T=0` is not unrealistic — it is the target workload.** HTTP connects and
  sends its request immediately. That is the majority of real short flows and
  precisely the case 0-RTT is designed for. Adding think time tests a *different*
  client, not a more realistic one.
- **F2 is a bug; `T` is a dimension.** F2 means the experiment measures the
  topology instead of the design. Adding an axis never repairs a wrong
  measurement on the existing one.

If run after F2, the sweep answers a real and separate question — *how much of
0-RTT's benefit survives a client that does not send immediately?* — and the
honest headline for the current data stays: at `T=0`, on a correct topology, one
RTT off both blocking time and completion time.

Distinct from [[wiki/Roadmap]]'s "multi-round send" item (flaw **F9**), which is
about steady-state translation across several segments, not about the delay
before the first one.
