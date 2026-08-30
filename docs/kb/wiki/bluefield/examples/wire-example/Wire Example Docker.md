---
type: Wiki Entry
title: "Docker Deployment Guide for Wire-Example"
description: "This guide shows how to containerize and deploy the wire-example application on Bluefield DPU using Docker and Scalable Functions (SFs)."
tags: [bluefield, examples, wire-example]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/examples/wire-example/DOCKER.md`

# Docker Deployment Guide for Wire-Example

This guide shows how to containerize and deploy the wire-example application on Bluefield DPU using Docker and Scalable Functions (SFs).

## Quick Start

### 1. Build the Docker Image

```bash
cd apps/wire-example

# Build the image (similar to compress_doca_image.sh pattern)
./build_wire_image.sh wire-app:latest

# Build and save as tarball for transfer to Bluefield
./build_wire_image.sh wire-app:latest --save
```

This will create:
- Docker image tagged as `wire-app:latest`
- Optional tarball: `wire_app_<timestamp>.tar` (if using `--save`)

### 2. Transfer to Bluefield (if built on different machine)

```bash
# On build machine
scp wire_app_*.tar ubuntu@bluefield-dpu:~/

# On Bluefield DPU
sudo docker load -i wire_app_*.tar
```

### 3. Run the Container

**List available ports:**
```bash
sudo docker run --rm --privileged --network host \
  -v /dev/hugepages:/dev/hugepages \
  wire-app:latest
```

**Start wire between ports (example: ports 2 and 3):**
```bash
sudo docker run --rm --privileged --network host \
  -v /dev/hugepages:/dev/hugepages \
  wire-app:latest -l 0-2 -- 2 3
```

## Advanced: Using Scalable Functions (SFs)

Instead of using physical ports, you can use SFs for better isolation and flexibility.

### Step 1: Create Scalable Functions on Bluefield

```bash
# Create two SFs
sudo mlxdevm sf add pci/0000:03:00.0 flavour pcivf pfnum 0 sfnum 100
sudo mlxdevm sf add pci/0000:03:00.0 flavour pcivf pfnum 0 sfnum 101

# Activate the SFs
sudo mlxdevm sf activate pci/0000:03:00.0/100
sudo mlxdevm sf activate pci/0000:03:00.0/101

# Verify SF creation
sudo mlxdevm sf show
```

### Step 2: Find SF Representor Ports

```bash
# List all ports to find your SF representors
sudo docker run --rm --privileged --network host \
  -v /dev/hugepages:/dev/hugepages \
  wire-app:latest

# Look for ports like:
# - 0000:03:00.0_representor_sf100
# - 0000:03:00.0_representor_sf101
```

### Step 3: Wire the SF Representor Ports

```bash
# Example: if SF100 is port 4 and SF101 is port 5
sudo docker run --rm --privileged --network host \
  -v /dev/hugepages:/dev/hugepages \
  wire-app:latest -l 0-2 -- 4 5
```

### Step 4: Configure Host-Side SF Interfaces

On the host system, configure the SF network interfaces:

```bash
# Find the SF interface names (usually sfN)
ip link show

# Bring up the SF interfaces
sudo ip link set sf0 up
sudo ip link set sf1 up

# Assign IP addresses if needed
sudo ip addr add 192.168.100.1/24 dev sf0
sudo ip addr add 192.168.100.2/24 dev sf1
```

### Step 5: Test SF-Based Wire

```bash
# From host, send test packets
sudo tcpdump -i sf0 &
ping -I sf1 192.168.100.1

# You should see packets flowing through the containerized wire app
```

## Architecture Diagrams

### Traditional Setup (Physical Ports)
```
Host <-> pf0hpf [Wire Container] p0 <-> External Network
```

### SF-Based Setup (Loopback)
```
Host SF0 <-> SF0_rep [Wire Container] SF1_rep <-> SF1 Host
```

### SF-Based Setup (with OVS)
```
Host <-> SF0_rep [Wire Container] SF1_rep <-> OVS <-> Physical Port
```

## Container Configuration Details

### Required Privileges
The container needs:
- `--privileged`: For DPDK device access
- `--network host`: To access host network stack
- `-v /dev/hugepages:/dev/hugepages`: For DPDK hugepage memory

### Alternative: Specific Capabilities (More Secure)
Instead of `--privileged`, you can use specific capabilities:

```bash
sudo docker run --rm \
  --cap-add=SYS_ADMIN \
  --cap-add=NET_ADMIN \
  --cap-add=IPC_LOCK \
  --device=/dev/vfio/vfio \
  --device=/dev/vfio/... \
  --network host \
  -v /dev/hugepages:/dev/hugepages \
  wire-app:latest -l 0-2 -- 2 3
```

## Docker Compose Example

For easier deployment, create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  wire-app:
    image: wire-app:latest
    container_name: wire-forwarder
    privileged: true
    network_mode: host
    volumes:
      - /dev/hugepages:/dev/hugepages
    command: ["-l", "0-2", "--", "2", "3"]
    restart: unless-stopped
```

Run with:
```bash
sudo docker-compose up -d
```

## Cleanup

### Remove SFs
```bash
sudo mlxdevm sf del pci/0000:03:00.0/100
sudo mlxdevm sf del pci/0000:03:00.0/101
```

### Stop and Remove Container
```bash
sudo docker stop wire-forwarder
sudo docker rm wire-forwarder
```

### Remove Image
```bash
sudo docker rmi wire-app:latest
```

## Troubleshooting

### "Cannot create mbuf pool" Error
- Ensure hugepages are configured:
  ```bash
  sudo sysctl -w vm.nr_hugepages=2048
  echo 'vm.nr_hugepages=2048' | sudo tee -a /etc/sysctl.conf
  ```

### "No DPDK ports found"
- Verify SF creation: `sudo mlxdevm sf show`
- Check DPDK bindings: `dpdk-devbind.py --status`
- Ensure container has `--privileged` or proper capabilities

### Performance Issues
- Ensure DPDK uses isolated CPU cores (use `-l` flag properly)
- Check CPU governor: `cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`
- Should be `performance`, not `powersave`

## References

- [NVIDIA DOCA Documentation](https://docs.nvidia.com/doca/)
- [DPDK Documentation](https://doc.dpdk.org/)
- [Scalable Functions Guide](https://docs.nvidia.com/networking/display/BlueFieldDPUOSLatest/Scalable+Functions)
