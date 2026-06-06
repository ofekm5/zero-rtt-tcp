# Integration Test Scripts

Two experiment orchestrators and one pcap validator. Choose the orchestrator based on the ClientNIC implementation being tested.

---

## experiments/scapy/run_experiment.sh

**Scapy stack** — ClientNIC uses Python/Scapy on both eth0 and eth1.

**Prerequisites**: `aws` CLI with SSM access, `python3` in PATH, `eu-central-1` region.

```bash
./experiments/scapy/run_experiment.sh
```

Exit code = number of failed checks (0 = all passed). Reports go in `experiments/scapy/reports/`.

### Steps

| Step | Action | Pass condition |
|------|--------|----------------|
| 0 | Discover EC2 instances by tag (`smartnics-*`) | All 4 IDs resolved |
| — | `git pull origin main` on all 4 VMs | (best-effort) |
| — | Kill leftover processes, delete old logs/pcaps | (cleanup) |
| 1 | Start Server (`setsid python3 server.py`) | `ss -tlnp` shows `:8080` |
| 2 | Start ServerNIC (Scapy forwarder) | `ip_forward == 1` |
| 3 | Start tcpdump on eth0+eth1, start `clientnic/scapy/main.py` | `ip_forward == 1` |
| 4 | Run client (`--mode repeated --count 3 --verbose`) | `Success: 3/3` or `100%` |
| 5 | Stop tcpdump | (always) |
| 6 | Read `/tmp/server.log` | Contains `Received` or `bytes` |
| 7 | Read `/tmp/clientnic.log` | Contains `delta`, `flow created`, `SYN received`, or `spoofed` |
| 8 | Run `validate_0rtt_capture.py` on ClientNIC | `All checks passed` |

### Key implementation details

- Uses `setsid ... < /dev/null >> /tmp/*.log 2>&1 &` — SSM requires full detachment
- Do NOT use `sudo` inside SSM `AWS-RunShellScript` — runs as root already, `sudo` hangs on missing tty
- `ssm_bg` fires and returns immediately; `ssm_run` waits via `aws ssm wait command-executed`
- Git pull uses `sudo -u ec2-user git ...` (SSM runs without `$HOME`)

---

## experiments/dpdk/run_experiment.sh

**DPDK stack** — ClientNIC uses C/DPDK 23.11 ENA PMD on eth1, AF_PACKET on eth0.

```bash
./experiments/dpdk/run_experiment.sh
```

Exit code = number of failed checks. Reports go in `experiments/dpdk/reports/`.

### Steps

| Step | Action | Pass condition |
|------|--------|----------------|
| 0 | Discover EC2 instances by tag | All 4 IDs resolved |
| — | `git pull`, cleanup | (best-effort / cleanup) |
| 10.1 | Rebuild `clientnic-dpdk` via meson+ninja | `BUILD_SUCCESS` in output |
| 10.2 | Smoke test: start binary for 5 s, kill, check log | `Entering busy-poll loop` in log |
| 1 | Start Server | `ss -tlnp` shows `:8080` |
| 2 | Start ServerNIC (Scapy forwarder) | `ip_forward == 1` |
| 10.3 | Start tcpdump on eth0, start `clientnic-dpdk --server-pcap=/tmp/server_side.pcap` | binary process running |
| 4 | Run client (`--count 1`) | `Success: 1/1` or `100%` |
| 5 | Stop tcpdump, SIGTERM binary | (always) |
| 6 | Read `/tmp/server.log` | Contains `Received` or `bytes` |
| 7 | Read `/tmp/clientnic.log` | Contains `SYN: flow created` and `SYN-ACK: delta=` |
| 10.4 | Run `validate_0rtt_capture.py` (copied to `/tmp/`) | `All checks passed` |

### DPDK-specific details

- **Gateway MAC** (`--gw-mac`): ServerNIC's eth0 MAC — get with `cat /sys/class/net/eth0/address` on ServerNIC. Needed so the DPDK port sets correct L2 destination on eth1 TX.
- **eth1 capture**: eth1 is bound to `vfio-pci` — tcpdump cannot see it. The binary writes eth1 RX packets directly to a pcap file via the built-in `capture.c` writer when `--server-pcap` is provided.
- **Scapy shadowing**: `validate_0rtt_capture.py` is copied to `/tmp/` before running. If run from `clientnic/`, Python adds that directory to `sys.path` and `clientnic/scapy/` shadows the real `scapy` package, causing `ImportError`.
- **Build time**: DPDK 23.11 is built from source at VM provision time (~15-20 min). The script rebuilds the `clientnic-dpdk` binary after each `git pull` to pick up code changes.

---

## clientnic/validate_0rtt_capture.py

Validates 0-RTT behavior from pcap files captured on ClientNIC. Runs **on the ClientNIC VM**.

```bash
# Always copy to /tmp first to avoid clientnic/scapy/ shadowing the scapy package
cp /home/ec2-user/zero-rtt-demo/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py
python3 /tmp/validate_0rtt.py \
    --client-pcap /tmp/client_side.pcap \
    --server-pcap /tmp/server_side.pcap
```

Exit code: 0 = all passed, 1 = one or more failures.

### Checks

**A. Spoofed SYN-ACK Detection**
- Loads SYN-ACKs from eth0 (client-side) and eth1 (server-side pcap)
- Real ISNs = ISNs seen on eth1
- Spoofed = eth0 SYN-ACKs whose ISN is NOT in the real set
- PASS: ≥1 spoofed SYN-ACK on eth0 and ≥1 real SYN-ACK on eth1

**B. ISN Delta**
- Matches spoofed and real SYN-ACKs by client dport
- `delta = (spoofed_ISN - real_ISN) & 0xFFFFFFFF`
- PASS: all matched flows have delta ≠ 0

**C. 0-RTT Timing** *(informational — does not count as failure)*
- `t_spoofed < t_real` per flow
- Intra-VPC RTT can be sub-ms so this may not always hold; reported but not a failure condition

**D. Checksum Validation**
- Recomputes expected IP (RFC 791) and TCP (RFC 793 pseudo-header) checksums
- PASS: zero bad checksums on eth0 AND eth1

### Expected output (all passing)

```
[PASS] Real SYN-ACK(s) found on eth1  (1 SYN-ACK(s))
[PASS] Spoofed SYN-ACK(s) found on eth0 (distinct ISN)  (1 spoofed, 0 forwarded-real)
[PASS] All deltas are non-zero  (1 matched flow(s))
[PASS] Spoofed SYN-ACK arrives before real (informational)  (1/1 flows -- ...)
[PASS] No bad checksums on eth0 (client side)  (all N packets valid)
[PASS] No bad checksums on eth1 (server side)  (all N packets valid)
All checks passed.
```
