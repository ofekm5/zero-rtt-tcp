---
type: Wiki Entry
title: "🔧 Using `mlnx-sf` to Manage Scalable Functions (SFs)"
description: "The mlnx-sf script creates, configures, and deploys an SF in a single command:"
tags: [bluefield, operations]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/docs/03-operations/sf-management.md`

# 🔧 Using `mlnx-sf` to Manage Scalable Functions (SFs)

The **`mlnx-sf`** script creates, configures, and deploys an SF in a single command:

```bash
mlnx-sf --action create --device <pci_address> --sfnum <sfnum> --hwaddr <mac_address>
```

### Example

```bash
mlnx-sf --action create --device 0000:03:00.0 --sfnum 9 --hwaddr 02:25:f2:8d:a2:4c
```

### Arguments

* `--action create` → creates the SF
  *(there is also a `show` action)*
* `--device <pci_address>` → links the created SF to a parent PCIe device
* `--sfnum <sfnum>` → assigns the SF a unique number
* `--hwaddr <mac_address>` → configures the MAC address of the SF

---

## 📋 Useful Commands

### Show SF Configuration

During or after configuration, you can display details of the created SF, including the auxiliary device needed at runtime:

```bash
mlnx-sf --action show
```

**Example output** (single SF shown):

```
SF Index: pci/0000:03:00.0/229409
 Parent PCI dev: 0000:03:00.0
 Representor netdev: en3f0pf0sf70
 Function HWADDR: 00:01:01:01:01:70
 Auxiliary device: mlx5_core.sf.4
 netdev: enp3s0f0s70
 RDMA dev: mlx5_4
```

---

### Delete an SF

To remove an SF port representor:

```bash
mlnx-sf --action delete --sfindex pci/<pci_address>/<pasre_dev>
```

**Example:**

```bash
mlnx-sf --action delete --sfindex pci/0000:03:00.0/229409
```

---

### Help

For full usage details:

```bash
mlnx-sf --help
```

---
