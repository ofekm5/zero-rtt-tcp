## ADDED Requirements

### Requirement: Packet parsing and validation
The pipeline SHALL parse each incoming packet by casting raw bytes to DPDK header structs (`rte_ether_hdr`, `rte_ipv4_hdr`, `rte_tcp_hdr`) and validate: ethertype is IPv4, protocol is TCP, and TCP port matches the configured application port.

#### Scenario: Valid TCP packet on application port
- **WHEN** a packet arrives with ethertype=0x0800, proto=TCP, and dst_port or src_port matches the application port
- **THEN** parsing SHALL succeed and the packet SHALL be routed to the decide phase

#### Scenario: Non-TCP or wrong port
- **WHEN** a packet is not TCP or does not match the application port
- **THEN** the packet SHALL be silently dropped

### Requirement: Re-capture loop prevention
The pipeline SHALL compare the source MAC of each packet against the local interface MAC. Packets originating from our own MACs SHALL be dropped.

#### Scenario: Outgoing packet re-captured on eth0
- **WHEN** a packet arrives on eth0 with source MAC equal to eth0's MAC
- **THEN** the packet SHALL be dropped without processing

### Requirement: Ingress-based routing
The pipeline SHALL route packets based on ingress interface and TCP flags:
- eth0 + SYN → `proc_handle_syn()`
- eth0 + non-SYN → `trans_c2s()`
- eth1 + SYN-ACK → `proc_handle_syn_ack()`
- eth1 + non-SYN-ACK → `trans_s2c()`

#### Scenario: SYN from client on eth0
- **WHEN** a packet with SYN flag (and not ACK) arrives on eth0
- **THEN** it SHALL be dispatched to `proc_handle_syn()`

#### Scenario: Data from client on eth0
- **WHEN** a non-SYN packet arrives on eth0
- **THEN** it SHALL be dispatched to `trans_c2s()`

#### Scenario: SYN-ACK from server on eth1
- **WHEN** a packet with both SYN and ACK flags arrives on eth1
- **THEN** it SHALL be dispatched to `proc_handle_syn_ack()`

#### Scenario: Data from server on eth1
- **WHEN** a non-SYN-ACK packet arrives on eth1
- **THEN** it SHALL be dispatched to `trans_s2c()`
