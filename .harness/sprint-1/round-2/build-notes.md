# Build notes — sprint 1 round 2

## Changes made
- src/clientnic/dpdk-forwarder/io.h:8-25 — replaced `struct eth0_io` (AF_PACKET: sock_fd/ifindex/tx_drops) with `struct client_io` (port_id/mac/client_mac/mbuf_pool, shaped like `eth1_io`); updated `eth0_init`/`eth0_send` signatures to take a DPDK `port_id` and dropped `eth0_recv`
- src/clientnic/dpdk-forwarder/io.c:1-107 — rewrote `eth0_init` as a DPDK ENA port bring-up (mirrors `eth1_init`: configure/rx-queue/tx-queue/start/promiscuous/mac read) and `eth0_send` as an `rte_pktmbuf_alloc` + `rte_eth_tx_burst` retry loop; removed AF_PACKET socket code, `eth0_recv`, and the now-unused socket headers
- src/clientnic/dpdk-forwarder/packet_processor.h:9,14, packet_processor.c:23 — `struct eth0_io *` → `struct client_io *`
- src/clientnic/dpdk-forwarder/forwarder.h:9,14, forwarder.c:46 — `struct eth0_io *` → `struct client_io *`
- src/clientnic/dpdk-forwarder/pipeline.h:11,18, pipeline.c:11,35 — `struct eth0_io *` → `struct client_io *`; refreshed stale "AF_PACKET raw buffer" comment
- src/clientnic/dpdk-forwarder/main.c — added `--client-mac` (required, parsed like `--gw-mac`); dropped the now-meaningless `--client-iface`/`--server-iface` AF_PACKET options; `nb_ports` check raised to require 2 DPDK ports; `eth0_init(&eth0, 0, mbuf_pool, client_mac)` / `eth1_init(&eth1, 1, mbuf_pool, gw_mac)`; busy-poll loop now does `rte_eth_rx_burst` on both `eth0.port_id` and `eth1.port_id` (mtod+len handed to `pipeline_feed_eth0`); shutdown stops/closes both ports

## Verification commands run
- C1: `grep -q "port_id" io.h && grep -qE "client_mac|peer_mac" io.h && ! grep -qE "sock_fd|ifindex|tx_drops" io.h` — exit 0
- C2: `grep -q "rte_eth_tx_burst" io.c && ! grep -qE "AF_PACKET|SOCK_RAW|SO_RCVBUFFORCE|SO_SNDBUFFORCE" io.c` — exit 0
- C3: `grep -qE "client-mac|client_mac" main.c && [ $(grep -c "rte_eth_rx_burst" main.c) -ge 2 ]` — exit 0
- C4: `grep -qE "peer_mac|client_mac" packet_processor.c forwarder.c` — exit 0 (unchanged from round 1; `forwarder.c` already used `entry->client_mac`)
- C5: `! grep -q "struct eth0_io" *.c *.h` — exit 0

## Open concerns
- `eth0` is now hardcoded to DPDK port 0 and `eth1` to port 1 in `main.c`; round 1's code had `eth1` on port 0. No contract criterion pins port numbering, and this is internal to the sprint's own file, so I picked an ordering that matches variable declaration order.
- Removed `--client-iface`/`--server-iface` CLI options entirely rather than leaving them as dead flags — they had no remaining consumer once both ports moved to DPDK (`server_iface` was already unused for anything but a log line before this round). Flag this if the experiment orchestration scripts (Sprint 4 scope) still pass `--client-iface`/`--server-iface` on the command line; that would need a follow-up.
- Per contract's Non-Goal, per-flow client MAC learning (from the observed source MAC on incoming client frames) is retained in `forward_s2c`/`proc_handle_syn` rather than switched to the new static `--client-mac`; that's not runtime ARP resolution, just L2 header inspection of already-received frames, so I read it as in-bounds. The new `client_io.client_mac` field is populated and available but not yet consumed as a TX destination anywhere — it exists to satisfy C1/C3's "configured peer MAC" requirement per task 1.1/1.3. If a future round wants it as the actual fallback destination MAC, that's a design call outside this contract's stated criteria.
