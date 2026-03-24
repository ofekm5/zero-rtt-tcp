## ADDED Requirements

### Requirement: SYN interception and flow creation
When a SYN arrives on eth0, the processor SHALL extract the flow key, generate a random 32-bit ISN, create a flow entry (with client_isn, spoofed_isn, client_mac), send a spoofed SYN-ACK on eth0, and forward the original SYN on eth1.

#### Scenario: First SYN from new client
- **WHEN** a SYN packet arrives on eth0 for a flow key not in the flow table
- **THEN** a flow entry SHALL be created, a spoofed SYN-ACK sent on eth0, and the original SYN forwarded on eth1

#### Scenario: Retransmitted SYN
- **WHEN** a SYN packet arrives on eth0 for a flow key already in the flow table
- **THEN** the packet SHALL be ignored (no duplicate flow creation)

### Requirement: Spoofed SYN-ACK construction
The spoofed SYN-ACK SHALL be a 54-byte Ethernet frame (14 Ether + 20 IP + 20 TCP, no options) with:
- Ether: src=server MAC (from incoming SYN's dst), dst=client MAC (from SYN's src)
- IP: src=server IP, dst=client IP, TTL=64
- TCP: sport=server port, dport=client port, seq=spoofed_isn, ack=(client_seq+1)&0xFFFFFFFF, flags=SYN-ACK, window=65535
- Valid IP and TCP checksums

#### Scenario: Correct spoofed SYN-ACK fields
- **WHEN** a SYN is intercepted with client_seq=1000 and spoofed_isn=0xABCD0000
- **THEN** the spoofed SYN-ACK SHALL have seq=0xABCD0000, ack=1001, flags=SA, and valid checksums

### Requirement: Real SYN-ACK processing
When a real SYN-ACK arrives on eth1, the processor SHALL compute the seq delta, flush buffered packets (rewriting their ACK numbers), and DROP the real SYN-ACK.

#### Scenario: Real SYN-ACK arrives for known flow
- **WHEN** a SYN-ACK arrives on eth1 with seq=real_isn for a flow with spoofed_isn=S
- **THEN** delta SHALL be set to (S - real_isn) & 0xFFFFFFFF, buffered packets SHALL be flushed with ACK rewritten, and the real SYN-ACK SHALL be dropped

#### Scenario: Real SYN-ACK for unknown flow
- **WHEN** a SYN-ACK arrives on eth1 for a flow key not in the table
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Random ISN generation
The spoofed ISN SHALL be generated using `rte_rand()` masked to 32 bits.

#### Scenario: ISN randomness
- **WHEN** a new flow is created
- **THEN** spoofed_server_isn SHALL be `(uint32_t)rte_rand()`, a uniformly distributed 32-bit value
