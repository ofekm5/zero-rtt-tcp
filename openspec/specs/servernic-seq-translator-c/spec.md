## ADDED Requirements

### Requirement: Client-to-server ACK rewriting
For non-SYN packets arriving from the ClientNIC, the ServerNIC translator SHALL subtract `seq_delta` from the TCP ACK field using 32-bit wraparound, recalculate IP and TCP checksums, and send the packet toward the Server.

#### Scenario: Translate ACK for active flow
- **WHEN** a data/ACK packet arrives from the ClientNIC with ACK=A for a flow with delta=D and delta_valid=1
- **THEN** the ACK SHALL be rewritten to `(A − D) & 0xFFFFFFFF`, checksums recalculated, and the packet sent toward the Server

#### Scenario: Buffer packet when delta unknown
- **WHEN** a non-SYN packet arrives from the ClientNIC for a PENDING flow with delta_valid=0
- **THEN** the packet SHALL be buffered via `ft_buffer_pkt()` and NOT sent

#### Scenario: Unknown flow from ClientNIC
- **WHEN** a non-SYN packet arrives from the ClientNIC for a flow key not in the table
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Server-to-client SEQ rewriting
For non-SYN-ACK packets arriving from the Server, the ServerNIC translator SHALL add `seq_delta` to the TCP SEQ field using 32-bit wraparound, recalculate IP and TCP checksums, and send the packet toward the ClientNIC.

#### Scenario: Translate SEQ for active flow
- **WHEN** a data packet arrives from the Server with SEQ=S for a flow with delta=D and delta_valid=1
- **THEN** the SEQ SHALL be rewritten to `(S + D) & 0xFFFFFFFF`, checksums recalculated, and the packet sent toward the ClientNIC

#### Scenario: Unknown or incomplete flow from Server
- **WHEN** a non-SYN-ACK packet arrives from the Server for a flow not in the table or with delta_valid=0
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Checksum recalculation
After any seq/ack modification, the IP header checksum and TCP checksum SHALL be recalculated using `rte_ipv4_cksum()` and `rte_ipv4_udptcp_cksum()`.

#### Scenario: Valid checksums after rewrite
- **WHEN** a packet's SEQ or ACK field is modified
- **THEN** `ip->hdr_checksum` SHALL be set to 0 then recalculated, and `tcp->cksum` SHALL be set to 0 then recalculated, producing valid checksums
