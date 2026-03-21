# pcap Analysis

> Phase: Post-capture — reading and analyzing packet captures offline

## Reading and Writing pcap Files

```python
from scapy.all import rdpcap, wrpcap

# Read
packets = rdpcap("capture.pcap")
print(f"Loaded {len(packets)} packets")

# Write
wrpcap("filtered.pcap", packets)

# Write a subset
syn_acks = [p for p in packets if p.haslayer(TCP) and p[TCP].flags == "SA"]
wrpcap("syn_acks_only.pcap", syn_acks)
```

## Packet Timestamps

Each sniffed/loaded packet has a `time` attribute (epoch float):

```python
for pkt in packets:
    t = float(pkt.time)
    print(f"t={t:.6f}  {pkt[IP].src} -> {pkt[IP].dst}")
```

Useful for timing analysis — e.g., measuring if spoofed SYN-ACK arrives before the real one.

## Raw Bytes Access

```python
raw_bytes = bytes(pkt)            # full packet as bytes
raw_bytes = raw(pkt)              # same thing (scapy.all.raw)
raw_tcp = raw(pkt[TCP])           # TCP segment bytes only
raw_ip_header = raw(pkt[IP])[:pkt[IP].ihl * 4]  # IP header only
```

## Manual TCP Checksum Verification

For offline validation (e.g., in `validate_0rtt_capture.py`), compute checksums from raw bytes:

```python
import socket
import struct
from scapy.utils import checksum as scapy_checksum

def expected_ip_checksum(pkt):
    """Compute expected IP header checksum (RFC 791)."""
    hdr = raw(pkt[IP])[:pkt[IP].ihl * 4]
    hdr_zeroed = hdr[:10] + b"\x00\x00" + hdr[12:]   # zero out chksum field
    return scapy_checksum(hdr_zeroed)

def expected_tcp_checksum(pkt):
    """Compute expected TCP checksum with pseudo-header (RFC 793)."""
    ip = pkt[IP]
    tcp_raw = raw(pkt[TCP])
    tcp_len = len(tcp_raw)
    pseudo = (
        socket.inet_aton(ip.src)
        + socket.inet_aton(ip.dst)
        + struct.pack("!BBH", 0, 6, tcp_len)
    )
    tcp_zeroed = tcp_raw[:16] + b"\x00\x00" + tcp_raw[18:]  # zero out chksum
    return scapy_checksum(pseudo + tcp_zeroed)

# Compare against packet's stored checksum
if expected_tcp_checksum(pkt) != pkt[TCP].chksum:
    print("Bad TCP checksum!")
```

## Reference Implementation

See `clientnic/validate_0rtt_capture.py` for a complete pcap analysis tool that validates:
- **A.** Spoofed SYN-ACK detection (ISN not matching real server ISN)
- **B.** ISN delta calculation and non-zero verification
- **C.** 0-RTT timing (spoofed SYN-ACK arrives before real one)
- **D.** Checksum correctness across all captured packets

## Filtering Packets from pcap

```python
packets = rdpcap("capture.pcap")

# By protocol
tcp_pkts = [p for p in packets if p.haslayer(TCP)]

# By flags
syns = [p for p in tcp_pkts if p[TCP].flags.S and not p[TCP].flags.A]
syn_acks = [p for p in tcp_pkts if p[TCP].flags.S and p[TCP].flags.A]

# By address
from_client = [p for p in tcp_pkts if p[IP].src == "10.0.1.10"]

# By port
port_8080 = [p for p in tcp_pkts if p[TCP].dport == 8080 or p[TCP].sport == 8080]
```
