## ADDED Requirements

### Requirement: Flow key identification
A ServerNIC flow SHALL be identified by a 4-tuple: (src_ip, src_port, dst_ip, dst_port) stored in network byte order in a `struct flow_key`, matching the client→server direction.

#### Scenario: Extract key from packet headers
- **WHEN** a TCP/IP packet is parsed
- **THEN** a `flow_key` SHALL be extracted from the IP source/destination and TCP source/destination port fields

#### Scenario: Reverse key for server-to-client direction
- **WHEN** a packet arrives from the Server
- **THEN** a reverse `flow_key` SHALL be constructed by swapping src↔dst for both IP and port fields so the client→server entry can be located

### Requirement: Flow entry state tracking
Each ServerNIC flow entry SHALL store: `spoofed_server_isn` (`V`, host order), `real_server_isn` (host order), `seq_delta` (host order), `delta_valid` flag, `state` (PENDING or ACTIVE), and the next-hop MAC needed to forward toward the Server.

#### Scenario: New pending flow creation
- **WHEN** a forwarded SYN carrying `V` is received for a 4-tuple not in the table
- **THEN** a flow entry SHALL be created with state=PENDING, delta_valid=0, and spoofed_server_isn set to `V`

### Requirement: Fixed-size hash table
The ServerNIC flow table SHALL use a fixed-size open-addressing hash table (1024 slots) with linear probing, keyed by `flow_key`.

#### Scenario: Flow lookup
- **WHEN** `ft_lookup()` is called with a flow key
- **THEN** it SHALL return a pointer to the matching flow entry, or NULL if not found

#### Scenario: Hash collision
- **WHEN** two different flow keys hash to the same slot
- **THEN** linear probing SHALL find the next available slot for insertion and correctly locate both entries on lookup

### Requirement: Delta computation
`ft_set_delta()` SHALL compute `seq_delta = (spoofed_server_isn − real_server_isn) & 0xFFFFFFFF`, set `delta_valid=1`, and transition state to ACTIVE.

#### Scenario: Real SYN-ACK arrives
- **WHEN** `ft_set_delta()` is called with the real server ISN for a PENDING flow
- **THEN** delta SHALL be computed with 32-bit wraparound, state set to ACTIVE, and delta_valid set to 1

#### Scenario: Duplicate SYN-ACK (idempotent)
- **WHEN** `ft_set_delta()` is called for a flow that already has delta_valid=1
- **THEN** it SHALL return the existing delta without modifying the entry

### Requirement: Per-flow packet buffering
The ServerNIC flow table SHALL support buffering up to 64 packets per flow for PENDING flows awaiting delta computation.

#### Scenario: Buffer packet before delta known
- **WHEN** `ft_buffer_pkt()` is called for a flow with delta_valid=0
- **THEN** the packet data SHALL be copied (malloc) and stored in the flow's buffer

#### Scenario: Flush buffer after delta computed
- **WHEN** `ft_flush_buffer()` is called for a flow
- **THEN** all buffered packets SHALL be returned and the buffer cleared

#### Scenario: Buffer overflow
- **WHEN** the buffer reaches 64 packets
- **THEN** subsequent `ft_buffer_pkt()` calls SHALL drop the packet and log a warning
