# Sending Packets

> Phase: **Modify** (in Parse → Decide → Modify pipeline)

## `sendp()` vs `send()` Decision Matrix

| Function | Layer | Ethernet Header | When to Use |
|----------|-------|-----------------|-------------|
| `sendp(pkt, iface="eth0")` | L2 | **You** control src/dst MAC | Spoofed replies, same-subnet forwarding, any packet with `Ether()` layer |
| `send(pkt, iface="eth0")` | L3 | **Kernel** adds via ARP/routing | Cross-subnet forwarding, when correct MACs aren't known |
| `sr1(pkt)` | L3 | Kernel adds | Send and wait for ONE reply |
| `srp(pkt, iface="eth0")` | L2 | You control | L2 send-receive pair |

### Key Rule: Always specify `iface`

```python
sendp(pkt, iface="eth0", verbose=False)  # ✅ explicit interface
send(pkt, iface="eth0", verbose=False)   # ✅ explicit interface
send(pkt, verbose=False)                 # ⚠️ uses default route — may work, may not
```

## Bug Lesson: MACs Dropped Cross-Subnet

**Problem**: Using `sendp()` with hardcoded MACs when forwarding across subnets causes packets to be dropped — the next-hop router/gateway expects its own MAC as the destination.

**Fix**: Use `send(pkt[IP], iface=..., verbose=False)` for cross-subnet forwarding. The kernel looks up the routing table and ARP cache to fill in the correct destination MAC.

```python
# ✅ Cross-subnet forwarding (this project's pattern)
send(packet[IP], iface=egress, verbose=False)

# ❌ Breaks cross-subnet — wrong dst MAC
sendp(packet, iface=egress, verbose=False)
```

This is why both ClientNIC (`rewriter.py`) and ServerNIC (`forwarder.py`) use `send()` not `sendp()` for forwarding.

## `send(iface=...)` Is Silently Ignored

**WARNING**: Scapy's `send()` (L3) **silently ignores the `iface` parameter**. The kernel routing table alone determines the outgoing interface:

```
SyntaxWarning: 'iface' has no effect on L3 I/O send()
```

This means `send(pkt, iface="eth1")` may send the packet out eth0 if the kernel's routing table points that way. The `iface` argument gives a false sense of control.

**Fix** — add OS-level routes so the kernel picks the correct interface:

```bash
# On ClientNIC: route server subnet via eth1
ip route replace 10.1.2.0/24 via 10.1.1.1 dev eth1

# On ServerNIC: route client subnet via eth0 (or eth1)
ip route replace 10.1.0.0/24 via 10.1.1.1 dev eth0
```

**Verify** before starting Scapy processes:
```bash
ip route get <destination_ip>
# Should show the correct dev and via
```

**Lesson from this project**: `server_side.pcap` captured zero packets because forwarded SYNs were going out eth0 (default route) instead of eth1. Adding the OS route fixed it immediately.

## Always Use `verbose=False`

Without this, Scapy prints a line per packet sent — floods logs in production sniff loops:

```python
send(pkt, iface="eth0", verbose=False)    # ✅ quiet
sendp(pkt, iface="eth0", verbose=False)   # ✅ quiet
```
