---
type: Wiki Entry
title: "BlueField-3 DPU Documentation"
description: "Comprehensive technical documentation for NVIDIA BlueField-3 DPU development, covering architecture, programming, operations, and reference materials."
tags: [bluefield, dpu]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/README.md`

# BlueField-3 DPU Documentation

## Overview

Comprehensive technical documentation for NVIDIA BlueField-3 DPU development, covering architecture, programming, operations, and reference materials.

**Target Platform**: NVIDIA BlueField-3 DPU with DOCA 2.x/3.x and DPDK 23.x

## Documentation Structure

### 01-architecture/ - Understanding the Hardware

Core architectural concepts and how components work together:

- **[[Hardware Overview]]** - BlueField-3 components, modes, and capabilities
- **[[Packet Pipeline]]** - Complete packet flow from ingress to egress
- **[[Eswitch Flow Engine]]** - Hardware flow engine and eSwitch internals
- **[[Queues Ports SFs]]** - Queues, ports, representors, and Scalable Functions

**Start here if**: You're new to BlueField or need to understand how packets flow through the system.

### 02-programming/ - Writing Code

Programming interfaces and APIs for packet processing:

**Core Programming APIs:**
- **[[DOCA Flow API]]** - Hardware flow programming with rte_flow
- **[[DPDK Integration]]** - DPDK queue setup and packet I/O
- **[[DPA Programming]]** - Custom packet processing on DPA cores
- **[[DOCA DPL P4]]** - P4-based pipeline programming and parser customization
- **[[Packet Modification]]** - Packet modification capabilities and generation

**Essential Utilities:**
- **[[DPDK Core Functions]]** - DPDK EAL initialization and multi-core management
- **[[DPDK Utility Functions]]** - Error handling, port discovery, statistics, and timing
- **[[DOCA ARGP]]** - Command-line argument parsing library
- **[[DOCA Logging]]** - Logging configuration and backends

**Start here if**: You're implementing packet processing applications.

### 03-operations/ - Managing the DPU

Operational procedures and system configuration:

- **[[SF Management]]** - Creating and managing Scalable Functions
- **[[OVS Management]]** - OVS bridge configuration and flow offload
- **[[Hugepages Setup]]** - Memory configuration for DPDK

**Start here if**: You're setting up or administering a BlueField system.

### 04-development/ - Building and Testing

Development workflows, testing, and optimization:

- **[[Code Examples]]** - Practical code samples
- **[[Local Simulation Strategies]]** - Testing without hardware using DPDK virtual devices
- **[[Testing Strategies]]** - Testing tools and methodologies
- **[[Debugging Guide]]** - Troubleshooting common issues
- **[[Performance Tuning]]** - Optimization techniques

**Start here if**: You're developing, testing, or optimizing applications.

### 05-reference/ - Quick Lookups

Reference materials and cheat sheets:

- **[[API Cheatsheet]]** - Function signatures and quick reference
- **[[CLI Commands]]** - Command-line tools and usage
- **[use-cases.md](05-reference/use-cases.md)** - Real-world deployment patterns
- **[[Gotchas]]** - Common pitfalls and misconceptions

**Start here if**: You need quick reference or troubleshooting hints.

## Recommended Reading Paths

### For Beginners

1. [[Hardware Overview]] - Understand the components
2. [[Packet Pipeline]] - Learn packet flow
3. [[Queues Ports SFs]] - Grasp fundamental concepts
4. [[DOCA Flow API]] - Start programming
5. [[Local Simulation Strategies]] - Test without hardware
6. [[Code Examples]] - See practical examples

### For Experienced Developers

1. [[DPDK Integration]] - DPDK specifics
2. [[DPDK Core Functions]] - Multi-core patterns
3. [[DPA Programming]] - Advanced processing
4. [[Performance Tuning]] - Optimize
5. [[Gotchas]] - Avoid common mistakes

### For Operators

1. [[SF Management]] - Manage SFs
2. [[OVS Management]] - Configure OVS
3. [[Hugepages Setup]] - System setup
4. [[Debugging Guide]] - Troubleshoot

## Quick Links to Common Tasks

### Setting Up Your First Application

1. Allocate hugepages: [[Hugepages Setup]]
2. Create SF: [[SF Management]]
3. Write DPDK code: [[DPDK Integration]]
4. Add flow rules: [[DOCA Flow API]]
5. Test locally: [[Local Simulation Strategies]]
6. Test on hardware: [[Testing Strategies]]

### Implementing Custom Packet Processing

1. Understand capabilities: [[Packet Modification]]
2. Choose approach: DPA vs ARM vs Flow Engine
3. Write DPA code: [[DPA Programming]]
4. Integrate with flows: [[DOCA Flow API]]
5. Optimize: [[Performance Tuning]]

### Debugging Performance Issues

1. Check offload status: [[Debugging Guide]]
2. Verify configuration: [[Performance Tuning]]
3. Review common pitfalls: [[Gotchas]]
4. Use testing tools: [[Testing Strategies]]

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

- Start with [[Gotchas]] for common mistakes
- Check [[Debugging Guide]] for troubleshooting
- Review [[API Cheatsheet]] for quick reference
- See [[CLI Commands]] for command usage

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
1. Read [[Hardware Overview]]
2. Understand [[Packet Pipeline]]
3. Try [[Code Examples]]

**Ready to code?**
1. Setup [[Hugepages Setup|hugepages]]
2. Learn [[DPDK Integration]]
3. Program [[DOCA Flow API|flow rules]]
4. Test locally [[Local Simulation Strategies|without hardware]]

**Need to troubleshoot?**
1. Check [[Gotchas]]
2. Use [[Debugging Guide]]
3. Review [[CLI Commands]]
