## MODIFIED Requirements

### Requirement: DPDK EAL initialization and port configuration
The application SHALL initialize the DPDK EAL, create a packet mempool, and configure exactly one RX queue and one TX queue on **two** DPDK ports using the ENA PMD. The mempool SHALL be sized to feed both ports' RX rings plus in-flight buffers.

Port roles SHALL NOT be assigned by port ID. DPDK numbers ports in PCI-enumeration order, which does not reliably track ENI `device_index`, so a fixed `port 0` / `port 1` role split can silently swap the two links. Each port's role SHALL be resolved by matching the port's own MAC (`rte_eth_macaddr_get()`) against the local ENI MACs supplied on the command line.

#### Scenario: Successful DPDK port startup
- **WHEN** the application starts with valid EAL arguments and both data ENIs are bound to vfio-pci
- **THEN** both DPDK ports SHALL be configured with 1 RX queue and 1 TX queue, started, and promiscuous mode enabled, each bound to its role by MAC match

#### Scenario: DPDK port unavailable
- **WHEN** fewer than two DPDK ports are available (a data ENI not bound to vfio-pci)
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: Busy-poll main loop
The application SHALL run a single-threaded busy-poll loop that polls both DPDK ports via `rte_eth_rx_burst` — the client-facing port and the server-facing port — on each iteration without blocking.

#### Scenario: Continuous polling
- **WHEN** the main loop is running
- **THEN** it SHALL call `rte_eth_rx_burst()` on both the client-facing and server-facing DPDK ports on each iteration without blocking

### Requirement: Sending toward the client via DPDK
The application SHALL send packets toward the client by allocating an mbuf from the mempool, writing the Ethernet frame (client-facing port MAC as src, the flow's client MAC as dst), and calling `rte_eth_tx_burst()` on the client-facing DPDK port, retrying briefly on a full ring before dropping.

The client's MAC SHALL be learned per-flow from the source MAC of the client's SYN and stored in the flow entry. It SHALL NOT be supplied as a CLI argument: unlike the server-side next hop, the client's MAC is always observable on an already-received frame before any client-bound frame needs to be sent.

#### Scenario: Send spoofed SYN-ACK to client
- **WHEN** a spoofed SYN-ACK is constructed in response to a client SYN
- **THEN** it SHALL be transmitted via `rte_eth_tx_burst()` on the client-facing DPDK port, addressed to the client MAC learned from that SYN

## ADDED Requirements

### Requirement: DPDK port identity from CLI arguments
The application SHALL accept `--client-port-mac` and `--server-port-mac` command-line arguments carrying the MACs of its **own** two data ENIs (client-facing and server-facing respectively), and SHALL exit non-zero if either is missing.

These identify which DPDK port plays which role. They are **local port identities, not peer/next-hop MACs**.

#### Scenario: Port roles resolved by MAC
- **WHEN** `--client-port-mac` and `--server-port-mac` are passed and each matches an available DPDK port's own MAC
- **THEN** the application SHALL bind each role to the matching port ID and log the resulting port map

#### Scenario: A supplied port MAC matches no DPDK port
- **WHEN** either port MAC matches no available DPDK port (e.g. that ENI was not bound to vfio-pci)
- **THEN** the application SHALL log an error naming the unmatched MAC and exit with a non-zero status code

#### Scenario: Both port MACs resolve to the same port
- **WHEN** `--client-port-mac` and `--server-port-mac` resolve to the same DPDK port ID
- **THEN** the application SHALL log an error and exit with a non-zero status code

## REMOVED Requirements

### Requirement: AF_PACKET raw socket for eth0
**Reason**: The client-facing interface is converted from a kernel AF_PACKET socket to a DPDK ENA PMD port, removing the kernel socket, its `sndbuf`/`qdisc` backpressure, and the per-packet syscall.
**Migration**: The client-facing port is now a DPDK port, identified by `--client-port-mac` (never by port ID); RX uses `rte_eth_rx_burst()` and TX uses `rte_eth_tx_burst()`. See the modified "Busy-poll main loop" and "Sending toward the client via DPDK" requirements.

### Requirement: Sending on eth0 via raw socket
**Reason**: Replaced by DPDK TX on the client-facing port.
**Migration**: Use `rte_eth_tx_burst()` on the client-facing DPDK port, addressed to the per-flow learned client MAC (see "Sending toward the client via DPDK").
