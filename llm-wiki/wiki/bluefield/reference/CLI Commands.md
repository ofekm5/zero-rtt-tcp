---
type: Wiki Entry
title: "CLI Commands Reference"
description: "Quick-reference CLI commands for managing BlueField-3 (mlnx-sf, ovs-vsctl, DOCA tools)."
tags: [bluefield, reference]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/05-reference/cli-commands.md`

# CLI Commands Reference

## mlnx-sf (Scalable Function Management)

### Create SF

```bash
mlnx-sf --action create --device <pci_address> --sfnum <sfnum> --hwaddr <mac_address>

# Example
mlnx-sf --action create --device 0000:03:00.0 --sfnum 9 --hwaddr 02:25:f2:8d:a2:4c
```

### Show SF Configuration

```bash
mlnx-sf --action show
```

Example output:
```
SF Index: pci/0000:03:00.0/229409
 Parent PCI dev: 0000:03:00.0
 Representor netdev: en3f0pf0sf70
 Function HWADDR: 00:01:01:01:01:70
 Auxiliary device: mlx5_core.sf.4
 netdev: enp3s0f0s70
 RDMA dev: mlx5_4
```

### Delete SF

```bash
mlnx-sf --action delete --sfindex pci/<pci_address>/<pasre_dev>

# Example
mlnx-sf --action delete --sfindex pci/0000:03:00.0/229409
```

## ovs-vsctl (OVS Management)

### Bridge Operations

```bash
# List all bridges
ovs-vsctl list-br

# Create bridge
ovs-vsctl add-br <bridge_name>

# Delete bridge
ovs-vsctl del-br <bridge_name>

# Show full topology
ovs-vsctl show
```

### Port Operations

```bash
# List ports in bridge
ovs-vsctl list-ports <bridge_name>

# Add port to bridge
ovs-vsctl add-port <bridge_name> <port_name>

# Remove port from bridge
ovs-vsctl del-port <bridge_name> <port_name>
```

### Flow Management

```bash
# Dump all flows
ovs-dpctl dump-flows

# Dump only hardware-offloaded flows
ovs-dpctl dump-flows type=offloaded

# Show datapath info
ovs-appctl dpctl/show
```

## Hugepage Commands

### Check Status

```bash
# Check if mounted
mountpoint -q /dev/hugepages

# Check allocation
cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Check usage
grep Huge /proc/meminfo
```

### Configure

```bash
# Mount hugepages
sudo mkdir -p /dev/hugepages
sudo mount -t hugetlbfs nodev /dev/hugepages

# Allocate hugepages
echo 1024 | sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Make persistent (add to /etc/sysctl.conf)
vm.nr_hugepages = 1024
```

## dpdk-testpmd Commands

### Launch testpmd

```bash
dpdk-testpmd -l 0-3 -n 4 -a 0000:03:00.0 -- -i

# With specific parameters
dpdk-testpmd -l 0-3 -n 4 -a 0000:03:00.0 \
    --socket-mem 1024 \
    -- -i --nb-cores=2 --rxq=2 --txq=2
```

### Common testpmd Commands

```bash
# In testpmd prompt:
start                    # Start forwarding
stop                     # Stop forwarding
show port stats all      # Show port statistics
show port info all       # Show port information
quit                     # Exit testpmd
```

## Network Interface Commands

### ip link

```bash
# List all interfaces
ip link show

# Bring interface up/down
sudo ip link set <interface> up
sudo ip link set <interface> down

# Show specific interface
ip link show <interface>
```

### ethtool

```bash
# Show statistics
ethtool -S <interface>

# Show interface settings
ethtool <interface>

# Show ring parameters
ethtool -g <interface>

# Change ring size
sudo ethtool -G <interface> rx 4096 tx 4096

# Show offload features
ethtool -k <interface>
```

## Firmware and Device Commands

### MST (Mellanox Software Tools)

```bash
# Start MST
sudo mst start

# List devices
sudo mst status

# Query device configuration
sudo mlxconfig -d /dev/mst/mt41686_pciconf0 query

# Set configuration
sudo mlxconfig -d /dev/mst/mt41686_pciconf0 set FLEX_PARSER_PROFILE_ENABLE=3

# Reset firmware
sudo mlxfwreset -d /dev/mst/mt41686_pciconf0 reset
```

### lspci

```bash
# List PCIe devices
lspci | grep Mellanox

# Detailed device info
lspci -vvv -s 0000:03:00.0
```

## Debugging Commands

### tcpdump

```bash
# Basic capture
sudo tcpdump -i <interface> -nn

# Capture specific protocol
sudo tcpdump -i <interface> tcp port 80

# Save to file
sudo tcpdump -i <interface> -w capture.pcap

# Read from file
tcpdump -r capture.pcap
```

### Performance Monitoring

```bash
# CPU usage
top
mpstat -P ALL 1

# NUMA topology
numactl --hardware

# Check process affinity
taskset -cp <pid>

# Set process affinity
taskset -c 0-3 <command>
```

## Quick Reference Table

| Task | Command |
|------|---------|
| Create SF | `mlnx-sf --action create --device <pci> --sfnum <num> --hwaddr <mac>` |
| Show SFs | `mlnx-sf --action show` |
| Create OVS bridge | `ovs-vsctl add-br <bridge>` |
| Add port to bridge | `ovs-vsctl add-port <bridge> <port>` |
| Check offloaded flows | `ovs-dpctl dump-flows type=offloaded` |
| Allocate hugepages | `echo 1024 \| sudo tee /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages` |
| Show interface stats | `ethtool -S <interface>` |
| Capture packets | `sudo tcpdump -i <interface> -nn` |

## Next Steps
- See [../operations/](../operations/) for operational procedures
- Read [[API Cheatsheet]] for API reference
- Check [[Debugging Guide]] for troubleshooting
