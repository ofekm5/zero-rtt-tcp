# zero-rtt-demo

Proof-of-concept demonstrating **0-RTT TCP** — eliminating the 3-way handshake latency by using intelligent middleware (ClientNIC) that spoofs server SYN-ACKs, allowing clients to send application data immediately without waiting for the real handshake to complete (~50-200ms saved per connection).

**Educational/demo use only. Not suitable for production.**

## Architecture

```
Client VM → ClientNIC VM → ServerNIC VM → Server VM
10.1.0.x     10.1.0.x        10.1.1.x      10.1.2.x
             (eth0/eth1)     (eth0/eth1)
```

| Component | Role |
|-----------|------|
| `client-app/` | Standard unmodified TCP client |
| `clientnic/` | Core 0-RTT logic — intercepts SYN, sends spoofed SYN-ACK, rewrites sequence numbers |
| `servernic/` | Stateless transparent packet forwarder |
| `experiments/` | Experiment scripts and test reports |
| `server-app/` | Standard unmodified TCP server |
| `infra/` | AWS CDK stacks that provision the 4-VM topology |

## Packet Flow

**ClientNIC has two implementations** — Scapy (Python, `clientnic/scapy/`) and DPDK (C, `clientnic/dpdk/`) — both producing identical 0-RTT behavior.

```
Client VM          ClientNIC VM        ServerNIC VM        Server VM
    │                    │                    │                    │
    │ ① SYN              │                    │                    │
    │───────────────────>│                    │                    │
    │                    │ ② SYN (forwarded)  │                    │
    │                    │───────────────────>│ ③ SYN (forwarded)  │
    │                    │                    │───────────────────>│
    │ ④ Spoofed SYN-ACK  │                    │                    │
    │<───────────────────│                    │ ⑤ Real SYN-ACK     │
    │                    │                    │<───────────────────│
    │ ⑥ ACK + DATA (early│                    │    (dropped)       │
    │───────────────────>│                    │                    │
    │                    │ ⑦ ACK+DATA         │                    │
    │                    │  (seq rewritten)   │                    │
    │                    │───────────────────>│ ⑧ ACK+DATA         │
    │                    │                    │───────────────────>│
    │                    │                    │ ⑨ Server response  │
    │                    │ ⑩ Response         │<───────────────────│
    │                    │  (ack rewritten)   │                    │
    │ ⑪ Response         │<───────────────────│                    │
    │<───────────────────│                    │                    │
```

**Key**: ClientNIC sends the spoofed SYN-ACK (④) before the real one (⑤) even arrives, so the client can send data (⑥) a full RTT earlier than normal TCP. The real SYN-ACK is dropped; sequence numbers are transparently rewritten (⑦, ⑩) so the server never knows.

## Sequence Number Translation

ClientNIC maintains a flow table with a per-connection `seq_delta`:

```
delta = spoofed_server_isn - real_server_isn   (mod 2^32)

client→server packets:  TCP.seq += delta
server→client packets:  TCP.ack -= delta
```

After rewriting, checksums are recalculated — automatically by Scapy (`del pkt[IP].chksum`), or explicitly in C via DPDK's `rte_ipv4_cksum()` / `rte_ipv4_udptcp_cksum()`.

## Infrastructure

Two AWS CDK stacks in `infra/`, both provisioning the same 4-VM chain topology in `eu-central-1`:

| Stack | ClientNIC data plane | Directory |
|-------|---------------------|-----------|
| Scapy | Python + Scapy (AF_PACKET) | `infra/scapy/` |
| DPDK | C + DPDK 23.11 ENA PMD | `infra/dpdk/` |

Both stacks share:
- **VPC** `10.1.0.0/16` with 3 public subnets: `Client` (`10.1.0.0/24`), `Middle` (`10.1.1.0/24`), `Server` (`10.1.2.0/24`)
- **4 EC2 instances** with source/dest check disabled on NIC VMs
- **SSM access** for all instances (no bastion or SSH key needed)
- **ip_forward=1** set persistently via sysctl.conf on NIC VMs at boot

```powershell
cd infra/dpdk      # or infra/scapy
.\deploy.ps1            # Creates venv, installs CDK deps, deploys
.\deploy.ps1 -Bootstrap # First-time CDK bootstrap + deploy
.\destroy.ps1           # Tear down all stacks
```

## Running the Tests

**Scapy stack** (ClientNIC uses Python/Scapy):
```bash
./experiments/zero-rtt-clientnic-translate/run_experiment.sh
```

**DPDK stack** (ClientNIC uses C/DPDK):
```bash
./experiments/zero-rtt-dpdk/run_experiment.sh
```

Both scripts discover all 4 VMs via AWS SSM, pull latest code, rebuild if needed, start services in the correct order, run a client connection, capture packets, and validate 0-RTT behavior with `validate_0rtt_capture.py`. Exit code = number of failures.

## Quick Start (manual, on the VMs)

Startup order: **Server → ServerNIC → ClientNIC → Client**

```bash
# 1. Server VM
setsid python3 server-app/server.py --host 0.0.0.0 --port 8080 --verbose < /dev/null >> /tmp/server.log 2>&1 &

# 2. ServerNIC VM
setsid python3 servernic/scapy/main.py < /dev/null >> /tmp/servernic.log 2>&1 &

# 3a. ClientNIC VM — Scapy
setsid python3 clientnic/scapy/main.py < /dev/null >> /tmp/clientnic.log 2>&1 &

# 3b. ClientNIC VM — DPDK (eth1 must already be bound to vfio-pci)
GW_MAC=$(ssh servernic cat /sys/class/net/eth0/address)
setsid ./clientnic/dpdk/builddir/clientnic-dpdk -l 0 -- \
    --port=8080 --gw-mac=$GW_MAC --server-pcap=/tmp/server_side.pcap \
    < /dev/null >> /tmp/clientnic.log 2>&1 &

# 4. Client VM
python3 client-app/client.py --host <server-ip> --port 8080 --mode repeated --count 3 --verbose
```

> All VMs: connect via `aws ssm start-session --target <instance-id> --region eu-central-1`

## Success Criteria

| Check | Expected |
|-------|----------|
| Connections | 3/3 succeed |
| Spoofed SYN-ACK | Arrives at client before real SYN-ACK |
| ISN delta | Non-zero, consistent across all packets |
| Checksums | Zero bad checksums on eth0 and eth1 |
| Flow table | delta logged for every connection |

## Constraints

- TCP only (no UDP, QUIC)
- Does not handle TCP options (timestamps, window scaling, SACK)
- No encryption or authentication — isolated/controlled environments only
- Assumes reliable network (no packet reordering)

## Technology Stack

| Layer | Scapy implementation | DPDK implementation |
|-------|---------------------|---------------------|
| Language | Python 3.8+ | C11 |
| Packet I/O | Scapy (AF_PACKET) | DPDK ENA PMD + AF_PACKET |
| Checksums | Scapy auto-recalc | `rte_ipv4_cksum()` / `rte_ipv4_udptcp_cksum()` |
| eth1 capture | `tcpdump` | Built-in `--server-pcap` pcap writer |

Infrastructure: AWS CDK v2 (Python), eu-central-1
