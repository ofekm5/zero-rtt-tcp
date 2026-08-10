---
type: Wiki Entry
title: "DOCA Argument Parsing Library (doca_argp)"
description: "The DOCA Argument Parsing Library (docaargp) provides a structured, type-safe way to define and parse command-line arguments for DOCA applications. It integr..."
tags: [bluefield, programming, doca]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/02-programming/doca-argp.md`

# DOCA Argument Parsing Library (doca_argp)

## Overview

The DOCA Argument Parsing Library (`doca_argp`) provides a structured, type-safe way to define and parse command-line arguments for DOCA applications. It integrates seamlessly with DPDK's EAL arguments and provides validation, help generation, and callback-based parameter handling.

## Why Use doca_argp?

**Without doca_argp (manual parsing):**
```c
// Fragile, error-prone
if (argc < 3) {
    printf("Usage: %s --size <num> --interval <num>\n", argv[0]);
    return -1;
}
int size = atoi(argv[2]);  // No validation!
```

**With doca_argp:**
```c
// Type-safe, validated, automatic help generation
doca_argp_param_create(&size_param);
doca_argp_param_set_type(size_param, DOCA_ARGP_TYPE_INT);
doca_argp_param_set_callback(size_param, size_callback);
doca_argp_register_param(size_param);
```

---

## Basic Workflow

```
1. doca_argp_init()              → Initialize argument parser
2. doca_argp_param_create()      → Create parameter
3. doca_argp_param_set_*()       → Configure parameter
4. doca_argp_register_param()    → Register parameter
5. doca_argp_set_dpdk_program()  → Set DPDK integration
6. doca_argp_start()             → Parse arguments
7. doca_argp_destroy()           → Cleanup
```

---

## Core Functions

### doca_argp_init()

Initializes the argument parsing system.

**Function Signature:**
```c
doca_error_t doca_argp_init(const char *program_name,
                            struct doca_argp_program *program);
```

**Parameters:**
- `program_name`: Name of the program (shown in help)
- `program`: Pointer to program configuration structure (can be NULL for defaults)

**Returns:** DOCA_SUCCESS or error code

**Example:**
```c
#include <doca_argp.h>

int main(int argc, char **argv) {
    doca_error_t result;

    // Initialize argument parser
    result = doca_argp_init("my_doca_app", NULL);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to init ARGP: %s",
                     doca_error_get_descr(result));
        return EXIT_FAILURE;
    }

    // Register parameters...
    // Parse arguments...

    doca_argp_destroy();
    return 0;
}
```

**Where Used:**
- apps/react-main/react_main.c

---

### doca_argp_param_create()

Creates a new parameter object.

**Function Signature:**
```c
doca_error_t doca_argp_param_create(struct doca_argp_param **param);
```

**Parameters:**
- `param`: Output pointer to created parameter

**Returns:** DOCA_SUCCESS or error code

**Example:**
```c
struct doca_argp_param *size_param;

result = doca_argp_param_create(&size_param);
if (result != DOCA_SUCCESS) {
    DOCA_LOG_ERR("Failed to create param: %s",
                 doca_error_get_descr(result));
    return result;
}
```

**Where Used:**
- apps/react-main/react_main.c (multiple parameters)

---

## Parameter Configuration Functions

### doca_argp_param_set_short_name()

Sets the short option name (single character).

**Function Signature:**
```c
void doca_argp_param_set_short_name(struct doca_argp_param *param,
                                    const char *short_name);
```

**Example:**
```c
doca_argp_param_set_short_name(size_param, "s");  // Usage: -s 1024
```

---

### doca_argp_param_set_long_name()

Sets the long option name.

**Function Signature:**
```c
void doca_argp_param_set_long_name(struct doca_argp_param *param,
                                   const char *long_name);
```

**Example:**
```c
doca_argp_param_set_long_name(size_param, "size");  // Usage: --size 1024
```

---

### doca_argp_param_set_arguments()

Sets the argument description shown in help.

**Function Signature:**
```c
void doca_argp_param_set_arguments(struct doca_argp_param *param,
                                   const char *arguments);
```

**Example:**
```c
doca_argp_param_set_arguments(size_param, "<size_in_bytes>");
// Help shows: -s, --size <size_in_bytes>
```

---

### doca_argp_param_set_description()

Sets the parameter description for help text.

**Function Signature:**
```c
void doca_argp_param_set_description(struct doca_argp_param *param,
                                     const char *description);
```

**Example:**
```c
doca_argp_param_set_description(size_param,
    "Set total bloom filter size in bits");
```

---

### doca_argp_param_set_type()

Sets the parameter data type.

**Function Signature:**
```c
void doca_argp_param_set_type(struct doca_argp_param *param,
                              enum doca_argp_type type);
```

**Supported Types:**
```c
DOCA_ARGP_TYPE_INT       // Integer
DOCA_ARGP_TYPE_STRING    // String
DOCA_ARGP_TYPE_BOOLEAN   // Boolean flag
```

**Example:**
```c
doca_argp_param_set_type(size_param, DOCA_ARGP_TYPE_INT);
```

---

### doca_argp_param_set_callback()

Sets the callback function to handle the parsed value.

**Function Signature:**
```c
void doca_argp_param_set_callback(struct doca_argp_param *param,
                                  doca_argp_param_cb_t callback);
```

**Callback Signature:**
```c
typedef doca_error_t (*doca_argp_param_cb_t)(void *param, void *config);
```

**Example:**
```c
// Callback function
static doca_error_t size_callback(void *param, void *config) {
    struct app_config *cfg = (struct app_config *)config;
    int value = *(int *)param;

    if (value <= 0) {
        DOCA_LOG_ERR("Size must be positive");
        return DOCA_ERROR_INVALID_VALUE;
    }

    cfg->size = value;
    DOCA_LOG_INFO("Bloom filter size set to %d bits", value);

    return DOCA_SUCCESS;
}

// Register callback
doca_argp_param_set_callback(size_param, size_callback);
```

**Where Used:**
- apps/react-main/react_main.c (bloom_size_callback, bloom_swap_callback, etc.)

---

### doca_argp_register_param()

Registers the configured parameter with the parser.

**Function Signature:**
```c
doca_error_t doca_argp_register_param(struct doca_argp_param *param);
```

**Example:**
```c
result = doca_argp_register_param(size_param);
if (result != DOCA_SUCCESS) {
    DOCA_LOG_ERR("Failed to register param: %s",
                 doca_error_get_descr(result));
    return result;
}
```

---

## DPDK Integration

### doca_argp_set_dpdk_program()

Configures DPDK integration (allows mixing DPDK EAL args with DOCA args).

**Function Signature:**
```c
doca_error_t doca_argp_set_dpdk_program(dpdk_main_t dpdk_main_func);
```

**Example:**
```c
// Your DPDK initialization function
static doca_error_t dpdk_init(void) {
    // DPDK EAL should already be initialized by argp
    uint16_t nb_ports = rte_eth_dev_count_avail();
    DOCA_LOG_INFO("Found %u DPDK ports", nb_ports);
    return DOCA_SUCCESS;
}

int main(int argc, char **argv) {
    doca_argp_init("my_app", NULL);

    // Register parameters...

    // Set DPDK integration
    result = doca_argp_set_dpdk_program(dpdk_init);
    if (result != DOCA_SUCCESS) {
        return EXIT_FAILURE;
    }

    // This will parse both DPDK and DOCA arguments
    result = doca_argp_start(argc, argv);

    return 0;
}
```

**Where Used:**
- apps/react-main/react_main.c

---

## Parsing and Execution

### doca_argp_start()

Parses command-line arguments and executes callbacks.

**Function Signature:**
```c
doca_error_t doca_argp_start(int argc, char **argv);
```

**Parameters:**
- `argc`: Argument count from main()
- `argv`: Argument vector from main()

**Returns:** DOCA_SUCCESS or error code

**Example:**
```c
result = doca_argp_start(argc, argv);
if (result != DOCA_SUCCESS) {
    DOCA_LOG_ERR("Failed to parse arguments: %s",
                 doca_error_get_descr(result));
    doca_argp_destroy();
    return EXIT_FAILURE;
}
```

**What It Does:**
1. Parses DPDK EAL arguments (if `doca_argp_set_dpdk_program()` was called)
2. Initializes DPDK EAL
3. Parses DOCA-specific arguments
4. Calls registered callbacks with parsed values
5. Validates all parameters

---

### doca_argp_destroy()

Cleans up argument parsing resources.

**Function Signature:**
```c
void doca_argp_destroy(void);
```

**Example:**
```c
int main(int argc, char **argv) {
    doca_argp_init("my_app", NULL);

    // Register parameters and parse...

    // Cleanup before exit
    doca_argp_destroy();
    return 0;
}
```

---

## Complete Example

Based on apps/react-main/react_main.c:

```c
#include <doca_argp.h>
#include <doca_log.h>

// Application configuration structure
struct app_config {
    int bloom_size;
    int swap_interval;
    int nb_cores;
};

struct app_config cfg = {
    .bloom_size = 1000000,     // Default values
    .swap_interval = 60,
    .nb_cores = 2,
};

// Callback for bloom size parameter
static doca_error_t bloom_size_callback(void *param, void *config) {
    struct app_config *app_cfg = (struct app_config *)config;
    int size = *(int *)param;

    if (size <= 0 || size > 100000000) {
        DOCA_LOG_ERR("Bloom size must be between 1 and 100M");
        return DOCA_ERROR_INVALID_VALUE;
    }

    app_cfg->bloom_size = size;
    DOCA_LOG_INFO("Bloom filter size: %d bits", size);

    return DOCA_SUCCESS;
}

// Callback for swap interval parameter
static doca_error_t swap_interval_callback(void *param, void *config) {
    struct app_config *app_cfg = (struct app_config *)config;
    int interval = *(int *)param;

    if (interval < 1 || interval > 3600) {
        DOCA_LOG_ERR("Swap interval must be between 1 and 3600 seconds");
        return DOCA_ERROR_INVALID_VALUE;
    }

    app_cfg->swap_interval = interval;
    DOCA_LOG_INFO("Bloom swap interval: %d seconds", interval);

    return DOCA_SUCCESS;
}

// DPDK initialization callback
static doca_error_t dpdk_init_callback(void) {
    DOCA_LOG_INFO("DPDK initialized by argp");
    return DOCA_SUCCESS;
}

// Register all application parameters
static doca_error_t register_params(void) {
    doca_error_t result;
    struct doca_argp_param *bloom_size, *swap_interval;

    // Register bloom size parameter
    result = doca_argp_param_create(&bloom_size);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to create param: %s",
                     doca_error_get_descr(result));
        return result;
    }

    doca_argp_param_set_short_name(bloom_size, "s");
    doca_argp_param_set_long_name(bloom_size, "bloom-size");
    doca_argp_param_set_arguments(bloom_size, "<size>");
    doca_argp_param_set_description(bloom_size,
        "Set total bloom filter size in bits");
    doca_argp_param_set_callback(bloom_size, bloom_size_callback);
    doca_argp_param_set_type(bloom_size, DOCA_ARGP_TYPE_INT);

    result = doca_argp_register_param(bloom_size);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to register param: %s",
                     doca_error_get_descr(result));
        return result;
    }

    // Register swap interval parameter
    result = doca_argp_param_create(&swap_interval);
    if (result != DOCA_SUCCESS) {
        return result;
    }

    doca_argp_param_set_short_name(swap_interval, "i");
    doca_argp_param_set_long_name(swap_interval, "bloom-swap");
    doca_argp_param_set_arguments(swap_interval, "<seconds>");
    doca_argp_param_set_description(swap_interval,
        "Set bloom filter swap interval in seconds");
    doca_argp_param_set_callback(swap_interval, swap_interval_callback);
    doca_argp_param_set_type(swap_interval, DOCA_ARGP_TYPE_INT);

    result = doca_argp_register_param(swap_interval);
    if (result != DOCA_SUCCESS) {
        return result;
    }

    return DOCA_SUCCESS;
}

int main(int argc, char **argv) {
    doca_error_t result;

    // Initialize DOCA argument parser
    result = doca_argp_init("my_bloom_app", NULL);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to init ARGP: %s",
                     doca_error_get_descr(result));
        return EXIT_FAILURE;
    }

    // Register application parameters
    result = register_params();
    if (result != DOCA_SUCCESS) {
        doca_argp_destroy();
        return EXIT_FAILURE;
    }

    // Enable DPDK integration
    result = doca_argp_set_dpdk_program(dpdk_init_callback);
    if (result != DOCA_SUCCESS) {
        doca_argp_destroy();
        return EXIT_FAILURE;
    }

    // Parse arguments (handles both DPDK and app args)
    result = doca_argp_start(argc, argv);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to parse arguments: %s",
                     doca_error_get_descr(result));
        doca_argp_destroy();
        return EXIT_FAILURE;
    }

    // Application logic using parsed configuration
    DOCA_LOG_INFO("Starting application with:");
    DOCA_LOG_INFO("  Bloom size: %d bits", cfg.bloom_size);
    DOCA_LOG_INFO("  Swap interval: %d seconds", cfg.swap_interval);

    // Run application...

    // Cleanup
    doca_argp_destroy();
    return 0;
}
```

**Running the Application:**
```bash
# Show help
./my_bloom_app --help

# Use defaults + DPDK args
./my_bloom_app -l 0-3

# Custom parameters
./my_bloom_app -l 0-3 -s 5000000 -i 120

# Long form
./my_bloom_app -l 0-3 --bloom-size 5000000 --bloom-swap 120
```

---

## Generated Help Output

When using `doca_argp`, automatic help is generated:

```
$ ./my_bloom_app --help

Usage: my_bloom_app [DPDK Flags] -- [DOCA Flags]

DOCA Flags:
  -s, --bloom-size <size>        Set total bloom filter size in bits
  -i, --bloom-swap <seconds>     Set bloom filter swap interval in seconds
  -h, --help                     Print this help and exit

DPDK Flags:
  -l CORELIST                    Set list of cores to run on
  -n CHANNELS                    Set number of memory channels
  -a, --allow <device>           Add a device to allow list
  ...
```

---

## Validation and Error Handling

### Built-in Validation

```c
// doca_argp automatically validates:
// - Parameter types (INT, STRING, BOOLEAN)
// - Required vs optional parameters
// - Duplicate parameter names

// Custom validation in callbacks:
static doca_error_t port_callback(void *param, void *config) {
    int port = *(int *)param;

    // Validate port number
    if (port < 0 || port > 65535) {
        DOCA_LOG_ERR("Invalid port: %d (must be 0-65535)", port);
        return DOCA_ERROR_INVALID_VALUE;
    }

    // Validate port is available
    if (!rte_eth_dev_is_valid_port(port)) {
        DOCA_LOG_ERR("Port %d is not available", port);
        return DOCA_ERROR_NOT_FOUND;
    }

    return DOCA_SUCCESS;
}
```

---

## Advanced Features

### Boolean Flags

```c
struct doca_argp_param *verbose_param;

static doca_error_t verbose_callback(void *param, void *config) {
    bool *verbose = (bool *)param;
    if (*verbose) {
        DOCA_LOG_INFO("Verbose mode enabled");
        // Set log level to debug
    }
    return DOCA_SUCCESS;
}

doca_argp_param_create(&verbose_param);
doca_argp_param_set_short_name(verbose_param, "v");
doca_argp_param_set_long_name(verbose_param, "verbose");
doca_argp_param_set_description(verbose_param, "Enable verbose output");
doca_argp_param_set_type(verbose_param, DOCA_ARGP_TYPE_BOOLEAN);
doca_argp_param_set_callback(verbose_param, verbose_callback);
doca_argp_register_param(verbose_param);

// Usage: ./myapp -v
//    or: ./myapp --verbose
```

---

## Best Practices

1. **Always validate in callbacks** - Don't trust user input
2. **Provide clear descriptions** - Users rely on `--help`
3. **Use meaningful parameter names** - Short and long forms
4. **Set sensible defaults** - App should work without args
5. **Log configuration** - Print parsed values for verification
6. **Error gracefully** - Return specific error codes from callbacks
7. **Group related parameters** - Register in logical order

---

## Common Pitfalls

❌ **Wrong:**
```c
// Forgetting to check return values
doca_argp_param_create(&param);  // Might fail!
doca_argp_param_set_type(param, DOCA_ARGP_TYPE_INT);  // NULL pointer!
```

✅ **Correct:**
```c
result = doca_argp_param_create(&param);
if (result != DOCA_SUCCESS) {
    DOCA_LOG_ERR("Failed: %s", doca_error_get_descr(result));
    return result;
}
```

---

## Key Takeaways

1. **doca_argp** provides type-safe, validated argument parsing
2. **Integrates with DPDK** via `doca_argp_set_dpdk_program()`
3. **Callbacks handle validation** and store parsed values
4. **Automatic help generation** from parameter descriptions
5. **Used extensively** in apps/react-main for complex configurations

---

## Next Steps

- See [[DOCA Logging|DOCA Logging Backend]] for logging configuration
- Read [[DPDK Core Functions]] for EAL integration
- Check [apps/react-main/react_main.c](../../apps/react-main/react_main.c) for complete example

---

## References

- **apps/react-main/react_main.c** - Complete doca_argp implementation
- DOCA ARGP Documentation: https://docs.nvidia.com/doca/sdk/doca+argp/index.html
