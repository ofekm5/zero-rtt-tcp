---
type: Wiki Entry
title: "BlueField BFB Installation Guide"
description: "This guide explains how to download and install a BFB (BlueField Bundle File) onto a BlueField DPU host manually using bash commands."
tags: [bluefield, setup]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/setup/bfb_install.md`

# BlueField BFB Installation Guide

This guide explains how to download and install a **BFB (BlueField Bundle File)** onto a BlueField DPU host manually using bash commands.
It removes the need for Ansible — just follow the steps below.

---

## 📋 Prerequisites

* You have **root (sudo) access** on the BlueField host.
* `mst` (Mellanox Software Tools) is installed.
* The host is running a Debian/Ubuntu-based system.
* You have the URL for the BFB file or you have downloaded the file itself from Nvidia site.

---

## ▶️ Installation Steps

### 1. Define the BFB URL

You need a URL to the BFB bundle (example):

```bash
BFB_URL="http://path/to/bf_bundle.bfb"
BFB_PATH="/tmp/bf_bundle.bfb"
```

---

### 2. Start the MST service

```bash
sudo mst start
```

---

### 3. Install `rshim` packages (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y rshim-dkms rshim-user-space
```

---

### 4. Enable and start the `rshim` service

```bash
sudo systemctl enable rshim
sudo systemctl start rshim
```

---

### 5. Download the BFB file

```bash
wget -O "$BFB_PATH" "$BFB_URL"
```

---

### 6. Run the BFB installer

```bash
sudo bfb-install --bfb "$BFB_PATH" -r /dev/rshim0
```

---

## ✅ Verification

After the installation completes, you can check BlueField boot status logs in:

```bash
sudo journalctl -u rshim
```

---