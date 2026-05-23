# DOCA Logging

## Overview

DOCA provides a comprehensive logging system with support for multiple backends, log levels, and source-level control. This guide covers both basic logging macros and advanced logging backend configuration.

## Basic Logging

### DOCA_LOG_REGISTER()

Registers a log source for a module. Must be called before using logging macros.

**Macro:**
```c
DOCA_LOG_REGISTER(source_name);
```

**Parameters:**
- `source_name`: Identifier for this log source (uppercase by convention)

**Example:**
```c
// In doca_flow_handler.c
#include <doca_log.h>

DOCA_LOG_REGISTER(DOCA_FLOW);

void some_function(void) {
    DOCA_LOG_INFO("Function called");  // Logs as "DOCA_FLOW: Function called"
}
```

**Where Used:**
- apps/syn-punt/src/doca_flow_handler.c:18 - `DOCA_LOG_REGISTER(DOCA_FLOW)`
- apps/syn-punt/src/dpdk_init.c:11 - `DOCA_LOG_REGISTER(DPDK_INIT)`
- apps/react-main (multiple modules)

---

### Logging Macros

Standard logging macros with different severity levels.

**Macros:**
```c
DOCA_LOG_INFO(format, ...);   // Informational messages
DOCA_LOG_WARN(format, ...);   // Warning messages
DOCA_LOG_ERR(format, ...);    // Error messages
DOCA_LOG_DBG(format, ...);    // Debug messages (disabled by default)
```

**Example:**
```c
#include <doca_log.h>

DOCA_LOG_REGISTER(MY_APP);

int main(void) {
    uint16_t port_id = 0;

    DOCA_LOG_INFO("Application starting...");

    int ret = initialize_port(port_id);
    if (ret != 0) {
        DOCA_LOG_ERR("Failed to initialize port %u: error %d",
                     port_id, ret);
        return EXIT_FAILURE;
    }

    DOCA_LOG_INFO("Port %u initialized successfully", port_id);
    DOCA_LOG_DBG("Debug info: buffer size = %u", buffer_size);

    return 0;
}
```

**Output:**
```
[INFO][MY_APP] Application starting...
[INFO][MY_APP] Port 0 initialized successfully
```

**Where Used:**
- apps/syn-punt - 39 log statements across all source files
  - DOCA_LOG_INFO: Port initialization, flow creation
  - DOCA_LOG_ERR: Error conditions
  - DOCA_LOG_WARN: Entry processing failures
- apps/react-main - Extensive logging throughout

---

## Log Levels

### Runtime Log Level Control

**Log Levels (from most to least verbose):**
```c
DOCA_LOG_LEVEL_CRIT    // Critical errors only
DOCA_LOG_LEVEL_ERROR   // Errors and above
DOCA_LOG_LEVEL_WARNING // Warnings and above
DOCA_LOG_LEVEL_INFO    // Info and above (default)
DOCA_LOG_LEVEL_DEBUG   // Debug and above (very verbose)
```

**Environment Variable:**
```bash
# Set global log level
export DOCA_LOG_LEVEL=DEBUG
./my_app

# Set per-source log level
export DOCA_LOG_LEVEL=INFO
export DOCA_LOG_LEVEL_DOCA_FLOW=DEBUG  # Only DOCA_FLOW at DEBUG
./my_app
```

---

## Logging Backends

### Overview

DOCA supports multiple logging backends that can be used simultaneously:

- **Standard backend**: Logs to stdout/stderr
- **File backend**: Logs to a file
- **Syslog backend**: Logs to syslog
- **Custom backends**: User-defined logging destinations

---

### doca_log_backend_create_standard()

Creates a standard logging backend (stdout/stderr).

**Function Signature:**
```c
doca_error_t doca_log_backend_create_standard(
    struct doca_log_backend **backend
);
```

**Parameters:**
- `backend`: Output pointer to created backend

**Returns:** DOCA_SUCCESS or error code

**Example:**
```c
#include <doca_log.h>

int main(void) {
    struct doca_log_backend *stdout_backend;
    doca_error_t result;

    // Create standard logging backend
    result = doca_log_backend_create_standard(&stdout_backend);
    if (result != DOCA_SUCCESS) {
        fprintf(stderr, "Failed to create log backend: %s\n",
                doca_error_get_descr(result));
        return EXIT_FAILURE;
    }

    DOCA_LOG_REGISTER(MY_APP);
    DOCA_LOG_INFO("Logging to stdout");

    return 0;
}
```

**Where Used:**
- apps/react-main

---

### doca_log_backend_create_with_file()

Creates a file-based logging backend.

**Function Signature:**
```c
doca_error_t doca_log_backend_create_with_file(
    const char *log_file_path,
    struct doca_log_backend **backend
);
```

**Parameters:**
- `log_file_path`: Path to log file
- `backend`: Output pointer to created backend

**Returns:** DOCA_SUCCESS or error code

**Example:**
```c
struct doca_log_backend *file_backend;

result = doca_log_backend_create_with_file("/var/log/myapp.log",
                                            &file_backend);
if (result != DOCA_SUCCESS) {
    DOCA_LOG_ERR("Failed to create file backend: %s",
                 doca_error_get_descr(result));
    return result;
}

DOCA_LOG_INFO("This goes to both stdout and file");
```

**Note:** This function is referenced in code but may be named `doca_log_backend_create_with_file_sdk()` in some SDK versions.

**Where Used:**
- apps/react-main

---

### doca_log_backend_set_sdk_level()

Sets the log level for a specific backend.

**Function Signature:**
```c
doca_error_t doca_log_backend_set_sdk_level(
    struct doca_log_backend *backend,
    enum doca_log_level level
);
```

**Parameters:**
- `backend`: Logging backend
- `level`: Log level to set

**Returns:** DOCA_SUCCESS or error code

**Example:**
```c
// Create two backends with different log levels
struct doca_log_backend *stdout_backend, *file_backend;

// Stdout: INFO and above
doca_log_backend_create_standard(&stdout_backend);
doca_log_backend_set_sdk_level(stdout_backend, DOCA_LOG_LEVEL_INFO);

// File: DEBUG and above (more verbose)
doca_log_backend_create_with_file("/var/log/debug.log", &file_backend);
doca_log_backend_set_sdk_level(file_backend, DOCA_LOG_LEVEL_DEBUG);

DOCA_LOG_INFO("This goes to both stdout and file");
DOCA_LOG_DBG("This only goes to the file");
```

**Where Used:**
- apps/react-main

---

## Complete Logging Setup Example

```c
#include <doca_log.h>
#include <doca_error.h>

// Register log sources for different modules
DOCA_LOG_REGISTER(MAIN);
DOCA_LOG_REGISTER(PACKET_PROC);
DOCA_LOG_REGISTER(FLOW_MGR);

// Setup logging backends
static doca_error_t setup_logging(void) {
    struct doca_log_backend *stdout_backend, *file_backend;
    doca_error_t result;

    // Create standard backend (console output)
    result = doca_log_backend_create_standard(&stdout_backend);
    if (result != DOCA_SUCCESS) {
        fprintf(stderr, "Failed to create stdout backend: %s\n",
                doca_error_get_descr(result));
        return result;
    }

    // Set console to INFO level (less verbose)
    result = doca_log_backend_set_sdk_level(stdout_backend,
                                              DOCA_LOG_LEVEL_INFO);
    if (result != DOCA_SUCCESS) {
        return result;
    }

    // Create file backend for detailed debugging
    result = doca_log_backend_create_with_file("/tmp/myapp_debug.log",
                                                 &file_backend);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_WARN("Failed to create file backend, continuing without it");
        // Non-fatal, continue with stdout only
    } else {
        // Set file to DEBUG level (very verbose)
        doca_log_backend_set_sdk_level(file_backend, DOCA_LOG_LEVEL_DEBUG);
        DOCA_LOG_INFO("Debug logging enabled to /tmp/myapp_debug.log");
    }

    return DOCA_SUCCESS;
}

int main(int argc, char **argv) {
    doca_error_t result;

    // Setup logging first
    result = setup_logging();
    if (result != DOCA_SUCCESS) {
        return EXIT_FAILURE;
    }

    DOCA_LOG_INFO("Application starting...");

    // Initialize DPDK
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        DOCA_LOG_ERR("Failed to initialize DPDK EAL");
        return EXIT_FAILURE;
    }

    DOCA_LOG_DBG("DPDK EAL initialized with %d arguments consumed", ret);

    // Application logic...

    DOCA_LOG_INFO("Application exiting normally");
    return 0;
}
```

**Console Output (INFO level):**
```
[INFO][MAIN] Application starting...
[INFO][MAIN] Debug logging enabled to /tmp/myapp_debug.log
[INFO][MAIN] Application exiting normally
```

**File Output (DEBUG level):**
```
[INFO][MAIN] Application starting...
[INFO][MAIN] Debug logging enabled to /tmp/myapp_debug.log
[DBG][MAIN] DPDK EAL initialized with 12 arguments consumed
[INFO][MAIN] Application exiting normally
```

---

## Advanced Logging Patterns

### Per-Module Log Levels

```c
// Different verbosity for different modules
DOCA_LOG_REGISTER(INIT);
DOCA_LOG_REGISTER(RX_PATH);
DOCA_LOG_REGISTER(TX_PATH);

// Environment variables:
// export DOCA_LOG_LEVEL_INIT=DEBUG     # Verbose init
// export DOCA_LOG_LEVEL_RX_PATH=INFO   # Normal RX
// export DOCA_LOG_LEVEL_TX_PATH=ERROR  # Quiet TX

DOCA_LOG_DBG("Detailed initialization step...");  // Only visible if INIT is DEBUG
```

---

### Conditional Logging

```c
// Avoid expensive string formatting when not needed
if (doca_log_level_get() >= DOCA_LOG_LEVEL_DEBUG) {
    // Build expensive debug string
    char buf[1024];
    format_packet_details(pkt, buf, sizeof(buf));
    DOCA_LOG_DBG("Packet details: %s", buf);
}
```

---

### Structured Logging

```c
// Use consistent formats for parsing
DOCA_LOG_INFO("EVENT=port_init PORT=%u STATUS=success", port_id);
DOCA_LOG_INFO("EVENT=flow_create PIPE=%s ENTRIES=%u STATUS=success",
              pipe_name, num_entries);

// Easy to grep/parse:
// grep "EVENT=flow_create.*STATUS=success" app.log
```

---

## Logging Best Practices

1. **Register sources early** - Call `DOCA_LOG_REGISTER()` at file scope
2. **Use appropriate levels**:
   - `ERROR`: Failures that prevent operation
   - `WARN`: Issues that don't prevent operation
   - `INFO`: Important state changes
   - `DEBUG`: Detailed diagnostics (disabled by default)

3. **Include context** - Log relevant identifiers (port IDs, flow names, etc.)
4. **Avoid logging in hot paths** - Don't log for every packet!
5. **Use structured formats** - Makes log parsing easier
6. **Check return values** - Even logging setup can fail
7. **Separate backends** - Console (INFO), File (DEBUG)

---

## Common Patterns from Real Apps

### Pattern 1: Error Reporting (syn-punt)

```c
// From apps/syn-punt/src/dpdk_init.c
int ret = rte_eth_dev_configure(port_id, nb_queues, nb_queues, &port_conf);
if (ret != 0) {
    DOCA_LOG_ERR("Failed to configure port %u: %s",
                 port_id, rte_strerror(-ret));
    return DOCA_ERROR_DRIVER;
}
```

**Why it's good:**
- Logs error with context (port_id)
- Includes human-readable error string
- Returns error code to caller

---

### Pattern 2: Progress Indication

```c
// From apps/syn-punt/src/doca_flow_handler.c
DOCA_LOG_INFO("DOCA Flow initialized (mode: %s, queues: %u)",
              flow_cfg.mode_args, nb_queues);

DOCA_LOG_INFO("Created pipe '%s':", pipe_name);
DOCA_LOG_INFO("  - SYN packets → Queue 0 (ARM cores)");
DOCA_LOG_INFO("  - Non-SYN packets → Port %u (hardware fast-path)",
              opposite_port_id);
```

**Why it's good:**
- Shows initialization progress
- Documents configuration choices
- Easy to verify correct setup

---

### Pattern 3: Debug Tracing

```c
DOCA_LOG_DBG("Entering packet_processor, nb_rx=%u", nb_rx);

for (int i = 0; i < nb_rx; i++) {
    DOCA_LOG_DBG("Processing packet %d: len=%u", i, pkts[i]->pkt_len);
    // Process packet...
}

DOCA_LOG_DBG("Exiting packet_processor, nb_tx=%u", nb_tx);
```

**Why it's good:**
- Only enabled when needed (DEBUG level)
- Traces execution flow
- Shows intermediate values

---

## Troubleshooting

### Logs Not Appearing

**Check:**
```bash
# Verify log level
echo $DOCA_LOG_LEVEL  # Should be INFO or DEBUG

# Try explicit level
DOCA_LOG_LEVEL=DEBUG ./myapp

# Check specific source
DOCA_LOG_LEVEL_MY_APP=DEBUG ./myapp
```

### Too Verbose Logs

**Solution:**
```bash
# Reduce global level
export DOCA_LOG_LEVEL=INFO

# Or increase specific sources only
export DOCA_LOG_LEVEL=WARNING
export DOCA_LOG_LEVEL_DOCA_FLOW=INFO  # Only this one more verbose
```

### File Logging Not Working

**Check:**
1. File path writable?
2. Disk space available?
3. Backend creation succeeded?

```c
result = doca_log_backend_create_with_file("/tmp/app.log", &backend);
if (result != DOCA_SUCCESS) {
    DOCA_LOG_ERR("File backend failed: %s",
                 doca_error_get_descr(result));
    // Fallback to stdout only
}
```

---

## Key Takeaways

1. **DOCA_LOG_REGISTER()** must be called before using logging macros
2. **Multiple backends** supported (stdout, file, syslog)
3. **Per-source log levels** via environment variables
4. **Backend log levels** can differ (console=INFO, file=DEBUG)
5. **Used extensively** in apps/syn-punt and apps/react-main
6. **Include context** in log messages (port IDs, error codes, etc.)

---

## Next Steps

- See [DOCA Argument Parsing](doca-argp.md) for command-line configuration
- Read [Debugging Guide](../04-development/debugging-guide.md) for troubleshooting
- Check [apps/syn-punt](../../apps/syn-punt/) for real-world logging examples

---

## References

- **apps/syn-punt** - Production logging patterns
- **apps/react-main** - Advanced multi-backend logging
- DOCA Log Documentation: https://docs.nvidia.com/doca/sdk/doca+log/index.html
