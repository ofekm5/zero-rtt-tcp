## ADDED Requirements

### Requirement: Packet parsing and validation
The pipeline SHALL parse each incoming packet by casting raw bytes to DPDK header structs (`rte_ether_hdr`, `rte_ipv4_hdr`, `rte_tcp_hdr`) and validate: ethertype is IPv4, protocol is TCP, and TCP port matches the configured application port.

#### Scenario: Valid TCP packet on application port
- **WHEN** a packet arrives with ethertype=0x0800, proto=TCP, and dst_port or src_port matching the application port
- **THEN** parsing SHALL succeed and the packet SHALL be routed to the decide phase

#### Scenario: Non-TCP or wrong port
- **WHEN** a packet is not TCP or does not match the application port
- **THEN** the packet SHALL be silently dropped

### Requirement: Re-capture loop prevention
The pipeline SHALL compare the source MAC of each packet against the local interface MACs. Packets originating from our own MACs SHALL be dropped.

#### Scenario: Outgoing packet re-captured on eth0
- **WHEN** a packet arrives on eth0 with source MAC equal to eth0's MAC
- **THEN** the packet SHALL be dropped without processing

### Requirement: Ingress-based routing
The `dpdk-forwarder` pipeline SHALL route packets based on ingress interface and TCP flags:
- eth0 + SYN → `proc_handle_syn()` (spoof SYN-ACK + forward SYN with `V` stamped)
- eth0 + non-SYN → `forward_c2s()` (transparent forward to eth1)
- eth1 + any → `forward_s2c()` (transparent forward to eth0)

The variant SHALL NOT special-case SYN-ACK on eth1, because the real SYN-ACK is dropped upstream at the ServerNIC and never reaches the ClientNIC.

#### Scenario: SYN from client on eth0
- **WHEN** a packet with SYN flag (and not ACK) arrives on eth0
- **THEN** it SHALL be dispatched to `proc_handle_syn()`

#### Scenario: Data from client on eth0
- **WHEN** a non-SYN packet arrives on eth0
- **THEN** it SHALL be dispatched to `forward_c2s()` and forwarded to eth1 without seq/ack modification

#### Scenario: Traffic from server on eth1
- **WHEN** any packet arrives on eth1 for a known flow
- **THEN** it SHALL be dispatched to `forward_s2c()` and forwarded to eth0 without seq/ack modification
