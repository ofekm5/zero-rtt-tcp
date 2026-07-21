# Roadmap

Tracks open GitHub issues and how they relate to the OpenSpec change pipeline (`openspec/backlog.yaml`, `openspec/changes/`).

## Status snapshot

- `full-dpdk-endpoint-interfaces` (#18) — **done**, archived 2026-07-14 (`openspec/changes/archive/2026-07-14-full-dpdk-endpoint-interfaces/`). Both SmartNICs now run dual-DPDK data-plane ports.
- [#20 — Scale DPDK experiment to 100k parallel connections with 3-NIC SmartNIC topology](https://github.com/ofekm5/zero-rtt-tcp/issues/20) — closed 2026-07-21, tracked here going forward (topology sub-scope already shipped via #18; remaining load-scale work stays open in this doc)
- [#21 — Run experiment on both DPDK and baseline stacks](https://github.com/ofekm5/zero-rtt-tcp/issues/21) — closed 2026-07-21, tracked here going forward

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
