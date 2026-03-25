## ADDED Requirements

### Requirement: eth0 uses DPDK PMD for kernel-bypass receive
The system SHALL initialize eth0 as a DPDK EAL port using `rte_eth_dev_configure` / `rte_eth_rx_queue_setup` / `rte_eth_dev_start`, replacing the AF_PACKET raw socket. The `eth0_recv` function SHALL drain packets via `rte_eth_rx_burst` and copy the first received frame into the caller-supplied `uint8_t*` buffer, preserving the existing function signature.

#### Scenario: eth0 receives a TCP SYN from client
- **WHEN** a TCP SYN frame arrives on the DPDK-bound eth0 port
- **THEN** `eth0_recv` returns the frame bytes into the buffer and the pipeline routes it to `proc_handle_syn`

#### Scenario: No packets available on eth0
- **WHEN** `rte_eth_rx_burst` returns 0 mbufs
- **THEN** `eth0_recv` returns 0 and the main loop continues to poll eth1

### Requirement: eth0 uses DPDK PMD for kernel-bypass transmit
The system SHALL transmit frames on eth0 by allocating an mbuf from the shared pool, copying the provided buffer, and calling `rte_eth_tx_burst`. The `eth0_send(uint8_t*, uint16_t)` signature SHALL be preserved.

#### Scenario: Spoofed SYN-ACK sent to client via eth0
- **WHEN** `eth0_send` is called with a crafted SYN-ACK frame
- **THEN** the frame is allocated as an mbuf and transmitted via `rte_eth_tx_burst` on eth0's TX queue

#### Scenario: mbuf pool exhausted during transmit
- **WHEN** `rte_pktmbuf_alloc` returns NULL
- **THEN** `eth0_send` logs a warning and returns -1 without crashing

### Requirement: Both NICs initialized as DPDK ports at startup
The system SHALL enumerate at least 2 available DPDK ports (or 1 port with 2 queue pairs in single-NIC mode) at startup and abort with a clear error message if insufficient ports are available.

#### Scenario: Both ENIs bound to vfio-pci before launch
- **WHEN** `rte_eth_dev_count_avail()` returns >= 2
- **THEN** eth0 initializes on port 0 and eth1 on port 1 (or as configured by CLI)

#### Scenario: Only one DPDK port available
- **WHEN** `rte_eth_dev_count_avail()` returns 1 and single-NIC mode is not set
- **THEN** startup aborts with error: "Full DPDK mode requires 2 ports; bind both NICs to vfio-pci"
