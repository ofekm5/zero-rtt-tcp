# servernic-dpdk-data-plane Specification

## Purpose
TBD - created by archiving change full-dpdk-endpoint-interfaces. Update Purpose after archive.
## Requirements

### Requirement: DPDK EAL initialization and port configuration
The ServerNIC application SHALL initialize the DPDK EAL, create a packet mempool, and configure exactly one RX queue and one TX queue on **two** DPDK ports using the ENA PMD: the ClientNIC-facing port (eth1, Middle-subnet ENI) and the Server-facing port (Server-subnet ENI). The mempool SHALL be sized to feed both ports' RX rings plus in-flight buffers.

#### Scenario: Successful DPDK port startup
- **WHEN** the application starts with valid EAL arguments and both the ClientNIC-facing and Server-facing ENIs are bound to vfio-pci
- **THEN** both DPDK ports SHALL be configured with 1 RX queue and 1 TX queue, started, and promiscuous mode enabled

#### Scenario: DPDK port unavailable
- **WHEN** fewer than two DPDK ports are available (a data ENI not bound to vfio-pci)
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: Busy-poll main loop
The application SHALL run a single-threaded busy-poll loop that polls both DPDK ports via `rte_eth_rx_burst` — the ClientNIC-facing port (eth1) and the Server-facing port — on each iteration without blocking.

#### Scenario: Continuous polling
- **WHEN** the main loop is running
- **THEN** it SHALL call `rte_eth_rx_burst()` on both the ClientNIC-facing and Server-facing DPDK ports on each iteration without blocking

### Requirement: Sending toward the Server via DPDK
The application SHALL send packets toward the Server by allocating an mbuf from the mempool, writing the Ethernet frame (Server-facing port MAC as src, the configured Server peer MAC as dst), and calling `rte_eth_tx_burst()` on the Server-facing DPDK port, retrying briefly on a full ring before dropping.

#### Scenario: Forward SYN/data to the Server
- **WHEN** a SYN (ack-num zeroed) or a translated client→server packet must be delivered to the Server
- **THEN** the application SHALL allocate an mbuf, set the Ether header with the Server-facing port MAC as src and the Server peer MAC as dst, copy the IP+TCP payload, and transmit via `rte_eth_tx_burst()`

### Requirement: Server peer MAC from CLI argument
The application SHALL accept a `--server-mac` command-line argument specifying the Server-side next-hop MAC used for Server-facing DPDK-port TX Ethernet headers, and SHALL exit non-zero if it is missing.

#### Scenario: Valid server MAC provided
- **WHEN** `--server-mac=AA:BB:CC:DD:EE:FF` is passed on the command line
- **THEN** the application SHALL parse and cache this MAC for all Server-facing DPDK-port TX Ethernet headers

### Requirement: Gateway MAC from CLI argument
The application SHALL accept a `--gw-mac` command-line argument specifying the Server-side next-hop MAC used for Server-facing DPDK-port (eth1) TX Ethernet headers.

#### Scenario: Valid gateway MAC provided
- **WHEN** `--gw-mac=AA:BB:CC:DD:EE:FF` is passed on the command line
- **THEN** the application SHALL parse and cache this MAC for all Server-facing DPDK-port TX Ethernet headers

#### Scenario: Missing gateway MAC
- **WHEN** `--gw-mac` is not provided
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: iptables rules at startup
The application SHALL install iptables rules at startup to suppress kernel RST packets and prevent the kernel from independently forwarding TCP traffic on the application port (the ServerNIC has `net.ipv4.ip_forward=1`, so the kernel would otherwise double-forward what the DPDK datapath forwards).

#### Scenario: RST suppression and forward blocking
- **WHEN** the application starts with `--port=8080`
- **THEN** it SHALL execute `iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP`, `iptables -A FORWARD -p tcp --dport 8080 -j DROP`, and `iptables -A FORWARD -p tcp --sport 8080 -j DROP`
