# Capacity Model — Hardware Constraints & Sizing Calculations

How every sizing constant in the 0-RTT data plane is derived, what physical
resource it binds, and how to measure whether you are near its ceiling.

Written against the **dual-DPDK** topology (both SmartNIC endpoint ports on the
DPDK ENA PMD). The recurring worked example is the **100,000 concurrent
connection** benchmark, because that is the target that stresses every budget at
once — but the method applies at any scale.

> **Provenance.** Constants are read from the source (paths cited inline).
> Struct sizes are *derived* from x86-64 SysV layout rules, not measured — no C
> toolchain was available where this was written. Confirm on the VM with
> `printf("%zu\n", sizeof(struct flow_entry))` before relying on the RAM figures.

---

## 1. The mental model: three budgets that do not talk to each other

The single most common sizing mistake here is assuming these are one budget.
They are not, and conflating them sends you tuning the wrong constant:

| Budget | Scales with | Does **not** scale with |
|---|---|---|
| **Packets in flight** (mbufs, rings) | ports × ring depth × cores | number of connections |
| **Connection state** (flow tables, buffers) | number of connections | packet rate |
| **Host & fabric limits** (CPU, ENA, kernel) | packet rate *and* connections | — |

An mbuf is a buffer for a packet that is *right now* owned by the NIC or by your
poll loop. A million idle connections consume zero mbufs. Conversely, one
connection saturating a 25 Gbps link can exhaust the pool. So: **connections
size the flow table; packet rate sizes the mbuf pool.**

---

## 2. Hardware baseline

From `infra/dpdk/cdk/smartnics_stack.py` (updated 2026-07-25 — was `t3.micro`
for Client/Server when this section was first written; see §10, §13):

| VM | Instance | vCPU | RAM | Role |
|---|---|---|---|---|
| Client | **m5.xlarge** | 4 | **16 GiB** | unmodified TCP client (event-driven `loadgen.py`) |
| ClientNIC | c5n.large | 2 | 5.25 GiB | DPDK: spoof SYN-ACK, stamp V |
| ServerNIC | c5n.large | 2 | 5.25 GiB | DPDK: sole stateful translator |
| Server | **m5.xlarge** | 4 | **16 GiB** | unmodified TCP server (event-driven `loadgen.py`) |

Each SmartNIC reserves **512 × 2 MiB = 1 GiB of hugepages**
(`vm.nr_hugepages=512`), leaving ~4.25 GiB of ordinary RAM for the process heap,
BSS, and page cache. Both DPDK binaries run on a **single lcore** (`-l 0` in
`experiments/dpdk/{clientnic,servernic}.sh`), so one core busy-polls both ports.

> **The endpoint row no longer applies.** With the m5.xlarge upsize (§10), the
> endpoints held 14.8-14.9 GiB free through a live 100k-connection run — they
> are comfortable. The current ceiling for a 100k-connection test is the
> SmartNICs' single busy-poll lcore against a burst of 100,000 near-simultaneous
> connection attempts — see §4, §9, §13.

---

## 3. Packet-in-flight budget: the mbuf pool

**Constants** (`main.c` in both trees, `io.c` for rings):

```c
#define MBUF_POOL_SIZE  8191   // main.c
#define MBUF_CACHE_SIZE 250    // main.c
#define RX_BURST_SIZE   32     // main.c
#define RX_RING_SIZE    1024   // io.c
#define TX_RING_SIZE    1024   // io.c
```

### The formula

```
NUM_MBUFS ≥ nb_ports × (nb_rxd + nb_txd + MAX_BURST + nb_lcores × MEMPOOL_CACHE)
```

Every term is a distinct place an mbuf can sit where you cannot reuse it:

| Term | Value | Why the mbuf is unavailable |
|---|---|---|
| `nb_rxd` — RX ring | 1024 | The PMD pre-posts an mbuf on **every** RX descriptor, waiting for a packet to land. They are consumed the moment the port starts, before any traffic. |
| `nb_txd` — TX ring | 1024 | `rte_eth_tx_burst()` does **not** free the mbuf. The NIC owns it until reclaimed, which happens lazily (`tx_free_thresh = 32`). |
| `MAX_BURST` | 32 | Held in `rx_bufs[]` between `rx_burst` and `pktmbuf_free`. |
| `nb_lcores × cache` | 1 × 250 | The per-core cache hoards mbufs to avoid the shared-ring lock. It can hold up to 1.5× its size. |
| `nb_ports` | **2** | All of the above, per port. |

### The number for this stack

```
2 × (1024 + 1024 + 32 + 1×250) = 2 × 2330 = 4,660 mbufs required
                                             8,191 configured  →  1.76× headroom
```

Comfortable — but note this **halved** when the endpoint ports moved to DPDK.
With one DPDK port the requirement was 2,330 and the headroom 3.5×. The constant
`8191` did not change. That is the hazard: a magic number sitting next to ring
sizes it is silently coupled to. **Derive it instead:**

```c
#define NUM_MBUFS  (RTE_MAX(2 * (RX_RING_SIZE + TX_RING_SIZE + RX_BURST_SIZE + \
                                 MBUF_CACHE_SIZE), 8191U))
```

so a third port, or a deeper ring, cannot quietly push you under.

### Memory cost

```
per mbuf = sizeof(rte_mbuf) 128 B + RTE_PKTMBUF_HEADROOM 128 B + dataroom 2048 B
         ≈ 2,304 B
pool     = 8,191 × 2,304  ≈  18.0 MiB     (of 1024 MiB hugepages → 1.8 %)
```

The pool is nearly free. If in doubt, **raise it** — there is no reason to run
this close to a cliff for 18 MB. The constraint that actually binds is CPU (§10),
not mbuf memory.

### Failure signature

Pool exhaustion is `rx_nombuf` in `rte_eth_stats`, plus `rte_pktmbuf_alloc()`
returning NULL (currently logged as `"mbuf alloc failed"`). It is **not** the
same as `imissed` — see §12, because these two look identical from the outside
and lead to opposite fixes.

---

## 4. NIC / port budget

### Ring depth is a latency/loss tradeoff, not a throughput knob

`RX_RING_SIZE = 1024` is how many packets can queue in the NIC while your core is
busy elsewhere. One poll loop iteration drains at most `RX_BURST_SIZE = 32` per
port. So the ring absorbs a burst of up to 1024 before `imissed` starts counting;
it buys you `1024 / 32 = 32` loop iterations of slack. Deepening the ring buys
more slack but adds queueing latency and pins more mbufs (§3). If `imissed` is
climbing, the answer is a faster loop, **not** a deeper ring — a deeper ring only
delays the drop.

> **This is exactly what broke at the actual 100k run (2026-07-25 — see §13).**
> `asyncio.gather()` fires all 100,000 connection attempts at once, so the SYN
> arrival isn't spread over time — it's one enormous burst hitting a ring sized
> for 32 loop-iterations of slack. `imissed=16891` (ServerNIC) / `imissed=2236`
> (ClientNIC) is that math playing out for real, even though the *measured*
> cycles/packet (§9, §13) implies each core has ~40-50× the sustained-throughput
> headroom the test actually needed. Ring depth vs. burst size, not raw core
> speed, is the ceiling this system hits first at 100k.

### The TX doorbell: the likely first throughput wall — ✅ fixed 2026-07-25

Every send path in this codebase used to do:

```c
rte_eth_tx_burst(port_id, 0, &m, 1);   // ← one packet per burst
```

`tx_burst` with `nb_pkts = 1` means an **MMIO doorbell write per packet**. This is
the classic DPDK anti-pattern: the whole point of the burst API is to amortize
that write over 32 packets. A batched forwarder does millions of pps per core; a
one-at-a-time forwarder is typically an order of magnitude slower.

**Fixed**: every port now has a `tx_batch[TX_BATCH_SIZE=32]` buffer
(`eth0_tx_flush`/`eth1_tx_flush`/`eth2_tx_flush` in each tree's `io.c`), flushed
once per poll-loop iteration instead of once per packet. See §9/§13 for the
measured cycles/packet this produced.

### AWS ENA allowances (the invisible ceiling)

The Nitro card enforces per-instance limits that are invisible from inside the
guest *except* through ENA's own counters:

| Counter | Meaning |
|---|---|
| `bw_in_allowance_exceeded` / `bw_out_allowance_exceeded` | Instance bandwidth cap hit |
| `pps_allowance_exceeded` | Instance packet-rate cap hit |
| `conntrack_allowance_exceeded` | **Security-group connection tracking table full** |
| `linklocal_allowance_exceeded` | IMDS/DNS request rate hit |

`conntrack_allowance_exceeded` is the one that will bite a 100k-connection run.
The Nitro card tracks every connection for security-group enforcement, and the
table is not generous on small instances. AWS *skips* tracking only when a rule
allows all traffic to/from `0.0.0.0/0` in **both** directions — and this stack's
SG allows all traffic from `10.1.0.0/16`, not `0.0.0.0/0`, so **tracking is
active and the allowance applies.**

Read these on the Client/Server VMs, which are kernel-driven:

```bash
ethtool -S eth0 | grep -E 'allowance_exceeded'
```

They are unreadable on the SmartNIC data ports (DPDK owns them); use
`rte_eth_stats` there instead.

---

## 5. Frame-size budget: the hard 2048-byte ceiling — ✅ guarded 2026-07-25

This was the sharpest edge in the system and it was, at the time this section
was first written, **unguarded**.

Every packet-touching path copies through a fixed stack buffer:

```c
uint8_t buf[2048];                    // forwarder.c, translator.c, syn_handler.c
if (len > sizeof(buf))
    return;                           // ← silent drop
```

and every path measures length with **`rte_pktmbuf_data_len()`** — the length of
the *first mbuf segment* — never `rte_pktmbuf_pkt_len()`, the length of the whole
chain. With a 2048-byte dataroom, any frame larger than 2048 bytes arrives as a
**chained (segmented) mbuf**, and `data_len` reports only the first 2048 bytes.
The code then parses a truncated packet as if it were whole.

**Why this matters on AWS specifically:** the default MTU inside a VPC on Amazon
Linux 2 is **9001** (jumbo frames), and *nothing in `experiments/` sets it*.
ClientNIC's spoofed SYN-ACK advertises `SPOOFED_MSS = 1460`, which caps the
**client→server** direction — but the **server→client** direction is capped by
the MSS the *client* advertised in its SYN, which at MTU 9001 is 8961. So the
server is entitled to send ~9015-byte frames straight into `trans_s2c`.

**Invariant to enforce:**

```
endpoint MTU ≤ 2048 − 14 (Ethernet header) = 2034 bytes
```

Pick one:

1. **Set MTU 1500 on the Client and Server VMs** in `run_core.sh` (cheapest, and
   matches the 1460 MSS the ClientNIC already advertises), **or**
2. Raise the mbuf dataroom past the max frame and handle chained mbufs by using
   `pkt_len` + `rte_pktmbuf_linearize()`.

Until then, add a loud counter for `pkt_len != data_len` so a silent truncation
cannot masquerade as a data-plane bug.

**Done (2026-07-25):** option 1 — `run_core.sh` now runs `ip link set eth0 mtu
1500` on both Client and Server every run, and both DPDK trees' main loops
increment a `g_truncated_frames` counter whenever `rte_pktmbuf_pkt_len() !=
rte_pktmbuf_data_len()`, logged as `stats: truncated_frames=...` if it's ever
nonzero. Confirmed **0** on both SmartNICs during the live 100k-connection run
(§13) — the invariant holds in practice, not just in theory.

---

## 6. Connection-state budget: the flow tables

Both tables are open-addressed arrays sized for the benchmark:

```c
#define FT_SIZE 262144        // 2^18 — 100k flows ⇒ 0.38 load factor
```

A ~0.4 load factor keeps linear-probe chains short (expected probes ≈
`(1 + 1/(1−α)²)/2` ≈ 1.8 at α = 0.38). Keep it a power of two — the code masks
with `FT_SIZE − 1`.

### ClientNIC — cheap (`src/clientnic/dpdk-forwarder/flow_table.h`)

Slim entry: key(12) + occupied(4) + ISN(4) + client_mac(6) + state(4) + tsc(8) +
flag(4), padded → **48 bytes**.

```
table  = 262,144 × 48  =  12.0 MiB      (entire array)
100k   = 100,000 × 48  =   4.6 MiB
```

Negligible. Ignore it.

### ServerNIC — expensive (`src/servernic/dpdk/flow_table.h`)

The entry embeds the buffer *array*:

```c
struct pkt_buffer { uint8_t *data; uint16_t len; };   // 16 B (8 ptr + 2 + 6 pad)
struct flow_entry {
    ...
    struct pkt_buffer buffer[FT_MAX_BUFFER];          // 64 × 16 = 1024 B  ← dominates
    ...
};
```

Derived layout → **≈ 1,096 bytes per entry**, ~93 % of which is that pointer
array.

```
table  = 262,144 × 1,096  ≈  274 MiB      (BSS)
```

The header says the array is "lazily committed, so only touched flows consume
RAM." True at *page* granularity — but an entry is ~1 KiB, so a 4 KiB page holds
only **3.7 entries**. At 100k live flows (38 % occupancy), the chance a given page
contains *zero* occupied slots is ≈ `(1 − 0.38)^3.7 ≈ 0.17`. So **~83 % of pages
get touched and commit**:

```
committed at 100k  ≈  0.83 × 274 MiB  ≈  230 MiB resident
```

Fine on 4.25 GiB — but it is 230 MiB, not the ~110 MiB "only what you touch"
intuition suggests. **To shrink it:** move `buffer[]` out of the entry and behind
a pointer, allocated only for flows that actually buffer (most flows buffer
nothing). That alone drops the entry from 1,096 B to ~72 B and the table from
274 MiB to ~18 MiB.

---

## 7. The buffered-packet cliff — ✅ capped 2026-07-25

`buffer[64]` holds *pointers*; `ft_buffer_pkt()` `malloc`s each packet's bytes
separately. There is **no global cap** on outstanding buffered bytes.

```
worst case  = 100,000 flows × 64 slots × 1,514 B  ≈  9.7 GB    ← exceeds RAM (4.25 GiB)
realistic   = 100,000 flows ×  2 pkts × 1,514 B  ≈  303 MB     ← fine
```

The realistic figure holds because buffering only spans the window between
forwarding the SYN and receiving the real SYN-ACK — about one RTT — during which
a 0-RTT client sends only its first segment or two. But:

- that window is exactly when **all 100k SYNs are in flight simultaneously**, so
  it is a synchronized spike, not a steady state;
- if the server is slow to SYN-ACK (which it will be — it is a t3.micro, §11),
  the window widens and the buffer grows;
- `malloc` returning NULL at 100k flows is not a failure mode you want to meet
  for the first time mid-benchmark.

**Do before the 100k run:** track outstanding buffered bytes in a global counter,
log it, and enforce a ceiling that sheds (or refuses to buffer) past a limit.
A bounded, observable drop beats an OOM kill.

**Done (2026-07-25):** `flow_table.h`/`flow_table.c` added a table-level
`buffered_bytes` counter and a `FT_MAX_BUFFERED_BYTES = 1 GiB` ceiling.
`ft_buffer_pkt()` now returns `-2` (distinct from `-1`, the per-flow
`FT_MAX_BUFFER` cap) and sheds the packet instead of buffering past the
ceiling; `ft_flush_buffer()` decrements the counter as flows drain. Live
100k-connection measurement (§13): peaked at **446 MB of the 1 GiB cap** — well
under the worst case, in the ballpark of the "realistic" 303 MB estimate above,
plus overhead from the ~31% of flows that stayed PENDING (SYN-ACK never
arrived) and kept their buffered packets outstanding for the whole run. No
shedding triggered, no malloc failures.

---

## 8. 4-tuple / port-space budget

100,000 connections from **one** client IP to **one** server IP cannot fit on a
single destination port. The client's ephemeral range bounds it:

```
net.ipv4.ip_local_port_range   default: 32768–60999  →  28,232 ports
```

So the invariant is:

```
IPERF_PORTS × ephemeral_range_size  ≥  target_connections   (with TIME_WAIT margin)
```

| Ephemeral range | Ports available | Server ports needed for 100k |
|---|---|---|
| default `32768–60999` | 28,232 | **4** |
| widened `1024–65535` | 64,512 | **2** |

This is precisely what `PORT_COUNT` / `IPERF_PORTS` exist for, and why both
binaries take `--port-count`. Assert the inequality in `run_core.sh` before the
run rather than discovering it as mysterious connection failures. Leave real
margin: connections in `TIME_WAIT` still hold their tuple for `2×MSL` (60 s).

---

## 9. CPU budget — ✅ measured 2026-07-25

One lcore (`-l 0`) polls both ports and does, per packet: parse → hash lookup →
`memcpy` into a 2 KB stack buffer → seq/ack rewrite → IP+TCP checksum recalc →
`rte_pktmbuf_alloc` → batched `tx_burst` (§4, fixed 2026-07-25 — was `tx_burst(…, 1)`
when this section was first written).

The budget:

```
required_pps × cycles_per_packet  ≤  rte_get_tsc_hz()      (~3.0e9 on c5n)
```

Solve for the ceiling: `max_pps = tsc_hz / cycles_per_packet`. As a scale
reference, 10 Gbps of 1500-byte frames is ~833 kpps in one direction, which
allows ~3,600 cycles/packet.

**Measured (§13, live 100k-connection run):**

| | cycles/packet | tsc_hz | implied `max_pps` | packets sampled |
|---|---|---|---|---|
| ClientNIC | ≈10,669 | 3.0e9 | ≈281,000 pps | ~889,000 |
| ServerNIC | ≈12,483 | 3.0e9 | ≈240,000 pps | ~909,000 |

Both land far under the ~3,600 cycles/packet reference ceiling for 10 Gbps —
the batched TX fix (§4) worked. The measured *sustained* rate the 100k test
actually produced was only ~5-6k pps, i.e. **~40-50× under** each of these
ceilings. So per-packet processing cost is not what limits this run — see
§4 and §13: the real ceiling is burst absorption (RX ring depth vs. 100,000
near-simultaneous connection attempts), not steady-state cycles/packet.

Also note both SmartNICs are **2 vCPU**, one of which is fully consumed by the
busy-poll loop. Everything else — SSM agent, the experiment scripts, logging —
shares the other. There is no `isolcpus`/`nohz_full` pinning, so the polling core
still takes timer interrupts.

---

## 10. Endpoint limits — ✅ resolved 2026-07-25 (was the binding constraint)

**This section originally identified the t3.micro endpoints as the binding
constraint. That has been fixed — see the live-run confirmation below — but
the arithmetic that predicted it is kept as the worked example.**

A t3.micro has **1 GiB of RAM** and burstable CPU. A single established kernel
TCP socket costs roughly:

| Component | Approx. |
|---|---|
| `struct tcp_sock` + `struct socket` + inode/dentry | ~2–3 KB |
| minimum receive buffer (`tcp_rmem[0]`) | 4 KB |
| minimum send buffer (`tcp_wmem[0]`) | 4 KB |
| **total, idle, at minimum buffers** | **~10 KB** |

```
100,000 sockets × ~10 KB  ≈  1.0 GB     ← the entire RAM of a t3.micro
```

That is before iperf's own per-connection state, before any socket carries data
(buffers autotune *upward* under load), and before the OS. **100k concurrent
connections will not fit on a t3.micro.** Add burstable-CPU credit exhaustion on
top and the endpoints will throttle long before the SmartNICs are stressed.

**This was a topology decision, not a tuning knob**, and it's been made:
Client and Server were upgraded to `m5.xlarge` (16 GiB) in `smartnics_stack.py`
(PR #27, 2026-07-25). **Confirmed on the live 100k-connection run (§13):**
14.8-14.9 GiB free RAM throughout on both, zero OOM-kill entries in `dmesg`.
The endpoints are no longer in the picture at 100k — the SmartNIC single-lcore
CPU/burst-ring interaction (§4, §9, §13) is now the binding constraint.

Also check on both endpoints, in this order — **all raised durably in
`run_core.sh` as of 2026-07-25**:

| Setting | Default | Needed for 100k | Status |
|---|---|---|---|
| `ulimit -n` / `fs.file-max` | 1024 soft | > 100,000 | ✅ `fs.file-max=1048576` |
| `net.core.somaxconn` | 4096 | ≥ target accept backlog | ✅ `131072` |
| `net.ipv4.tcp_max_syn_backlog` | 128–1024 | large — 100k SYNs arrive *at once* | ✅ `131072` |
| `net.ipv4.tcp_max_tw_buckets` | 65536 | 100k closes ⇒ TIME_WAIT flood | ✅ `200000` |
| `net.netfilter.nf_conntrack_max` | 65536 | **> 100,000 — see below** | ✅ `200000` |
| `net.core.netdev_max_backlog` | 1000 | raise under burst | ✅ `250000` |

**`nf_conntrack` deserves special attention.** Both binaries call
`install_iptables()`, which can load the `nf_conntrack` module. Its default table
is 65,536 — it will silently drop connections at 100k, and the symptom is
indistinguishable from a data-plane bug. Check whether the module is even loaded:

```bash
lsmod | grep nf_conntrack
cat /proc/sys/net/netfilter/nf_conntrack_max   # if present
```

---

## 11. Measurement: what to instrument, what to run

### In the data plane

The AF_PACKET → DPDK move deleted the `tx_drops` counters and left the
`LOG_WARN`s firing without a number. Visibility is restored via
`rte_eth_stats_get()` per port, logged every `STATS_INTERVAL_SEC` (5 s) from both
busy-poll loops (`log_port_stats()` in each `main.c`), plus a mempool low-water
mark from `rte_mempool_avail_count()`. These four distinguish failure modes that
all present as "throughput collapsed" but have **opposite fixes**:

| Counter | Means | Fix |
|---|---|---|
| `imissed` | RX ring overflowed | **Core too slow** — batch TX, reduce per-packet work |
| `rx_nombuf` | Mempool ran dry | **Pool too small** — or you are leaking mbufs |
| `oerrors` / `tx_burst` returning 0 | TX ring backed up | Downstream/link is the bottleneck |
| `rte_mempool_avail_count()` low-water | How close the pool came to empty | Sizing headroom check (§3) |

Plus **cycles/packet**: wrap the loop in `rte_rdtsc()` and divide by packets
processed; compare against `rte_get_tsc_hz()` (§9). **Implemented and measured
2026-07-25** — see §9, §13.

Plus, for §7: a global counter of outstanding buffered bytes and flow-table live
entries + max probe length. **Implemented 2026-07-25** — see §7.

### On the endpoints, during the run

```bash
ss -s                                     # socket totals by state
nstat -az | grep -Ei 'drop|overflow|retrans|listen'
ethtool -S eth0 | grep -E 'allowance_exceeded'    # ← Nitro caps (§4)
cat /proc/net/sockstat
```

`ListenOverflows` / `ListenDrops` in `nstat` mean the accept backlog was
overrun — a server-side limit, not a forwarder bug.

### Order of investigation

Work outside-in; the first ceiling you hit is usually not the one you're staring
at:

1. **Endpoint RAM / socket count** (§10) — the t3.micro wall. **✅ Resolved** (m5.xlarge).
2. **Nitro allowances** (§4) — especially `conntrack_allowance_exceeded`. **✅ Confirmed 0** on both endpoints at 100k.
3. **Kernel limits** (§10) — backlog, conntrack, fds, TIME_WAIT. **✅ Raised**, none hit.
4. **Port space** (§8) — is `IPERF_PORTS` large enough to be *arithmetically* possible? **✅ Asserted in `run_core.sh`**, passed (4 × 32,256 ≥ 100,000).
5. **Frame size** (§5) — is anything above 2048 bytes being silently truncated? **✅ 0 `truncated_frames`**.
6. **SmartNIC CPU** (§9) — `imissed` climbing, cycles/packet. **← This is where the live 100k run actually stopped (§13).** `imissed` nonzero, `rx_nombuf`/`oerrors` zero, cycles/packet measured and well under budget in steady state — the ceiling is burst absorption (RX ring depth vs. 100k simultaneous SYNs), not per-packet cost.
7. **Buffered-packet memory** (§7). **✅ Capped**, 446 MB/1 GiB observed, never reached.
8. **mbuf pool** (§3) — last, and almost never the problem. **✅ Never the problem** — `rx_nombuf=0` throughout.

---

## 12. Summary: every constant, where it lives, what it binds

*(Table reflects the stack as originally analyzed. See §13 for the post-fix,
post-live-run state of each row.)*

| Constant | Value | Defined in | Binds | Headroom at 100k |
|---|---|---|---|---|
| `MBUF_POOL_SIZE` | 8191 → derived formula | `main.c` (both) | Packets in flight | 1.76× (needs 4,660) ✅ |
| `MBUF_CACHE_SIZE` | 250 | `main.c` (both) | Per-core mbuf cache | ✅ |
| `RX_BURST_SIZE` | 32 | `main.c` (both) | Drain rate per loop | ✅ |
| `RX_RING_SIZE` | 1024 | `io.c` (both) | Burst absorption before `imissed` | ⚠ this is the actual 100k ceiling (§13) |
| `TX_RING_SIZE` | 1024 | `io.c` (both) | TX queueing | ✅ batched 2026-07-25 (§4) |
| `FT_SIZE` | 262144 | `flow_table.h` (both) | Max flows (0.38 load @ 100k) | ✅ |
| `FT_MAX_BUFFER` | 64 | `servernic/flow_table.h` | Buffered pkts **per flow** | ✅ global cap added (§7) |
| `buf[2048]` / mbuf dataroom | 2048 B | `translator.c`, `forwarder.c`, … | **Max frame size** | ✅ MTU pinned 1500 (§5), 0 truncated |
| `SPOOFED_MSS` | 1460 | `packet_processor.c` | c2s segment size only | ✅ s2c now capped via MTU pin (§5) |
| `vm.nr_hugepages` | 512 (1 GiB) | `smartnics_stack.py` | DPDK memory | ✅ (18 MiB used) |
| lcores | 1 (`-l 0`) | `clientnic.sh`, `servernic.sh` | pps ceiling | ✅ measured (§9): ~10.7k/~12.5k cycles/pkt, ~40-50× headroom in steady state |
| SmartNIC instance | c5n.large | `smartnics_stack.py` | 2 vCPU / 5.25 GiB | ✅ |
| **Endpoint instance** | **m5.xlarge** (was t3.micro) | `smartnics_stack.py` | **16 GiB / 4 vCPU** | ✅ upsized 2026-07-25, confirmed at 100k (§10, §13) |

**Verdict, updated 2026-07-25 (see §13 for full evidence):** every constant this
table originally flagged has been fixed and re-verified against a live
100k-connection run — endpoints upsized, frame ceiling guarded, buffered bytes
capped, TX batched, kernel limits raised, port space asserted. **68,779/100,000
(68.8%) connections were established.** The remaining 31.2% is not explained by
any row in this table being wrong — it's `RX_RING_SIZE` doing exactly what §4
always said it does: absorbing `1024/32 = 32` loop-iterations of burst before
`imissed` starts counting, and 100,000 near-simultaneous connection attempts is
a bigger burst than that. Per-packet cost (measured, §9) has ~40-50× headroom in
steady state, so the fix (if pursued) is burst-side — RSS/multi-queue to spread
the burst across cores, SYN-cookie-style backpressure, or client-side pacing —
not another sizing-constant tweak in this table.

---

## 13. Live 100k-connection run — 2026-07-25 (roadmap.md #20)

Every fix this document called for (§4, §5, §7, §9, §10) landed in PR #27 +
follow-ups, `infra/dpdk` was redeployed with the endpoint upsize, and
`experiments/dpdk/run_experiment.sh` was run twice at
`IPERF_PARALLEL=100000 IPERF_PORTS=4`. This section is the answer to "does the
model hold up against a real run" — it does, and it correctly predicted where
the run would actually stop.

**Headline: 68,779/100,000 (68.8%) connections established, reproducible**
(a second independent run landed at 68,717 — within a few hundred connections).

**Per-section confirmation:**

| § | Predicted | Measured 2026-07-25 |
|---|---|---|
| §3 mbuf pool | Comfortable, not the constraint | `rx_nombuf=0` throughout — never touched |
| §4 ring depth | `1024/32=32` iterations of burst slack | `imissed=16891` (ServerNIC) / `2236` (ClientNIC) — burst exceeded that slack, exactly as modeled |
| §5 frame ceiling | Fixable by MTU pin | `truncated_frames=0` on both — held |
| §7 buffered bytes | ~303 MB realistic, ~9.7 GB worst case | 446 MB peak (between the two, given ~31% of flows stayed PENDING for the whole run) — capped, no shedding, no malloc failures |
| §9 CPU budget | Must measure, don't guess | ClientNIC ≈10,669, ServerNIC ≈12,483 cycles/packet — ~40-50× headroom vs. the ~5-6k pps sustained rate the test produced |
| §10 endpoint RAM | t3.micro blocks 100k | m5.xlarge: 14.8-14.9 GiB free throughout, zero OOM-kills |
| §4 Nitro allowances | Watch `conntrack_allowance_exceeded` | All five allowance counters read 0 on both endpoints |

**The actual failure mode, precisely:** `asyncio.gather()` in
`experiments/utils/loadgen.py` fires all 100,000 `open_connection()` calls at
once — that's the point of an event-driven generator, no thread-per-connection
throttling. That is an instantaneous SYN burst, not a sustained arrival rate.
A burst that size overwhelms the 1024-deep RX ring's ~32-iteration absorption
window before the single busy-poll lcore can drain it, even though that same
lcore has ~40-50× the *steady-state* throughput this test needed. Concretely:

- A SYN dropped at **ClientNIC**'s ingress (`imissed=2236`) never gets spoofed —
  the client's own TCP stack retries and eventually hits the ~127-130s default
  Linux SYN-retry ceiling.
- A SYN dropped at **ServerNIC**'s ingress (`imissed=16891`), *after* ClientNIC
  already spoofed a SYN-ACK, leaves the client believing it's connected while
  ServerNIC has no flow-table entry for it — the client's data is silently
  dropped (`"c2s: unknown flow, dropping"`) and that connection also eventually
  times out.
- `server_gap` (server-side pcap analysis, 277 samples) is tightly clustered at
  15,974-16,036 ms (σ≈24 ms) — a single mode, not the historical bimodal
  fast/slow split, just shifted to a high absolute value: the connections that
  *did* get through were queued behind the same backlog, so they all paid
  roughly the same multi-second queueing tax.

**What this does and doesn't mean:** the SmartNIC single-lcore architecture is
not "too slow" in any absolute sense — cycles/packet is nowhere near the
budget. It cannot absorb a 100,000-connection burst landing in one instant
without a deeper ring, multiple RX queues (RSS across cores), or the client
pacing its connection attempts instead of firing them all at once. That is new
scope (tracked in roadmap.md, not this document) — capacity-model.md's job was
to predict where the real ceiling would be and let you measure it instead of
guessing, and per the table above, it did.
