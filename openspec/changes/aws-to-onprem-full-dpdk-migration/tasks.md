## 1. Restructure eth0_io for DPDK

- [ ] 1.1 Update `eth0_io` struct in `io.h` — replace `sock_fd`/`ifindex` fields with `port_id` (uint16_t), `mbuf_pool` pointer, and `gw_mac[6]` to mirror `eth1_io`
- [ ] 1.2 Add `client-port` CLI arg to `main.c` (DPDK port ID for eth0, default 0)
- [ ] 1.3 Rewrite `eth0_init` in `io.c` using `rte_eth_dev_configure` / `rte_eth_rx_queue_setup` / `rte_eth_tx_queue_setup` / `rte_eth_dev_start` (same pattern as `eth1_init`)
- [ ] 1.4 Rewrite `eth0_recv` to call `rte_eth_rx_burst`, copy first mbuf payload into caller buffer, free mbuf, return byte count
- [ ] 1.5 Rewrite `eth0_send` to allocate mbuf from pool, memcpy buffer in, call `rte_eth_tx_burst`; log warning and return -1 on pool exhaustion

## 2. Update Main Loop and Startup

- [ ] 2.1 Remove `install_iptables()` call and function body from `main.c`
- [ ] 2.2 Update port availability check: require >= 2 DPDK ports in two-NIC mode; abort with clear error if insufficient
- [ ] 2.3 Pass `mbuf_pool` and `gw_mac` to `eth0_init` in `main.c` (pool can be shared with eth1)
- [ ] 2.4 Replace `eth0_recv` AF_PACKET poll in main loop with the new DPDK-backed call (loop body stays structurally identical)

## 3. ARP Handler

- [ ] 3.1 Create `arp.h` / `arp.c` — `arp_handle(eth_io, pkt, len)` function that parses ARP REQUEST and sends REPLY using the interface's own IP and MAC
- [ ] 3.2 Add IP address fields to both `eth0_io` and `eth1_io` structs (needed for ARP target matching); populate from CLI args `--eth0-ip` / `--eth1-ip`
- [ ] 3.3 Wire `arp_handle` into `pipeline_feed_eth0` and `pipeline_feed_eth1` in `pipeline.c` — check ethertype 0x0806 before existing TCP dispatch; drop non-IPv4/non-ARP frames silently
- [ ] 3.4 Add RST software drop in `pipeline_feed_eth0`: if TCP RST flag set, return without forwarding
- [ ] 3.5 Implement gratuitous ARP transmission in `arp.c` (`arp_send_gratuitous(eth_io)`); call for both interfaces in `main.c` after port init, before poll loop

## 4. Single-NIC VLAN Mode

- [ ] 4.1 Add `--single-nic`, `--client-vlan <id>`, `--server-vlan <id>` CLI args to `main.c`; validate that client-vlan != server-vlan
- [ ] 4.2 In single-NIC mode, initialize both `eth0_io` and `eth1_io` against port 0 with queue indices 0 and 1 respectively
- [ ] 4.3 Enable DPDK VLAN filtering per queue pair using `rte_eth_dev_vlan_filter` for the configured VLAN IDs
- [ ] 4.4 Log single-NIC startup message: "Single-NIC mode: port=0 client-queue=0 vlan=X server-queue=1 vlan=Y"
- [ ] 4.5 Ensure two-NIC mode remains default (no VLAN config) when `--single-nic` is absent

## 5. Validation

- [ ] 5.1 Smoke test two-NIC mode on bare metal: bind both NICs to vfio-pci, run a full 0-RTT connection, verify SYN-ACK spoof and sequence number translation work end-to-end
- [ ] 5.2 Verify ARP: confirm neighbor caches are populated on both sides after startup (check with `arp -n` on client/server before sending traffic)
- [ ] 5.3 Confirm no iptables rules are needed: verify RST packets are dropped in pipeline and kernel never sees them
- [ ] 5.4 Smoke test single-NIC VLAN mode with a VLAN-trunked switch port; verify traffic separation between client and server VLANs
