## ADDED Requirements

### Requirement: SYN interception, spoofing, and V stamping
When a SYN arrives on eth0, the `src/clientnic/dpdk-forwarder` variant SHALL extract the flow key, generate a random 32-bit ISN (`V`) via `rte_rand()`, create a flow entry (with spoofed_isn and client_mac), send a spoofed SYN-ACK on eth0, and forward the original SYN on eth1 with its ack-num field set to `V` and the TCP checksum recomputed. The forwarded SYN's seq (client ISN) and SYN flag SHALL be unchanged.

#### Scenario: First SYN from new client
- **WHEN** a SYN packet arrives on eth0 for a flow key not in the flow table
- **THEN** a flow entry SHALL be created, a spoofed SYN-ACK sent on eth0, and the original SYN forwarded on eth1 with ack-num == `V` and a valid recomputed TCP checksum

#### Scenario: Retransmitted SYN re-stamps V
- **WHEN** a SYN packet arrives on eth0 for a flow key already in the flow table with spoofed ISN `V`
- **THEN** no new flow SHALL be created, and the SYN SHALL be re-forwarded on eth1 with ack-num == `V` re-stamped and a valid recomputed TCP checksum

### Requirement: Spoofed SYN-ACK construction
The spoofed SYN-ACK SHALL be a 54-byte Ethernet frame (14 Ether + 20 IP + 20 TCP, no options) with:
- Ether: src=server MAC (from incoming SYN's dst), dst=client MAC (from SYN's src)
- IP: src=server IP, dst=client IP, TTL=64
- TCP: sport=server port, dport=client port, seq=`V`, ack=(client_seq+1)&0xFFFFFFFF, flags=SYN-ACK, window=65535
- Valid IP and TCP checksums

#### Scenario: Correct spoofed SYN-ACK fields
- **WHEN** a SYN is intercepted with client_seq=1000 and `V`=0xABCD0000
- **THEN** the spoofed SYN-ACK SHALL have seq=0xABCD0000, ack=1001, flags=SA, and valid checksums

### Requirement: No real SYN-ACK processing on the ClientNIC
The `dpdk-forwarder` variant SHALL NOT compute a seq delta, buffer packets, or otherwise process the real SYN-ACK. The real SYN-ACK is dropped at the ServerNIC and does not reach the ClientNIC; any SYN-ACK observed on eth1 SHALL be treated as ordinary server→client traffic and forwarded transparently.

#### Scenario: No delta computation path exists
- **WHEN** the variant is built
- **THEN** it SHALL contain no `proc_handle_syn_ack`/delta-computation entry point; eth1 ingress is handled only by transparent forwarding

### Requirement: Random ISN generation
The spoofed ISN `V` SHALL be generated using `rte_rand()` masked to 32 bits.

#### Scenario: ISN randomness
- **WHEN** a new flow is created
- **THEN** spoofed_server_isn SHALL be `(uint32_t)rte_rand()`, a uniformly distributed 32-bit value
