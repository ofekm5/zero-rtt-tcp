---
type: Wiki Entry
title: "DPU Mode Setup"
description: " You can run the configuration commands either from the host CLI or directly inside the DPU CLI (host CLI is not mandatory)."
tags: [bluefield, setup]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/setup/dpu_mode_setup.md`

## 🔧 Configuring BlueField-3 as a DPU (SoC Mode)

### 🧰 Requirements:

* You can run the configuration commands **either from the host CLI or directly inside the DPU CLI** (host CLI is not mandatory).
* `mstflint` tools are installed (`mst`, `mlxconfig`).
* The BlueField-3 card is properly recognized and bound.

---

### 1. ✅ Start the MST Service

This detects Mellanox devices and prepares them for configuration.
This is also the **first hardware fast fix** if PCI devices don’t show up.

```bash
sudo mst start
```

You should see output like:

```
MST devices:
------------
/dev/mst/mt41692_pciconf0
```

---

### 2. ⏰ Sync DPU Time (First Access Only)

When you log into the DPU for the first time, make sure the clock is in sync.
Replace with the current date/time:

```bash
sudo timedatectl set-time "2025-08-20 14:20:00"
```

---

### 3. 🛠️ Set Read/Write Permissions (Optional)

Make sure your user or automation tool can access the device node:

```bash
sudo chmod 666 /dev/mst/*
```

---

### 4. 🔄 Set SoC Mode Parameters

Enable the internal CPU (Arm cores) and configure it for SoC operation:

```bash
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 set INTERNAL_CPU_MODEL=1
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 set INTERNAL_CPU_OFFLOAD_ENGINE=0
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 set INTERNAL_CPU_RSHIM=0
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 set FLEX_PARSER_PROFILE_ENABLE=3
```

💡 If scripting, combine into one:

```bash
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 set INTERNAL_CPU_MODEL=1 INTERNAL_CPU_OFFLOAD_ENGINE=0 INTERNAL_CPU_RSHIM=0 FLEX_PARSER_PROFILE_ENABLE=3
```

---

### 5. 🔁 Apply Flex Parser Setting

After setting `FLEX_PARSER_PROFILE_ENABLE=3`, you must reset the HCA to latch the change:

```bash
sudo mlxfwreset -d 0000:03:00.0 --yes reset
```

---

### 6. 🔍 Verify Settings

Run:

```bash
sudo mlxconfig -d /dev/mst/mt41692_pciconf0 q | egrep 'INTERNAL_CPU_MODEL|INTERNAL_CPU_OFFLOAD_ENGINE|INTERNAL_CPU_RSHIM|FLEX_PARSER_PROFILE_ENABLE'
```

Expected output (values may differ depending on config):

```
    INTERNAL_CPU_MODEL              1
    INTERNAL_CPU_OFFLOAD_ENGINE     0
    INTERNAL_CPU_RSHIM              0
    FLEX_PARSER_PROFILE_ENABLE      3
```

---

### 🧪 Optional Final Step: Reboot

Reboot the host machine to apply the changes cleanly:

```bash
sudo reboot
```

---