## ADDED Requirements

### Requirement: Client-to-server ACK rewriting
For non-SYN packets from eth0, the translator SHALL subtract seq_delta from the TCP ACK field using 32-bit wraparound, recalculate IP and TCP checksums, and send the packet on eth1.

#### Scenario: Translate ACK for established flow
- **WHEN** a data packet arrives on eth0 with ACK=A for a flow with delta=D and delta_valid=1
- **THEN** the ACK SHALL be rewritten to (A - D) & 0xFFFFFFFF, checksums recalculated, and the packet sent on eth1

#### Scenario: Buffer packet when delta unknown
- **WHEN** a data packet arrives on eth0 for a flow with delta_valid=0
- **THEN** the packet SHALL be buffered via `ft_buffer_pkt()` and NOT sent

#### Scenario: Unknown flow on eth0
- **WHEN** a non-SYN packet arrives on eth0 for a flow key not in the table
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Server-to-client SEQ rewriting
For non-SYN-ACK packets from eth1, the translator SHALL add seq_delta to the TCP SEQ field using 32-bit wraparound, recalculate IP and TCP checksums, and send the packet on eth0.

#### Scenario: Translate SEQ for established flow
- **WHEN** a data packet arrives on eth1 with SEQ=S for a flow with delta=D and delta_valid=1
- **THEN** the SEQ SHALL be rewritten to (S + D) & 0xFFFFFFFF, checksums recalculated, and the packet sent on eth0

#### Scenario: Unknown or incomplete flow on eth1
- **WHEN** a non-SYN-ACK packet arrives on eth1 for a flow not in the table or with delta_valid=0
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Checksum recalculation
After any seq/ack modification, the IP header checksum and TCP checksum SHALL be recalculated using `rte_ipv4_cksum()` and `rte_ipv4_udptcp_cksum()`.

#### Scenario: Valid checksums after rewrite
- **WHEN** a packet's SEQ or ACK field is modified
- **THEN** `ip->hdr_checksum` SHALL be set to 0 then recalculated, and `tcp->cksum` SHALL be set to 0 then recalculated, producing valid checksums
