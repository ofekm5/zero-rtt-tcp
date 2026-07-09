## Why

The AF_PACKET endpoint-facing interfaces (ClientNIC client-facing port, ServerNIC eth2 server-facing port) are the sole remaining source of egress backpressure and RX tail-drop in the SmartNIC data plane: the kernel socket `sndbuf`/`qdisc` fills under the 100k-connection burst, and every packet pays a `sendto`/`recvfrom` syscall. The last batch of work (16 MB `SO_*BUFFORCE` buffers, bounded `sendto` retries, drain-until-empty RX loops) treated the symptom. Moving these ports to the DPDK ENA PMD removes the kernel queue entirely, so the fix is structural rather than a mitigation.

## Non-Goals

- **Not** porting to the BlueField-3 / DPU platform — this is AWS EC2 ENA PMD only.
- **Not** touching the legacy Scapy stack (`src/clientnic/scapy/`, `src/servernic/scapy/`).
- **Not** converting the full-owner `src/clientnic/dpdk/` variant — only the active T8 `src/clientnic/dpdk-forwarder/`.
- **Not** changing T8 translation logic (V stamping, delta math, seq/ack rewrite, buffering) — this is an I/O-layer change only.
- **Not** runtime ARP resolution on the DPDK ports — peer MACs are resolved out-of-band and passed on the CLI, mirroring the existing `--gw-mac` pattern (this was considered and deferred).
- **Not** adding in-binary DPDK pcap capture on the endpoint ports — measurement relies on the Client/Server host captures per `endpoint-pcap-measurement`.
- **Not** re-tuning flow-table sizing or the 100k sysctls — those remain as-is.

## What Changes

- **Infra (CDK, both stacks' `smartnics_stack.py`):** Each SmartNIC gets a **dedicated management ENI** (primary, device_index 0, kernel-bound, SSM only). All data-plane ENIs become **vfio-pci secondaries**. ClientNIC's client-facing data moves from its primary ENI onto a new secondary ENI; ServerNIC's eth2 (server-facing) rebinds from kernel to vfio-pci. User-data binds every data ENI to vfio-pci at boot. **BREAKING** for the deployed topology (requires stack redeploy).
- **ClientNIC forwarder (`src/clientnic/dpdk-forwarder/`):** Replace the `eth0_io` AF_PACKET struct and its `eth0_recv`/`eth0_send`/`SO_*BUFFORCE`/drain-loop/`sendto`-retry code with a **second ENA PMD port** (`rte_eth_rx_burst`/`tx_burst`, shared mbuf pool). Both ports polled in the single busy-poll loop. Client MAC passed via a new `--client-mac` CLI flag.
- **ServerNIC (`src/servernic/dpdk/`):** Same conversion for the eth2 server-facing port — drop `eth2_io` AF_PACKET, add a second ENA PMD port, add `--server-mac`.
- **Experiments (`experiments/dpdk/*.sh`, `run_core.sh`):** Resolve client/server peer MACs via EC2 `describe-instances`; pass the new `--client-mac`/`--server-mac`. Remove the now-impossible SmartNIC-side `tcpdump` (the interface is DPDK-owned); metrics come from the Client/Server host pcaps.

## Capabilities

### New Capabilities
- `smartnic-dual-dpdk-io`: Both data-plane interfaces on each SmartNIC run on the DPDK ENA PMD (no AF_PACKET in the data path), with a dedicated kernel management ENI reserved for SSM and peer MACs supplied via CLI.

### Modified Capabilities
- `dpdk-data-plane`: ClientNIC forwarder I/O layer changes from AF_PACKET eth0 + DPDK eth1 to dual DPDK ports.
- `servernic-dpdk-data-plane`: ServerNIC I/O layer changes from DPDK eth1 + AF_PACKET eth2 to dual DPDK ports.
- `dpdk-node-script-runner`: Experiment runners resolve/pass peer MACs and no longer run SmartNIC-side tcpdump.

## Impact

- **Code:** `src/clientnic/dpdk-forwarder/{io.c,io.h,main.c,packet_processor.c,forwarder.c}`, `src/servernic/dpdk/{io.c,io.h,main.c,syn_handler.c,translator.c}`, both `meson.build` if needed.
- **Infra:** `infra/dpdk/cdk/smartnics_stack.py` (ENI topology + user-data vfio bind); `infra/dpdk/cdk.out/` re-synth. Scapy stack ENIs unaffected but its `smartnics_stack.py` shares patterns.
- **Experiments:** `experiments/dpdk/clientnic.sh`, `experiments/dpdk/servernic.sh`, `experiments/utils/run_core.sh`.
- **Dependencies:** none new — DPDK 23.11 ENA PMD already provisioned.
- **Ops:** requires a full stack redeploy (ENI topology change); SmartNICs reachable only via the new management ENI once data ENIs are bound.

## Success Criteria

- [ ] Both binaries run with zero AF_PACKET sockets in the data path — measured by: `grep -rE "AF_PACKET|SOCK_RAW|PF_PACKET" src/clientnic/dpdk-forwarder src/servernic/dpdk` returns no matches in non-test source, plus code review.
- [ ] SmartNICs remain SSM-reachable after all data ENIs are vfio-pci bound — measured by: an `aws ssm send-command` round-trip to both SmartNICs succeeds post-boot.
- [ ] The 100k-connection DPDK experiment completes with no bimodal `server_gap` regression vs. the AF_PACKET baseline — measured by: `experiments/dpdk/run_experiment.sh` + `analyze_metrics.py` report shows unimodal server_gap.
- [ ] No first-data-loss warnings and no tx-drop accounting in the ServerNIC run log during the benchmark — measured by: run-log inspection (the AF_PACKET `tx_drops` counters and warnings are gone).
- [ ] Unit tests pass for both components — measured by: `python3 -m pytest src/clientnic/dpdk-forwarder/tests src/servernic/dpdk/tests`.

triage-verdict: ok
