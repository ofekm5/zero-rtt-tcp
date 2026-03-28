---
name: zero-rtt-integration-tester
description: End-to-end integration testing for the 0-RTT TCP demo across all 4 VMs (Client, ClientNIC, ServerNIC, Server). Use when running integration tests, validating 0-RTT behavior, diagnosing packet flow issues, verifying sequence number translation, or troubleshooting the 4-VM chain topology on AWS. Triggers on phrases like "run integration tests", "test 0-RTT", "check the VMs", "verify packet flow", "debug the demo", or "validate the setup".
---

# 0-RTT Integration Tester

## Step 0 — Choose ClientNIC implementation

**Always ask the user** which ClientNIC data plane they want to test before doing anything:

> "Which ClientNIC implementation should I run the experiment with?
> 1. **Scapy** — Python/Scapy, AF_PACKET (`experiments/zero-rtt-clientnic-translate/run_experiment.sh`)
> 2. **DPDK** — C/DPDK 23.11 ENA PMD (`experiments/zero-rtt-dpdk/run_experiment.sh`)"

Set variables based on the answer:

| Variable | Scapy | DPDK |
|----------|-------|------|
| `EXPERIMENT_SCRIPT` | `experiments/zero-rtt-clientnic-translate/run_experiment.sh` | `experiments/zero-rtt-dpdk/run_experiment.sh` |
| `REPORT_DIR` | `experiments/zero-rtt-clientnic-translate/reports/` | `experiments/zero-rtt-dpdk/reports/` |
| `IMPL_NAME` | `scapy` | `dpdk` |

## Step 1 — Run the automated script

```bash
./<EXPERIMENT_SCRIPT>
```

Exit code = number of failures. The script handles VM discovery, git pull, service startup, packet capture, client test, log checks, and pcap analysis automatically.

See `references/test-scripts.md` for the full step-by-step breakdown and expected output of both scripts.

For DPDK-only unit tests (no full 4-VM chain needed), see `references/dpdk-tests.md` and run:
```bash
./experiments/zero-rtt-clientnic-translate/run_dpdk_tests_ssm.sh
```

**DPDK note**: The CDK user data builds `clientnic-dpdk` at provision time (~15-20 min after deploy). The DPDK script checks whether the binary exists and rebuilds from source if needed. If the binary is missing, wait for the user data to finish before running.

## Step 2 — Save the report

**Always save a report to the experiment's `reports/` subfolder** after every run, regardless of pass/fail outcome. Never skip this step.

Report filename: `integration-test-report-YYYY-MM-DD.md` (today's date).
Report path: `<REPORT_DIR>/integration-test-report-YYYY-MM-DD.md`

Report template:

```markdown
# Integration Test Report — <YYYY-MM-DD>

**Implementation**: <Scapy | DPDK>
**Experiment script**: `<EXPERIMENT_SCRIPT>`
**Overall result**: <ALL PASSED ✅ | N FAILURE(S) ❌>

## Check Results

| Step | Check | Result |
|------|-------|--------|
| 10.1 / Build | Binary compiles cleanly | ✅ / ❌ |   ← DPDK only
| 10.2 / Smoke | Binary starts without error | ✅ / ❌ |  ← DPDK only
| 1 | Server listening on :8080 | ✅ / ❌ |
| 2 | ServerNIC IP forwarding enabled | ✅ / ❌ |
| 3 | ClientNIC process running | ✅ / ❌ |
| 4 | Client connections succeeded | ✅ / ❌ |
| 6 | Server received data | ✅ / ❌ |
| 7 | ClientNIC 0-RTT flow table activity | ✅ / ❌ |
| 8 | Packet capture analysis — all checks passed | ✅ / ❌ |

## Client Output

```
<client stdout — connection count and TTFB statistics>
```

## ClientNIC Log (0-RTT activity)

```
<relevant lines: SYN intercepted, spoofed SYN-ACK sent, delta calculated, buffered packets flushed>
```

## Packet Capture Analysis

```
<full validate_0rtt_capture.py output>
```

## Failures / Notes

<Describe any failures with exact log lines. "None" if all passed.>
```

## Step 3 — Report results to the user in chat

After saving the report, post a concise summary in chat:

---
**Experiment Run — `<timestamp>`** (`<IMPL_NAME>`)

**Overall: ✅ ALL PASSED** / **❌ N FAILURE(S)**

| Step | Check | Result |
|------|-------|--------|
| 1 | Server listening on :8080 | ✅ PASS |
| 2 | ServerNIC IP forwarding enabled | ✅ PASS |
| 3 | ClientNIC process running | ✅ PASS |
| 4 | Client connections succeeded | ✅ PASS |
| 6 | Server received data | ✅ PASS |
| 7 | ClientNIC 0-RTT flow table activity | ✅ PASS |
| 8 | Packet capture analysis | ✅ PASS |

**Client output** (Step 4):
```
<client stdout>
```

**ClientNIC log excerpt** (Step 7 — SYN intercept, spoofed SYN-ACK, delta):
```
<relevant clientnic.log lines>
```

**Packet analysis** (Step 8):
```
<validate_0rtt_capture.py output>
```

**Report saved**: `<REPORT_DIR>/integration-test-report-YYYY-MM-DD.md`

---

For each [FAIL], quote the exact log line or output that caused the failure.

## Step 4 — Investigate any failures

1. **Read the logs** — the script prints them inline; look for the first anomaly
2. **SSM into the relevant VM** and run the manual diagnostic commands below
3. **Cross-correlate**: clientnic log + pcap + server log together tell the full story
4. **Report observed vs expected** for each failed check with exact log lines or packet timestamps

Common failure patterns and their fixes: `references/troubleshooting.md`.

---

## Manual / Interactive Testing

Use the steps below when the script fails partway, or to run individual checks in isolation.

### VM Access

Discover instance IDs and IPs:
```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=smartnics-*" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],InstanceId,PublicIpAddress,PrivateIpAddress]" \
  --output table --region eu-central-1
```

Connect via SSM (no SSH key needed):
```bash
aws ssm start-session --target <instance-id> --region eu-central-1
```

**Note**: VM IPs change on instance restart. Always query fresh IPs before testing.

### Startup Order

Always: **Server → ServerNIC → ClientNIC → Client**

```bash
# 1. Server VM
setsid python3 server-app/server.py --host 0.0.0.0 --port 8080 --verbose \
    < /dev/null >> /tmp/server.log 2>&1 &

# 2. ServerNIC VM
setsid python3 servernic/scapy/main.py --client-iface eth0 --server-iface eth1 \
    < /dev/null >> /tmp/servernic.log 2>&1 &

# 3a. ClientNIC VM — Scapy
setsid python3 clientnic/scapy/main.py \
    < /dev/null >> /tmp/clientnic.log 2>&1 &

# 3b. ClientNIC VM — DPDK
#     GW_MAC = ServerNIC's eth0 MAC: cat /sys/class/net/eth0/address (on ServerNIC)
setsid ./clientnic/dpdk/builddir/clientnic-dpdk -l 0 -- \
    --port=8080 --gw-mac=<GW_MAC> --server-pcap=/tmp/server_side.pcap \
    < /dev/null >> /tmp/clientnic.log 2>&1 &

# 4. Client VM
python3 client-app/client.py --host <server-ip> --port 8080 --mode repeated --count 3 --verbose
```

### Pre-flight Checks

**Both implementations:**
```bash
# IP forwarding must be 1 on NIC VMs
cat /proc/sys/net/ipv4/ip_forward

# Block kernel forwarding so Scapy/DPDK wins the race
iptables -A FORWARD -p tcp --dport 8080 -j DROP
iptables -A FORWARD -p tcp --sport 8080 -j DROP
```

**DPDK only (ClientNIC VM):**
```bash
# eth1 must be bound to vfio-pci (done by CDK at boot)
dpdk-devbind.py --status | grep -E "(vfio|eth1)"

# Hugepages must be configured
grep HugePages_Total /proc/meminfo   # expect 512

# Binary must be built
ls -lh /home/ec2-user/zero-rtt-demo/clientnic/dpdk/builddir/clientnic-dpdk

# Rebuild if needed
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
cd /home/ec2-user/zero-rtt-demo/clientnic/dpdk
meson setup builddir && ninja -C builddir
```

### Packet Capture

**Scapy** — tcpdump works on both interfaces:
```bash
tcpdump -i eth0 -nn -tttt 'tcp port 8080' -w /tmp/client_side.pcap &
tcpdump -i eth1 -nn -tttt 'tcp port 8080' -w /tmp/server_side.pcap &
```

**DPDK** — eth1 is DPDK-controlled, tcpdump cannot capture it. Use `--server-pcap`:
```bash
tcpdump -i eth0 -nn -tttt 'tcp port 8080' -w /tmp/client_side.pcap &
# eth1 captured via --server-pcap flag on the binary (see startup above)
```

### Running the Validator

```bash
# Copy to /tmp first — running from clientnic/ causes clientnic/scapy/ to shadow the scapy package
cp /home/ec2-user/zero-rtt-demo/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py
python3 /tmp/validate_0rtt.py \
    --client-pcap /tmp/client_side.pcap \
    --server-pcap /tmp/server_side.pcap
```

## Known Issues

See `references/troubleshooting.md` for documented bugs and fixes:
- SSM daemon detachment (use `setsid`, not `nohup ... &`)
- Scapy `sendp()` vs `send()` for cross-subnet forwarding
- Spoofed SYN-ACK arriving late (sniff filter too broad)
- Kernel forwarding races Scapy (fix: iptables FORWARD DROP)
- Packet re-capture loop on ServerNIC (fix: MAC filter)
- Swapped SEQ/ACK rewrite fields
- `scapy/` directory shadowing when running validator from `clientnic/` (fix: copy to `/tmp/`)
