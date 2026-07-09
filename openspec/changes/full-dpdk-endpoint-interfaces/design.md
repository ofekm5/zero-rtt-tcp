## Context

Each SmartNIC currently mixes two I/O backends. The ClientNIC forwarder polls one DPDK ENA port (eth1, server-facing) and one AF_PACKET raw socket (eth0, client-facing); ServerNIC polls one DPDK port (eth1, ClientNIC-facing) and one AF_PACKET socket (eth2, server-facing). The AF_PACKET side carries per-packet `sendto`/`recvfrom` syscalls plus kernel `sndbuf`/`qdisc` queues, which are the last remaining backpressure/tail-drop source under the 100k-connection benchmark. Prior mitigations (16 MB `SO_*BUFFORCE`, bounded retries, drain-until-empty RX) live in both `io.c` files and `main.c` poll loops.

Two AWS constraints frame the infra work:
1. The **primary ENI** (device_index 0) is the boot / default-route NIC and hosts the SSM agent's connectivity; it cannot be vfio-pci bound without losing management.
2. **ClientNIC's client-facing traffic is currently on the primary ENI**, so that port does double duty (client data + SSM). ServerNIC already isolates management on its primary ENI, so only its eth2 secondary needs rebinding.

The T8 data-plane logic (V stamping, delta computation, seq/ack rewrite, buffering) is backend-agnostic — it operates on parsed packet buffers/mbufs, not on the socket — so this change is confined to the I/O layer plus the CDK ENI topology.

## Goals / Non-Goals

**Goals:**
- Zero AF_PACKET in the data path of both `clientnic/dpdk-forwarder` and `servernic/dpdk`.
- A dedicated kernel management ENI on each SmartNIC so all data-plane ENIs can be vfio-pci bound while SSM stays reachable.
- Preserve the existing single-core busy-poll model and the T8 translation logic unchanged.
- Peer (client/server) MAC supplied via CLI, mirroring the existing `--gw-mac` contract.

**Non-Goals:**
- (Inherit `proposal.md` Non-Goals.) No DPU port, no Scapy stack, no full-owner `clientnic/dpdk/`, no T8 logic changes, no runtime ARP, no in-binary pcap on the endpoint ports, no flow-table/sysctl re-tuning.

## Decisions

**D1 — Dedicated management ENI = primary ENI on both SmartNICs.**
The primary ENI (device_index 0) becomes management-only (kernel, SSM). All data-plane ENIs are secondaries bound to vfio-pci. ClientNIC gains a new secondary ENI for the client-facing data (moved off the primary); ServerNIC's existing eth2 secondary is rebound from kernel to vfio-pci. This yields a uniform layout — *primary=mgmt, secondaries=DPDK* — on both nodes.

**D2 — Second ENA PMD port, not a merged/bonded port.**
Each binary initializes two independent `rte_eth` ports and polls both in the existing loop. The endpoint-facing `ethX_io` AF_PACKET struct is replaced with an ENA-port struct shaped like the current `eth1_io` (`port_id`, `mac`, `peer_mac`, `mbuf_pool`). Send becomes `rte_eth_tx_burst` with the same bounded-retry-then-drop shape already used on the DPDK side; receive becomes `rte_eth_rx_burst`. The AF_PACKET-specific code (socket fd, `sll` addressing, `SO_*BUFFORCE`, drain-loop) is deleted.

**D3 — Peer MAC via CLI (`--client-mac` / `--server-mac`).**
DPDK ports have no ARP. The endpoint peer's MAC is resolved out-of-band in the experiment scripts (EC2 `describe-instances` on the client/server data ENI) and passed on the CLI, exactly as `--gw-mac` already supplies the middle-link peer. The Ethernet-rewrite paths that previously read `io->mac` for the AF_PACKET egress now use the port MAC + configured peer MAC.

**D4 — Measurement stays on endpoint hosts.**
Kernel `tcpdump` on the converted interface is impossible once it is DPDK-owned. The `endpoint-pcap-measurement` model already captures `/tmp/client_side.pcap` and `/tmp/server_side.pcap` on the Client and Server hosts and runs `analyze_metrics.py` there. The SmartNIC-side `tcpdump` invocation in `clientnic.sh` is removed; no new capture path is added.

**D5 — mbuf pool sizing.**
A single shared mbuf pool now feeds two RX ports; bump `MBUF_POOL_SIZE` to cover both ports' RX descriptor rings plus in-flight buffers. Keep it a power-of-two-minus-one per DPDK convention.

## Alternatives Considered

**A1 — Keep AF_PACKET, only deepen buffers / tune the kernel path further.**
Summary: extend the existing mitigations (bigger `SO_*BUFFORCE`, `PACKET_MMAP`/`TPACKET_V3` ring, more `txqueuelen`). Tradeoffs: stays within the kernel, no infra change, but every packet still pays a syscall and the qdisc remains a backpressure point — it raises the ceiling without removing the failure mode. Verdict: **rejected** — this is the symptom-treatment path the last batch already exhausted.

**A2 — `PACKET_MMAP` (TPACKET_V3) zero-copy AF_PACKET instead of DPDK.**
Summary: replace `sendto`/`recvfrom` with a memory-mapped packet ring, cutting syscall overhead while staying on the kernel driver. Tradeoffs: no vfio-pci / ENI topology change (keeps SSM trivially), but it's a second, divergent I/O model to maintain alongside the DPDK port, still shares the kernel driver's qdisc semantics, and does not match line-rate ENA PMD. Verdict: **rejected** — half-measure that adds a third I/O backend to the codebase.

**A3 — Dual ENA PMD ports + dedicated management ENI (chosen).**
Summary: both data ports on the ENA PMD, management isolated on the primary ENI. Tradeoffs: requires the CDK ENI topology change and a stack redeploy, and hand-managed peer MACs — but it removes the kernel queue entirely and unifies both ports under one I/O model already proven on eth1. Verdict: **recommended** — the only option that structurally eliminates the backpressure source.

## Risks / Trade-offs

- **Loss of kernel observability on the converted ports.** No `tcpdump`, `ip`, or `ethtool` on a vfio-pci NIC. Mitigation: endpoint-host captures (D4) already own the metrics; the in-binary `--server-pcap` path remains for the middle link.
- **Management reachability during redeploy.** If the management ENI is misconfigured, a SmartNIC with all data ENIs bound to vfio-pci is unreachable via SSM. Mitigation: verify SSM round-trip is a Success Criterion; keep the primary ENI kernel-bound and never in the vfio bind list.
- **Stale peer MAC.** A hardcoded/CLI peer MAC goes stale if an endpoint ENI is replaced. Mitigation: resolve at experiment start via `describe-instances`, same failure surface as the existing `--gw-mac`.
- **mbuf exhaustion under two RX ports.** Undersized pool starves RX. Mitigation: D5 sizing + review against both ports' ring sizes.
- **Redeploy cost / BREAKING topology.** Existing stacks must be torn down and redeployed. Acceptable — this is a demo/benchmark environment, not production.
