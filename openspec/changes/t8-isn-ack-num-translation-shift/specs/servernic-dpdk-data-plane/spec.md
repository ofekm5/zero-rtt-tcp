## ADDED Requirements

### Requirement: DPDK EAL initialization and port configuration
The ServerNIC application SHALL initialize the DPDK EAL, create a packet mempool, and configure exactly one RX queue and one TX queue on the ClientNIC-facing DPDK port (eth1) using the ENA PMD.

#### Scenario: Successful DPDK port startup
- **WHEN** the application starts with valid EAL arguments and the ClientNIC-facing ENI is bound to vfio-pci
- **THEN** the DPDK port SHALL be configured with 1 RX queue and 1 TX queue, started, and promiscuous mode enabled

#### Scenario: DPDK port unavailable
- **WHEN** no DPDK port is available (ENI not bound to vfio-pci)
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: AF_PACKET raw socket for Server-facing interface
The ServerNIC application SHALL open a non-blocking `AF_PACKET SOCK_RAW` socket bound to the Server-facing interface (eth2) for sending forwarded SYN/data to the Server and receiving the Server's responses.

#### Scenario: Server-facing socket initialization
- **WHEN** the application starts and the Server-facing interface exists as a kernel interface
- **THEN** an AF_PACKET raw socket SHALL be opened, bound to that interface's index, and set to non-blocking mode

#### Scenario: Receiving packets from the Server
- **WHEN** a TCP packet matching the configured port arrives on the Server-facing interface
- **THEN** the packet SHALL be read via `recvfrom()` into a raw buffer and passed to the pipeline

### Requirement: Busy-poll main loop
The application SHALL run a single-threaded busy-poll loop that alternates between polling the ClientNIC-facing DPDK port (`rte_eth_rx_burst`) and the Server-facing AF_PACKET socket (non-blocking `recvfrom`).

#### Scenario: Continuous polling
- **WHEN** the main loop is running
- **THEN** it SHALL poll the DPDK port via `rte_eth_rx_burst()` and the Server-facing socket via `recvfrom()` on each iteration without blocking

### Requirement: Sending toward the ClientNIC via DPDK
The application SHALL send packets toward the ClientNIC by allocating an mbuf from the mempool, writing the Ethernet frame (using the cached ClientNIC-side gateway MAC as destination), and calling `rte_eth_tx_burst()`.

#### Scenario: Forward translated server response toward client
- **WHEN** a server→client packet has been translated and must be sent toward the ClientNIC
- **THEN** the application SHALL allocate an mbuf, set the Ether header with the DPDK port MAC as src and the ClientNIC-side gateway MAC as dst, copy the IP+TCP payload, and transmit via `rte_eth_tx_burst()`

### Requirement: Sending toward the Server via raw socket
The application SHALL send packets toward the Server by constructing a complete Ethernet frame and calling `sendto()` on the Server-facing AF_PACKET socket.

#### Scenario: Forward SYN/data to the Server
- **WHEN** a SYN (ack-num zeroed) or a translated client→server packet must be delivered to the Server
- **THEN** it SHALL be sent via `sendto()` on the AF_PACKET socket with the Server-side next-hop MAC as destination

### Requirement: Gateway MAC from CLI argument
The application SHALL accept a `--gw-mac` command-line argument specifying the ClientNIC-side next-hop MAC used for DPDK-port TX Ethernet headers.

#### Scenario: Valid gateway MAC provided
- **WHEN** `--gw-mac=AA:BB:CC:DD:EE:FF` is passed on the command line
- **THEN** the application SHALL parse and cache this MAC for all DPDK-port TX Ethernet headers

#### Scenario: Missing gateway MAC
- **WHEN** `--gw-mac` is not provided
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: iptables rules at startup
The application SHALL install iptables rules at startup to suppress kernel RST packets and prevent kernel forwarding of TCP traffic on the application port across its interfaces.

#### Scenario: RST suppression and forward blocking
- **WHEN** the application starts with `--port=8080`
- **THEN** it SHALL execute `iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP`, `iptables -A FORWARD -p tcp --dport 8080 -j DROP`, and `iptables -A FORWARD -p tcp --sport 8080 -j DROP`
