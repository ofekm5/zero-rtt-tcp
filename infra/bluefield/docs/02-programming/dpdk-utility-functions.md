# DPDK Utility Functions

## Overview

This document covers essential DPDK utility functions for error handling, memory management, timing, and port management. These functions are heavily used in real applications but often overlooked in basic tutorials.

## Error Handling

### rte_strerror()

Converts DPDK error codes to human-readable strings. **Critical for debugging!**

**Function Signature:**
```c
const char *rte_strerror(int errnum);
```

**Parameters:**
- `errnum`: Error code (typically negated errno value)

**Returns:** Pointer to error message string

**Example:**
```c
int ret = rte_eth_dev_configure(port_id, nb_rx_q, nb_tx_q, &port_conf);
if (ret != 0) {
    DOCA_LOG_ERR("Failed to configure port %u: %s",
                 port_id, rte_strerror(-ret));
    return DOCA_ERROR_DRIVER;
}
```

**Where Used:**
- apps/syn-punt/src/dpdk_init.c - 8 occurrences for comprehensive error reporting
  - Line 20: EAL init failure
  - Line 57: Device info failure
  - Line 83: Port configuration failure
  - Line 91: Descriptor adjustment failure
  - Line 111: RX queue setup failure
  - Line 131: TX queue setup failure
  - Line 139: Port start failure
  - Line 166: Promiscuous mode failure

**Why It's Important:**
DPDK functions return negative errno values. Without `rte_strerror()`, you get:
```
Failed to configure port: -22
```

With `rte_strerror()`:
```
Failed to configure port: Invalid argument
```

**Common DPDK Error Codes:**
```c
-EINVAL  (-22)  // Invalid argument
-ENOMEM  (-12)  // Out of memory
-ENOTSUP (-95)  // Operation not supported
-ENODEV  (-19)  // No such device
-EBUSY   (-16)  // Device or resource busy
```

---

### rte_exit()

Terminates the application with an error message and cleanup.

**Function Signature:**
```c
void rte_exit(int exit_code, const char *format, ...) __rte_noreturn;
```

**Parameters:**
- `exit_code`: Exit status code (e.g., EXIT_FAILURE)
- `format`: Printf-style format string
- `...`: Variable arguments

**Returns:** Never returns (noreturn function)

**Example:**
```c
int main(int argc, char **argv) {
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        rte_exit(EXIT_FAILURE, "Error with EAL initialization: %s\n",
                 rte_strerror(-ret));
    }

    uint16_t nb_ports = rte_eth_dev_count_avail();
    if (nb_ports == 0) {
        rte_exit(EXIT_FAILURE, "No Ethernet ports available\n");
    }

    // Application logic...
    return 0;
}
```

**Where Used:**
- apps/wire-example/wire.c - Multiple occurrences (17 total)
  - Line 167: Insufficient memory for mbuf pool
  - Line 311: EAL initialization failure
  - Line 326: Insufficient port arguments
  - Line 362: Not enough worker lcores

**Best Practice:**
Use `rte_exit()` instead of `exit()` because it:
1. Performs DPDK cleanup automatically
2. Flushes log buffers
3. Releases shared resources properly

---

## Port Discovery and Management

### rte_eth_dev_count_avail()

Returns the number of available Ethernet ports.

**Function Signature:**
```c
uint16_t rte_eth_dev_count_avail(void);
```

**Returns:** Number of available Ethernet ports

**Example:**
```c
uint16_t nb_ports = rte_eth_dev_count_avail();
printf("Total ports available: %u\n", nb_ports);

if (nb_ports == 0) {
    rte_exit(EXIT_FAILURE, "No DPDK ports found!\n");
}

if (nb_ports < 2) {
    rte_exit(EXIT_FAILURE, "Need at least 2 ports for forwarding\n");
}
```

**Where Used:**
- apps/wire-example/wire.c:61

---

### rte_eth_dev_get_name_by_port()

Gets the name of an Ethernet port by its ID.

**Function Signature:**
```c
int rte_eth_dev_get_name_by_port(uint16_t port_id, char *name);
```

**Parameters:**
- `port_id`: Port identifier
- `name`: Buffer to store port name (min RTE_ETH_NAME_MAX_LEN bytes)

**Returns:**
- 0 on success
- Negative value on error

**Example:**
```c
char name[RTE_ETH_NAME_MAX_LEN];
uint16_t port_id;

RTE_ETH_FOREACH_DEV(port_id) {
    int ret = rte_eth_dev_get_name_by_port(port_id, name);
    if (ret == 0) {
        printf("Port %u: %s\n", port_id, name);

        // Check if this is a representor port
        if (strstr(name, "_representor_")) {
            printf("  Type: Representor Port\n");
        }
    }
}
```

**Example Output:**
```
Port 0: 0000:03:00.0
Port 1: 0000:03:00.0_representor_pf0vf0
Port 2: 0000:03:00.0_representor_pf0vf1
```

**Where Used:**
- apps/wire-example/wire.c:85

---

### rte_dev_name()

Gets the name of a device.

**Function Signature:**
```c
const char *rte_dev_name(const struct rte_device *dev);
```

**Parameters:**
- `dev`: Pointer to device structure (from `rte_eth_dev_info.device`)

**Returns:** Device name string or NULL

**Example:**
```c
struct rte_eth_dev_info dev_info;
rte_eth_dev_info_get(port_id, &dev_info);

if (dev_info.device && rte_dev_name(dev_info.device)) {
    printf("Device: %s\n", rte_dev_name(dev_info.device));
}
```

**Where Used:**
- apps/wire-example/wire.c:115-116

---

### rte_eth_link_get_nowait()

Gets the link status without waiting for link to come up.

**Function Signature:**
```c
int rte_eth_link_get_nowait(uint16_t port_id, struct rte_eth_link *link);
```

**Parameters:**
- `port_id`: Port identifier
- `link`: Pointer to link structure to fill

**Returns:**
- 0 on success
- Negative value on error

**Example:**
```c
struct rte_eth_link link;
int ret = rte_eth_link_get_nowait(port_id, &link);

if (ret == 0) {
    printf("Link Status: %s\n", link.link_status ? "UP" : "DOWN");

    if (link.link_status) {
        printf("Link Speed: %u Mbps\n", link.link_speed);
        printf("Link Duplex: %s\n",
               link.link_duplex == RTE_ETH_LINK_FULL_DUPLEX ? "Full" : "Half");
    }
}
```

**Where Used:**
- apps/wire-example/wire.c:125

**Use Cases:**
- Port discovery tools
- Health monitoring
- Pre-flight checks before starting application

---

## Statistics and Monitoring

### rte_eth_stats_get()

Gets basic Ethernet statistics for a port.

**Function Signature:**
```c
int rte_eth_stats_get(uint16_t port_id, struct rte_eth_stats *stats);
```

**Parameters:**
- `port_id`: Port identifier
- `stats`: Pointer to statistics structure

**Returns:**
- 0 on success
- Negative value on error

**Example:**
```c
struct rte_eth_stats stats;

if (rte_eth_stats_get(port_id, &stats) == 0) {
    printf("Port %u Statistics:\n", port_id);
    printf("  RX packets: %lu\n", stats.ipackets);
    printf("  TX packets: %lu\n", stats.opackets);
    printf("  RX bytes:   %lu\n", stats.ibytes);
    printf("  TX bytes:   %lu\n", stats.obytes);
    printf("  RX errors:  %lu\n", stats.ierrors);
    printf("  TX errors:  %lu\n", stats.oerrors);
    printf("  RX dropped: %lu\n", stats.imissed);
}
```

**Where Used:**
- apps/react-main/react_arm.c (2 occurrences)

**Monitoring Loop Example:**
```c
void print_stats_loop(uint16_t port_id) {
    struct rte_eth_stats stats, prev_stats = {0};

    while (1) {
        sleep(1);

        if (rte_eth_stats_get(port_id, &stats) != 0) {
            continue;
        }

        uint64_t rx_pps = stats.ipackets - prev_stats.ipackets;
        uint64_t tx_pps = stats.opackets - prev_stats.opackets;
        uint64_t rx_bps = (stats.ibytes - prev_stats.ibytes) * 8;

        printf("RX: %lu pps, %.2f Gbps | TX: %lu pps\n",
               rx_pps, rx_bps / 1e9, tx_pps);

        prev_stats = stats;
    }
}
```

---

### rte_eth_xstats_get_names_by_id() / rte_eth_xstats_get_by_id()

Gets extended statistics (hardware-specific counters).

**Function Signatures:**
```c
int rte_eth_xstats_get_names_by_id(uint16_t port_id,
                                   struct rte_eth_xstat_name *xstats_names,
                                   unsigned int size,
                                   uint64_t *ids);

int rte_eth_xstats_get_by_id(uint16_t port_id,
                              const uint64_t *ids,
                              uint64_t *values,
                              unsigned int size);
```

**Example:**
```c
// Get number of extended stats
int len = rte_eth_xstats_get_names_by_id(port_id, NULL, 0, NULL);
if (len < 0) {
    return -1;
}

// Allocate arrays
struct rte_eth_xstat_name *names = malloc(len * sizeof(*names));
uint64_t *values = malloc(len * sizeof(*values));

// Get stat names and values
rte_eth_xstats_get_names_by_id(port_id, names, len, NULL);
rte_eth_xstats_get_by_id(port_id, NULL, values, len);

// Print all extended stats
for (int i = 0; i < len; i++) {
    printf("%s: %lu\n", names[i].name, values[i]);
}
```

**Where Used:**
- apps/react-main/react_sample.c

**Use Cases:**
- Debugging packet drops
- Hardware counter monitoring
- Performance profiling

---

## Memory Management

### rte_zmalloc() / rte_zmalloc_socket()

Allocates zero-initialized memory from DPDK hugepages.

**Function Signatures:**
```c
void *rte_zmalloc(const char *type, size_t size, unsigned align);

void *rte_zmalloc_socket(const char *type, size_t size,
                         unsigned align, int socket_id);
```

**Parameters:**
- `type`: String describing allocation (for debugging/statistics)
- `size`: Size in bytes
- `align`: Alignment requirement (0 for default)
- `socket_id`: NUMA socket ID (for socket-specific allocation)

**Returns:** Pointer to allocated memory or NULL on failure

**Example:**
```c
// Allocate on current NUMA socket
struct my_struct *ptr = rte_zmalloc("my_data",
                                     sizeof(struct my_struct),
                                     0);
if (!ptr) {
    rte_exit(EXIT_FAILURE, "Failed to allocate memory\n");
}

// Allocate on specific NUMA socket
struct my_struct *ptr2 = rte_zmalloc_socket("my_data",
                                             sizeof(struct my_struct),
                                             RTE_CACHE_LINE_SIZE,
                                             rte_socket_id());
```

**Where Used:**
- apps/react-main

**When to Use:**
- Large allocations that benefit from hugepages
- NUMA-aware memory allocation
- Cache-line aligned structures

**Normal malloc() vs rte_zmalloc():**
```
malloc():     Uses standard heap (4KB pages)
rte_zmalloc(): Uses hugepages (2MB pages) - better TLB efficiency
```

---

### rte_free()

Frees memory allocated by `rte_malloc()` or `rte_zmalloc()`.

**Function Signature:**
```c
void rte_free(void *ptr);
```

**Parameters:**
- `ptr`: Pointer to memory allocated by rte_malloc/rte_zmalloc

**Example:**
```c
void *ptr = rte_zmalloc("data", 1024, 0);

// Use memory...

rte_free(ptr);
```

**Where Used:**
- apps/react-main

---

## Timing Functions

### rte_get_timer_hz()

Gets the frequency of the TSC timer in Hz.

**Function Signature:**
```c
uint64_t rte_get_timer_hz(void);
```

**Returns:** Timer frequency in Hz

**Example:**
```c
uint64_t hz = rte_get_timer_hz();
printf("Timer frequency: %lu Hz\n", hz);

// Convert cycles to microseconds
uint64_t cycles = 1000000;
uint64_t usec = (cycles * 1000000) / hz;
printf("%lu cycles = %lu usec\n", cycles, usec);
```

**Where Used:**
- apps/react-main

---

### rte_get_tsc_hz()

Gets the frequency of the CPU Time Stamp Counter.

**Function Signature:**
```c
uint64_t rte_get_tsc_hz(void);
```

**Returns:** TSC frequency in Hz

**Example:**
```c
uint64_t tsc_hz = rte_get_tsc_hz();
printf("TSC frequency: %.2f GHz\n", tsc_hz / 1e9);
```

**Where Used:**
- apps/react-main

---

### rte_get_tsc_cycles()

Reads the current CPU Time Stamp Counter value.

**Function Signature:**
```c
static inline uint64_t rte_get_tsc_cycles(void);
```

**Returns:** Current TSC value

**Example - Latency Measurement:**
```c
uint64_t start = rte_get_tsc_cycles();

// Process packet
process_packet(pkt);

uint64_t end = rte_get_tsc_cycles();
uint64_t cycles = end - start;

// Convert to nanoseconds
uint64_t tsc_hz = rte_get_tsc_hz();
uint64_t ns = (cycles * 1000000000) / tsc_hz;

printf("Processing took %lu ns\n", ns);
```

**Where Used:**
- apps/react-main
- bluefield-docs/04-development/testing-strategies.md (latency testing)

---

## Complete Example: Port Discovery Tool

```c
// Based on apps/wire-example/wire.c list_ports() function

#include <rte_ethdev.h>

void list_ports(void) {
    uint16_t port_id;
    uint16_t nb_ports = rte_eth_dev_count_avail();

    printf("\n=== Available DPDK Ports ===\n");
    printf("Total ports available: %u\n\n", nb_ports);

    if (nb_ports == 0) {
        printf("No DPDK ports found!\n");
        return;
    }

    RTE_ETH_FOREACH_DEV(port_id) {
        char name[RTE_ETH_NAME_MAX_LEN];
        struct rte_eth_dev_info dev_info;
        struct rte_ether_addr addr;
        struct rte_eth_link link;
        int ret;

        printf("Port %u:\n", port_id);

        // Get port name
        ret = rte_eth_dev_get_name_by_port(port_id, name);
        if (ret == 0) {
            printf("  DPDK Name: %s\n", name);

            if (strstr(name, "_representor_")) {
                printf("  Type: Representor Port\n");
            }
        }

        // Get MAC address
        ret = rte_eth_macaddr_get(port_id, &addr);
        if (ret == 0) {
            printf("  MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                   addr.addr_bytes[0], addr.addr_bytes[1],
                   addr.addr_bytes[2], addr.addr_bytes[3],
                   addr.addr_bytes[4], addr.addr_bytes[5]);
        }

        // Get device info
        ret = rte_eth_dev_info_get(port_id, &dev_info);
        if (ret == 0) {
            if (dev_info.driver_name) {
                printf("  Driver: %s\n", dev_info.driver_name);
            }

            if (dev_info.device && rte_dev_name(dev_info.device)) {
                printf("  Device: %s\n", rte_dev_name(dev_info.device));
            }

            printf("  Max RX queues: %u\n", dev_info.max_rx_queues);
            printf("  Max TX queues: %u\n", dev_info.max_tx_queues);
        }

        // Get link status
        ret = rte_eth_link_get_nowait(port_id, &link);
        if (ret == 0) {
            printf("  Link Status: %s\n",
                   link.link_status ? "UP" : "DOWN");
            if (link.link_status) {
                printf("  Link Speed: %u Mbps\n", link.link_speed);
                printf("  Link Duplex: %s\n",
                       link.link_duplex == RTE_ETH_LINK_FULL_DUPLEX
                       ? "Full" : "Half");
            }
        }

        printf("\n");
    }
    printf("============================\n\n");
}
```

---

## Best Practices

1. **Always use rte_strerror()** for error messages - Makes debugging much easier
2. **Use rte_exit() instead of exit()** - Ensures proper DPDK cleanup
3. **Validate port count** before use - Check `rte_eth_dev_count_avail()` early
4. **Use NUMA-aware allocation** - `rte_zmalloc_socket(rte_socket_id())`
5. **Monitor statistics regularly** - Use `rte_eth_stats_get()` for health checks
6. **Measure with TSC** - Use `rte_get_tsc_cycles()` for high-resolution timing

---

## Key Takeaways

1. **rte_strerror()** is critical for debugging (used 8+ times in syn-punt)
2. **rte_exit()** handles cleanup automatically
3. **Port discovery functions** enable dynamic port management
4. **Statistics functions** essential for monitoring and debugging
5. **NUMA-aware allocation** improves performance
6. **TSC functions** provide high-resolution timing

---

## Next Steps

- See [DPDK Core Functions](dpdk-core-functions.md) for EAL functions
- Read [Debugging Guide](../04-development/debugging-guide.md) for troubleshooting
- Check [wire-example](../../apps/wire-example/wire.c) for complete examples

---

## References

- **apps/syn-punt/src/dpdk_init.c** - Error handling with rte_strerror()
- **apps/wire-example/wire.c** - Port discovery and management
- **apps/react-main** - Statistics and memory management
- DPDK API Documentation: https://doc.dpdk.org/api/
