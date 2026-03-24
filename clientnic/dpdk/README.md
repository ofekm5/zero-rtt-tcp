# ClientNIC DPDK Implementation (WIP)

This directory will contain the DPDK-based implementation of the ClientNIC 0-RTT logic.

Infrastructure is already provisioned under `infra/dpdk/` with:
- DPDK 23.11 installed from source
- Hugepages configured (512 × 2MB = 1 GiB)
- `vfio-pci` driver with no-IOMMU mode
- Secondary ENI (eth1) bound to DPDK via `dpdk-devbind.py`

## Status

**Work in progress.** See `clientnic/scapy/` for the reference Scapy implementation.
