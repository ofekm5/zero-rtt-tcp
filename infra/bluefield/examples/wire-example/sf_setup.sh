#!/bin/bash
# Subfunction-based setup for wire-example on Bluefield-3 DPU
# This setup works with the classic DPDK wire example

set -e

echo "=== Subfunction Setup for Wire Example ==="

PCI_DEV="0000:03:00.0"  # Adjust based on your system
SF_NUM=10                # Arbitrary SF number
SF_MAC="02:25:f2:00:00:10"

# 1. Enable switchdev mode (required for subfunctions)
echo "Enabling switchdev mode..."
devlink dev eswitch set pci/${PCI_DEV} mode switchdev

# 2. Create a subfunction for host connectivity
echo "Creating subfunction SF${SF_NUM}..."
mlnx-sf --action create --device ${PCI_DEV} --sfnum ${SF_NUM} --hwaddr ${SF_MAC}

# 3. Show created subfunction details
echo ""
echo "Subfunction created. Details:"
mlnx-sf --action show

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Available ports for DPDK wire example:"
echo "Run './wire' to see DPDK port IDs, then:"
echo "  sudo ./wire -l 0-2 -- <physical_port_id> <sf_representor_port_id>"
echo ""
echo "Typical configuration:"
echo "  Port 0: p0 (physical uplink)"
echo "  Port N: en3f0pf0sf${SF_NUM} (SF representor to host)"
echo ""
echo "The wire app will forward bidirectionally between these ports"
echo "using ARM cores, while DPU is in smartnic mode."
