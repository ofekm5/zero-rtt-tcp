# OVS Management

## When You Need OVS

- Connecting VMs/containers to network
- Default routing for unmatched traffic
- Mixed environment (some DOCA apps, some regular networking)

## When You Don't Need OVS

- DOCA app handles all traffic on its bound SFs
- Pure bump-in-wire scenarios
- Your flow rules explicitly handle all packets

## Minimal OVS Commands

```bash
# Inspect
ovs-vsctl show                      # Full topology
ovs-vsctl list-br                   # List bridges
ovs-vsctl list-ports <bridge>       # Ports in bridge

# Create
ovs-vsctl add-br <bridge>           # New bridge
ovs-vsctl add-port <bridge> <port>  # Add interface

# Delete
ovs-vsctl del-port <bridge> <port>  # Remove interface
ovs-vsctl del-br <bridge>           # Remove bridge

# Check offload
ovs-dpctl dump-flows type=offloaded # Hardware-offloaded rules
```

## Default Behavior (No Explicit Rules)

OVS bridges act as learning L2 switches:
- Learn MAC addresses automatically
- Flood unknown unicast
- Forward known unicast to correct port

You add explicit rules only when you need specific steering, offloading, or ACLs.

## OVS Bridge Basics

### Creating a Bridge

```bash
# Create bridge
ovs-vsctl add-br sf_bridge1

# Add ports
ovs-vsctl add-port sf_bridge1 pf0hpf
ovs-vsctl add-port sf_bridge1 en3f0pf0sf2

# Verify
ovs-vsctl show
```

### Checking Offloaded Flows

```bash
# Check if flows are hardware-offloaded
ovs-dpctl dump-flows type=offloaded

# Verify offload status
ovs-appctl dpctl/show  # Look for "offloaded: yes"
```

## Port Naming in OVS

| Name Pattern | Type | Purpose |
|-------------|------|---------|
| `pf0hpf` | Host PF representor | Represents host PCI function |
| `en3f0pf0sf2` | SF representor | Represents SF in switching |
| `p0` | Physical uplink | External network port |
| Bridge interface | Internal | Same name as bridge |

## Research Setup (No OVS Needed)

```
                    ┌─────────────────────┐
   Physical Port    │     DOCA App        │    Physical Port
        p0 ────────►│                     │───────► p1
                    │  SF bound directly  │
                    │  doca_flow rules    │
                    │  handle all traffic │
                    └─────────────────────┘

App controls:
  • Ingress flow rules (catch packets from p0)
  • Packet modification (TCP seq, options)
  • Egress forwarding (send to p1)
```

Container packaging doesn't change this - your DOCA app talks directly to the SF and eSwitch hardware regardless of whether it runs bare-metal or containerized.

## Key Takeaways

1. **OVS optional** for DOCA applications with direct SF access
2. **OVS required** for VM networking and mixed environments
3. **Representors go in OVS**, netdevs bind to DPDK
4. **Check offload status** with `ovs-dpctl dump-flows type=offloaded`
5. **Default L2 switching** works without explicit rules

## Next Steps
- See [SF Management](sf-management.md) for creating SFs
- Read [../01-architecture/queues-ports-sfs.md](../01-architecture/queues-ports-sfs.md) for interface concepts
- Check [../05-reference/cli-commands.md](../05-reference/cli-commands.md) for command reference
