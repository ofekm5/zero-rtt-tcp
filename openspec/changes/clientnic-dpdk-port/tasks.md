## 1. Project Scaffolding

- [x] 1.1 Create `clientnic/dpdk/` directory structure with all `.c` and `.h` files (stubs)
- [x] 1.2 Create `clientnic/dpdk/meson.build` linking against `libdpdk` with all source files

## 2. Flow Table (no DPDK deps — pure C)

- [x] 2.1 Implement `flow_table.h`: `flow_key`, `flow_entry`, `pkt_buffer`, `flow_table` structs
- [x] 2.2 Implement `flow_table.c`: `ft_init()`, `ft_create()`, `ft_lookup()` with open-addressing hash + linear probing
- [x] 2.3 Implement `flow_table.c`: `ft_set_delta()` with 32-bit wraparound and idempotent behavior
- [x] 2.4 Implement `flow_table.c`: `ft_buffer_pkt()`, `ft_flush_buffer()`, `ft_extract_key()`, `ft_reverse_key()`

## 3. Checksum Helpers

- [x] 3.1 Implement `checksum.h/c`: `recalc_ip_checksum()` using `rte_ipv4_cksum()` and `recalc_tcp_checksum()` using `rte_ipv4_udptcp_cksum()`

## 4. I/O Abstraction

- [x] 4.1 Implement `io.h`: `eth0_io` and `eth1_io` structs with MAC storage and gateway MAC
- [x] 4.2 Implement `io.c`: `eth0_init()` — open AF_PACKET SOCK_RAW, bind to eth0, set O_NONBLOCK, read MAC
- [x] 4.3 Implement `io.c`: `eth0_recv()` and `eth0_send()` wrapping `recvfrom()`/`sendto()` with `sockaddr_ll`
- [x] 4.4 Implement `io.c`: `eth1_init()` — configure DPDK port 0 with 1 RX/TX queue, mempool, promiscuous mode, read MAC

## 5. Logging

- [x] 5.1 Implement `log.h/c`: RTE_LOG wrapper macros/functions for consistent logging

## 6. Packet Processor (SYN/SYN-ACK Handling)

- [x] 6.1 Implement `packet_processor.h`: `packet_processor` struct, `proc_init()`, `proc_handle_syn()`, `proc_handle_syn_ack()` signatures
- [x] 6.2 Implement `proc_handle_syn()`: extract key, check duplicate, generate ISN via `rte_rand()`, create flow with client_mac, build spoofed SYN-ACK (54-byte frame), send on eth0, forward SYN on eth1 (mbuf alloc + tx_burst)
- [x] 6.3 Implement `proc_handle_syn_ack()`: extract reverse key, call `ft_set_delta()`, flush buffer (rewrite ACK, recalc checksums, send on eth1), drop real SYN-ACK

## 7. Translator (Seq/Ack Rewriting)

- [x] 7.1 Implement `translator.h`: `translator` struct, `trans_init()`, `trans_c2s()`, `trans_s2c()` signatures
- [x] 7.2 Implement `trans_c2s()`: lookup flow, buffer if delta unknown, else subtract delta from ACK, recalc checksums, send on eth1
- [x] 7.3 Implement `trans_s2c()`: lookup reverse flow, drop if unknown, else add delta to SEQ, recalc checksums, send on eth0 (use cached client_mac)

## 8. Pipeline (Parse + Route)

- [x] 8.1 Implement `pipeline.h`: `pipeline_ctx` struct, `pipeline_init()`, `pipeline_feed_eth0()`, `pipeline_feed_eth1()` signatures
- [x] 8.2 Implement `pipeline_feed_eth0()`: parse Ether/IP/TCP, MAC filter, port filter, route SYN→proc_handle_syn, non-SYN→trans_c2s
- [x] 8.3 Implement `pipeline_feed_eth1()`: parse mbuf headers, MAC filter, port filter, route SYN-ACK→proc_handle_syn_ack, non-SYN-ACK→trans_s2c

## 9. Main Entry Point

- [x] 9.1 Implement `main.c`: EAL init, CLI arg parsing (--port, --gw-mac, --client-iface, --server-iface), mempool creation
- [x] 9.2 Implement `main.c`: component initialization (eth0_init, eth1_init, ft_init, proc_init, trans_init, pipeline_init)
- [x] 9.3 Implement `main.c`: iptables rules via `system()`, signal handler for clean shutdown
- [x] 9.4 Implement `main.c`: busy-poll loop — alternate `eth0_recv()` and `rte_eth_rx_burst()`, feed to pipeline

## 10. Build and Smoke Test

- [ ] 10.1 Verify `meson setup build && ninja -C build` compiles cleanly on ClientNIC VM
- [ ] 10.2 Run `sudo ./clientnic-dpdk -l 0 -- --port=8080 --gw-mac=<MAC>` and verify it starts without errors
- [ ] 10.3 Run single-connection end-to-end test: Server → ServerNIC (Scapy) → ClientNIC (DPDK) → Client
- [ ] 10.4 Validate with `validate_0rtt_capture.py` — all checks (spoofed SYN-ACK, ISN delta, checksums) must pass
