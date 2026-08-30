## 1. Probe verification gate (do first)

- [x] 1.1 On the deployed AWS VPC path, emit a SYN from the ClientNIC toward the Server with ack-num=`0xDEADBEEF` (one-off test program or a temporary `proc_handle_syn` flag)
- [x] 1.2 Capture ServerNIC ingress (tcpdump on the kernel interface, or a `--server-pcap`-style DPDK writer) and confirm bytes 8–11 == `0xDEADBEEF`
- [x] 1.3 Record the result in `experiments/zero-rtt-dpdk/reports/`; if the field is rewritten, STOP and fall back to T3 (out of scope here)

## 2. ClientNIC variant — create folder (preserve clientnic/dpdk/)

- [x] 2.1 Copy `clientnic/dpdk/` → new sibling folder `clientnic/dpdk-forwarder/` (do NOT modify `clientnic/dpdk/`); keep `dpdk-data-plane` code — EAL/AF_PACKET/busy-poll/iptables — verbatim
- [x] 2.2 Update `clientnic/dpdk-forwarder/meson.build` (project/binary name) so the variant builds independently alongside `clientnic/dpdk/`
- [x] 2.3 In `clientnic/dpdk-forwarder/flow_table.h`, remove `seq_delta`, `delta_valid`, and the `buffer`/`buf_count` fields from `struct flow_entry`; keep `spoofed_server_isn`, `state`, `client_mac`
- [x] 2.4 In `clientnic/dpdk-forwarder/flow_table.c`, delete `ft_set_delta`, `ft_buffer_pkt`, `ft_flush_buffer`, and the `pkt_buffer` machinery; keep `ft_create`/`ft_lookup`/`ft_extract_key`/`ft_reverse_key`

## 3. ClientNIC variant — SYN handling + V stamping

- [x] 3.1 In `clientnic/dpdk-forwarder/packet_processor.c` `proc_handle_syn`, after generating `V`, stamp `forwarded_syn.ack_num = htonl(V)` before TX on eth1 and recompute the TCP checksum (`recalc_tcp_checksum`)
- [x] 3.2 Change retransmit handling: on an existing flow, do NOT ignore — re-forward the SYN on eth1 with the same `V` re-stamped and checksum recomputed (no duplicate flow creation, no buffer)
- [x] 3.3 Remove `proc_handle_syn_ack` entirely from the variant (real SYN-ACK is now dropped at the ServerNIC and never reaches the ClientNIC)

## 4. ClientNIC variant — transparent forwarding

- [x] 4.1 Replace `trans_c2s` with `forward_c2s`: forward eth0 non-SYN packets to eth1 with Ethernet rewrite only (src=eth1 MAC, dst=gw MAC), no seq/ack change, no checksum recompute; drop unknown flows with a warning
- [x] 4.2 Replace `trans_s2c` with `forward_s2c`: forward eth1 packets to eth0 with Ethernet rewrite only (src=eth0 MAC, dst=cached client_mac), no seq/ack change
- [x] 4.3 Update `clientnic/dpdk-forwarder/pipeline.c` routing: eth0+SYN→`proc_handle_syn`; eth0+non-SYN→`forward_c2s`; eth1+any (known flow)→`forward_s2c` (drop the SYN-ACK special case)
- [x] 4.4 Build the `dpdk-forwarder` variant binary (`meson`/`ninja`) and confirm all checks pass; confirm `clientnic/dpdk/` still builds unchanged

## 5. ServerNIC DPDK — scaffolding & I/O

- [x] 5.1 Create `servernic/dpdk/` skeleton mirroring ClientNIC: `main.c`, `io.c/h`, `pipeline.c/h`, `flow_table.c/h`, `syn_handler.c/h`, `translator.c/h`, `checksum.c/h`, `log.c/h`, `meson.build`
- [x] 5.2 Implement EAL init, mempool, and one RX/one TX queue on the ClientNIC-facing DPDK port (eth1); enable promiscuous mode; error+exit if no DPDK port
- [x] 5.3 Implement the Server-facing AF_PACKET raw socket (eth2): non-blocking, bound, MAC read; `recv`/`send` helpers
- [x] 5.4 Implement the busy-poll loop alternating `rte_eth_rx_burst` (eth1) and `recvfrom` (eth2)
- [x] 5.5 Implement CLI parsing (`--port`, `--gw-mac` for ClientNIC-side next hop, `--client-iface`, `--server-iface`) and startup iptables RST/forward-drop rules

## 6. ServerNIC DPDK — flow table

- [x] 6.1 Implement `struct flow_key` (4-tuple, network order) + open-addressing hash table (1024 slots, linear probe) with `ft_lookup`/`ft_create`/`ft_extract_key`/`ft_reverse_key`
- [x] 6.2 Implement `struct flow_entry` with `spoofed_server_isn`(V), `real_server_isn`, `seq_delta`, `delta_valid`, `state` (PENDING/ACTIVE), Server-side next-hop MAC
- [x] 6.3 Implement idempotent `ft_set_delta` (`delta = (V − real_isn) & 0xFFFFFFFF`, state→ACTIVE) and per-flow buffering (`ft_buffer_pkt`/`ft_flush_buffer`, cap 64, overflow drop+warn)

## 7. ServerNIC DPDK — SYN handler

- [x] 7.1 `syn_handler_handle_syn`: extract key, read `V = ntohl(tcp->recv_ack)`, create/refresh PENDING flow with `V`, set `tcp->recv_ack = 0`, recompute TCP checksum, forward SYN to Server (eth2)
- [x] 7.2 Handle retransmitted SYN: retain existing PENDING entry, still zero ack + recompute + forward
- [x] 7.3 `syn_handler_handle_syn_ack`: reverse-key lookup, `ft_set_delta(real_isn)`, flush buffered c→s packets (ACK −= delta, recompute checksums, send to Server), then DROP the SYN-ACK; warn+drop on unknown flow

## 8. ServerNIC DPDK — translator

- [x] 8.1 `trans_c2s`: eth1 non-SYN → if `delta_valid` subtract delta from ACK, recompute checksums, send to Server (eth2); else buffer; drop unknown flow with warning
- [x] 8.2 `trans_s2c`: eth2 non-SYN-ACK → add delta to SEQ, recompute checksums, send toward ClientNIC (eth1); drop unknown/incomplete flow with warning
- [x] 8.3 Implement `checksum.c` (IP via `rte_ipv4_cksum`, TCP via `rte_ipv4_udptcp_cksum`) and wire into all rewrite paths
- [x] 8.4 Implement `pipeline.c` parse/validate (IPv4/TCP/port), re-capture MAC filter, ingress+flags routing to the four handlers
- [x] 8.5 Build the ServerNIC binary and confirm all checks pass

## 9. Infra & orchestration

- [x] 9.1 Update `infra/dpdk/` ServerNIC user data to build the ServerNIC DPDK binary (DPDK 23.11) and bind the ClientNIC-facing secondary ENI to vfio-pci; pin which ENI is the DPDK port vs. the AF_PACKET kernel interface
- [x] 9.1b Update `infra/dpdk/` ClientNIC user data to build the `clientnic/dpdk-forwarder/` variant (and select which ClientNIC binary — full-owner `dpdk/` vs `dpdk-forwarder/` — runs)
- [x] 9.2 Update `experiments/zero-rtt-dpdk/run_experiment.sh` to launch the `dpdk-forwarder` ClientNIC + the ServerNIC DPDK binary (startup order Server → ServerNIC → ClientNIC → Client) with correct `--gw-mac`/iface args
- [x] 9.3 Update capture/validation expectations: the real SYN-ACK is now dropped at the ServerNIC (not the ClientNIC); adjust `validate_0rtt_capture.py` usage / report assertions accordingly

## 10. Tests & docs

- [x] 10.1 Unit tests: ServerNIC flow table (create/lookup/collision/delta/idempotent/buffer overflow), SYN handler (V extract + ack zero + checksum), translator (c2s ACK −delta, s2c SEQ +delta, 32-bit wraparound)
- [x] 10.2 ClientNIC `dpdk-forwarder` unit tests: SYN forwarding stamps `V` + valid checksum, retransmit re-stamps `V`, transparent forward leaves seq/ack unchanged
- [x] 10.3 Integration test: end-to-end 0-RTT establishment, data correctness both directions, exactly one (spoofed) SYN-ACK reaches the client, c→s pre-delta buffering works
- [x] 10.4 Add `clientnic/dpdk-forwarder/README.md` documenting the variant and how it differs from `clientnic/dpdk/` (translation shifted to ServerNIC, ISN ack-num channel); add a pointer note at the top of `clientnic/dpdk/README.md`
- [x] 10.5 Update `servernic/dpdk/README.md` (no longer WIP) and `CLAUDE.md` — module structure (two coexisting ClientNIC DPDK variants), architecture (translation-shift), and key-docs references; mark `todos/tech-improvements.md` T8 done
