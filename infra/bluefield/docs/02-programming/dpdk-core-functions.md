# DPDK Core Functions (rte_eal_*)

## Overview

The DPDK Environment Abstraction Layer (EAL) provides core functionality for initializing DPDK, managing CPU cores (lcores), and controlling the application lifecycle. This guide covers essential EAL functions used in BlueField-3 applications.

## Initialization and Cleanup

### rte_eal_init()

Initializes the DPDK Environment Abstraction Layer (EAL). This must be the first DPDK function called.

**Function Signature:**
```c
int rte_eal_init(int argc, char **argv);
```

**Parameters:**
- `argc`: Argument count (from main)
- `argv`: Argument vector (from main)

**Returns:**
- Number of parsed arguments on success (caller should skip these)
- Negative value on error

**Example:**
```c
int main(int argc, char **argv) {
    // Initialize DPDK EAL
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        rte_exit(EXIT_FAILURE, "Error with EAL initialization: %s\n",
                 rte_strerror(-ret));
    }

    // Update argc/argv to skip EAL arguments
    argc -= ret;
    argv += ret;

    // Now parse application-specific arguments...

    return 0;
}
```

**Common EAL Arguments:**
```bash
# Basic usage
./myapp -l 0-3                    # Use cores 0-3
./myapp -l 0-3 -n 4               # 4 memory channels
./myapp -l 0-3 -- <app args>      # App args after --

# BlueField-3 specific
./myapp -a auxiliary:mlx5_core.sf.2,dv_flow_en=2   # Bind SF with flow offload
```

**Where Used:**
- apps/syn-punt/src/dpdk_init.c:18
- apps/wire-example/wire.c:309
- apps/react-main (multiple locations)

---

### rte_eal_cleanup()

Cleans up EAL resources before application exit.

**Function Signature:**
```c
int rte_eal_cleanup(void);
```

**Returns:**
- 0 on success
- Negative value on error

**Example:**
```c
int main(int argc, char **argv) {
    rte_eal_init(argc, argv);

    // Application logic...

    // Cleanup before exit
    rte_eal_cleanup();
    return 0;
}
```

**Where Used:**
- apps/react-main

---

## Multi-Core Management

### rte_eal_remote_launch()

Launches a function on a remote lcore (worker core).

**Function Signature:**
```c
int rte_eal_remote_launch(int (*f)(void *), void *arg, unsigned worker_id);
```

**Parameters:**
- `f`: Function to execute (must return int and accept void*)
- `arg`: Argument to pass to function
- `worker_id`: Lcore ID to run the function on

**Returns:**
- 0 on success
- Negative value on error

**Example:**
```c
// Thread function
static int lcore_main(void *arg) {
    unsigned lcore_id = rte_lcore_id();
    printf("Starting on lcore %u\n", lcore_id);

    // Main processing loop
    while (1) {
        // Process packets...
    }

    return 0;
}

int main(int argc, char **argv) {
    rte_eal_init(argc, argv);

    unsigned lcore_id;

    // Launch worker threads
    RTE_LCORE_FOREACH_WORKER(lcore_id) {
        rte_eal_remote_launch(lcore_main, NULL, lcore_id);
    }

    // Main thread can also process or just wait
    rte_eal_mp_wait_lcore();

    return 0;
}
```

**Where Used:**
- apps/wire-example/wire.c:365-366 (launches bidirectional forwarding threads)
- apps/react-main/react_sample.c:1037

**Common Pattern - Per-Core Packet Processing:**
```c
struct worker_args {
    uint16_t port_id;
    uint16_t queue_id;
};

static int packet_worker(void *arg) {
    struct worker_args *args = (struct worker_args *)arg;
    struct rte_mbuf *pkts[BURST_SIZE];

    while (1) {
        uint16_t nb_rx = rte_eth_rx_burst(args->port_id, args->queue_id,
                                          pkts, BURST_SIZE);

        // Process packets on this core
        for (int i = 0; i < nb_rx; i++) {
            process_packet(pkts[i]);
        }

        rte_eth_tx_burst(args->port_id, args->queue_id, pkts, nb_rx);
    }

    return 0;
}

int main(int argc, char **argv) {
    rte_eal_init(argc, argv);

    // Create argument structure for each worker
    struct worker_args args[MAX_LCORES];
    unsigned lcore_id;
    int i = 0;

    RTE_LCORE_FOREACH_WORKER(lcore_id) {
        args[i].port_id = PORT_ID;
        args[i].queue_id = i;  // 1:1 mapping queue to lcore
        rte_eal_remote_launch(packet_worker, &args[i], lcore_id);
        i++;
    }

    rte_eal_mp_wait_lcore();
    return 0;
}
```

---

### rte_eal_mp_wait_lcore()

Waits for all remote lcores (worker threads) to finish.

**Function Signature:**
```c
void rte_eal_mp_wait_lcore(void);
```

**Returns:** Nothing (blocks until all workers complete)

**Example:**
```c
int main(int argc, char **argv) {
    rte_eal_init(argc, argv);

    // Launch workers
    RTE_LCORE_FOREACH_WORKER(lcore_id) {
        rte_eal_remote_launch(worker_func, NULL, lcore_id);
    }

    // Main thread waits for all workers
    // (Workers typically run forever, so this blocks indefinitely)
    rte_eal_mp_wait_lcore();

    return 0;
}
```

**Where Used:**
- apps/wire-example/wire.c:368

---

### rte_eal_wait_lcore()

Waits for a specific lcore to finish.

**Function Signature:**
```c
int rte_eal_wait_lcore(unsigned worker_id);
```

**Parameters:**
- `worker_id`: Lcore ID to wait for

**Returns:**
- Return value from the lcore function
- Negative value if lcore is in wrong state

**Example:**
```c
// Launch specific worker
rte_eal_remote_launch(worker_func, NULL, 2);

// Wait only for lcore 2
int ret = rte_eal_wait_lcore(2);
printf("Lcore 2 finished with return value: %d\n", ret);
```

**Where Used:**
- apps/react-main

---

## Lcore Information

### rte_lcore_id()

Gets the ID of the current lcore.

**Function Signature:**
```c
unsigned rte_lcore_id(void);
```

**Returns:** Current lcore ID

**Example:**
```c
static int worker_func(void *arg) {
    unsigned lcore_id = rte_lcore_id();
    printf("Running on lcore %u\n", lcore_id);

    // Use lcore ID for queue assignment
    uint16_t queue_id = lcore_id;

    while (1) {
        rte_eth_rx_burst(PORT_ID, queue_id, pkts, BURST_SIZE);
        // Process packets...
    }

    return 0;
}
```

**Where Used:**
- apps/wire-example (via RTE_LCORE_FOREACH_WORKER macro)
- apps/react-main

---

### Common Macros

#### RTE_LCORE_FOREACH_WORKER

Iterates over all worker lcores (excludes main lcore).

**Example:**
```c
unsigned lcore_id;

RTE_LCORE_FOREACH_WORKER(lcore_id) {
    printf("Worker lcore: %u\n", lcore_id);
    rte_eal_remote_launch(worker_func, NULL, lcore_id);
}
```

**Where Used:**
- apps/wire-example/wire.c:351

---

## NUMA and Socket Information

### rte_socket_id()

Gets the NUMA socket ID of the current lcore.

**Function Signature:**
```c
unsigned rte_socket_id(void);
```

**Returns:** Socket ID of current lcore

**Example:**
```c
// Create mempool on same NUMA node as lcore
struct rte_mempool *pool = rte_pktmbuf_pool_create(
    "MBUF_POOL",
    NUM_MBUFS,
    MBUF_CACHE_SIZE,
    0,
    RTE_MBUF_DEFAULT_BUF_SIZE,
    rte_socket_id()  // Use current socket
);
```

**Where Used:**
- apps/syn-punt/src/dpdk_init.c:72
- apps/wire-example/wire.c:164

---

## Complete Multi-Core Example

```c
// wire-example pattern from apps/wire-example/wire.c

#include <rte_eal.h>
#include <rte_lcore.h>
#include <rte_launch.h>

struct wire_args {
    uint16_t in_port;
    uint16_t out_port;
};

static int wire_lcore(void *arg) {
    struct wire_args *args = (struct wire_args *)arg;
    unsigned lcore_id = rte_lcore_id();

    printf("Lcore %u: Forwarding %u -> %u\n",
           lcore_id, args->in_port, args->out_port);

    while (1) {
        struct rte_mbuf *pkts[32];
        uint16_t nb_rx = rte_eth_rx_burst(args->in_port, 0, pkts, 32);

        if (nb_rx > 0) {
            rte_eth_tx_burst(args->out_port, 0, pkts, nb_rx);
        }
    }

    return 0;
}

int main(int argc, char **argv) {
    // Initialize EAL
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        rte_exit(EXIT_FAILURE, "EAL init failed\n");
    }
    argc -= ret;
    argv += ret;

    // Initialize ports
    init_ports();

    // Setup bidirectional forwarding on two worker cores
    struct wire_args args1 = {.in_port = 0, .out_port = 1};
    struct wire_args args2 = {.in_port = 1, .out_port = 0};

    unsigned lcore_id;
    unsigned launched = 0;
    unsigned lcore1 = 0, lcore2 = 0;

    // Find two worker lcores
    RTE_LCORE_FOREACH_WORKER(lcore_id) {
        if (launched == 0) {
            lcore1 = lcore_id;
            launched++;
        } else if (launched == 1) {
            lcore2 = lcore_id;
            launched++;
            break;
        }
    }

    if (launched < 2) {
        rte_exit(EXIT_FAILURE, "Need at least 2 worker cores. Run with -l 0-2\n");
    }

    // Launch workers
    rte_eal_remote_launch(wire_lcore, &args1, lcore1);
    rte_eal_remote_launch(wire_lcore, &args2, lcore2);

    // Wait for workers (blocks forever)
    rte_eal_mp_wait_lcore();

    // Cleanup (never reached in this example)
    rte_eal_cleanup();
    return 0;
}
```

---

## Best Practices

1. **Always call rte_eal_init() first** - It must be the very first DPDK function called
2. **Update argc/argv after init** - Skip parsed EAL arguments
3. **One queue per core** - Assign queue_id = lcore_id for lock-free operation
4. **Use NUMA-aware allocation** - Pass `rte_socket_id()` to allocation functions
5. **Check worker count** - Verify enough lcores before launching workers
6. **Handle signals** - Workers typically run forever; implement signal handling for graceful shutdown
7. **Don't mix blocking and polling** - Workers should either poll continuously or use interrupts, not both

---

## Common Patterns

### Pattern 1: Symmetric Multi-Processing (Wire Example)
Each core handles one direction of traffic independently.

```c
// Core 1: Port A -> Port B
// Core 2: Port B -> Port A
```

### Pattern 2: Pipeline Processing
Each core performs one stage of processing.

```c
// Core 1: Receive + Parse
// Core 2: Classify + Modify
// Core 3: Transmit
```

### Pattern 3: Per-Queue Processing (RSS)
Each core processes its own queue via RSS distribution.

```c
// Core 1: Queue 0
// Core 2: Queue 1
// Core 3: Queue 2
// etc.
```

---

## Troubleshooting

### Workers Don't Start

**Symptom:** `rte_eal_remote_launch()` fails

**Check:**
```bash
# Verify enough cores allocated
./myapp -l 0-3  # Allocates cores 0,1,2,3 (4 total)

# Check core isolation
cat /proc/cmdline | grep isolcpus
```

### Poor Performance on Multi-Core

**Check:**
1. NUMA placement: Are cores on same socket as NICs?
2. Queue assignment: One queue per core?
3. Core affinity: Are cores actually running on assigned CPUs?

**Verify:**
```bash
# Check lcore to physical CPU mapping
cat /proc/<pid>/status | grep Cpus_allowed_list

# Monitor per-core CPU usage
htop  # Press 't' to see individual cores
```

---

## Key Takeaways

1. **rte_eal_init()** must be first DPDK call
2. **rte_eal_remote_launch()** runs functions on worker cores
3. **rte_eal_mp_wait_lcore()** waits for all workers
4. **RTE_LCORE_FOREACH_WORKER** iterates worker cores
5. **One queue per core** is optimal for performance
6. **rte_socket_id()** enables NUMA-aware allocation

---

## Next Steps

- See [DPDK Integration](dpdk-integration.md) for queue setup
- Read [Performance Tuning](../04-development/performance-tuning.md) for optimization
- Check [wire-example](../../apps/wire-example/wire.c) for complete implementation

---

## References

- **apps/wire-example/wire.c** - Complete multi-core wire application
- **apps/react-main** - Advanced multi-threaded packet processing
- DPDK EAL Documentation: https://doc.dpdk.org/guides/prog_guide/env_abstraction_layer.html
