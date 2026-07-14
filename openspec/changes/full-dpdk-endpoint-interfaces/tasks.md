> **Design deviation (post-review, PR #22).** Tasks 1.1/1.3/4.1 originally mandated a
> `--client-mac` flag carrying the *Client VM's peer MAC*. Review found the flag was
> **required but never read**: client-bound frames use the client MAC learned per-flow
> from the SYN (`entry->client_mac`), so no configured client peer MAC is needed. The
> flag was removed.
>
> In its place, both binaries now take the MACs of their **own** two DPDK ports
> (`--client-port-mac` / `--server-port-mac`) and resolve each port's role by matching
> `rte_eth_macaddr_get()` against them. This closes a latent bug the original design
> did not anticipate: DPDK assigns port IDs in **PCI-enumeration order, which does not
> reliably track ENI `device_index`**, so the hardcoded `port 0 / port 1` split could
> silently swap the two links. Verify commands and outcomes below reflect the shipped
> design.

## 1. ClientNIC forwarder — client-facing port to DPDK

- [x] 1.1 Replace the AF_PACKET `eth0_io` struct with a second ENA-port struct — verify: `grep -q "port_id" src/clientnic/dpdk-forwarder/io.h && ! grep -qE "sock_fd|ifindex|tx_drops" src/clientnic/dpdk-forwarder/io.h`
    - File: `src/clientnic/dpdk-forwarder/io.h`
    - Outcome: the client-facing I/O type (`struct client_io`) carries `port_id`, port `mac`, and `mbuf_pool` — shaped like the existing `eth1_io` — with no `sock_fd`/`ifindex`/`tx_drops` socket fields. It carries **no** configured client peer MAC (see deviation note); the client MAC is learned per-flow.
    - Commit: `refactor(clientnic-fwd): model client-facing port as a DPDK ENA port`

- [x] 1.2 Implement client-facing port init + RX/TX on the ENA PMD, deleting the AF_PACKET socket/`SO_*BUFFORCE`/drain-loop/`sendto`-retry code — verify: `grep -q "rte_eth_tx_burst" src/clientnic/dpdk-forwarder/io.c && ! grep -q "AF_PACKET\|SOCK_RAW\|SO_RCVBUFFORCE" src/clientnic/dpdk-forwarder/io.c`
    - File: `src/clientnic/dpdk-forwarder/io.c`
    - Outcome: client-facing init configures a DPDK port (1 RX/1 TX queue, started, promiscuous); send uses `rte_eth_tx_burst` with bounded-retry-then-drop; no raw-socket code remains.
    - Commit: `feat(clientnic-fwd): drive client-facing interface via DPDK ENA PMD`

- [x] 1.3 Poll both DPDK ports in the busy-poll loop and resolve each port's role by its own MAC; require both port MACs at startup — verify: `grep -q "io_find_port_by_mac" src/clientnic/dpdk-forwarder/main.c && grep -q "client-port-mac" src/clientnic/dpdk-forwarder/main.c && [ $(grep -c "rte_eth_rx_burst" src/clientnic/dpdk-forwarder/main.c) -ge 2 ]`
    - File: `src/clientnic/dpdk-forwarder/main.c`
    - Outcome: two ports initialized and both polled via `rte_eth_rx_burst` each iteration. `--client-port-mac` / `--server-port-mac` are parsed and required (missing value exits non-zero); each is resolved to a `port_id` via `io_find_port_by_mac()`, and an unmatched or colliding MAC is a startup error. The stale `eth0_buf`/drain loop is gone.
    - Commit: `feat(clientnic-fwd): poll dual DPDK ports, resolve port roles by MAC`

- [x] 1.4 Update packet_processor / forwarder Ethernet-rewrite paths for the DPDK client-facing port — verify: `grep -rq "client_mac" src/clientnic/dpdk-forwarder/forwarder.c && grep -q "eth0_send" src/clientnic/dpdk-forwarder/packet_processor.c`
    - File: `src/clientnic/dpdk-forwarder/packet_processor.c`, `src/clientnic/dpdk-forwarder/forwarder.c`
    - Outcome: spoofed SYN-ACK and s2c frames egress the client-facing DPDK port via `eth0_send`, addressed with the per-flow learned `entry->client_mac`; the MSS-option SYN-ACK behavior is preserved.
    - Commit: `feat(clientnic-fwd): emit client-bound frames on the DPDK client port`

## 2. ServerNIC — server-facing port to DPDK

- [x] 2.1 Replace the AF_PACKET `eth2_io` struct with a second ENA-port struct — verify: `grep -q "port_id" src/servernic/dpdk/io.h && grep -q "server_mac\|peer_mac" src/servernic/dpdk/io.h`
    - File: `src/servernic/dpdk/io.h`
    - Outcome: the server-facing I/O type carries `port_id`, port `mac`, and the configured Server peer MAC (`server_mac` — genuinely used as the TX destination, unlike ClientNIC's removed `client_mac`); no `sock_fd`/`ifindex`/`tx_drops` fields.
    - Commit: `refactor(servernic): model server-facing port as a DPDK ENA port`

- [x] 2.2 Implement server-facing port init + RX/TX on the ENA PMD, deleting the AF_PACKET socket/`SO_*BUFFORCE`/drain-loop/`sendto`-retry code — verify: `grep -q "rte_eth_tx_burst" src/servernic/dpdk/io.c && ! grep -q "AF_PACKET\|SOCK_RAW\|SO_SNDBUFFORCE" src/servernic/dpdk/io.c`
    - File: `src/servernic/dpdk/io.c`
    - Outcome: server-facing init configures a DPDK port (1 RX/1 TX, started, promiscuous); send uses `rte_eth_tx_burst` with bounded-retry-then-drop; no raw-socket code remains.
    - Commit: `feat(servernic): drive server-facing interface via DPDK ENA PMD`

- [x] 2.3 Poll both DPDK ports in the busy-poll loop, resolve port roles by MAC, and wire `--server-mac`; require it at startup — verify: `grep -q "io_find_port_by_mac" src/servernic/dpdk/main.c && grep -q "server-mac" src/servernic/dpdk/main.c && [ $(grep -c "rte_eth_rx_burst" src/servernic/dpdk/main.c) -ge 2 ]`
    - File: `src/servernic/dpdk/main.c`
    - Outcome: two ports initialized and both polled via `rte_eth_rx_burst` each iteration; `--server-mac` (Server peer MAC) parsed, cached, missing value exits non-zero; `--client-port-mac`/`--server-port-mac` resolve each port's role via `io_find_port_by_mac()`; the `eth2_buf` drain loop is gone.
    - Commit: `feat(servernic): poll dual DPDK ports and accept --server-mac`

- [x] 2.4 Update syn_handler / translator server-facing TX (SYN-ACK flush + trans_c2s) to emit via the DPDK server port with the server peer MAC — verify: `grep -q "rte_eth_tx_burst" src/servernic/dpdk/translator.c && grep -rq "peer_mac\|server_mac" src/servernic/dpdk/syn_handler.c src/servernic/dpdk/translator.c`
    - File: `src/servernic/dpdk/syn_handler.c`, `src/servernic/dpdk/translator.c`
    - Outcome: the first-data flush and all c2s server-bound segments transmit via `rte_eth_tx_burst` on the server-facing port; the T8 delta/seq/ack rewrite logic is unchanged.
    - Commit: `feat(servernic): emit server-bound frames on the DPDK server port`

## 3. Infra — dedicated management ENI + vfio bind

- [x] 3.1 Give each SmartNIC a kernel management primary ENI and make all data ENIs vfio-pci secondaries in the DPDK stack — verify: `grep -q "management\|mgmt" infra/dpdk/cdk/smartnics_stack.py`
    - File: `infra/dpdk/cdk/smartnics_stack.py`
    - Outcome: ClientNIC has a management primary ENI plus a client-facing secondary data ENI (moved off the primary, `ClientNicClientENI`, `device_index=2`) plus the middle-subnet DPDK ENI; ServerNIC keeps its management primary and its two data ENIs; the primary ENI is never bound to vfio-pci.
    - Commit: `feat(infra): dedicate a management ENI and make data ENIs DPDK on both SmartNICs`

- [x] 3.2 Bind every data ENI (not just eth1) to vfio-pci at boot, keyed on ENI identity rather than kernel interface name — verify: `grep -q "_bind_data_enis_to_vfio" infra/dpdk/cdk/smartnics_stack.py && [ $(grep -c "_bind_data_enis_to_vfio(expected_enis=" infra/dpdk/cdk/smartnics_stack.py) -ge 2 ] && grep -q "device-number" infra/dpdk/cdk/smartnics_stack.py`
    - File: `infra/dpdk/cdk/smartnics_stack.py`
    - Outcome: a shared `_bind_data_enis_to_vfio()` helper (invoked by both SmartNICs' user-data) enumerates ENIs via IMDS, reads each one's `device-number`, skips `0` (primary — management/SSM, never bound), and binds every other ENI to vfio-pci by locating its netdev **by MAC**. This replaces the original per-interface `eth1`/`eth2` bind loops, which had a naming race: unbinding `eth1` frees the name for a later-arriving ENI, so the loop waiting on `eth2` could hang and leave the box with one DPDK port. Kernel naming no longer participates in role assignment.
    - Commit: `feat(infra): bind all SmartNIC data ENIs to vfio-pci at boot`

- [x] 3.3 ~~Re-synth the DPDK CDK stack so `cdk.out/` reflects the new topology~~ — **obsolete**
    - File: ~~`infra/dpdk/cdk.out/`~~
    - Outcome: **no longer applicable.** `infra/dpdk/cdk.out/` is generated output and is now untracked/gitignored (commit `fb6462b`, "chore: untrack generated CDK output"), so there is no checked-in template to re-synth. `cdk synth` runs as part of `cdk deploy`; the topology change is validated by the deploy itself (see the deploy-gated criteria on issue #18).

## 4. Experiment orchestration — port MACs + drop tcpdump

- [x] 4.1 Resolve the MACs each SmartNIC binary needs — its peer MACs and its own two DPDK port MACs — and pass them to the node scripts — verify: `grep -q "client-port-mac" experiments/dpdk/clientnic.sh && grep -q "server-mac" experiments/dpdk/servernic.sh && grep -q "CLIENTNIC_ETH2_MAC" experiments/dpdk/run_experiment.sh`
    - File: `experiments/utils/run_core.sh`, `experiments/dpdk/clientnic.sh`, `experiments/dpdk/servernic.sh`, `experiments/dpdk/run_experiment.sh`, `experiments/proxmox/run_experiment.sh`
    - Outcome: the orchestrator discovers, via `ec2 describe-instances`, both the peer MACs (TX destinations) and each SmartNIC's own two DPDK port MACs (role identity); `run_experiment()` takes five MACs; a failed lookup aborts before launch. Also retires `servernic.sh`'s "detect the Middle ENI landed on the wrong kernel name and rebind it" hack — role assignment no longer depends on kernel naming, and under dual-DPDK that hack would have unbound whichever vfio device it found first.
    - Commit: `feat(experiments): resolve and pass DPDK port-identity and peer MACs`

- [x] 4.2 Remove the SmartNIC-side `tcpdump` on the now-DPDK client-facing interface — verify: `! grep -q "tcpdump -i eth0" experiments/dpdk/clientnic.sh`
    - File: `experiments/dpdk/clientnic.sh`
    - Outcome: no `tcpdump` runs on the DPDK-owned interface; the script relies on the Client host capture (`endpoint-pcap-measurement`) for `client_side.pcap`. The stale `ethtool -K eth0` / `txqueuelen` no-ops against the now kernel-only management ENI are gone too.
    - Commit: `refactor(experiments): drop SmartNIC-side tcpdump on DPDK-owned NIC`

## 5. Tests & docs

- [x] 5.1 Update/extend unit tests for both components to cover DPDK peer-MAC framing and remove AF_PACKET assumptions — verify: `python3 -m pytest src/clientnic/dpdk-forwarder/tests src/servernic/dpdk/tests -q`
    - File: `src/clientnic/dpdk-forwarder/tests/`, `src/servernic/dpdk/tests/`
    - Outcome: 26 tests pass and assert client/server-bound frames use the correct destination MAC; no test asserts AF_PACKET behavior.
    - Commit: `test(dpdk): cover dual-DPDK peer-MAC framing`

- [x] 5.2 Update component READMEs and CLAUDE.md to describe the dual-DPDK data plane and management ENI — verify: `grep -q "dual.DPDK\|management ENI" src/clientnic/dpdk-forwarder/README.md src/servernic/dpdk/README.md && grep -q "client-port-mac" src/clientnic/dpdk-forwarder/README.md`
    - File: `src/clientnic/dpdk-forwarder/README.md`, `src/servernic/dpdk/README.md`, `CLAUDE.md`
    - Outcome: docs reflect both ports on DPDK, the management ENI, the `--server-mac` peer flag and the `--client-port-mac`/`--server-port-mac` port-identity flags, why port IDs must not be assumed, and that endpoint interfaces are no longer AF_PACKET. `docs/capacity-model.md` additionally documents the sizing constraints of the resulting topology.
    - Commit: `docs(dpdk): document dual-DPDK data plane and peer-MAC flags`

---

## Not covered by this change (deploy-gated)

These are the change's remaining acceptance criteria and **cannot be verified without a
live stack** — they gate closing issue #18, not the code:

- [ ] SmartNICs remain SSM-reachable after all data ENIs are vfio-pci bound (needs `cdk deploy`)
- [ ] No first-data-loss / tx-drop warnings in the ServerNIC run log (needs a run — **and the
      drop counters to be restored**: the AF_PACKET→DPDK move deleted `tx_drops`, so the
      `LOG_WARN`s now fire without a number and this criterion is currently unevaluable.
      Log `rte_eth_stats_get()` per port: `imissed`, `rx_nombuf`, `oerrors`.)
- [ ] 100k-connection run shows unimodal `server_gap` — **blocked on #20**, not on this change.
      Per `docs/capacity-model.md`, the t3.micro endpoints cannot hold 100k sockets in 1 GiB
      and iperf2 is thread-per-connection, so 100k is unreachable regardless of this change.
      This criterion belongs to #20.
