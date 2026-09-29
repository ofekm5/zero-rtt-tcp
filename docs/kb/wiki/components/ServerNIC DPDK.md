---
type: Wiki Entry
title: "ServerNIC DPDK Implementation"
description: "DPDK-based ServerNIC for the ISN ack-num translation shift. The ServerNIC is the sole"
tags: [component, servernic, dpdk]
timestamp: 2026-07-11T23:33:29+03:00
---

Source: `src/servernic/dpdk/README.md`

# ServerNIC DPDK Implementation

DPDK-based ServerNIC for the ISN ack-num translation shift. The ServerNIC is the **sole
stateful translator** — it reads V from the forwarded SYN's ack-num field, computes the
seq/ack delta after the real SYN-ACK arrives, drops the real SYN-ACK, and rewrites all
subsequent packets in both directions.

## ENI layout (design D6) — dual-DPDK data plane

```
Client ──► ClientNIC ──eth1(DPDK)──► [ServerNIC] ──eth2(DPDK)──► Server
                                       eth0 = kernel (SSM management)
                                       eth1 = DPDK ENA PMD (ClientNIC-facing, vfio-pci)
                                       eth2 = DPDK ENA PMD (Server-facing, vfio-pci)
```

Both data-plane ports run the DPDK ENA PMD (vfio-pci) — the Server-facing port has moved off
AF_PACKET. A dedicated **management ENI** (`eth0`, primary, kernel-driven) carries SSM Session
Manager access and is never bound to vfio-pci, keeping the box reachable while both `eth1`/`eth2`
are DPDK-owned.

- **eth1** (Middle subnet, secondary ENI): DPDK ENA PMD — receives forwarded SYN/data from
  ClientNIC, sends translated server→client frames back
- **eth2** (Server subnet, tertiary ENI): DPDK ENA PMD — forwards SYN/data to Server,
  receives Server responses. Frames are addressed with the configured `--server-mac` peer MAC
  rather than kernel ARP, since a DPDK-owned port can't ARP.

## State machine

```
SYN arrives on eth1
  → extract V = ntohl(tcp.ack_num), zero ack_num, recompute checksum
  → create PENDING flow {V, server_mac}, forward clean SYN to Server via eth2

Real SYN-ACK arrives on eth2
  → reverse-key lookup: find PENDING flow
  → ft_set_delta(real_isn): seq_delta = (V - real_isn) & 0xFFFFFFFF, state → ACTIVE
  → flush buffered c→s packets (ACK -= delta, recompute, forward to Server)
  → DROP the SYN-ACK (client already has the spoofed one from ClientNIC)

Client→Server (eth1, non-SYN):
  → ACTIVE: ACK -= delta, recompute, forward to Server (eth2)
  → PENDING: buffer (cap 64); overflow drops with warning

Server→Client (eth2, non-SYN-ACK):
  → reverse-key lookup, SEQ += delta, recompute, send toward ClientNIC (eth1)
```

## Source files

| File | Purpose |
|------|---------|
| `main.c` | EAL init, CLI parsing, mempool, busy-poll loop |
| `flow_table.c/h` | Hash table (1024 slots, linear probe): `{V, real_isn, delta, buffer}` |
| `syn_handler.c/h` | SYN: extract V, zero ack, forward; SYN-ACK: set delta, flush, drop |
| `translator.c/h` | `trans_c2s` (ACK -= delta) and `trans_s2c` (SEQ += delta) |
| `pipeline.c/h` | Parse Ethernet/IP/TCP, classify, dispatch to handlers |
| `io.c/h` | Both data-plane ports: DPDK ENA PMD (ClientNIC-facing eth1 + Server-facing eth2) |
| `checksum.c/h` | IP + TCP checksum via DPDK helpers |
| `log.c/h` | `RTE_LOG` wrappers |
| `tests/` | Python unit tests (no DPDK required) |

## Build

Requires DPDK 23.11 (provisioned by `infra/dpdk/` CDK stack).

```bash
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
cd src/servernic/dpdk
meson setup builddir
ninja -C builddir
```

## Run

```bash
sudo ./builddir/servernic-dpdk -l 0 -- \
    --port=8080 \
    --gw-mac=<ClientNIC-eth1-MAC> \
    --client-iface=eth1 \
    --server-iface=eth2
```

`--gw-mac` is the **ClientNIC's eth1 MAC** (Middle-subnet DPDK port). Retrieve from EC2 API:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=smartnics-clientnic" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
  --output text
```

Startup order: **Server → ServerNIC → ClientNIC → Client**

## Tests

```bash
python3 -m pytest src/servernic/dpdk/tests/ -v
```

Covers: flow create/lookup/collision, delta computation (including wraparound), idempotent
`ft_set_delta`, buffer cap-64 overflow, V extraction, ack-num zeroing, checksum validity,
c2s ACK−delta and s2c SEQ+delta with 32-bit wraparound cases.

## Integration

Run the full experiment (drives all 4 VMs via SSM):

```bash
./experiments/run.sh
```

`servernic-dpdk` and `clientnic-dpdk-forwarder` are a matched pair — deploy together.
