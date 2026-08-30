## ADDED Requirements

### Requirement: Flow key identification
A flow SHALL be identified by a 4-tuple: (src_ip, src_port, dst_ip, dst_port) stored in network byte order in a `struct flow_key`.

#### Scenario: Extract key from packet headers
- **WHEN** a TCP/IP packet is parsed
- **THEN** a `flow_key` SHALL be extracted from the IP source/destination and TCP source/destination port fields

#### Scenario: Reverse key for server-to-client direction
- **WHEN** a packet arrives from the server (eth1)
- **THEN** a reverse `flow_key` SHALL be constructed by swapping src↔dst for both IP and port fields

### Requirement: Flow entry state tracking
Each flow entry SHALL store: `client_isn` (host order), `spoofed_server_isn` (host order), `state` (SYN_SENT or ESTABLISHED), `delta_valid` flag, `seq_delta` (host order), and `client_mac` (6 bytes).

#### Scenario: New flow creation
- **WHEN** a SYN is intercepted
- **THEN** a flow entry SHALL be created with state=SYN_SENT, delta_valid=0, client_isn and spoofed_server_isn set, and client_mac copied from the SYN's source Ethernet address

### Requirement: Fixed-size hash table
The flow table SHALL use a fixed-size open-addressing hash table (1024 slots) with linear probing, keyed by `flow_key`.

#### Scenario: Flow lookup
- **WHEN** `ft_lookup()` is called with a flow key
- **THEN** it SHALL return a pointer to the matching flow entry, or NULL if not found

#### Scenario: Hash collision
- **WHEN** two different flow keys hash to the same slot
- **THEN** linear probing SHALL find the next available slot for insertion and correctly locate both entries on lookup

### Requirement: Delta computation
`ft_set_delta()` SHALL compute `seq_delta = (spoofed_server_isn - real_server_isn) & 0xFFFFFFFF`, set `delta_valid=1`, and transition state to ESTABLISHED.

#### Scenario: Real SYN-ACK arrives
- **WHEN** `ft_set_delta()` is called with the real server ISN
- **THEN** delta SHALL be computed with 32-bit wraparound, state set to ESTABLISHED, and delta_valid set to 1

#### Scenario: Duplicate SYN-ACK (idempotent)
- **WHEN** `ft_set_delta()` is called for a flow that already has delta_valid=1
- **THEN** it SHALL return the existing delta without modifying the entry

### Requirement: Per-flow packet buffering
The flow table SHALL support buffering up to 64 packets per flow for flows awaiting delta computation.

#### Scenario: Buffer packet before delta known
- **WHEN** `ft_buffer_pkt()` is called for a flow with delta_valid=0
- **THEN** the packet data SHALL be copied (malloc) and stored in the flow's buffer

#### Scenario: Flush buffer after delta computed
- **WHEN** `ft_flush_buffer()` is called for a flow
- **THEN** all buffered packets SHALL be returned and the buffer cleared

#### Scenario: Buffer overflow
- **WHEN** the buffer reaches 64 packets
- **THEN** subsequent `ft_buffer_pkt()` calls SHALL drop the packet and log a warning
