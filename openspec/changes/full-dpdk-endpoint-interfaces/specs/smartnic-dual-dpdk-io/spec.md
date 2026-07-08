## ADDED Requirements

### Requirement: Both data-plane interfaces run on the DPDK ENA PMD
Each SmartNIC binary SHALL drive both of its data-plane interfaces through the DPDK ENA PMD. No `AF_PACKET`/`SOCK_RAW` socket SHALL exist in the data path of either `clientnic/dpdk-forwarder` or `servernic/dpdk`.

#### Scenario: Both ports are DPDK
- **WHEN** a SmartNIC binary starts with both data ENIs bound to vfio-pci
- **THEN** it SHALL initialize exactly two `rte_eth` ports (each with 1 RX and 1 TX queue, started, promiscuous) and open zero raw sockets

#### Scenario: A data ENI is not bound
- **WHEN** fewer than two DPDK ports are available at startup
- **THEN** the binary SHALL log an error naming the missing port and exit with a non-zero status code

### Requirement: Dedicated kernel management ENI reserved for SSM
Each SmartNIC SHALL retain its primary ENI (device_index 0) as a kernel-bound management interface used only for SSM. This ENI SHALL NOT appear in the vfio-pci bind list.

#### Scenario: SSM reachable after data ENIs are bound
- **WHEN** all data-plane ENIs on a SmartNIC are bound to vfio-pci and the binary is running
- **THEN** an `aws ssm send-command` to that instance SHALL complete successfully over the management ENI

### Requirement: Peer MAC supplied via CLI for each DPDK port
Because DPDK ports perform no ARP, each endpoint-facing DPDK port's next-hop (peer) MAC SHALL be supplied on the command line and cached for all TX Ethernet headers on that port.

#### Scenario: Client peer MAC provided to the ClientNIC forwarder
- **WHEN** `--client-mac=AA:BB:CC:DD:EE:FF` is passed to `clientnic-dpdk-forwarder`
- **THEN** the client-facing DPDK port SHALL use that MAC as the destination for all client-bound frames

#### Scenario: Server peer MAC provided to ServerNIC
- **WHEN** `--server-mac=AA:BB:CC:DD:EE:FF` is passed to `servernic-dpdk`
- **THEN** the server-facing DPDK port SHALL use that MAC as the destination for all server-bound frames

#### Scenario: Missing required peer MAC
- **WHEN** a binary is started without the peer MAC required for its endpoint-facing port
- **THEN** it SHALL log an error and exit with a non-zero status code
