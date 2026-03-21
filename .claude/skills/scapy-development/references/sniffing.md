# Sniffing Packets

> Sniffing provides the entry point for the Parse → Decide → Modify pipeline. The `prn` callback is your handler.

## `sniff()` Parameters

```python
sniff(
    iface="eth0",           # Interface to capture on (required for middlebox)
    prn=handler,            # Callback — receives one Packet per call
    filter="tcp port 8080", # BPF filter (kernel-level, efficient)
    store=False,            # Don't accumulate packets in memory
    count=0,                # 0 = infinite (default)
    timeout=10,             # Stop after N seconds (omit for infinite)
)
```

### Critical: `store=False` for Long-Running Sniffers

Without `store=False`, Scapy accumulates every packet in memory → OOM on long runs:
```python
sniff(iface="eth0", prn=handler, store=False)   # ✅ production
sniff(iface="eth0", count=10)                    # ✅ finite capture
sniff(iface="eth0", prn=handler)                 # ❌ leaks memory
```

## BPF Filter Gotcha: Exclude 169.254.169.254

On AWS EC2, the instance metadata service generates constant TCP traffic to 169.254.169.254. This fills Scapy's callback queue and causes handlers to fire late.

```python
# ✅ Exclude metadata traffic
filter="tcp port 8080 and not host 169.254.169.254"

# ❌ Will capture metadata traffic, causing latency in handlers
filter="tcp port 8080"
```

## Multi-Interface Sniffing

Sniff multiple interfaces by running each in its own thread. Use `sniffed_on` to identify which interface a packet arrived on:

```python
import threading
from scapy.sendrecv import sniff

# Background thread for eth1
eth1_thread = threading.Thread(
    target=sniff,
    kwargs=dict(
        iface="eth1",
        prn=server_handler.handle,
        filter="tcp port 8080",
        store=False,
    ),
    daemon=True,
)
eth1_thread.start()

# Main thread for eth0
sniff(
    iface="eth0",
    prn=client_handler.handle,
    filter="tcp port 8080",
    store=False,
)
```

Inside the handler, `packet.sniffed_on` tells you the ingress interface:
```python
def handle(self, packet):
    ingress = packet.sniffed_on   # "eth1" or "eth2"
    if ingress == self.client_iface:
        egress = self.server_iface
    # ...
```

## AsyncSniffer

Alternative to threading — Scapy's built-in async wrapper:

```python
from scapy.sendrecv import AsyncSniffer

sniffer = AsyncSniffer(
    iface="eth0",
    prn=handler,
    filter="tcp port 8080",
    store=False,
)
sniffer.start()

# ... do other work ...

sniffer.stop()
```

Use `AsyncSniffer` when you need to start/stop sniffing programmatically. Use the threading pattern (as in `clientnic/main.py`) when you need separate handlers per interface.

## BPF Filter Syntax

The `filter` parameter uses the same syntax as tcpdump. Test complex filters with:
```bash
tcpdump -d "tcp port 8080 and not host 169.254.169.254"
```

Common filters:
| Filter | Matches |
|--------|---------|
| `tcp` | All TCP packets |
| `tcp port 8080` | TCP with src or dst port 8080 |
| `tcp dst port 80` | TCP with dst port 80 only |
| `host 10.0.0.1` | Any packet to/from 10.0.0.1 |
| `not host 169.254.169.254` | Exclude metadata service |
| `tcp and not port 22` | TCP but not SSH |
