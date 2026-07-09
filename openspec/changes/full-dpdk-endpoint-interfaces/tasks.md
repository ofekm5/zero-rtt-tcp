## 1. ClientNIC forwarder — client-facing port to DPDK

- [ ] 1.1 Replace the AF_PACKET `eth0_io` struct with a second ENA-port struct — verify: `grep -q "port_id" src/clientnic/dpdk-forwarder/io.h && grep -q "client_mac\|peer_mac" src/clientnic/dpdk-forwarder/io.h`
    - File: `src/clientnic/dpdk-forwarder/io.h`
    - Outcome: the client-facing I/O type carries `port_id`, port `mac`, and a configured peer MAC — shaped like the existing `eth1_io` — with no `sock_fd`/`ifindex`/`tx_drops` socket fields. The planner derives exact field names from `design.md` D2/D3.
    - Commit: `refactor(clientnic-fwd): model client-facing port as a DPDK ENA port`

- [ ] 1.2 Implement client-facing port init + RX/TX on the ENA PMD, deleting the AF_PACKET socket/`SO_*BUFFORCE`/drain-loop/`sendto`-retry code — verify: `grep -q "rte_eth_tx_burst" src/clientnic/dpdk-forwarder/io.c && ! grep -q "AF_PACKET\|SOCK_RAW\|SO_RCVBUFFORCE" src/clientnic/dpdk-forwarder/io.c`
    - File: `src/clientnic/dpdk-forwarder/io.c`
    - Outcome: client-facing init configures a DPDK port (1 RX/1 TX queue, started, promiscuous); send uses `rte_eth_tx_burst` with bounded-retry-then-drop; no raw-socket code remains.
    - Commit: `feat(clientnic-fwd): drive client-facing interface via DPDK ENA PMD`

- [ ] 1.3 Poll both DPDK ports in the busy-poll loop and wire `--client-mac`; require it at startup — verify: `grep -q "client-mac\|client_mac" src/clientnic/dpdk-forwarder/main.c && [ $(grep -c "rte_eth_rx_burst" src/clientnic/dpdk-forwarder/main.c) -ge 2 ]`
    - File: `src/clientnic/dpdk-forwarder/main.c`
    - Outcome: two ports initialized and both polled via `rte_eth_rx_burst` each iteration; `--client-mac` parsed, cached, and a missing value exits non-zero. The stale `eth0_buf`/drain loop is gone.
    - Commit: `feat(clientnic-fwd): poll dual DPDK ports and accept --client-mac`

- [ ] 1.4 Update packet_processor / forwarder Ethernet-rewrite paths to use the client peer MAC on client-facing TX — verify: `grep -rq "peer_mac\|client_mac" src/clientnic/dpdk-forwarder/packet_processor.c src/clientnic/dpdk-forwarder/forwarder.c`
    - File: `src/clientnic/dpdk-forwarder/packet_processor.c`, `src/clientnic/dpdk-forwarder/forwarder.c`
    - Outcome: spoofed SYN-ACK and s2c frames set the client peer MAC as destination via the client-facing DPDK port; the MSS-option SYN-ACK behavior is preserved.
    - Commit: `feat(clientnic-fwd): emit client-bound frames on the DPDK client port`

## 2. ServerNIC — server-facing port to DPDK

- [ ] 2.1 Replace the AF_PACKET `eth2_io` struct with a second ENA-port struct — verify: `grep -q "port_id" src/servernic/dpdk/io.h && grep -q "server_mac\|peer_mac" src/servernic/dpdk/io.h`
    - File: `src/servernic/dpdk/io.h`
    - Outcome: the server-facing I/O type carries `port_id`, port `mac`, and a configured peer MAC; no `sock_fd`/`ifindex`/`tx_drops` fields.
    - Commit: `refactor(servernic): model server-facing port as a DPDK ENA port`

- [ ] 2.2 Implement server-facing port init + RX/TX on the ENA PMD, deleting the AF_PACKET socket/`SO_*BUFFORCE`/drain-loop/`sendto`-retry code — verify: `grep -q "rte_eth_tx_burst" src/servernic/dpdk/io.c && ! grep -q "AF_PACKET\|SOCK_RAW\|SO_SNDBUFFORCE" src/servernic/dpdk/io.c`
    - File: `src/servernic/dpdk/io.c`
    - Outcome: server-facing init configures a DPDK port (1 RX/1 TX, started, promiscuous); send uses `rte_eth_tx_burst` with bounded-retry-then-drop; no raw-socket code remains.
    - Commit: `feat(servernic): drive server-facing interface via DPDK ENA PMD`

- [ ] 2.3 Poll both DPDK ports in the busy-poll loop and wire `--server-mac`; require it at startup — verify: `grep -q "server-mac\|server_mac" src/servernic/dpdk/main.c && [ $(grep -c "rte_eth_rx_burst" src/servernic/dpdk/main.c) -ge 2 ]`
    - File: `src/servernic/dpdk/main.c`
    - Outcome: two ports initialized and both polled via `rte_eth_rx_burst` each iteration; `--server-mac` parsed, cached, missing value exits non-zero; the `eth2_buf` drain loop is gone.
    - Commit: `feat(servernic): poll dual DPDK ports and accept --server-mac`

- [ ] 2.4 Update syn_handler / translator server-facing TX (SYN-ACK flush + trans_c2s) to emit via the DPDK server port with the server peer MAC — verify: `grep -q "rte_eth_tx_burst" src/servernic/dpdk/translator.c && grep -rq "peer_mac\|server_mac" src/servernic/dpdk/syn_handler.c src/servernic/dpdk/translator.c`
    - File: `src/servernic/dpdk/syn_handler.c`, `src/servernic/dpdk/translator.c`
    - Outcome: the first-data flush and all c2s server-bound segments transmit via `rte_eth_tx_burst` on the server-facing port; the T8 delta/seq/ack rewrite logic is unchanged.
    - Commit: `feat(servernic): emit server-bound frames on the DPDK server port`

## 3. Infra — dedicated management ENI + vfio bind

- [ ] 3.1 Give each SmartNIC a kernel management primary ENI and make all data ENIs vfio-pci secondaries in the DPDK stack — verify: `grep -q "management\|mgmt" infra/dpdk/cdk/smartnics_stack.py`
    - File: `infra/dpdk/cdk/smartnics_stack.py`
    - Outcome: ClientNIC has a management primary ENI plus a client-facing secondary data ENI (moved off the primary) plus the middle-subnet DPDK ENI; ServerNIC keeps its management primary and its two data ENIs; the primary ENI is never in the vfio bind list.
    - Commit: `feat(infra): dedicate a management ENI and make data ENIs DPDK on both SmartNICs`

- [ ] 3.2 Extend user-data to bind every data ENI (not just eth1) to vfio-pci at boot — verify: `[ $(grep -c "dpdk-devbind.py --bind=vfio-pci" infra/dpdk/cdk/smartnics_stack.py) -ge 2 ]`
    - File: `infra/dpdk/cdk/smartnics_stack.py`
    - Outcome: boot user-data binds both SmartNICs' data ENIs to vfio-pci (more than one bind invocation), leaving the management ENI kernel-bound.
    - Commit: `feat(infra): bind all SmartNIC data ENIs to vfio-pci at boot`

- [ ] 3.3 Re-synth the DPDK CDK stack so `cdk.out/` reflects the new topology — manual review
    - File: `infra/dpdk/cdk.out/`
    - Outcome: `cdk.out/SmartNicsStack.template.json` shows the added management ENI and updated attachments. (Synth requires the CDK venv/toolchain, so this is validated by human review of the diff, not a sandbox command.)
    - Commit: `chore(infra): re-synth DPDK stack with dual-DPDK ENI topology`

## 4. Experiment orchestration — peer MACs + drop tcpdump

- [ ] 4.1 Resolve Client and Server data-ENI MACs and pass `--client-mac`/`--server-mac` to the node scripts — verify: `grep -q "client-mac\|CLIENT_MAC" experiments/dpdk/clientnic.sh && grep -q "server-mac\|SERVER_MAC" experiments/dpdk/servernic.sh`
    - File: `experiments/utils/run_core.sh`, `experiments/dpdk/clientnic.sh`, `experiments/dpdk/servernic.sh`
    - Outcome: the orchestrator discovers the peer MACs and each SmartNIC binary is launched with its required peer-MAC flag; a failed lookup aborts before launch.
    - Commit: `feat(experiments): resolve and pass endpoint peer MACs for DPDK ports`

- [ ] 4.2 Remove the SmartNIC-side `tcpdump` on the now-DPDK client-facing interface — verify: `! grep -q "tcpdump -i eth0" experiments/dpdk/clientnic.sh`
    - File: `experiments/dpdk/clientnic.sh`
    - Outcome: no `tcpdump` runs on the DPDK-owned interface; the script relies on the Client host capture (`endpoint-pcap-measurement`) for `client_side.pcap`.
    - Commit: `refactor(experiments): drop SmartNIC-side tcpdump on DPDK-owned NIC`

## 5. Tests & docs

- [ ] 5.1 Update/extend unit tests for both components to cover DPDK peer-MAC framing and remove AF_PACKET assumptions — verify: `python3 -m pytest src/clientnic/dpdk-forwarder/tests src/servernic/dpdk/tests -q`
    - File: `src/clientnic/dpdk-forwarder/tests/`, `src/servernic/dpdk/tests/`
    - Outcome: tests pass and assert client/server-bound frames use the configured peer MAC; no test asserts AF_PACKET behavior.
    - Commit: `test(dpdk): cover dual-DPDK peer-MAC framing`

- [ ] 5.2 Update component READMEs and CLAUDE.md to describe the dual-DPDK data plane and management ENI — verify: `grep -q "client-mac\|dual.DPDK\|management ENI" src/clientnic/dpdk-forwarder/README.md src/servernic/dpdk/README.md`
    - File: `src/clientnic/dpdk-forwarder/README.md`, `src/servernic/dpdk/README.md`, `CLAUDE.md`
    - Outcome: docs reflect both ports on DPDK, the `--client-mac`/`--server-mac` flags, the management ENI, and that endpoint interfaces are no longer AF_PACKET.
    - Commit: `docs(dpdk): document dual-DPDK data plane and peer-MAC flags`
