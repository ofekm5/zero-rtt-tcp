---
name: runs-lab-connect
description: Connect to RUNS lab VMs and Proxmox through the lab OpenVPN profile, diagnose reachability, or install an SSH public key for authorized agent access. Use for lab connectivity and SSH setup.
---

# RUNS Lab — Connection Reference

## Prerequisites
- **OpenVPN** client with the lab profile imported. The profile is `runs.ovpn` (in this skill folder,
  `.agents/skills/runs-lab-connect/runs.ovpn`) and is already loaded into the local OpenVPN program — just
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

## Step 4 — Bind Codex to a VM (key auth, for automation)

To let **Codex** drive a lab VM non-interactively (no password per command), install its durable SSH
key with the bundled helper:

```bash
# in a REAL Git Bash window (see the gotcha below):
./install_agent_ssh_key.sh [user@]<ip> [[user@]<ip> ...]
# or via lab-connect.sh:
./lab-connect.sh bind ubuntu@10.13.36.16
```

What it does: generates a durable key once at `~/.ssh/claude_code_ed25519`, installs the public key into the
VM's `~/.ssh/authorized_keys`, adds an `~/.ssh/config` entry, and verifies key auth. Default user is `ubuntu`
(override with `DEFAULT_USER=root` or a `user@` prefix). All lab hosts are Ubuntu.

Afterwards Codex connects with:
```bash
ssh -i ~/.ssh/claude_code_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes <user>@<ip>
```

> **Gotcha — must run in a real Git Bash window.** Not a non-interactive tool call (no TTY → ssh can't prompt for
> the password, fails instantly as `Permission denied` with no prompt) and not PowerShell (Windows-native
> OpenSSH can't do the interactive prompt or ControlMaster multiplexing → `getsockname failed: Not a socket`).
> Only MSYS/Git Bash `ssh` works, and it shares `$HOME` (`/c/Users/shir`) + `/tmp` with the terminal environment.

> **After a VM is re-imaged** (e.g. a BlueField BFB flash) its host key changes. Clear the stale entry first:
> `ssh-keygen -R <ip> -f ~/.ssh/known_hosts`, then reconnect (and re-run `bind` — the fresh OS has no key).

---

The helper retains the existing `~/.ssh/claude_code_ed25519` identity and SSH-config markers for compatibility; override `KEY_PATH` explicitly to use a different key. Do not install a key unless the user requested or authorized SSH access.

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
| OpenVPN profile missing from client | Re-import `.agents/skills/runs-lab-connect/runs.ovpn`. |
| `bind` gives `Permission denied` with no password prompt | You're in a non-interactive tool call or PowerShell — re-run in a real Git Bash window. |
| Host key changed / `REMOTE HOST IDENTIFICATION HAS CHANGED` after a re-image | `ssh-keygen -R <ip> -f ~/.ssh/known_hosts`, then reconnect and re-run `bind`. |
