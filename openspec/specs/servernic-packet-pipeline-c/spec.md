## ADDED Requirements

### Requirement: Packet parsing and validation
The ServerNIC pipeline SHALL parse each incoming packet by casting raw bytes to DPDK header structs (`rte_ether_hdr`, `rte_ipv4_hdr`, `rte_tcp_hdr`) and validate: ethertype is IPv4, protocol is TCP, and TCP port matches the configured application port.

#### Scenario: Valid TCP packet on application port
- **WHEN** a packet arrives with ethertype=0x0800, proto=TCP, and dst_port or src_port matching the application port
- **THEN** parsing SHALL succeed and the packet SHALL be routed to the decide phase

#### Scenario: Non-TCP or wrong port
- **WHEN** a packet is not TCP or does not match the application port
- **THEN** the packet SHALL be silently dropped

### Requirement: Re-capture loop prevention
The ServerNIC pipeline SHALL compare the source MAC of each packet against the local interface MACs. Packets originating from our own MACs SHALL be dropped.

#### Scenario: Outgoing packet re-captured
- **WHEN** a packet arrives with source MAC equal to one of the ServerNIC's own interface MACs
- **THEN** the packet SHALL be dropped without processing

### Requirement: Ingress-based routing
The ServerNIC pipeline SHALL route packets based on ingress interface and TCP flags:
- ClientNIC-facing + SYN → `syn_handler_handle_syn()`
- ClientNIC-facing + non-SYN → `trans_c2s()`
- Server-facing + SYN-ACK → `syn_handler_handle_syn_ack()`
- Server-facing + non-SYN-ACK → `trans_s2c()`

#### Scenario: Forwarded SYN from ClientNIC
- **WHEN** a packet with SYN flag (and not ACK) arrives on the ClientNIC-facing interface
- **THEN** it SHALL be dispatched to `syn_handler_handle_syn()`

#### Scenario: Client data from ClientNIC
- **WHEN** a non-SYN packet arrives on the ClientNIC-facing interface
- **THEN** it SHALL be dispatched to `trans_c2s()`

#### Scenario: Real SYN-ACK from Server
- **WHEN** a packet with both SYN and ACK flags arrives on the Server-facing interface
- **THEN** it SHALL be dispatched to `syn_handler_handle_syn_ack()`

#### Scenario: Data from Server
- **WHEN** a non-SYN-ACK packet arrives on the Server-facing interface
- **THEN** it SHALL be dispatched to `trans_s2c()`
