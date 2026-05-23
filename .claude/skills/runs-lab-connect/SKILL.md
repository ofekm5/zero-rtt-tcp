---
name: runs-lab-connect
description: >
  Knowledge base for connecting to the RUNS lab infrastructure (Proxmox cluster, gateway, internal VMs).
  Use this skill whenever the user mentions connecting to the lab, accessing Proxmox, SSHing into the gateway,
  reaching internal lab IPs, asking about lab credentials, or troubleshooting lab connectivity — even if they
  don't say "RUNS lab" explicitly. Also use when the user asks about F5 VPN setup for the lab or how to reach
  dev/production/management network segments.
---

# RUNS Lab — Connection Reference

## Prerequisites
- **F5 VPN (HAIFA)** must be connected before anything else. Contact Shir to get access set up.
- OpenSSH installed on your machine.
- In-house **OpenVPN is currently unavailable** (routing conflict with F5 VPN). This means local IPs (`10.13.35.x`, `10.13.36.x`, `10.13.37.x`) **cannot be reached directly** — all access to internal resources goes through the SSH gateway.

---

## Step 1 — SSH into the Gateway

`~/.ssh/config` entry (Windows: `C:\Users\<user>\.ssh\config`):

```
Host runs-gateway
  HostName 132.75.121.140
  User runs
```

Connect:
```
ssh runs-gateway
```
Password: see Logins wiki → https://gitlab.com/runs-lab/common/-/wikis/Login-(New)  
Default credential: username `runs`, password in wiki.

---

## Step 2 — Access Proxmox (Web UI)

Directly accessible over HTTPS while on F5 VPN (no SSH tunnel needed):

| Host  | URL                       | Username | Password  |
|-------|---------------------------|----------|-----------|
| runs1 | https://132.75.121.131    | root     | see wiki  |
| runs2 | https://132.75.121.132    | root     | see wiki  |
| runs3 | https://132.75.121.133    | root     | see wiki  |
| runs4 | https://132.75.121.134    | root     | see wiki  |

---

## Step 3 — Reach Internal Resources (OpenVPN unavailable)

Since OpenVPN is down, use the gateway as a jump host:

```bash
# SSH into a dev VM from the gateway shell
ssh runs-gateway
ssh root@10.13.37.X

# Or use local port forwarding to expose an internal service on your machine
ssh -L 8443:10.13.37.X:443 runs-gateway
# then browse https://localhost:8443
```

---

## Credentials Reference

| Resource         | IP / URL                    | Username | Password     |
|------------------|-----------------------------|----------|--------------|
| Gateway (SSH)    | 132.75.121.140              | runs     | see wiki |
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

### Special hardware (internal IPs, access via gateway)
- `runs-bf1` (Barefoot Tofino): `10.13.35.4` (DHCP)
- `bluefield-runs3-dpu`: `10.13.36.16` (DHCP)
- `bluefield-runs4-dpu`: `10.13.36.46` (DHCP)
- `bluefield-runs3/4-bmc`: `10.13.36.233/234` (DHCP)

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| SSH `Permission denied` to gateway | Check username is `runs` (not email). Verify password from wiki. |
| Can't reach `10.13.x.x` directly | Expected — OpenVPN is down. Use gateway jump host instead. |
| Proxmox HTTPS unreachable | Make sure F5 VPN is connected first. |
| Gateway IP changed | New GW IP is `132.75.121.140` (old: `172.27.105.177`). Update `~/.ssh/config`. |
