# ClientNIC DPDK Forwarder (T8 variant)

> **T8 variant** — spoof SYN-ACK + stamp V + transparent forward.
> Translation responsibility has been shifted to the ServerNIC.
> See `clientnic/dpdk/` for the original full-owner implementation.

## How it differs from `clientnic/dpdk/`

| Aspect | `clientnic/dpdk/` (full owner) | `clientnic/dpdk-forwarder/` (T8 variant) |
|--------|-------------------------------|------------------------------------------|
| seq/ack rewriting | ClientNIC rewrites all packets | **ServerNIC** rewrites all packets |
| Flow state | `{V, real_isn, delta, buffer, client_mac}` | `{V, client_mac}` — no delta, no buffer |
| SYN forwarded | As-is | **V stamped in ack-num field** before TX |
| SYN-ACK (real) | Dropped at ClientNIC | Dropped at **ServerNIC** (never reaches here) |
| Packet pipeline | SYN → spoof+forward; non-SYN → translate | SYN → spoof+stamp+forward; non-SYN → **transparent forward** |

## ISN ack-num channel (T8)

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
| `io.c/h` | eth0 AF_PACKET socket + eth1 DPDK ENA port |
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
cd clientnic/dpdk-forwarder
meson setup builddir
ninja -C builddir
```

Both `clientnic/dpdk/` and `clientnic/dpdk-forwarder/` build independently and can coexist.
The CDK stack builds both; the active binary is selected via a symlink (`clientnic/dpdk-active`).

## Run

```bash
sudo ./builddir/clientnic-dpdk-forwarder -l 0 -- --port=8080 --gw-mac=<ServerNIC-eth1-MAC>
```

`--gw-mac` is the **ServerNIC's eth1 MAC** (Middle-subnet DPDK port). Retrieve it from the EC2
API — eth1 is DPDK-controlled so the kernel can't ARP for it:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=smartnics-servernic" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`1\`].MacAddress" \
  --output text
```

## Tests

```bash
python3 -m pytest clientnic/dpdk-forwarder/tests/ -v
```

Tests cover: V stamping, checksum validity, retransmit re-stamps same V, independent V per
flow, transparent c2s/s2c forwarding (seq/ack/IP-payload unchanged).

## Integration

Run the full experiment (drives all 4 VMs via SSM):

```bash
./experiments/zero-rtt-dpdk/run_experiment.sh
```

The experiment uses `clientnic-dpdk-forwarder` on ClientNIC and `servernic-dpdk` on ServerNIC
together as a matched pair. Do not mix with the `clientnic/dpdk/` full-owner binary — the two
variants have incompatible translation responsibilities.
