---
name: runs-lab-connect
description: >
  Knowledge base for connecting to the RUNS lab infrastructure (Proxmox cluster, gateway, internal VMs).
  Use this skill whenever the user mentions connecting to the lab, accessing Proxmox, SSHing into the gateway,
  reaching internal lab IPs, asking about lab credentials, or troubleshooting lab connectivity — even if they
  don't say "RUNS lab" explicitly. Also use when the user asks how to reach dev/production/management network
  segments or how to connect the lab OpenVPN profile.
---

# RUNS Lab — Connection Reference

## Prerequisites
- **OpenVPN** client with the lab profile imported. The profile is `runs.ovpn` (in this skill folder,
  `.claude/skills/runs-lab-connect/runs.ovpn`) and is already loaded into the local OpenVPN program — just
  connect through it.
- OpenSSH installed on your machine.
- No F5 VPN, no SSH gateway jump host, no port-forward workarounds needed — the OpenVPN tunnel routes directly
  into the lab subnets (`10.13.35.x`, `10.13.36.x`, `10.13.37.x`).

---

## Step 1 — Connect the VPN

Open the OpenVPN client, select the `runs` profile (imported from `runs.ovpn`), and connect. Once the tunnel is
up, every internal lab IP is reachable directly from your machine — no jump host required.

---

## Step 2 — Reach Internal Resources Directly

```bash
# SSH straight into any internal VM — no gateway jump needed
ssh root@10.13.37.X

# Browse an internal HTTPS service directly
https://10.13.35.X
```

Credentials: see Logins wiki → https://gitlab.com/runs-lab/common/-/wikis/Login-(New)

---

## Step 3 — Access Proxmox (Web UI)

Reachable directly once the VPN is connected:

| Host  | URL                       | Username | Password  |
|-------|---------------------------|----------|-----------|
| runs1 | https://132.75.121.131    | root     | see wiki  |
| runs2 | https://132.75.121.132    | root     | see wiki  |
| runs3 | https://132.75.121.133    | root     | see wiki  |
| runs4 | https://132.75.121.134    | root     | see wiki  |

---

## Credentials Reference

| Resource         | IP / URL                    | Username | Password     |
|------------------|-----------------------------|----------|--------------|
| pfSense          | 10.13.35.1 / 132.75.121.141 | admin    | see wiki |
| runs1–2 (Prox)   | 132.75.121.131–132          | root     | see wiki |
| runs3–4 (Prox)   | 132.75.121.133–134          | root     | see wiki |
| BMC runs1–4      | 132.75.121.10–13            | —        | —            |
| Bitwarden        | inside network (10.13.35.x) | —        | contact Shir |

External credentials (Gmail, GitLab, etc.) → Bitwarden inside the network.

---

## Network Segments

| Subnet          | Purpose                                                         |
|-----------------|-----------------------------------------------------------------|
| 10.13.35.0/24   | Management — pfSense, Bitwarden, tooling                        |
| 10.13.36.0/24   | Production — hardware NICs, Tofino/Bluefield, limited internet  |
| 10.13.37.0/24   | Development — free-use VMs, unrestricted internet access        |

### Special hardware (internal IPs, reachable directly once the VPN is up)
- `runs-bf1` (Barefoot Tofino): `10.13.35.4` (DHCP)
- `bluefield-runs3-dpu`: `10.13.36.16` (DHCP)
- `bluefield-runs4-dpu`: `10.13.36.46` (DHCP)
- `bluefield-runs3/4-bmc`: `10.13.36.233/234` (DHCP)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Can't reach `10.13.x.x` at all | Check the OpenVPN client shows "Connected" for the `runs` profile. Reconnect if it dropped. |
| SSH `Permission denied` to an internal VM | Verify username/password from the Logins wiki. |
| Proxmox HTTPS unreachable | Confirm OpenVPN is connected — Proxmox no longer requires F5. |
| OpenVPN profile missing from client | Re-import `.claude/skills/runs-lab-connect/runs.ovpn`. |
