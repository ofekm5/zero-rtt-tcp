---
type: Wiki Entry
title: "Known Limitations"
description: "Acknowledged, out-of-scope limitations of the 0-RTT PoC — scale beyond the measured load, and the spoofing-amplifier exposure. Not planned work."
tags: [project, limitations]
timestamp: 2026-09-19T00:00:00+03:00
---

Source: `roadmap.md` → "Out of scope: scale beyond the measured load" (removed
from the roadmap 2026-09-19; this is now its only copy). `docs/index.html` §6
carries the same statement.
See also: [[wiki/Roadmap]], [[wiki/Capacity Model]]

# Known Limitations

**Acknowledged limitations, not planned work.** No figure in `docs/index.html`
depends on either. Two roadmap ideas re-open them — *DDoS: purge delta rows* and
*Scale up experiments on BlueField* ([[wiki/Roadmap]]); read this first if
either is picked up.

## Scale beyond the measured load

The measured claim rests on 2000-flow runs at 500 conn/s. Concurrency there is
roughly 50-100 flows in flight (arrival rate x mean FCT), well under the 2000 the
`LOAD_CONCURRENCY=2000` cap allows — at that volume the cap never binds, so 2000
*concurrent* flows are not demonstrated either. Runs at 100,000 total flows have
never completed:

| Run | Plain TCP | 0-RTT |
| --- | --- | --- |
| 2026-07-25 (unpaced) | — | 68,779 / 100,000 |
| 2026-08-11 | 100,000 / 100,000 | 84,143 / 100,000 |
| 2026-08-17 | 99,728 / 100,000 | 87,073 / 100,000 |

Both 2026-08-17 runs also failed their endpoint metric check (326 and 171
unresolvable metric events), and latency at that load is queueing rather than
path (plain TCP p95 blocking reached 64.1 s). The harness is therefore implicated
alongside the data plane.

**What is not established:** that the shortfall is unrelated to the 0-RTT
mechanism. Under identical conditions baseline lost 0.3% where 0-RTT lost 12.9%,
an asymmetry shared infrastructure limits would not produce. The defensible
statement is "not demonstrated at scale", not "limited by infrastructure" — the
latter is a finding, and the runs do not support it.

Sketched and not pursued: RSS/multi-queue, SYN-cookie-style backpressure, arrival
pacing (landed, and did not close the gap), and a pre-generated ISN pool in place
of per-SYN `rte_rand()`.

If this is ever re-opened, one measurement defect comes first: `loadgen.py`
reports achieved arrival rate from coroutine-spawn timing, not from connection
establishment (`_client_conn` takes the semaphore inside the task, so the spawn
loop never blocks on it). Every 100k arrival-rate figure recorded so far is
unreliable on that axis.

## Spoofing amplifier

The design is structurally a spoofing amplifier — ClientNIC answers every SYN
before the server has agreed to anything, so a spoofed source gets a SYN-ACK
sent to a third party and every SYN costs flow-table state on both SmartNICs.
Stated, not defended: this is an isolated lab with no untrusted clients, and any
real mitigation (SYN cookies, admission control) is more machinery than the
result needs.
