## ADDED Requirements

### Requirement: DPDK EAL initialization and port configuration
The ServerNIC application SHALL initialize the DPDK EAL, create a packet mempool, and configure exactly one RX queue and one TX queue on the Server-facing DPDK port (eth1, the Server-subnet ENI bound to vfio-pci) using the ENA PMD.

#### Scenario: Successful DPDK port startup
- **WHEN** the application starts with valid EAL arguments and the Server-facing ENI (eth1) is bound to vfio-pci
- **THEN** the DPDK port SHALL be configured with 1 RX queue and 1 TX queue, started, and promiscuous mode enabled

#### Scenario: DPDK port unavailable
- **WHEN** no DPDK port is available (eth1 not bound to vfio-pci)
- **THEN** the application SHALL log an error and exit with a non-zero status code

### Requirement: AF_PACKET raw socket for ClientNIC-facing interface
The ServerNIC application SHALL open a non-blocking `AF_PACKET SOCK_RAW` socket bound to the ClientNIC-facing interface (eth0, the Middle-subnet kernel ENI) for receiving forwarded SYN/data from the ClientNIC and sending translated server→client traffic back toward the ClientNIC.

#### Scenario: ClientNIC-facing socket initialization
- **WHEN** the application starts and the ClientNIC-facing interface (eth0) exists as a kernel interface
- **THEN** an AF_PACKET raw socket SHALL be opened, bound to that interface's index, and set to non-blocking mode

#### Scenario: Receiving packets from the ClientNIC
- **WHEN** a TCP packet matching the configured port arrives on the ClientNIC-facing interface (eth0)
- **THEN** the packet SHALL be read via `recvfrom()` into a raw buffer and passed to the pipeline

### Requirement: Busy-poll main loop
The application SHALL run a single-threaded busy-poll loop that alternates between polling the Server-facing DPDK port (`rte_eth_rx_burst` on eth1) and the ClientNIC-facing AF_PACKET socket (non-blocking `recvfrom` on eth0).

#### Scenario: Continuous polling
- **WHEN** the main loop is running
- **THEN** it SHALL poll the DPDK port via `rte_eth_rx_burst()` and the ClientNIC-facing socket via `recvfrom()` on each iteration without blocking

### Requirement: Sending toward the Server via DPDK
The application SHALL send packets toward the Server by allocating an mbuf from the mempool, writing the Ethernet frame (using the cached Server-side next-hop MAC as destination), and calling `rte_eth_tx_burst()` on the Server-facing DPDK port (eth1).

#### Scenario: Forward SYN/data to the Server
- **WHEN** a SYN (ack-num zeroed) or a translated client→server packet must be delivered to the Server
- **THEN** the application SHALL allocate an mbuf, set the Ether header with the DPDK port MAC as src and the Server-side next-hop MAC as dst, copy the IP+TCP payload, and transmit via `rte_eth_tx_burst()`

### Requirement: Sending toward the ClientNIC via raw socket
The application SHALL send packets toward the ClientNIC by constructing a complete Ethernet frame and calling `sendto()` on the ClientNIC-facing AF_PACKET socket (eth0).

#### Scenario: Forward translated server response toward the ClientNIC
- **WHEN** a server→client packet has been translated and must be sent toward the ClientNIC
- **THEN** it SHALL be sent via `sendto()` on the AF_PACKET socket with the ClientNIC Middle-subnet ENI MAC as destination

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
