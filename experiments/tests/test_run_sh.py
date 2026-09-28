"""
Pins the remote-call sequence of experiments/run.sh for every supported
STACK x TRANSPORT combination, against a mock transport.

run.sh drives four VMs over SSM or SSH, so the test substitutes the transport
primitives (remote_run/remote_bg/remote_stdout and, where the transport has
them, ssm_run/ssm_bg/ssm_stdout) with recorders that answer every command the
way a healthy chain would, then runs the real run.sh end to end. The EC2 API
(`aws`), the lab reachability probe (`ssh`) and `sleep` are stubbed too, so no
call leaves the machine and a run takes seconds.

The expected sequences (the RECORDED block at the bottom) are generated, not
typed: `python experiments/tests/test_run_sh.py --record` runs each old runner
under this same harness and rewrites the block with its calls, verbatim:
    0rtt     + ssm  <- experiments/dpdk/run_experiment.sh
    0rtt     + ssh  <- experiments/proxmox/run_experiment.sh
    baseline + ssm  <- experiments/baseline-tcp/run_experiment.sh
While the old runners exist, re-running --record and finding no git diff proves
the block is theirs. The pinned block is the parity check — there is
deliberately no test that runs the old runners, so it outlives their deletion.
The test fails if run.sh drops, adds, reorders or changes a remote call.

No AWS, no SSH, no live infrastructure.
"""

import functools
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

_TESTS_DIR = Path(__file__).parent

# The PATH-resolved bash, by full path: a bare "bash" on Windows resolves via
# System32 first, i.e. to the WSL launcher, which drops argv[0] and stdin.
_BASH = shutil.which("bash")

pytestmark = pytest.mark.skipif(_BASH is None, reason="bash not available on this host")

# Evaluated by `bash -c 'eval "$(cat)"' <script> <stack> <transport>`, so $0 is
# the script path and its `$(dirname "$0")/lib/...` sources resolve for real.
# Every recorded call is written to fd 9 (the original stderr) as
#     TRACE|<run|bg|stdout>|<node>|<command, newlines flattened>
# fd 9 rather than stdout: remote_stdout is called inside `x=$(...)`, which
# would swallow a stdout trace.
_HARNESS = r"""
exec 9>&2
STACK=$1 TRANSPORT=$2
set --

# Hermetic: a knob exported in the caller's shell must not change the commands.
unset CONNECTIONS LOAD_PARALLEL LOAD_PORTS LOAD_TIMEOUT LOAD_BYTES LOAD_RATE \
      LOAD_CONCURRENCY LOAD_THINK_MS NETEM_RTT_MS REPO_REF ANALYSIS_TIMEOUT \
      REMOTE_OUTPUT_CAP ENDPOINT_METRICS CLIENT_STDOUT

# Node ids are role names on both transports: ssh_lab.sh takes them from these,
# the aws stub below hands out the same ones.
LAB_CLIENT_IP=client LAB_CLIENTNIC_IP=clientnic
LAB_SERVERNIC_IP=servernic LAB_SERVER_IP_INTERNAL=server

sleep() { :; }
ssh()   { :; }    # ssh_lab.sh discover_nodes' reachability probe

# EC2 discovery: `Values=smartnics-server` -> id "server"; MACs "mac-<role>-eth<N>".
aws() {
    local s="$*" role i
    role=${s#*Values=}; role=${role%% *}; role=${role#*-}
    case "$s" in
        *InstanceId*)       echo "$role" ;;
        *PrivateIpAddress*) echo 10.1.2.10 ;;
        *MacAddress*)       i=${s#*DeviceIndex==?}; echo "mac-$role-eth${i:0:1}" ;;
        *)                  echo "unexpected aws call: $s" >&2; return 97 ;;
    esac
}

# What a healthy chain answers. Only the commands run.sh branches on matter.
_reply() {
    local i
    case "$2" in
        *"rev-parse --short HEAD"*)    echo abc1234 ;;
        *ip_forward*)                  echo 1 ;;
        *"ip route show 10.1.2.0/24"*) echo "10.1.2.0/24 via 10.1.1.1 dev eth1" ;;
        *"ip route show 10.1.0.0/24"*) echo "10.1.0.0/24 via 10.1.1.1 dev eth0" ;;
        *"tc qdisc show"*)
            case "$1" in
                clientnic|servernic) echo "qdisc netem 8001: root limit 1000000 delay 50ms" ;;
                *)                   echo "qdisc mq 0: root" ;;
            esac ;;
        *"ss -tlnp"*)                  echo LISTEN_OK ;;
        *pgrep*)                       echo RUNNING ;;
        *"meson setup"*)               echo BUILD_SUCCESS ;;
        *clientnic_smoke.log*)         echo "Entering busy-poll loop" ;;
        *"--mode client"*)             echo "Success: 1/1" ;;
        *analyze_metrics.py*)          echo "summary=send_unlock node=client n=1 min_ms=1 p50_ms=1 p95_ms=1 p99_ms=1 max_ms=1 mean_ms=1" ;;
        *"cat /tmp/server.log"*)       echo "Received 1024 bytes" ;;
        *"cat /tmp/clientnic.log"*)    echo "flow created V=1" ;;
        *"cat /tmp/servernic.log"*)    echo "delta V=1" ;;
        */sys/class/net/*)             i=${2#*/sys/class/net/}; echo "mac-$1-${i%%/*}" ;;
    esac
}

_trace()  { printf 'TRACE|%s|%s|%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '\n' ' ')" >&9; }
_run()    { _trace run "$1" "$2"; printf '["Success","%s",""]\n' "$(_reply "$1" "$2")"; }
_bg()     { _trace bg "$1" "$2"; }
_stdout() { _trace stdout "$1" "$2"; _reply "$1" "$2"; }

# Replace whichever primitive layers the sourced transport defined. SSH has no
# ssm_* functions, so they stay undefined there, exactly as in a real run.
_restub() {
    if declare -F remote_run >/dev/null; then
        remote_run() { _run "$@"; }; remote_bg() { _bg "$@"; }; remote_stdout() { _stdout "$@"; }
    fi
    if declare -F ssm_run >/dev/null; then
        ssm_run() { _run "$@"; }; ssm_bg() { _bg "$@"; }; ssm_stdout() { _stdout "$@"; }
    fi
}
# run.sh defines its remote_* wrappers after sourcing the transport; re-stubbing
# after every `source` catches them before the first remote call.
source() { builtin source "$@"; local rc=$?; _restub; return $rc; }

builtin source "$0"
"""


@functools.lru_cache(maxsize=None)
def _calls(script, stack, transport):
    """Run <script> (relative to experiments/tests) under the mock transport.

    Returns (exit_code, calls), each call "<verb> <node> <command>" with the
    command's whitespace collapsed — the continuation-line indentation inside a
    command string is layout, not behaviour.
    """
    result = subprocess.run(
        [_BASH, "-c", 'eval "$(cat)"', script, stack, transport],
        input=_HARNESS, capture_output=True, text=True,
        encoding="utf-8", errors="replace", cwd=str(_TESTS_DIR),
    )
    calls = []
    for line in result.stderr.splitlines():
        if line.startswith("TRACE|"):
            verb, node, cmd = line[len("TRACE|"):].split("|", 2)
            calls.append(f"{verb} {node} {' '.join(cmd.split())}")
    return result.returncode, tuple(calls)


# ─── Recorded sequences ─────────────────────────────────────────────────────

# (stack, transport) -> the old runner whose calls run.sh must reproduce.
_OLD_RUNNERS = {
    ("0rtt", "ssm"): "dpdk/run_experiment.sh",
    ("0rtt", "ssh"): "proxmox/run_experiment.sh",
    ("baseline", "ssm"): "baseline-tcp/run_experiment.sh",
}

_BEGIN = "# >>> RECORDED by `python experiments/tests/test_run_sh.py --record` — do not edit"
_END = "# <<< RECORDED"


def _record():
    """Rewrite the RECORDED block from the old runners' own calls.

    Each runner runs from a temp copy with lib/ beside it, so the report it
    writes on exit lands in the temp dir, not in the repo. STACK and TRANSPORT
    are passed empty — i.e. unset, as the old runners were always invoked.
    """
    experiments = _TESTS_DIR.parent
    text = ""
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copytree(experiments / "lib", Path(tmp, "lib"))
        for (stack, transport), runner in _OLD_RUNNERS.items():
            copy = Path(tmp, runner)
            copy.parent.mkdir()
            shutil.copy(experiments / runner, copy)
            rc, calls = _calls(copy.as_posix(), "", "")
            text += f"== {stack} {transport} {rc} <- {runner}\n" + "".join(c + "\n" for c in calls)
    assert '"""' not in text, "a call would end the raw string literal"
    src = Path(__file__).read_text(encoding="utf-8")
    head, rest = src.split(f"\n{_BEGIN}\n", 1)
    tail = rest.split(f"\n{_END}\n", 1)[1]
    block = f'_RECORDED = r"""\n{text}"""'
    Path(__file__).write_text(f"{head}\n{_BEGIN}\n{block}\n{_END}\n{tail}", encoding="utf-8", newline="\n")


def _parse(text):
    """RECORDED block -> {(stack, transport): (exit code, calls)}."""
    out = {}
    for line in text.splitlines():
        if line.startswith("== "):
            stack, transport, rc = line.split()[1:4]
            calls = out.setdefault((stack, transport), (int(rc), []))[1]
        elif line:
            calls.append(line)
    return {key: (rc, tuple(calls)) for key, (rc, calls) in out.items()}


@pytest.fixture(scope="module")
def run_sh(tmp_path_factory):
    """run.sh in a temp copy of experiments/ (run.sh + lib/), so the report it
    writes on exit lands in the temp tree, not in the repo's reports/."""
    root = tmp_path_factory.mktemp("experiments")
    shutil.copytree(_TESTS_DIR.parent / "lib", root / "lib")
    shutil.copy(_TESTS_DIR.parent / "run.sh", root / "run.sh")
    return (root / "run.sh").as_posix()


@pytest.mark.parametrize("stack,transport", list(_OLD_RUNNERS))
def test_remote_call_sequence_matches_the_old_runner(run_sh, stack, transport):
    rc, calls = _calls(run_sh, stack, transport)
    want_rc, want = RECORDED[(stack, transport)]
    assert calls == want
    assert rc == want_rc


def test_baseline_issues_no_nic_build_or_start(run_sh):
    """STACK=baseline has no data plane: the NIC VMs are plain kernel routers."""
    _, calls = _calls(run_sh, "baseline", "ssm")
    nic = [c for c in calls if re.search(r"meson setup|nodes/(client|server)nic\.sh|nic-dpdk", c)]
    assert nic == []


@pytest.mark.parametrize("stack,transport,prefix", [
    ("0rtt", "ssm", "0rtt/integration-test-report-"),
    ("0rtt", "ssh", "0rtt/proxmox-test-report-"),
    ("baseline", "ssm", "baseline/baseline-report-"),
])
def test_run_sh_writes_its_report_under_reports_stack(run_sh, stack, transport, prefix):
    _calls(run_sh, stack, transport)
    reports = Path(run_sh).parent / "reports"
    assert any(p.relative_to(reports).as_posix().startswith(prefix) for p in reports.rglob("*.md"))


# 0rtt+ssh records exit 1 and no client-load call, exactly as proxmox/run_experiment.sh:
# measure.sh's run_ttfb_measurement calls ssm_run, which the SSH transport does not
# define, so the load step fails with "command not found".
# Every entry is "<verb> <node> <command, whitespace collapsed>".
# >>> RECORDED by `python experiments/tests/test_run_sh.py --record` — do not edit
_RECORDED = r"""
== 0rtt ssm 0 <- dpdk/run_experiment.sh
run clientnic rm -f /tmp/clientnic_smoke.log; setsid /home/ec2-user/zero-rtt-tcp/src/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder -l 0 -- --port=8080 --gw-mac=mac-servernic-eth1 --client-port-mac=mac-clientnic-eth2 --server-port-mac=mac-clientnic-eth1 < /dev/null > /tmp/clientnic_smoke.log 2>&1 & BPID=$!; sleep 3; kill $BPID 2>/dev/null; wait $BPID 2>/dev/null; true
stdout clientnic cat /tmp/clientnic_smoke.log 2>/dev/null || echo MISSING
bg server git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
bg servernic git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
bg clientnic git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
bg client git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
stdout server git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout servernic git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout clientnic git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout client git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
bg client sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; sysctl -w net.ipv4.ip_local_port_range='1024 65535'; sysctl -w net.ipv4.tcp_tw_reuse=1; sysctl -w net.ipv4.tcp_max_tw_buckets=200000; sysctl -w net.core.netdev_max_backlog=250000; sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; sysctl -w fs.file-max=1048576
bg server sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; sysctl -w net.core.somaxconn=131072 net.ipv4.tcp_max_syn_backlog=131072; sysctl -w net.ipv4.tcp_max_tw_buckets=200000; sysctl -w net.core.netdev_max_backlog=250000; sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; sysctl -w fs.file-max=1048576
bg client ip link set eth0 mtu 1500
bg server ip link set eth0 mtu 1500
bg client ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true
bg server ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true
bg client tc qdisc del dev eth0 root 2>/dev/null || true
bg server tc qdisc del dev eth0 root 2>/dev/null || true
stdout client tc qdisc show dev eth0 2>&1
stdout server tc qdisc show dev eth0 2>&1
bg server pkill -9 -f loadgen.py 2>/dev/null; conntrack -F 2>/dev/null || true; rm -f /tmp/server.log
bg servernic pkill -x servernic-dpdk 2>/dev/null; pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null
run clientnic pkill -f clientnic-dpdk-forwarder 2>/dev/null; pkill -f clientnic-dpdk 2>/dev/null; pkill tcpdump 2>/dev/null; sleep 5; pkill -9 -f clientnic-dpdk-forwarder 2>/dev/null; sleep 2; rm -rf /var/run/dpdk/rte/ 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/validate_0rtt.py; iptables -F FORWARD 2>/dev/null; echo CLEANUP_DONE
run clientnic export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; cd /home/ec2-user/zero-rtt-tcp/src/clientnic/dpdk-forwarder; rm -rf builddir; /usr/local/bin/meson setup builddir 2>&1 && cd builddir && /usr/local/bin/ninja 2>&1 && echo 'BUILD_SUCCESS'
run servernic export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; cd /home/ec2-user/zero-rtt-tcp/src/servernic/dpdk; rm -rf builddir; /usr/local/bin/meson setup builddir 2>&1 && cd builddir && /usr/local/bin/ninja 2>&1 && echo 'BUILD_SUCCESS'
bg server LOAD_PORTS=4 REPO_REF=main setsid bash /home/ec2-user/zero-rtt-tcp/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &
stdout server ss -tlnp | grep -q :8080 && echo LISTEN_OK || echo LISTEN_NONE
bg servernic SKIP_BUILD=1 PORT_COUNT=4 CLIENTNIC_GW_MAC=mac-clientnic-eth1 SERVER_GW_MAC=mac-server-eth0 CLIENT_PORT_MAC=mac-servernic-eth1 SERVER_PORT_MAC=mac-servernic-eth2 REPO_REF=main WAN_DELAY_US=50000 setsid bash /home/ec2-user/zero-rtt-tcp/experiments/nodes/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &
stdout servernic pgrep -f servernic-dpdk && echo RUNNING || echo NOT_RUNNING
stdout servernic cat /proc/sys/net/ipv4/ip_forward
bg clientnic iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true
bg clientnic SKIP_BUILD=1 PORT_COUNT=4 REPO_REF=main CLIENT_PORT_MAC=mac-clientnic-eth2 SERVER_PORT_MAC=mac-clientnic-eth1 WAN_DELAY_US=50000 setsid bash /home/ec2-user/zero-rtt-tcp/experiments/nodes/clientnic.sh mac-servernic-eth1 < /dev/null >> /tmp/clientnic.log 2>&1 &
stdout clientnic cat /proc/sys/net/ipv4/ip_forward
stdout clientnic pgrep -f clientnic-dpdk-forwarder && echo RUNNING || echo NOT_RUNNING
run client pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap
run server pkill tcpdump 2>/dev/null || true; rm -f /tmp/server_side.pcap
bg client if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='--time-stamp-precision=nano' elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='-j adapter' else HIPREC_FLAG='' fi tcpdump $HIPREC_FLAG -i eth0 -nn -s 128 'tcp portrange 8080-8083' -w /tmp/client_side.pcap </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
bg server if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='--time-stamp-precision=nano' elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='-j adapter' else HIPREC_FLAG='' fi tcpdump $HIPREC_FLAG -i eth0 -nn -s 128 'tcp portrange 8080-8083' -w /tmp/server_side.pcap </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
run client command -v python3 >/dev/null || { echo 'ERROR: python3 not installed'; exit 1; } ulimit -n 1048576 2>/dev/null || true success=0 for i in $(seq 1 1); do echo "--- Round $i/1: 4 port(s) starting at 8080 x 100000 total connections, 1024 bytes/conn, 2000 conn/s arrival, 0ms think, max 2000 in flight ---" python3 /home/ec2-user/zero-rtt-tcp/experiments/nodes/loadgen.py --mode client --host 10.1.2.10 --port 8080 --port-count 4 --parallel 100000 --bytes 1024 --rate 2000 --think-ms 0 --concurrency-limit 2000 && success=$((success + 1)) done echo "Success: ${success}/1"
run client pkill tcpdump 2>/dev/null || true; sleep 1
run server pkill tcpdump 2>/dev/null || true; sleep 1
run clientnic pkill tcpdump 2>/dev/null || true; sleep 1
run clientnic pkill -f clientnic-dpdk-forwarder 2>/dev/null || true; sleep 2
run servernic pkill -f servernic-dpdk 2>/dev/null || true; sleep 2
stdout server cat /tmp/server.log
stdout servernic cat /tmp/servernic.log 2>/dev/null || echo '(no log)'
stdout clientnic cat /tmp/clientnic.log
stdout client ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'
stdout server ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'
run client python3 /home/ec2-user/zero-rtt-tcp/experiments/nodes/analyze_metrics.py --client-pcap /tmp/client_side.pcap --summary --detail-out /tmp/client_metrics_per_flow.txt
run server python3 /home/ec2-user/zero-rtt-tcp/experiments/nodes/analyze_metrics.py --server-pcap /tmp/server_side.pcap --summary --detail-out /tmp/server_metrics_per_flow.txt
== 0rtt ssh 1 <- proxmox/run_experiment.sh
stdout servernic cat /sys/class/net/eth1/address 2>/dev/null || echo UNKNOWN
stdout clientnic cat /sys/class/net/eth1/address 2>/dev/null || echo UNKNOWN
stdout server cat /sys/class/net/eth0/address 2>/dev/null || echo UNKNOWN
stdout clientnic cat /sys/class/net/eth2/address 2>/dev/null || echo UNKNOWN
stdout servernic cat /sys/class/net/eth2/address 2>/dev/null || echo UNKNOWN
bg server git config --global --add safe.directory /home/user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/user/zero-rtt-tcp 2>/dev/null || true; fi
bg servernic git config --global --add safe.directory /home/user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/user/zero-rtt-tcp 2>/dev/null || true; fi
bg clientnic git config --global --add safe.directory /home/user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/user/zero-rtt-tcp 2>/dev/null || true; fi
bg client git config --global --add safe.directory /home/user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/user/zero-rtt-tcp 2>/dev/null || true; fi
stdout server git -c safe.directory=/home/user/zero-rtt-tcp -C /home/user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout servernic git -c safe.directory=/home/user/zero-rtt-tcp -C /home/user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout clientnic git -c safe.directory=/home/user/zero-rtt-tcp -C /home/user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout client git -c safe.directory=/home/user/zero-rtt-tcp -C /home/user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
bg client sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; sysctl -w net.ipv4.ip_local_port_range='1024 65535'; sysctl -w net.ipv4.tcp_tw_reuse=1; sysctl -w net.ipv4.tcp_max_tw_buckets=200000; sysctl -w net.core.netdev_max_backlog=250000; sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; sysctl -w fs.file-max=1048576
bg server sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; sysctl -w net.core.somaxconn=131072 net.ipv4.tcp_max_syn_backlog=131072; sysctl -w net.ipv4.tcp_max_tw_buckets=200000; sysctl -w net.core.netdev_max_backlog=250000; sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; sysctl -w fs.file-max=1048576
bg client ip link set eth0 mtu 1500
bg server ip link set eth0 mtu 1500
bg client ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true
bg server ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true
bg client tc qdisc del dev eth0 root 2>/dev/null || true
bg server tc qdisc del dev eth0 root 2>/dev/null || true
stdout client tc qdisc show dev eth0 2>&1
stdout server tc qdisc show dev eth0 2>&1
bg server pkill -9 -f loadgen.py 2>/dev/null; conntrack -F 2>/dev/null || true; rm -f /tmp/server.log
bg servernic pkill -x servernic-dpdk 2>/dev/null; pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null
run clientnic pkill -f clientnic-dpdk-forwarder 2>/dev/null; pkill -f clientnic-dpdk 2>/dev/null; pkill tcpdump 2>/dev/null; sleep 5; pkill -9 -f clientnic-dpdk-forwarder 2>/dev/null; sleep 2; rm -rf /var/run/dpdk/rte/ 2>/dev/null; rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/validate_0rtt.py; iptables -F FORWARD 2>/dev/null; echo CLEANUP_DONE
run clientnic export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; cd /home/user/zero-rtt-tcp/src/clientnic/dpdk-forwarder; rm -rf builddir; /usr/local/bin/meson setup builddir 2>&1 && cd builddir && /usr/local/bin/ninja 2>&1 && echo 'BUILD_SUCCESS'
run servernic export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; cd /home/user/zero-rtt-tcp/src/servernic/dpdk; rm -rf builddir; /usr/local/bin/meson setup builddir 2>&1 && cd builddir && /usr/local/bin/ninja 2>&1 && echo 'BUILD_SUCCESS'
bg server LOAD_PORTS=4 REPO_REF=main setsid bash /home/user/zero-rtt-tcp/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &
stdout server ss -tlnp | grep -q :8080 && echo LISTEN_OK || echo LISTEN_NONE
bg servernic SKIP_BUILD=1 PORT_COUNT=4 CLIENTNIC_GW_MAC=mac-clientnic-eth1 SERVER_GW_MAC=mac-server-eth0 CLIENT_PORT_MAC=mac-servernic-eth1 SERVER_PORT_MAC=mac-servernic-eth2 REPO_REF=main WAN_DELAY_US=50000 setsid bash /home/user/zero-rtt-tcp/experiments/nodes/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &
stdout servernic pgrep -f servernic-dpdk && echo RUNNING || echo NOT_RUNNING
stdout servernic cat /proc/sys/net/ipv4/ip_forward
bg clientnic iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true
bg clientnic SKIP_BUILD=1 PORT_COUNT=4 REPO_REF=main CLIENT_PORT_MAC=mac-clientnic-eth2 SERVER_PORT_MAC=mac-clientnic-eth1 WAN_DELAY_US=50000 setsid bash /home/user/zero-rtt-tcp/experiments/nodes/clientnic.sh mac-servernic-eth1 < /dev/null >> /tmp/clientnic.log 2>&1 &
stdout clientnic cat /proc/sys/net/ipv4/ip_forward
stdout clientnic pgrep -f clientnic-dpdk-forwarder && echo RUNNING || echo NOT_RUNNING
run client pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap
run server pkill tcpdump 2>/dev/null || true; rm -f /tmp/server_side.pcap
bg client if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='--time-stamp-precision=nano' elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='-j adapter' else HIPREC_FLAG='' fi tcpdump $HIPREC_FLAG -i eth0 -nn -s 128 'tcp portrange 8080-8083' -w /tmp/client_side.pcap </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
bg server if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='--time-stamp-precision=nano' elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='-j adapter' else HIPREC_FLAG='' fi tcpdump $HIPREC_FLAG -i eth0 -nn -s 128 'tcp portrange 8080-8083' -w /tmp/server_side.pcap </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
run client pkill tcpdump 2>/dev/null || true; sleep 1
run server pkill tcpdump 2>/dev/null || true; sleep 1
run clientnic pkill tcpdump 2>/dev/null || true; sleep 1
run clientnic pkill -f clientnic-dpdk-forwarder 2>/dev/null || true; sleep 2
run servernic pkill -f servernic-dpdk 2>/dev/null || true; sleep 2
stdout server cat /tmp/server.log
stdout servernic cat /tmp/servernic.log 2>/dev/null || echo '(no log)'
stdout clientnic cat /tmp/clientnic.log
stdout client ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'
stdout server ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'
run client python3 /home/user/zero-rtt-tcp/experiments/nodes/analyze_metrics.py --client-pcap /tmp/client_side.pcap --summary --detail-out /tmp/client_metrics_per_flow.txt
run server python3 /home/user/zero-rtt-tcp/experiments/nodes/analyze_metrics.py --server-pcap /tmp/server_side.pcap --summary --detail-out /tmp/server_metrics_per_flow.txt
== baseline ssm 0 <- baseline-tcp/run_experiment.sh
bg server git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
bg servernic git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
bg clientnic git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
bg client git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; if [ -d /home/ec2-user/zero-rtt-tcp/.git ]; then sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp fetch origin main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout -B main origin/main 2>&1 && sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp reset --hard origin/main 2>&1 || true; else GITHUB_TOKEN=$(aws secretsmanager get-secret-value --secret-id zero-rtt/github-token --query SecretString --output text --region eu-central-1 | tr -d '"[:space:]'); sudo -u ec2-user git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git" /home/ec2-user/zero-rtt-tcp 2>&1 || true; sudo -u ec2-user git -C /home/ec2-user/zero-rtt-tcp checkout main 2>&1 || true; chown -R ec2-user:ec2-user /home/ec2-user/zero-rtt-tcp 2>/dev/null || true; fi
stdout server git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout servernic git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout clientnic git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout client git -c safe.directory=/home/ec2-user/zero-rtt-tcp -C /home/ec2-user/zero-rtt-tcp rev-parse --short HEAD 2>/dev/null || echo NOREPO
stdout clientnic cat /proc/sys/net/ipv4/ip_forward
stdout servernic cat /proc/sys/net/ipv4/ip_forward
stdout clientnic ip route show 10.1.2.0/24 2>/dev/null || echo MISSING
stdout servernic ip route show 10.1.0.0/24 2>/dev/null || echo MISSING
bg server pkill -f loadgen.py 2>/dev/null; rm -f /tmp/server.log
bg client sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; sysctl -w net.ipv4.ip_local_port_range='1024 65535'; sysctl -w net.ipv4.tcp_tw_reuse=1; sysctl -w net.ipv4.tcp_max_tw_buckets=200000; sysctl -w net.core.netdev_max_backlog=250000; sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; sysctl -w fs.file-max=1048576
bg server sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; sysctl -w net.core.somaxconn=131072 net.ipv4.tcp_max_syn_backlog=131072; sysctl -w net.ipv4.tcp_max_tw_buckets=200000; sysctl -w net.core.netdev_max_backlog=250000; sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; sysctl -w fs.file-max=1048576
bg client ip link set eth0 mtu 1500
bg server ip link set eth0 mtu 1500
bg client ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true
bg server ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true
bg client tc qdisc del dev eth0 root 2>/dev/null || true
bg server tc qdisc del dev eth0 root 2>/dev/null || true
stdout client tc qdisc show dev eth0 2>&1
stdout server tc qdisc show dev eth0 2>&1
run clientnic command -v tc >/dev/null || yum install -y iproute-tc 2>&1 | tail -2
run servernic command -v tc >/dev/null || yum install -y iproute-tc 2>&1 | tail -2
bg clientnic tc qdisc del dev eth1 root 2>/dev/null || true; tc qdisc add dev eth1 root netem delay 50ms limit 1000000 2>/dev/null || true
bg servernic tc qdisc del dev eth0 root 2>/dev/null || true; tc qdisc add dev eth0 root netem delay 50ms limit 1000000 2>/dev/null || true
stdout clientnic tc qdisc show dev eth1 2>&1
stdout servernic tc qdisc show dev eth0 2>&1
bg server LOAD_PORTS=4 REPO_REF=main setsid bash /home/ec2-user/zero-rtt-tcp/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &
stdout server ss -tlnp | grep -q :8080 && echo LISTEN_OK || echo LISTEN_NONE
run client pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap
run server pkill tcpdump 2>/dev/null || true; rm -f /tmp/server_side.pcap
bg client if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='--time-stamp-precision=nano' elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='-j adapter' else HIPREC_FLAG='' fi tcpdump $HIPREC_FLAG -i eth0 -nn -s 128 'tcp portrange 8080-8083' -w /tmp/client_side.pcap </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
bg server if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='--time-stamp-precision=nano' elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then HIPREC_FLAG='-j adapter' else HIPREC_FLAG='' fi tcpdump $HIPREC_FLAG -i eth0 -nn -s 128 'tcp portrange 8080-8083' -w /tmp/server_side.pcap </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
run client command -v python3 >/dev/null || { echo 'ERROR: python3 not installed'; exit 1; } ulimit -n 1048576 2>/dev/null || true success=0 for i in $(seq 1 1); do echo "--- Round $i/1: 4 port(s) starting at 8080 x 100000 total connections, 1024 bytes/conn, 2000 conn/s arrival, 0ms think, max 2000 in flight ---" python3 /home/ec2-user/zero-rtt-tcp/experiments/nodes/loadgen.py --mode client --host 10.1.2.10 --port 8080 --port-count 4 --parallel 100000 --bytes 1024 --rate 2000 --think-ms 0 --concurrency-limit 2000 && success=$((success + 1)) done echo "Success: ${success}/1"
run client pkill tcpdump 2>/dev/null || true; sleep 1
run server pkill tcpdump 2>/dev/null || true; sleep 1
bg server pkill -f loadgen.py 2>/dev/null || true
stdout client ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'
stdout server ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'
run client python3 /home/ec2-user/zero-rtt-tcp/experiments/nodes/analyze_metrics.py --client-pcap /tmp/client_side.pcap --summary --detail-out /tmp/client_metrics_per_flow.txt
run server python3 /home/ec2-user/zero-rtt-tcp/experiments/nodes/analyze_metrics.py --server-pcap /tmp/server_side.pcap --summary --detail-out /tmp/server_metrics_per_flow.txt
stdout server cat /tmp/server.log
"""
# <<< RECORDED

RECORDED = _parse(_RECORDED)


if __name__ == "__main__":
    if sys.argv[1:] == ["--record"]:
        _record()
    else:
        sys.exit(pytest.main([__file__, "-v"]))
