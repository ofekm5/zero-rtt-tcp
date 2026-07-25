# Roadmap

Tracks open GitHub issues and how they relate to the OpenSpec change pipeline (`openspec/backlog.yaml`, `openspec/changes/`).

## Status snapshot

- `full-dpdk-endpoint-interfaces` (#18) — **code done**, OpenSpec change archived 2026-07-14 (`openspec/changes/archive/2026-07-14-full-dpdk-endpoint-interfaces/`). Both SmartNICs now run dual-DPDK data-plane ports. **Deploy-gated verification still open** — see [#18 — remaining deploy-gated DoD](#18--remaining-deploy-gated-dod).
- [#20 — Scale DPDK experiment to 100k parallel connections with 3-NIC SmartNIC topology](https://github.com/ofekm5/zero-rtt-tcp/issues/20) — closed 2026-07-21, tracked here going forward (topology sub-scope already shipped via #18; remaining load-scale work stays open in this doc)
- [#21 — Run experiment on both DPDK and baseline stacks](https://github.com/ofekm5/zero-rtt-tcp/issues/21) — closed 2026-07-21, tracked here going forward
- **Infra hand-tailoring** — CDK/runtime properties need to be tuned to the ceilings `docs/capacity-model.md` documents before the #20 100k run is meaningful; not yet started. See [Infra hand-tailoring](#infra-hand-tailoring-per-docscapacity-modelmd).

## #18 — remaining deploy-gated DoD

The code is shipped and the OpenSpec change is archived, but every remaining #18
success criterion needs a live AWS deploy + run — none were verified in the
authoring environment (no DPDK toolchain, no infra). Do these before closing #18.

- [ ] **Compile the data plane on the VM.** PR [#25](https://github.com/ofekm5/zero-rtt-tcp/pull/25) (drop counters) and everything in the archived change are **unverified builds** — no local DPDK. First `meson`/`ninja` happens on the ClientNIC/ServerNIC during deploy; treat "it builds" as open.
- [ ] **Redeploy the 3-ENI/SmartNIC topology** (Task 2). Each SmartNIC now provisions 3 ENIs (1 kernel/SSM mgmt + 2 vfio-pci data) — **BREAKING**, a full redeploy, not update-in-place. Use the `deploy-infra` skill (GitHub Actions path needs no local AWS creds). Watch the `vfio-bind:` boot log (`_bind_data_enis_to_vfio()` in `infra/dpdk/cdk/smartnics_stack.py`).
- [ ] **Criterion 2 — SSM reachability** (Task 3). Both SmartNICs stay SSM-reachable with both data ENIs bound to vfio-pci: expect exactly 2 vfio-pci devices per SmartNIC and `eth0` still kernel-bound with an IP. If SSM is dead, the primary ENI got bound — check `/var/log/cloud-init-output.log`.
- [ ] **Criterion 4 — regression run at current working scale** (Task 4). `./experiments/dpdk/run_experiment.sh`; confirm no `server_gap` regression vs. the AF_PACKET baseline (`experiments/dpdk/reports/`). Use the `run-experiment` skill.
  - Read the startup `Port map: client-facing=port N, ServerNIC-facing=port M` line first — if swapped vs. the ENI subnets, the whole fix premise is wrong and you'll see zero 0-RTT behaviour.
  - Pin endpoint MTU to 1500 in `run_core.sh` before the run — the 2048-byte frame ceiling vs. default 9001 MTU trap (`docs/capacity-model.md` §5) presents as data-plane corruption/stalls.
  - The restored drop counters (PR #25) now make this criterion evaluable: `imissed`/`rx_nombuf`/`oerrors` should be zero or explained.
- [ ] **Then close #18** and reconcile the GitHub issue state with this roadmap (issue is still open; the OpenSpec change is already archived).

## #20 — Scale to 100k connections, 3-NIC topology

**Goal:** run `experiments/dpdk/run_experiment.sh` at 100k parallel connections on SmartNICs that carry 3 interfaces each (1 dedicated management ENI + 2 DPDK data-plane ENIs), and confirm the endpoints — not the SmartNICs — are the bottleneck.

### Original scope
- Upsize Client + Server EC2 instances (`infra/dpdk/cdk/smartnics_stack.py`) — **still `T3.MICRO`/1 GB RAM as of 2026-07-21** (verified in code: `ec2.InstanceClass.T3, ec2.InstanceSize.MICRO` for both), OOMs/stalls well before 10k connections. Not yet upsized.
- Confirm `c5n.large`-class SmartNICs sustain 100k once both data-plane ports are pure DPDK (this depended on #18, now shipped).
- ~~Provision 3 ENIs per SmartNIC in `smartnics_stack.py`: 1 mgmt (kernel, SSM) + 2 data-plane (vfio-pci).~~ **Already done** — verified in code: ClientNIC and ServerNIC are both `C5N.LARGE` with 3 `CfnNetworkInterface`/attachment pairs each (eth0 primary/kernel/SSM, eth1 + eth2 secondary/tertiary DPDK vfio-pci), shipped with #18 (`openspec/changes/archive/2026-07-14-full-dpdk-endpoint-interfaces/`). Nothing further needed here — remaining #20 work is purely load-scale, not topology.
- Re-run the DPDK experiment at 100k and confirm the middlebox is actually load-tested, not bottlenecked by client/server OOM.

### Additional scope (surfaced via `docs/capacity-model.md`, added in #22)
Running the 100k target against the capacity model confirmed the premise (endpoints are the ceiling) but surfaced more constraints. The mbuf pool (4,660 needed vs. 8,191 available) and flow tables (`FT_SIZE=262144`, 0.38 load factor) are fine as-is.

**A. Blocks regardless of instance size**
- Replace the load generator: iperf2 is thread-per-connection — 100k threads is not viable at any instance size (`kernel.threads-max`, `pid_max`, `vm.max_map_count`, scheduler thrash). Move to an event-driven generator (many `iperf3` processes across the port range, or epoll-based).
- Fix the 2048-byte frame ceiling vs. default 9001 MTU: packet paths use `uint8_t buf[2048]` and measure via `rte_pktmbuf_data_len()` (first segment only), never `pkt_len`. Server→client isn't capped by `SPOOFED_MSS`; a 9001-MTU client SYN lets the server send ~9015-byte frames, arriving as chained mbufs and getting parsed as truncated. Fix: pin endpoint MTU to 1500 in `run_core.sh`, or raise mbuf dataroom + handle chained mbufs (`pkt_len` + `rte_pktmbuf_linearize()`). Add a `pkt_len != data_len` counter either way.

**B. Capacity ceilings to budget for**
- Cap ServerNIC's buffered-packet allocation: `FT_MAX_BUFFER=64` per flow with no global cap — worst case ~9.7 GB at 100k SYNs, spiking exactly when the server is slow to SYN-ACK. Add a global outstanding-bytes counter with a shedding ceiling.
- Budget ServerNIC flow-table RAM: `buffer[64]` inline per entry makes the table ~274 MiB BSS, ~230 MiB actually committed at 100k live flows. Fine on 5.25 GiB but should be measured, not assumed. Optional: move `buffer[]` behind a pointer (entry ~72 B, table ~18 MiB).
- Assert port-space arithmetic pre-run: 100k connections to one server IP needs `IPERF_PORTS × ephemeral_range ≥ target_connections`, with TIME_WAIT margin (2×MSL = 60s).

**C. Limits outside our code**
- Nitro/security-group conntrack allowance — watch `ethtool -S eth0 | grep allowance_exceeded`.
- `nf_conntrack_max` (65,536 default) on endpoints via `install_iptables()`.
- Endpoint kernel limits: `ulimit -n`, `fs.file-max`, `net.core.somaxconn`, `tcp_max_syn_backlog`, `tcp_max_tw_buckets`, `netdev_max_backlog`.

**D. SmartNIC CPU — the thing to actually measure**
- Both binaries run single-lcore, one-packet-per-burst TX (`rte_eth_tx_burst(port, 0, &m, 1)`) — the classic DPDK anti-pattern and likely throughput wall. Batch TX into `struct rte_mbuf *tx[32]`, measure `cycles_per_packet`.
- Restore drop visibility (prerequisite for the above): log `rte_eth_stats_get()` per port (`imissed`, `rx_nombuf`, `oerrors`) plus `rte_mempool_avail_count()` low-water — these were deleted in the AF_PACKET→DPDK move.

### Success criteria
- [ ] Client and Server no longer OOM/stall before 100k connections established
- [ ] Load generator is not thread-per-connection
- [x] Each SmartNIC shows exactly 3 interfaces (1 mgmt + 2 data) — shipped in #18, verified in `infra/dpdk/cdk/smartnics_stack.py`
- [ ] Endpoint MTU ≤ 2034B or chained-mbuf handling landed; zero `pkt_len != data_len` events
- [ ] ServerNIC outstanding buffered bytes capped; no malloc failures
- [ ] `imissed`/`rx_nombuf`/`oerrors` zero or explained; no `*_allowance_exceeded`
- [ ] `experiments/dpdk/run_experiment.sh` completes a 100k run, report under `experiments/dpdk/reports/`
- [ ] `analyze_metrics.py` shows unimodal `server_gap` at 100k (no bimodal regression)
- [ ] Measured `cycles_per_packet` documented against offered load

## Infra hand-tailoring (per `docs/capacity-model.md`)

**Goal:** stop deploying `infra/dpdk` with generic/default properties and instead
hand-tailor every instance size, MTU, sysctl, and DPDK sizing constant to the
ceilings the capacity model derived — so a 100k-connection run (#20) tests the
data plane, not an untuned default.

This is infra-as-code + runtime config work, distinct from #20's "run the
experiment at scale" scope — it's the set of concrete edits the capacity model
says are needed *before* that run is worth trusting.

### CDK stack (`infra/dpdk/cdk/smartnics_stack.py`)
- [ ] Upsize Client + Server EC2 instances off `T3.MICRO` (1 GiB RAM caps out at
      ~20-30k sockets at minimum buffers per capacity-model.md §10) to an
      `m5.xlarge`-class instance (≥16 GiB) — same gap tracked in #20's original
      scope, landing it here as the actual CDK diff.
  - SmartNICs (`c5n.large`, 2 vCPU / 5.25 GiB) stay as-is — capacity-model.md §2
    confirms they're comfortable; only the endpoints are the ceiling.
- [ ] Confirm security-group rules once endpoints are upsized: SG currently
      scopes to `10.1.0.0/16` rather than `0.0.0.0/0`, so Nitro conntrack
      tracking stays active and `conntrack_allowance_exceeded` (§4) is reachable
      at 100k — decide whether to widen the rule or budget for the allowance.

### Endpoint runtime tuning (`run_core.sh` / boot-time config on Client + Server)
- [ ] Pin endpoint MTU to 1500 (matches `SPOOFED_MSS=1460`) instead of the AWS
      VPC default 9001 — closes the unguarded 2048-byte frame ceiling
      (capacity-model.md §5) that lets the server send ~9015-byte frames into
      `trans_s2c`. Same fix already called out under [#18's regression-run
      criterion](#18--remaining-deploy-gated-dod); this item is the durable
      infra-config version so it isn't a one-off manual step per run.
- [ ] Raise kernel limits ahead of 100k connections (capacity-model.md §10,
      table in "Endpoint limits"): `ulimit -n`/`fs.file-max` > 100,000,
      `net.core.somaxconn`, `net.ipv4.tcp_max_syn_backlog`,
      `net.ipv4.tcp_max_tw_buckets`, `net.core.netdev_max_backlog`.
- [ ] Raise or confirm `net.netfilter.nf_conntrack_max` (default 65,536) above
      100,000 on both endpoints — `install_iptables()` in both DPDK binaries can
      load `nf_conntrack`, and its default table silently drops connections at
      100k in a way indistinguishable from a data-plane bug.
- [ ] Assert the port-space inequality in `run_core.sh` before every run rather
      than discovering it as connection failures: `IPERF_PORTS × ephemeral_range
      ≥ target_connections`, with 2×MSL (60s) TIME_WAIT margin
      (capacity-model.md §8).

### DPDK sizing constants (`main.c`, `io.c`, `flow_table.h` in both trees)
- [ ] Derive `NUM_MBUFS` from the ring/port formula instead of the hardcoded
      `8191` magic number, so a third port or deeper ring can't silently drop
      headroom below the required minimum (capacity-model.md §3):
      `RTE_MAX(2 * (RX_RING_SIZE + TX_RING_SIZE + RX_BURST_SIZE + MBUF_CACHE_SIZE), 8191U)`.
- [ ] Add a global outstanding-buffered-bytes counter + shedding ceiling to
      ServerNIC's flow table — `FT_MAX_BUFFER=64` per flow has no global cap and
      a worst case of ~9.7 GB against 5.25 GiB of RAM (capacity-model.md §7).
- [ ] Batch TX (`struct rte_mbuf *tx[32]` + one `tx_burst` per loop) instead of
      the current one-packet-per-burst doorbell write — capacity-model.md §4
      flags this as the likely first throughput wall, ahead of any endpoint or
      NIC limit.

### Success criteria
- [ ] Client/Server instance class changed in `smartnics_stack.py` and
      redeployed (this is a replacement, not update-in-place, like #18's ENI
      change)
- [ ] Endpoint MTU pinned to ≤2034B as durable boot-time config, not a manual
      per-run step
- [ ] `nf_conntrack_max`, `somaxconn`, `tcp_max_syn_backlog`, `tcp_max_tw_buckets`
      confirmed ≥ 100k-connection requirements on both endpoints
- [ ] `NUM_MBUFS` derived from ring sizes in source, not a bare constant
- [ ] ServerNIC buffered-byte ceiling lands with a shedding policy
- [ ] TX batching lands in both `forwarder.c`/`translator.c` send paths
- [ ] Re-run `experiments/dpdk/run_experiment.sh` post-tailoring and confirm the
      constraints in `docs/capacity-model.md` §11 ("order of investigation") are
      each individually checked off, not just the top-level pass/fail

## #21 — Run experiment on both DPDK and baseline stacks

**Goal:** run the integration experiment on both the live DPDK 0-RTT stack (`infra/dpdk`) and the plain-TCP baseline (`infra/baseline`), so TTFB/FCT numbers are directly comparable.

### Scope
- `experiments/dpdk/run_experiment.sh` — live DPDK 0-RTT data plane
- `experiments/baseline-tcp/run_experiment.sh` — plain-TCP baseline (kernel-routed NIC VMs)
- Deploy each stack, run end-to-end, collect both reports.

### Success criteria
- [ ] `experiments/dpdk/run_experiment.sh` completes, report under `experiments/dpdk/reports/`
- [ ] `experiments/baseline-tcp/run_experiment.sh` completes, report under `experiments/baseline-tcp/reports/`
- [ ] Both reports cover the same connection load for a fair comparison
- [ ] TTFB/FCT delta documented (expected ~1-RTT / 50-200ms improvement per `CLAUDE.md`)

### Sequencing note
Run this comparison first at whatever scale currently works; re-run at 100k once #20 lands. The two issues are complementary, not blocking: #21 can proceed independently at current scale while #20's scale work is in flight.
