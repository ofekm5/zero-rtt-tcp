## ADDED Requirements

### Requirement: DPDK EAL initialization and port configuration
The application SHALL initialize the DPDK EAL, create a packet mempool, and configure exactly one RX queue and one TX queue on DPDK port 0 (eth1) using the ENA PMD.

#### Scenario: Successful DPDK port startup
- **WHEN** the application starts with valid EAL arguments and eth1 is bound to vfio-pci
- **THEN** DPDK port 0 SHALL be configured with 1 RX queue and 1 TX queue, the port SHALL be started, and promiscuous mode SHALL be enabled

#### Scenario: DPDK port unavailable
- **WHEN** no DPDK port is available (eth1 not bound to vfio-pci)
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: AF_PACKET raw socket for eth0
The application SHALL open a non-blocking `AF_PACKET SOCK_RAW` socket bound to eth0 for receiving and sending raw Ethernet frames on the client-facing interface.

#### Scenario: eth0 socket initialization
- **WHEN** the application starts and eth0 exists as a kernel interface
- **THEN** an AF_PACKET raw socket SHALL be opened, bound to eth0's interface index, and set to non-blocking mode

#### Scenario: Receiving packets from eth0
- **WHEN** a TCP packet matching the configured port arrives on eth0
- **THEN** the packet SHALL be read via `recvfrom()` into a raw buffer and passed to the pipeline

### Requirement: Busy-poll main loop
The application SHALL run a single-threaded busy-poll loop that alternates between polling eth0 (non-blocking `recvfrom`) and eth1 (`rte_eth_rx_burst`).

#### Scenario: Continuous polling
- **WHEN** the main loop is running
- **THEN** it SHALL poll eth0 via `recvfrom()` and eth1 via `rte_eth_rx_burst()` on each iteration without blocking

### Requirement: Sending on eth1 via DPDK
The application SHALL send packets on eth1 by allocating an mbuf from the mempool, writing the Ethernet frame (using cached gateway MAC as destination), and calling `rte_eth_tx_burst()`.

#### Scenario: Forward SYN to server
- **WHEN** a SYN is intercepted on eth0 and must be forwarded to the server
- **THEN** the application SHALL allocate an mbuf, set Ether header with our eth1 MAC as src and gateway MAC as dst, copy the IP+TCP payload, and transmit via `rte_eth_tx_burst()`

### Requirement: Sending on eth0 via raw socket
The application SHALL send packets on eth0 by constructing a complete Ethernet frame and calling `sendto()` on the AF_PACKET socket.

#### Scenario: Send spoofed SYN-ACK to client
- **WHEN** a spoofed SYN-ACK is constructed
- **THEN** it SHALL be sent via `sendto()` on the AF_PACKET socket with the client's MAC as destination

### Requirement: Gateway MAC from CLI argument
The application SHALL accept a `--gw-mac` command-line argument specifying the middle subnet gateway's MAC address for eth1 Ethernet header construction.

#### Scenario: Valid gateway MAC provided
- **WHEN** `--gw-mac=AA:BB:CC:DD:EE:FF` is passed on the command line
- **THEN** the application SHALL parse and cache this MAC for all eth1 TX Ethernet headers

#### Scenario: Missing gateway MAC
- **WHEN** `--gw-mac` is not provided
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: iptables rules at startup
The application SHALL install iptables rules at startup to suppress kernel RST packets and prevent kernel forwarding of TCP traffic on the application port.

#### Scenario: RST suppression and forward blocking
- **WHEN** the application starts with `--port=8080`
- **THEN** it SHALL execute: `iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP`, `iptables -A FORWARD -p tcp --dport 8080 -j DROP`, and `iptables -A FORWARD -p tcp --sport 8080 -j DROP`
