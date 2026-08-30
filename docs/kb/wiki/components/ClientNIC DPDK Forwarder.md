---
type: Wiki Entry
title: "ClientNIC DPDK Forwarder"
description: "Spoof SYN-ACK + stamp V + transparent forward."
tags: [component, clientnic, dpdk]
timestamp: 2026-07-14T08:55:14+03:00
---

Source: `src/clientnic/dpdk-forwarder/README.md`

# ClientNIC DPDK Forwarder

> Spoof SYN-ACK + stamp V + transparent forward.
> Translation responsibility has been shifted to the ServerNIC.
> (An earlier full-owner implementation, `clientnic/dpdk/`, kept spoofing and
> translation both on the ClientNIC; it was removed — see git history.)

## Dual-DPDK data plane

ClientNIC runs a **dual-DPDK** data plane — both the client-facing and
ServerNIC-facing ports are DPDK ENA PMD (vfio-pci), not AF_PACKET. A third,
dedicated **management ENI** (kernel-driven, primary interface) carries SSM
Session Manager access and is never bound to vfio-pci, so it stays reachable
even while both data-plane ports are DPDK-owned:

```
eth0 (primary, kernel)   → SSM management only, never bound to vfio-pci
eth1 (secondary, DPDK)   → ServerNIC-facing data plane (vfio-pci)
eth2 (tertiary, DPDK)    → Client-facing data plane (vfio-pci)
```

DPDK port IDs are assigned in PCI-enumeration order, which does **not** reliably
track ENI `device_index` — so the binary never assumes port 0 is the client link.
`--client-port-mac` and `--server-port-mac` carry the MACs of ClientNIC's *own*
two ENIs, and each port is matched to its role by comparing its MAC against them.
Getting this wrong swaps the two links silently, so a mismatch is a startup error.

Server-bound frames are addressed with the configured peer MAC (`--gw-mac`), since
a DPDK-owned port can't ARP. Client-bound frames need no configured peer: the
client's MAC is learned per-flow from the SYN and stored in the flow entry.

## How it differs from the full-owner design

| Aspect | Full owner (removed `clientnic/dpdk/`) | `src/clientnic/dpdk-forwarder/` |
|--------|----------------------------------------|------------------------------------------|
| seq/ack rewriting | ClientNIC rewrites all packets | **ServerNIC** rewrites all packets |
| Flow state | `{V, real_isn, delta, buffer, client_mac}` | `{V, client_mac}` — no delta, no buffer |
| SYN forwarded | As-is | **V stamped in ack-num field** before TX |
| SYN-ACK (real) | Dropped at ClientNIC | Dropped at **ServerNIC** (never reaches here) |
| Packet pipeline | SYN → spoof+forward; non-SYN → translate | SYN → spoof+stamp+forward; non-SYN → **transparent forward** |

## ISN ack-num channel

When a SYN arrives from the client, the forwarder:
1. Generates a random `V` (spoofed server ISN), records it in the flow table
2. Sends a spoofed SYN-ACK with `seq=V` to the client immediately (0-RTT)
3. Forwards the SYN to ServerNIC with `ack_num = V` (RFC 9293 §3.10.7.2: a LISTEN-state
   endpoint ignores `ack_seq` when ACK flag is clear, so this field is free on a pure SYN)
4. The ServerNIC reads `V`, zeros the field, and computes the delta when the real SYN-ACK arrives

On retransmit, the same `V` is re-stamped (no new flow entry created).

## Source files

| File | Purpose |
|------|---------|
| `main.c` | EAL init, CLI parsing, mempool, busy-poll loop |
| `flow_table.c/h` | Slim flow table: `{V, client_mac, state}` — no delta or buffer |
| `io.c/h` | Both data-plane ports: DPDK ENA PMD (client-facing + ServerNIC-facing) |
| `packet_processor.c/h` | `proc_handle_syn`: spoof SYN-ACK + stamp V + forward |
| `forwarder.c/h` | `forward_c2s` / `forward_s2c`: Ethernet rewrite only, seq/ack untouched |
| `pipeline.c/h` | Parse → classify → dispatch |
| `checksum.c/h` | `recalc_ip_checksum()`, `recalc_tcp_checksum()` |
| `log.c/h` | `RTE_LOG` wrappers |
| `tests/` | Python unit tests (no DPDK required) |

## Build

Requires DPDK 23.11 (provisioned by `infra/dpdk/` CDK stack).

```bash
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
cd src/clientnic/dpdk-forwarder
meson setup builddir
ninja -C builddir
```

The CDK stack builds this binary at provision time and points the
`src/clientnic/dpdk-active` symlink at it.

## Run

```bash
sudo ./builddir/clientnic-dpdk-forwarder -l 0 -- \
    --port=8080 \
    --gw-mac=<ServerNIC-eth1-MAC> \
    --client-port-mac=<our-own-eth2-MAC> \
    --server-port-mac=<our-own-eth1-MAC>
```

| Flag | Whose MAC | Why |
|------|-----------|-----|
| `--gw-mac` | ServerNIC's eth1 (**peer**) | TX destination for server-bound frames; a DPDK port can't ARP for it |
| `--client-port-mac` | ClientNIC's own eth2 (**local**) | Identifies which DPDK port is the client link |
| `--server-port-mac` | ClientNIC's own eth1 (**local**) | Identifies which DPDK port is the ServerNIC link |

The client's MAC is *not* a flag — it's learned per-flow from the incoming SYN.

All three come from the EC2 API (`DeviceIndex` 1 of `smartnics-servernic`, then 2 and 1
of `smartnics-clientnic`); the run scripts resolve them automatically:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=smartnics-servernic" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
  --output text
```

## Tests

```bash
python3 -m pytest src/clientnic/dpdk-forwarder/tests/ -v
```

Tests cover: V stamping, checksum validity, retransmit re-stamps same V, independent V per
flow, transparent c2s/s2c forwarding (seq/ack/IP-payload unchanged).

## Integration

Run the full experiment (drives all 4 VMs via SSM):

```bash
./experiments/dpdk/run_experiment.sh
```

The experiment uses `clientnic-dpdk-forwarder` on ClientNIC and `servernic-dpdk` on ServerNIC
together as a matched pair — the two halves of the translation split.
