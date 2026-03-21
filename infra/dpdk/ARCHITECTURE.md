# Infrastructure Architecture — DPDK Variant

## CDK Stacks

```
┌─────────────────────────────────────────────────────────────────────────┐
│  PacketTestStack                                                        │
│  (VPC + Subnets + Internet Gateway)                                     │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ vpc (passed as prop)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  SmartNicsStack                                                         │
│  (EC2 Instances + ENIs + Security Groups + Route Tables + Key Pair)     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## VPC Layout  —  `PacketTestStack`

```
VPC: 10.1.0.0/16   (eu-central-1, single AZ)
│
├── Internet Gateway
│
├── Subnet: Client   10.1.0.0/24  (PUBLIC)
├── Subnet: Middle   10.1.1.0/24  (PUBLIC)
└── Subnet: Server   10.1.2.0/24  (PUBLIC)
```

---

## EC2 Instances & Network Interfaces  —  `SmartNicsStack`

### Instance Types

| VM         | Instance Type | Purpose                              |
|------------|---------------|--------------------------------------|
| Client     | t3.micro      | Unmodified TCP client app            |
| ClientNIC  | c5n.large     | 0-RTT core logic — DPDK data plane   |
| ServerNIC  | c5n.large     | Stateless forwarder — DPDK data plane|
| Server     | t3.micro      | Unmodified TCP server app            |

> **Cost note**: c5n.large is ~$0.108/hr (~$78/mo per NIC VM) vs t3.micro at ~$0.0104/hr (~$7.50/mo).

### ENI Binding Model

```
ClientNIC:
  eth0 (primary, Client subnet)   → Kernel driver (ENA) → SSM management
  eth1 (secondary, Middle subnet) → vfio-pci (DPDK)     → Data plane

ServerNIC:
  eth0 (primary, Middle subnet)   → Kernel driver (ENA) → SSM management
  eth1 (secondary, Server subnet) → vfio-pci (DPDK)     → Data plane
```

### Network Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ VPC  10.1.0.0/16                                                                 │
│                                                                                  │
│  ┌─────────────────────────────┐                                                 │
│  │ Subnet: Client  10.1.0.0/24 │                                                 │
│  │                             │                                                 │
│  │  ┌──────────────────────┐   │                                                 │
│  │  │ smartnics-client     │   │                                                 │
│  │  │ t3.micro / AL2       │   │                                                 │
│  │  │ eth0: 10.1.0.x       │   │                                                 │
│  │  │ source/dest: OFF     │   │                                                 │
│  │  └──────────────────────┘   │                                                 │
│  │                             │                                                 │
│  │  ┌──────────────────────┐   │                                                 │
│  │  │ smartnics-clientnic  │   │                                                 │
│  │  │ c5n.large / AL2      │   │                                                 │
│  │  │ eth0: 10.1.0.x  ◄────┼───┼── primary ENI (kernel/SSM)                     │
│  │  │ source/dest: OFF     │   │                                                 │
│  │  └──────────┬───────────┘   │                                                 │
│  └─────────────┼───────────────┘                                                 │
│                │ eth1 (secondary ENI, vfio-pci / DPDK)                          │
│  ┌─────────────┼───────────────────────────┐                                     │
│  │ Subnet: Middle  10.1.1.0/24             │                                     │
│  │             │                           │                                     │
│  │  ┌──────────▼───────────────────────┐   │                                     │
│  │  │ clientnic-middle-eni             │   │                                     │
│  │  │ eth1: 10.1.1.x  source/dest: OFF │   │                                     │
│  │  └──────────────────────────────────┘   │                                     │
│  │                                         │                                     │
│  │  ┌──────────────────────┐               │                                     │
│  │  │ smartnics-servernic  │               │                                     │
│  │  │ c5n.large / AL2      │               │                                     │
│  │  │ eth0: 10.1.1.x  ◄────┼───────────────┼── primary ENI (kernel/SSM)          │
│  │  │ source/dest: OFF     │               │                                     │
│  │  └──────────┬───────────┘               │                                     │
│  └─────────────┼─────────────────────────────                                    │
│                │ eth1 (secondary ENI, vfio-pci / DPDK)                          │
│  ┌─────────────┼───────────────┐                                                 │
│  │ Subnet: Server  10.1.2.0/24 │                                                 │
│  │             │               │                                                 │
│  │  ┌──────────▼───────────────────────┐   │                                     │
│  │  │ servernic-server-eni             │   │                                     │
│  │  │ eth1: 10.1.2.x  source/dest: OFF │   │                                     │
│  │  └──────────────────────────────────┘   │                                     │
│  │                                         │                                     │
│  │  ┌──────────────────────┐               │                                     │
│  │  │ smartnics-server     │               │                                     │
│  │  │ t3.micro / AL2       │               │                                     │
│  │  │ eth0: 10.1.2.x       │               │                                     │
│  │  └──────────────────────┘               │                                     │
│  └─────────────────────────────────────────┘                                     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## DPDK Setup (NIC VMs)

### Hugepages
- 512 × 2 MB pages = 1 GiB reserved at boot via `/etc/sysctl.conf`
- Mounted at `/dev/hugepages` (hugetlbfs), persisted in `/etc/fstab`

### vfio-pci (no-IOMMU mode)
- Required because AWS Nitro does not expose an IOMMU to guests
- `enable_unsafe_noiommu_mode=1` set at boot
- Module loaded persistently via `/etc/modules-load.d/vfio.conf`

### DPDK 23.11
- Built from source at `/opt/dpdk-23.11` using meson + ninja
- Includes the ENA PMD (AWS Elastic Network Adapter driver)
- Installed to `/usr/local`; `ldconfig` run so apps find shared libs

### eth1 Binding
- User data waits up to 60 s for eth1 to appear (secondary ENI attach races boot)
- `ip link set eth1 down` before binding (required by vfio-pci)
- `dpdk-devbind.py --bind=vfio-pci <PCI-addr>` hands eth1 to DPDK

### EBS Volume
- NIC VMs: 50 GiB GP3 (DPDK source tree + build artifacts ~3–4 GiB)
- Client/Server VMs: 30 GiB GP3

---

## Routing Tables

### Client Subnet (10.1.0.0/24)
| Destination   | Target                              | Purpose                        |
|---------------|-------------------------------------|--------------------------------|
| 0.0.0.0/0     | Internet Gateway                    | SSH / internet access          |
| 10.1.2.0/24   | smartnics-clientnic (instance-id)   | Force traffic through ClientNIC|

### Middle Subnet (10.1.1.0/24)
| Destination   | Target                              | Purpose                              |
|---------------|-------------------------------------|--------------------------------------|
| 0.0.0.0/0     | Internet Gateway                    | Boot-time git clone / DPDK build     |
| 10.1.2.0/24   | smartnics-servernic (instance-id)   | Forward path → Server                |
| 10.1.0.0/24   | clientnic-middle-eni (ENI-id)       | Return path → Client                 |

### Server Subnet (10.1.2.0/24)
| Destination   | Target                              | Purpose                        |
|---------------|-------------------------------------|--------------------------------|
| 0.0.0.0/0     | Internet Gateway                    | SSH / internet access          |
| 10.1.0.0/24   | servernic-server-eni (ENI-id)       | Return traffic → ClientNIC     |

---

## Security Groups

All four VMs share the same inbound rules pattern:

| Port / Protocol | Source          | Purpose              |
|-----------------|-----------------|----------------------|
| All traffic     | 10.1.0.0/16     | Intra-VPC traffic    |

Outbound: all traffic allowed. Access is via SSM Session Manager — no inbound SSH required.

> Security groups are enforced at the Nitro hypervisor level and apply regardless of whether the interface is kernel-managed or DPDK-bound.

---

## IAM

| Resource              | Details                                              |
|-----------------------|------------------------------------------------------|
| EC2 Instance Role     | `AmazonSSMManagedInstanceCore` (SSM Session Manager) |
| SSM Parameter access  | `ssm:GetParameter` on `/zero-rtt/*` (GitHub token)  |

---

## Packet Flow (0-RTT Chain)

```
Internet
   │  SSH (port 22)
   ▼
┌──────────────┐        ┌──────────────────┐        ┌──────────────────┐        ┌──────────────┐
│    Client    │        │   ClientNIC      │        │   ServerNIC      │        │    Server    │
│ 10.1.0.x     │──eth0──▶ eth0: 10.1.0.x  │──eth1──▶ eth0: 10.1.1.x  │──eth1──▶ 10.1.2.x    │
│              │        │ eth1: 10.1.1.x   │        │ eth1: 10.1.2.x   │        │              │
└──────────────┘        └──────────────────┘        └──────────────────┘        └──────────────┘
                         ▲ kernel (SSM)               kernel (SSM)
                         │ eth1: DPDK data plane       eth1: DPDK data plane
                         │ 0-RTT core logic            stateless forwarder
```

---

## Post-Deploy Verification

1. **SSM access**: `aws ssm start-session --target <NicInstanceId>` (primary ENI kernel-managed)
2. **Instance type**: `curl -s http://169.254.169.254/latest/meta-data/instance-type` → `c5n.large`
3. **Hugepages**: `grep HugePages_Total /proc/meminfo` → `512`
4. **DPDK binding**: `dpdk-devbind.py --status` → secondary ENI shows `drv=vfio-pci`
5. **DPDK smoke test**: `dpdk-testpmd -l 0-1 --socket-mem 256 -- -i` starts and detects ENA device
6. **Primary ENI healthy**: `ip addr show eth0` has IP, `ping 10.1.x.x` works

---

## CloudFormation Outputs  (`SmartNicsStack`)

| Output Key               | Description                              |
|--------------------------|------------------------------------------|
| `ClientInstanceId`       | EC2 instance ID of Client VM             |
| `ClientPublicIp`         | Public IP of Client VM                   |
| `ClientNicInstanceId`    | EC2 instance ID of ClientNIC VM          |
| `ClientNicPublicIp`      | Public IP of ClientNIC VM                |
| `ServerNicInstanceId`    | EC2 instance ID of ServerNIC VM          |
| `ServerNicPublicIp`      | Public IP of ServerNIC VM                |
| `ServerInstanceId`       | EC2 instance ID of Server VM             |
| `ServerPublicIp`         | Public IP of Server VM                   |
