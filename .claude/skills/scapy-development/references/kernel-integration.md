# Kernel Integration

> Critical for the **Modify** phase — the kernel is always in the loop when using AF_PACKET sockets.

## AF_PACKET Sockets Receive Copies

Scapy's `sniff()` uses AF_PACKET raw sockets. These receive **copies** of packets, not the originals:

```
NETWORK CORE
    │
    ├──→ Copy to AF_PACKET socket (Scapy sees it)
    │
    └──→ ip_rcv() → normal stack processing continues
```

**The kernel STILL processes the original packet.** This has three critical implications:

### 1. RST Suppression

The kernel's TCP stack doesn't know about connections managed by Scapy. When it sees a SYN-ACK for an unknown connection, it sends RST.

```bash
# Drop outgoing RSTs from kernel
iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP
```

### 2. Packet Re-Capture Loop

`sniff()` on AF_PACKET captures **both incoming AND outgoing** frames on the interface. When your handler calls `send()`, the sent packet is re-captured by the same sniffer → infinite loop.

**Fix**: Filter out packets sent by our own MAC addresses (Parse phase):

```python
# ── PARSE ──
if packet.haslayer(Ether) and packet[Ether].src.lower() in our_macs:
    return  # skip self-sent packet
```

Both ClientNIC and ServerNIC use this pattern. Collect MACs at startup:
```python
our_macs = set()
for iface in (CLIENT_IFACE, SERVER_IFACE):
    try:
        our_macs.add(get_if_hwaddr(iface).lower())
    except Exception:
        pass
```

### 3. Kernel Forwarding Race

If `ip_forward` is enabled, the kernel forwards the original packet **at line rate (~microseconds)** — far faster than Scapy's Python-based handler. In low-latency networks (intra-VPC, sub-ms RTT), the kernel completes the full TCP handshake before Scapy even processes the SYN.

**Symptoms**: Spoofed SYN-ACK arrives 50-300ms **after** the real SYN-ACK. Connections succeed but bypass 0-RTT entirely. Log shows `Data from server for unknown/unready flow` before SYN processing.

**Fix** — use **port-specific** iptables rules to block kernel forwarding for your application port while keeping SSM, metadata, and other system traffic flowing:

```bash
# Block kernel forwarding for application port only
iptables -A FORWARD -p tcp --dport 8080 -j DROP
iptables -A FORWARD -p tcp --sport 8080 -j DROP

# Clean up on teardown
iptables -F FORWARD
```

**Do NOT use blanket `iptables -A FORWARD -j DROP`** — this breaks SSM agent connectivity and instance metadata, locking you out of the VM.

**Alternative** (if no other traffic needs forwarding):
```bash
echo 0 > /proc/sys/net/ipv4/ip_forward
```

## iptables Rules Reference

| Rule | Purpose |
|------|---------|
| `-A OUTPUT -p tcp --tcp-flags RST RST -j DROP` | Suppress kernel RSTs |
| `-A FORWARD -p tcp --dport 8080 -j DROP` | Block kernel forwarding for app port (keeps SSM alive) |
| `-A FORWARD -p tcp --sport 8080 -j DROP` | Block kernel forwarding for app port (return traffic) |
| `-A OUTPUT -p tcp --dport <port> -j DROP` | Suppress kernel responses on specific port |
| `-A INPUT -p tcp --dport <port> -j DROP` | Drop inbound traffic kernel would process |

**Teardown**: Always `iptables -F FORWARD` when done to restore normal forwarding.

## BPF Filter: Exclude Metadata Traffic

On AWS EC2, the instance metadata service (169.254.169.254) generates constant traffic. Exclude it from sniff filters to avoid filling the callback queue:

```python
sniff(
    iface="eth0",
    prn=handler,
    filter="tcp port 8080 and not host 169.254.169.254",
    store=False,
)
```
