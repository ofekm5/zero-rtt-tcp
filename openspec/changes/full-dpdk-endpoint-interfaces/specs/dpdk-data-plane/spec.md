## MODIFIED Requirements

### Requirement: DPDK EAL initialization and port configuration
The application SHALL initialize the DPDK EAL, create a packet mempool, and configure exactly one RX queue and one TX queue on **two** DPDK ports using the ENA PMD: port 0 = the client-facing interface, port 1 = the server-facing interface (eth1). The mempool SHALL be sized to feed both ports' RX rings plus in-flight buffers.

#### Scenario: Successful DPDK port startup
- **WHEN** the application starts with valid EAL arguments and both data ENIs are bound to vfio-pci
- **THEN** both DPDK ports SHALL be configured with 1 RX queue and 1 TX queue, started, and promiscuous mode enabled

#### Scenario: DPDK port unavailable
- **WHEN** fewer than two DPDK ports are available (a data ENI not bound to vfio-pci)
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: Busy-poll main loop
The application SHALL run a single-threaded busy-poll loop that polls both DPDK ports via `rte_eth_rx_burst` — the client-facing port and the server-facing port (eth1) — on each iteration without blocking.

#### Scenario: Continuous polling
- **WHEN** the main loop is running
- **THEN** it SHALL call `rte_eth_rx_burst()` on both the client-facing and server-facing DPDK ports on each iteration without blocking

### Requirement: Sending toward the client via DPDK
The application SHALL send packets toward the client by allocating an mbuf from the mempool, writing the Ethernet frame (client-facing port MAC as src, the configured client peer MAC as dst), and calling `rte_eth_tx_burst()` on the client-facing DPDK port, retrying briefly on a full ring before dropping.

#### Scenario: Send spoofed SYN-ACK to client
- **WHEN** a spoofed SYN-ACK is constructed
- **THEN** it SHALL be transmitted via `rte_eth_tx_burst()` on the client-facing DPDK port with the client peer MAC as destination

## ADDED Requirements

### Requirement: Client peer MAC from CLI argument
The application SHALL accept a `--client-mac` command-line argument specifying the client-side next-hop MAC used for client-facing DPDK-port TX Ethernet headers, and SHALL exit non-zero if it is missing.

#### Scenario: Valid client MAC provided
- **WHEN** `--client-mac=AA:BB:CC:DD:EE:FF` is passed on the command line
- **THEN** the application SHALL parse and cache this MAC for all client-facing DPDK-port TX Ethernet headers

## REMOVED Requirements

### Requirement: AF_PACKET raw socket for eth0
**Reason**: The client-facing interface is converted from a kernel AF_PACKET socket to a DPDK ENA PMD port, removing the kernel socket, its `sndbuf`/`qdisc` backpressure, and the per-packet syscall.
**Migration**: The client-facing port is now DPDK port 0; RX uses `rte_eth_rx_burst()` and TX uses `rte_eth_tx_burst()`. See the modified "Busy-poll main loop" and "Sending toward the client via DPDK" requirements.

### Requirement: Sending on eth0 via raw socket
**Reason**: Replaced by DPDK TX on the client-facing port.
**Migration**: Use `rte_eth_tx_burst()` on the client-facing DPDK port with the `--client-mac` destination (see "Sending toward the client via DPDK").
