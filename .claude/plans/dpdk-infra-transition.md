# Infra Transition Plan: Scapy → DPDK

## Context

The NIC VMs (ClientNIC, ServerNIC) currently use Scapy (Python, AF_PACKET sockets) for packet processing. To achieve higher performance with kernel bypass, we're migrating to DPDK with C/C++ applications. This plan covers **infrastructure changes only** — the DPDK application code is a separate effort. The goal is to have VMs that boot with DPDK installed, hugepages configured, and the data-plane ENI bound to `vfio-pci`, ready for a native C/C++ DPDK app.

**Decisions:**
- Language: C/C++ (native DPDK)
- Mode: Full replacement (no Scapy fallback)
- Instance type: c5n.large for NIC VMs

---

## Changes by File

### 1. `infra/cdk/smartnics_stack.py` — Primary changes

**A. Instance type for NIC VMs → `c5n.large`**
- Change both `ClientNicInstance` and `ServerNicInstance` from `T3.MICRO` to `C5N.LARGE`
- Client and Server VMs stay `T3.MICRO` (unmodified TCP apps)

**B. Replace `nic_user_data` with DPDK setup**

Remove `pip3 install scapy` and IP forwarding. Replace with:

```bash
# System packages + DPDK build deps
yum update -y
yum install -y git gcc make meson ninja-build python3-pyelftools \
    numactl-devel kernel-devel libpcap-devel pciutils

# Clone repo (same as before)
GITHUB_TOKEN=$(aws ssm get-parameter --name /zero-rtt/github-token \
    --with-decryption --query Parameter.Value --output text --region eu-central-1)
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-demo.git" \
    /home/ec2-user/zero-rtt-demo
chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-demo

# Hugepages (512 x 2MB = 1 GiB)
echo 'vm.nr_hugepages=512' >> /etc/sysctl.conf
sysctl -p
mkdir -p /dev/hugepages
mount -t hugetlbfs nodev /dev/hugepages
echo 'nodev /dev/hugepages hugetlbfs defaults 0 0' >> /etc/fstab

# Build DPDK 23.11 (includes ENA PMD)
cd /opt
curl -LO https://fast.dpdk.org/rel/dpdk-23.11.tar.xz
tar xf dpdk-23.11.tar.xz
cd dpdk-23.11
meson setup build
cd build && ninja && ninja install
ldconfig
echo '/usr/local/lib64' > /etc/ld.so.conf.d/dpdk.conf
ldconfig

# vfio-pci driver (no-IOMMU mode for Nitro)
modprobe vfio-pci
echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
echo 'vfio-pci' > /etc/modules-load.d/vfio.conf

# Bind secondary ENI (eth1) to DPDK
for i in $(seq 1 30); do
    SECONDARY_PCI=$(basename $(readlink /sys/class/net/eth1/device) 2>/dev/null || true)
    [ -n "$SECONDARY_PCI" ] && break
    sleep 2
done
if [ -n "$SECONDARY_PCI" ]; then
    ip link set eth1 down
    dpdk-devbind.py --bind=vfio-pci $SECONDARY_PCI
fi
```

**C. Remove `base_user_data` scapy install**
- Client/Server VMs: replace `pip3 install scapy` with just the git clone + system packages (no scapy, no DPDK)

**D. EBS volume → 50 GiB for NIC VMs**
- DPDK source + build artifacts need more space than Scapy
- Client/Server stay at 30 GiB

**E. Remove IP forwarding from NIC user data**
- DPDK bypasses the kernel stack; `net.ipv4.ip_forward` is irrelevant for bound interfaces
- Primary ENI (eth0) stays kernel-managed for SSM — if forwarding is needed there, add it back

**F. No changes to:**
- ENI topology (secondary ENIs, attachments, source_dest_check)
- Security groups (all-VPC-traffic already allowed; Nitro enforces SGs at hypervisor level regardless of DPDK)
- Route tables (chain topology unchanged)
- IAM role

### 2. `infra/cdk.json` — No changes needed
No context parameter since we're fully replacing (not switchable).

### 3. `infra/cdk/packet_test_stack.py` — No changes
VPC, subnets, internet gateway all stay the same.

### 4. `infra/deploy.ps1` / `infra/destroy.ps1` — No changes
Same deployment workflow.

### 5. `infra/ARCHITECTURE.md` — Update documentation
- Update instance type table (NIC VMs → c5n.large)
- Add DPDK section: hugepages, vfio-pci, ENI binding model
- Note: primary ENI = kernel/SSM, secondary ENI = DPDK data plane
- Update user data description
- Add cost note (~$78/mo per NIC VM vs ~$7.50/mo)

---

## What Stays the Same

| Component | Why unchanged |
|-----------|--------------|
| VPC / Subnets | Network topology is independent of packet engine |
| Route tables | Routes reference instance/ENI IDs, not drivers |
| Security groups | Nitro enforces SGs at hypervisor, works with DPDK |
| ENI creation + attachment | DPDK binding is OS-level (user data), not CloudFormation |
| source_dest_check=False | Still required for spoofed packets |
| Client/Server VMs | Unmodified TCP apps, no DPDK needed |
| IAM role | SSM + GitHub token access unchanged |

---

## ENI Binding Model

```
ClientNIC:
  eth0 (primary, Client subnet)  → Kernel driver (ENA) → SSM management
  eth1 (secondary, Middle subnet) → vfio-pci (DPDK)    → Data plane

ServerNIC:
  eth0 (primary, Middle subnet)  → Kernel driver (ENA) → SSM management
  eth1 (secondary, Server subnet) → vfio-pci (DPDK)    → Data plane
```

---

## Verification

After `cdk deploy`:

1. **SSM access**: `aws ssm start-session --target <NicInstanceId>` works (primary ENI kernel-managed)
2. **Instance type**: `curl -s http://169.254.169.254/latest/meta-data/instance-type` → `c5n.large`
3. **Hugepages**: `grep HugePages_Total /proc/meminfo` → `512`
4. **DPDK binding**: `dpdk-devbind.py --status` → secondary ENI shows `drv=vfio-pci`
5. **DPDK smoke test**: `dpdk-testpmd -l 0-1 --socket-mem 256 -- -i` starts and detects ENA device
6. **Primary ENI healthy**: `ip addr show eth0` has IP, `ping 10.1.x.x` works

---

## Critical Files

- `infra/cdk/smartnics_stack.py` — instance type, user data, volume size
- `infra/ARCHITECTURE.md` — documentation update
