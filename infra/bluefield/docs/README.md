# BlueField-3 DPU Documentation

## Overview

Comprehensive technical documentation for NVIDIA BlueField-3 DPU development, covering architecture, programming, operations, and reference materials.

**Target Platform**: NVIDIA BlueField-3 DPU with DOCA 2.x/3.x and DPDK 23.x

## Documentation Structure

### 01-architecture/ - Understanding the Hardware

Core architectural concepts and how components work together:

- **[hardware-overview.md](01-architecture/hardware-overview.md)** - BlueField-3 components, modes, and capabilities
- **[packet-pipeline.md](01-architecture/packet-pipeline.md)** - Complete packet flow from ingress to egress
- **[eswitch-flow-engine.md](01-architecture/eswitch-flow-engine.md)** - Hardware flow engine and eSwitch internals
- **[queues-ports-sfs.md](01-architecture/queues-ports-sfs.md)** - Queues, ports, representors, and Scalable Functions

**Start here if**: You're new to BlueField or need to understand how packets flow through the system.

### 02-programming/ - Writing Code

Programming interfaces and APIs for packet processing:

**Core Programming APIs:**
- **[doca-flow-api.md](02-programming/doca-flow-api.md)** - Hardware flow programming with rte_flow
- **[dpdk-integration.md](02-programming/dpdk-integration.md)** - DPDK queue setup and packet I/O
- **[dpa-programming.md](02-programming/dpa-programming.md)** - Custom packet processing on DPA cores
- **[doca-dpl-p4.md](02-programming/doca-dpl-p4.md)** - P4-based pipeline programming and parser customization
- **[packet-modification.md](02-programming/packet-modification.md)** - Packet modification capabilities and generation

**Essential Utilities:**
- **[dpdk-core-functions.md](02-programming/dpdk-core-functions.md)** - DPDK EAL initialization and multi-core management
- **[dpdk-utility-functions.md](02-programming/dpdk-utility-functions.md)** - Error handling, port discovery, statistics, and timing
- **[doca-argp.md](02-programming/doca-argp.md)** - Command-line argument parsing library
- **[doca-logging.md](02-programming/doca-logging.md)** - Logging configuration and backends

**Start here if**: You're implementing packet processing applications.

### 03-operations/ - Managing the DPU

Operational procedures and system configuration:

- **[sf-management.md](03-operations/sf-management.md)** - Creating and managing Scalable Functions
- **[ovs-management.md](03-operations/ovs-management.md)** - OVS bridge configuration and flow offload
- **[hugepages-setup.md](03-operations/hugepages-setup.md)** - Memory configuration for DPDK

**Start here if**: You're setting up or administering a BlueField system.

### 04-development/ - Building and Testing

Development workflows, testing, and optimization:

- **[code-examples.md](04-development/code-examples.md)** - Practical code samples
- **[local-simulation-strategies.md](04-development/local-simulation-strategies.md)** - Testing without hardware using DPDK virtual devices
- **[testing-strategies.md](04-development/testing-strategies.md)** - Testing tools and methodologies
- **[debugging-guide.md](04-development/debugging-guide.md)** - Troubleshooting common issues
- **[performance-tuning.md](04-development/performance-tuning.md)** - Optimization techniques

**Start here if**: You're developing, testing, or optimizing applications.

### 05-reference/ - Quick Lookups

Reference materials and cheat sheets:

- **[api-cheatsheet.md](05-reference/api-cheatsheet.md)** - Function signatures and quick reference
- **[cli-commands.md](05-reference/cli-commands.md)** - Command-line tools and usage
- **[use-cases.md](05-reference/use-cases.md)** - Real-world deployment patterns
- **[gotchas.md](05-reference/gotchas.md)** - Common pitfalls and misconceptions

**Start here if**: You need quick reference or troubleshooting hints.

## Recommended Reading Paths

### For Beginners

1. [hardware-overview.md](01-architecture/hardware-overview.md) - Understand the components
2. [packet-pipeline.md](01-architecture/packet-pipeline.md) - Learn packet flow
3. [queues-ports-sfs.md](01-architecture/queues-ports-sfs.md) - Grasp fundamental concepts
4. [doca-flow-api.md](02-programming/doca-flow-api.md) - Start programming
5. [local-simulation-strategies.md](04-development/local-simulation-strategies.md) - Test without hardware
6. [code-examples.md](04-development/code-examples.md) - See practical examples

### For Experienced Developers

1. [dpdk-integration.md](02-programming/dpdk-integration.md) - DPDK specifics
2. [dpdk-core-functions.md](02-programming/dpdk-core-functions.md) - Multi-core patterns
3. [dpa-programming.md](02-programming/dpa-programming.md) - Advanced processing
4. [performance-tuning.md](04-development/performance-tuning.md) - Optimize
5. [gotchas.md](05-reference/gotchas.md) - Avoid common mistakes

### For Operators

1. [sf-management.md](03-operations/sf-management.md) - Manage SFs
2. [ovs-management.md](03-operations/ovs-management.md) - Configure OVS
3. [hugepages-setup.md](03-operations/hugepages-setup.md) - System setup
4. [debugging-guide.md](04-development/debugging-guide.md) - Troubleshoot

## Quick Links to Common Tasks

### Setting Up Your First Application

1. Allocate hugepages: [hugepages-setup.md](03-operations/hugepages-setup.md)
2. Create SF: [sf-management.md](03-operations/sf-management.md)
3. Write DPDK code: [dpdk-integration.md](02-programming/dpdk-integration.md)
4. Add flow rules: [doca-flow-api.md](02-programming/doca-flow-api.md)
5. Test locally: [local-simulation-strategies.md](04-development/local-simulation-strategies.md)
6. Test on hardware: [testing-strategies.md](04-development/testing-strategies.md)

### Implementing Custom Packet Processing

1. Understand capabilities: [packet-modification.md](02-programming/packet-modification.md)
2. Choose approach: DPA vs ARM vs Flow Engine
3. Write DPA code: [dpa-programming.md](02-programming/dpa-programming.md)
4. Integrate with flows: [doca-flow-api.md](02-programming/doca-flow-api.md)
5. Optimize: [performance-tuning.md](04-development/performance-tuning.md)

### Debugging Performance Issues

1. Check offload status: [debugging-guide.md](04-development/debugging-guide.md)
2. Verify configuration: [performance-tuning.md](04-development/performance-tuning.md)
3. Review common pitfalls: [gotchas.md](05-reference/gotchas.md)
4. Use testing tools: [testing-strategies.md](04-development/testing-strategies.md)

## Key Concepts to Understand

### Architecture
- **eSwitch**: Flow engine logic (not separate hardware) for packet steering
- **DPA**: Programmable hardware cores for custom processing (50-100 Gbps)
- **ARM Cores**: Full CPU flexibility (10-20 Gbps per core)
- **Flow Engine**: Hardware pipeline for line-rate processing (400 Gbps)

### Programming
- **rte_flow**: Standard API for hardware flow programming
- **DPDK**: Packet I/O, queue management, and multi-core support
- **DPA**: C programming for custom packet operations
- **DOCA DPL/P4**: Declarative pipeline programming
- **DOCA Utilities**: Argument parsing (doca_argp), logging, error handling

### Operations
- **SFs (Scalable Functions)**: Lightweight network endpoints
- **Representors**: Virtual ports in OVS for switching
- **Netdevs**: Direct hardware access for DPDK/DOCA
- **Hugepages**: Required memory configuration

## Performance Targets

| Component | Throughput | Latency | Use Case |
|-----------|-----------|---------|----------|
| **NIC Flow Engine** | 400 Gbps | <1 μs | Standard forwarding/NAT |
| **DPA** | 50-100 Gbps | 5-20 μs | Custom processing |
| **ARM Cores** | 10-20 Gbps/core | 50-200 μs | Complex logic |

## Getting Help

### Documentation

- Start with [gotchas.md](05-reference/gotchas.md) for common mistakes
- Check [debugging-guide.md](04-development/debugging-guide.md) for troubleshooting
- Review [api-cheatsheet.md](05-reference/api-cheatsheet.md) for quick reference
- See [cli-commands.md](05-reference/cli-commands.md) for command usage

### External Resources

- **NVIDIA DOCA Documentation**: https://docs.nvidia.com/doca/
- **DPDK Documentation**: https://doc.dpdk.org/
- **BlueField Firmware Downloads**: https://network.nvidia.com/support/firmware/doca/
- **NVIDIA BlueField Docs**: https://docs.nvidia.com/networking/

## Document Conventions

- **Code blocks** show actual commands and code
- **Diagrams** illustrate packet flows and architecture
- **Examples** are complete and runnable
- **Links** connect related topics
- **Performance numbers** based on BlueField-3 hardware

## Contributing

This documentation covers BlueField-3 with DOCA 2.x/3.x. If you find errors or have suggestions:

1. Check if the information is version-specific
2. Verify against NVIDIA official documentation
3. Test on actual hardware when possible

## Version Information

- **Target Platform**: NVIDIA BlueField-3 DPU
- **Software Versions**: DOCA 2.x/3.x, DPDK 23.x
- **Last Updated**: 2025

## Quick Start

**New to BlueField?**
1. Read [hardware-overview.md](01-architecture/hardware-overview.md)
2. Understand [packet-pipeline.md](01-architecture/packet-pipeline.md)
3. Try [code-examples.md](04-development/code-examples.md)

**Ready to code?**
1. Setup [hugepages](03-operations/hugepages-setup.md)
2. Learn [DPDK integration](02-programming/dpdk-integration.md)
3. Program [flow rules](02-programming/doca-flow-api.md)
4. Test locally [without hardware](04-development/local-simulation-strategies.md)

**Need to troubleshoot?**
1. Check [gotchas](05-reference/gotchas.md)
2. Use [debugging guide](04-development/debugging-guide.md)
3. Review [CLI commands](05-reference/cli-commands.md)
