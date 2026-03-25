# ClientNIC DPDK Implementation

DPDK-based implementation of the ClientNIC 0-RTT logic. Replaces the Scapy prototype with a C/DPDK data plane for higher throughput and lower latency.

## How it works

- **eth0** (client-facing): AF_PACKET raw socket — receives SYNs from the client, sends spoofed SYN-ACKs back
- **eth1** (server-facing): DPDK ENA PMD via `vfio-pci` — forwards SYNs to the server, receives real SYN-ACKs

On each SYN from the client:
1. Generate a random spoofed ISN, send a SYN-ACK on eth0 immediately (0-RTT)
2. Forward the original SYN to the server via eth1
3. When the real SYN-ACK arrives on eth1, record the real ISN and calculate `delta = spoofed_ISN - real_ISN`
4. Rewrite all subsequent packets: subtract delta from client ACKs, add delta to server SEQs
5. Recalculate IP and TCP checksums after every rewrite

## Source files

| File | Purpose |
|------|---------|
| `main.c` | EAL init, CLI parsing, mempool, busy-poll loop |
| `flow_table.c/h` | Per-connection state: ISNs, delta, packet buffer |
| `io.c/h` | eth0 AF_PACKET socket + eth1 DPDK ENA port init/send/recv |
| `packet_processor.c/h` | SYN → spoof + forward; SYN-ACK → set delta + flush buffer |
| `translator.c/h` | Per-packet seq/ack rewriting for established flows |
| `pipeline.c/h` | Parse Ethernet/IP/TCP, classify, dispatch to processor or translator |
| `checksum.c/h` | `recalc_ip_checksum()`, `recalc_tcp_checksum()` via DPDK helpers |
| `capture.c/h` | Optional pcap writer for eth1 RX packets (`--server-pcap`) |
| `log.c/h` | `RTE_LOG` wrappers |

## Build

Requires DPDK 23.11 installed (see `infra/dpdk/` CDK stack — it builds DPDK from source and binds eth1 to `vfio-pci` automatically).

```bash
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
cd clientnic/dpdk
meson setup builddir
ninja -C builddir
```

## Run

```bash
# Minimal
sudo ./builddir/clientnic-dpdk -l 0 -- --port=8080 --gw-mac=<ServerNIC-eth0-MAC>

# With eth1 capture (required for validate_0rtt_capture.py)
sudo ./builddir/clientnic-dpdk -l 0 -- \
    --port=8080 \
    --gw-mac=<ServerNIC-eth0-MAC> \
    --server-pcap=/tmp/server_side.pcap
```

`--gw-mac` is the MAC of the ServerNIC's eth0 interface (next hop on the middle subnet). Get it with `cat /sys/class/net/eth0/address` on the ServerNIC VM.

| Flag | Default | Description |
|------|---------|-------------|
| `--port` | `8080` | TCP port to intercept |
| `--gw-mac` | *(required)* | Ethernet next-hop MAC for eth1 TX |
| `--client-iface` | `eth0` | Kernel interface for client-facing traffic |
| `--server-iface` | `eth1` | Logical name for the DPDK port (informational) |
| `--server-pcap` | *(none)* | Write eth1 RX packets to this pcap file |

## Infrastructure

The `infra/dpdk/` CDK stack provisions the ClientNIC VM with:
- DPDK 23.11 built from source (`-Dplatform=generic`, `-j1` to stay within 4 GB RAM)
- 512 × 2 MB hugepages (1 GiB total)
- `vfio-pci` in no-IOMMU mode (AWS Nitro doesn't expose IOMMU to guests)
- eth1 bound to `vfio-pci` via `dpdk-devbind.py` at boot
- `clientnic-dpdk` binary built from this directory at provision time

## Validation

Run the full end-to-end experiment (drives all 4 VMs via SSM):

```bash
./experiments/zero-rtt-dpdk/run_experiment.sh
```

The experiment passes `--server-pcap=/tmp/server_side.pcap` so that `validate_0rtt_capture.py` has a real eth1 capture to validate against:

```
[PASS] Real SYN-ACK(s) found on eth1
[PASS] Spoofed SYN-ACK(s) found on eth0 (distinct ISN)
[PASS] All deltas are non-zero
[PASS] Spoofed SYN-ACK arrives before real
[PASS] No bad checksums on eth0 (client side)
[PASS] No bad checksums on eth1 (server side)
```
