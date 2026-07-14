## ADDED Requirements

### Requirement: Both data-plane interfaces run on the DPDK ENA PMD
Each SmartNIC binary SHALL drive both of its data-plane interfaces through the DPDK ENA PMD. No `AF_PACKET`/`SOCK_RAW` socket SHALL exist in the data path of either `src/clientnic/dpdk-forwarder` or `src/servernic/dpdk`.

#### Scenario: Both ports are DPDK
- **WHEN** a SmartNIC binary starts with both data ENIs bound to vfio-pci
- **THEN** it SHALL initialize exactly two `rte_eth` ports (each with 1 RX and 1 TX queue, started, promiscuous) and open zero raw sockets

#### Scenario: A data ENI is not bound
- **WHEN** fewer than two DPDK ports are available at startup
- **THEN** the binary SHALL log an error naming the missing port and exit with a non-zero status code

### Requirement: Dedicated kernel management ENI reserved for SSM
Each SmartNIC SHALL retain its primary ENI (device_index 0) as a kernel-bound management interface used only for SSM. This ENI SHALL NOT appear in the vfio-pci bind list.

The boot-time vfio-pci bind SHALL select ENIs by identity — IMDS `device-number`, with the netdev located by MAC — and SHALL NOT key on kernel interface names. Names are unreliable here on two counts: the data ENIs are not guaranteed to come up as `eth1`/`eth2` in `device_index` order, and unbinding one ENI frees its name for a later-arriving one.

#### Scenario: SSM reachable after data ENIs are bound
- **WHEN** all data-plane ENIs on a SmartNIC are bound to vfio-pci and the binary is running
- **THEN** an `aws ssm send-command` to that instance SHALL complete successfully over the management ENI

#### Scenario: Every non-primary ENI is bound regardless of naming
- **WHEN** the instance boots with a primary ENI and two data ENIs, in any kernel-naming order
- **THEN** boot user-data SHALL bind exactly the ENIs whose IMDS `device-number` is non-zero to vfio-pci, and SHALL leave `device-number` 0 kernel-bound

### Requirement: Next-hop MAC supplied via CLI only where it cannot be learned
Because DPDK ports perform no ARP, a next-hop MAC that cannot be observed on an already-received frame SHALL be supplied on the command line and cached for all TX Ethernet headers on that port.

This applies to the **server-side** next hops only. A client's MAC is always visible as the source MAC of its own SYN, so it SHALL be learned per-flow and stored in the flow entry rather than configured; a configured client peer MAC would be dead configuration.

#### Scenario: Server peer MAC provided to ServerNIC
- **WHEN** `--server-mac=AA:BB:CC:DD:EE:FF` is passed to `servernic-dpdk`
- **THEN** the server-facing DPDK port SHALL use that MAC as the destination for all server-bound frames

#### Scenario: ServerNIC gateway MAC provided to the ClientNIC forwarder
- **WHEN** `--gw-mac=AA:BB:CC:DD:EE:FF` is passed to `clientnic-dpdk-forwarder`
- **THEN** the ServerNIC-facing DPDK port SHALL use that MAC as the destination for all ServerNIC-bound frames

#### Scenario: Client MAC learned, not configured
- **WHEN** `clientnic-dpdk-forwarder` emits a spoofed SYN-ACK or an s2c frame on the client-facing port
- **THEN** the destination MAC SHALL be the one learned from that flow's SYN, and the binary SHALL NOT require a client peer MAC on the command line

#### Scenario: Missing required next-hop MAC
- **WHEN** a binary is started without a next-hop MAC that it cannot learn
- **THEN** it SHALL log an error and exit with a non-zero status code

### Requirement: DPDK port roles resolved by ENI identity, not by port ID
Each SmartNIC binary SHALL determine which DPDK port is client-facing and which is server-facing by matching each port's own MAC (`rte_eth_macaddr_get()`) against the local ENI MACs supplied via `--client-port-mac` / `--server-port-mac`. Port roles SHALL NOT be derived from DPDK port IDs, kernel interface names, or ENI `device_index` — none of which reliably correspond to one another.

#### Scenario: Ports enumerate in an unexpected order
- **WHEN** PCI enumeration places a SmartNIC's endpoint-facing ENI at DPDK port 0 on one instance and at port 1 on another
- **THEN** the binary SHALL still bind each role to the correct link, because the role is resolved by MAC rather than by port ID

#### Scenario: An expected port MAC is absent or ambiguous
- **WHEN** a supplied port MAC matches no available DPDK port, or both supplied MACs resolve to the same port
- **THEN** the binary SHALL log an error naming the offending MAC and exit non-zero, rather than proceed with an ambiguous mapping
