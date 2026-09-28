"""
Pins the remote-call sequence of experiments/run.sh for every supported
STACK x TRANSPORT combination, against a mock transport.

run.sh drives four VMs over SSM or SSH, so the test substitutes the transport
primitives (remote_run/remote_bg/remote_stdout and, where the transport has
them, ssm_run/ssm_bg/ssm_stdout) with recorders that answer every command the
way a healthy chain would, then runs the real run.sh end to end. The EC2 API
(`aws`), the lab reachability probe (`ssh`) and `sleep` are stubbed too, so no
call leaves the machine and a run takes seconds.

The expected sequences below were RECORDED by running the old runners under
this same harness while they still existed:
    0rtt     + ssm  <- experiments/dpdk/run_experiment.sh
    0rtt     + ssh  <- experiments/proxmox/run_experiment.sh
    baseline + ssm  <- experiments/baseline-tcp/run_experiment.sh
Those pinned lists are the parity check — there is deliberately no test that
runs the old runners. The test fails if run.sh drops, adds or reorders a step.

No AWS, no SSH, no live infrastructure.
"""

import functools
import re
import shutil
import subprocess
import sys
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
# Each entry is "<verb> <node> <leading part of the command>": a call matches
# when it starts with its entry. Long commands are pinned by a prefix that names
# the step; the order, count, target node and call kind are pinned exactly.

_SSM_REPO = "/home/ec2-user/zero-rtt-tcp"
_SSH_REPO = "/home/user/zero-rtt-tcp"
_NODES = ("server", "servernic", "clientnic", "client")


def _sync(repo):
    return (
        [f"bg {n} git config --global --add safe.directory {repo} 2>/dev/null || true; "
         f"if [ -d {repo}/.git ]; then" for n in _NODES]
        + [f"stdout {n} git -c safe.directory={repo} -C {repo} rev-parse --short HEAD "
           "2>/dev/null || echo NOREPO" for n in _NODES]
    )


_ENDPOINT_TUNE = [
    "bg client sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0;",
    "bg server sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0;",
    "bg client ip link set eth0 mtu 1500",
    "bg server ip link set eth0 mtu 1500",
    "bg client ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true",
    "bg server ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true",
    "bg client tc qdisc del dev eth0 root 2>/dev/null || true",
    "bg server tc qdisc del dev eth0 root 2>/dev/null || true",
    "stdout client tc qdisc show dev eth0 2>&1",
    "stdout server tc qdisc show dev eth0 2>&1",
]


def _server_start(repo):
    return [
        f"bg server LOAD_PORTS=4 REPO_REF=main setsid bash {repo}/experiments/nodes/server.sh "
        "< /dev/null >> /tmp/server.log 2>&1 &",
        "stdout server ss -tlnp | grep -q :8080 && echo LISTEN_OK || echo LISTEN_NONE",
    ]


_CAPTURE_START = [
    "run client pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap",
    "run server pkill tcpdump 2>/dev/null || true; rm -f /tmp/server_side.pcap",
    "bg client if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then",
    "bg server if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then",
]

_CLIENT_LOAD = "run client command -v python3 >/dev/null || { echo 'ERROR: python3 not installed'; exit 1; }"

_CAPTURE_STOP = [
    "run client pkill tcpdump 2>/dev/null || true; sleep 1",
    "run server pkill tcpdump 2>/dev/null || true; sleep 1",
]


def _analyze(repo):
    return [
        "stdout client ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'",
        "stdout server ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'",
        f"run client python3 {repo}/experiments/nodes/analyze_metrics.py --client-pcap /tmp/client_side.pcap --summary",
        f"run server python3 {repo}/experiments/nodes/analyze_metrics.py --server-pcap /tmp/server_side.pcap --summary",
    ]


# The transport prologues — the only place the two 0-RTT sequences differ in
# shape. SSM smoke-tests the ClientNIC forwarder; the lab reads MACs off the VMs.
_SSM_PROLOGUE = [
    f"run clientnic rm -f /tmp/clientnic_smoke.log; setsid {_SSM_REPO}/src/clientnic/dpdk-forwarder/"
    "builddir/clientnic-dpdk-forwarder -l 0 -- --port=8080 --gw-mac=mac-servernic-eth1 "
    "--client-port-mac=mac-clientnic-eth2 --server-port-mac=mac-clientnic-eth1",
    "stdout clientnic cat /tmp/clientnic_smoke.log 2>/dev/null || echo MISSING",
]
_SSH_PROLOGUE = [
    f"stdout {node} cat /sys/class/net/{iface}/address 2>/dev/null || echo UNKNOWN"
    for node, iface in [("servernic", "eth1"), ("clientnic", "eth1"), ("server", "eth0"),
                        ("clientnic", "eth2"), ("servernic", "eth2")]
]


def _zero_rtt(repo, prologue, client_load=True):
    return [
        *prologue,
        *_sync(repo),
        *_ENDPOINT_TUNE,
        # NIC cleanup
        "bg server pkill -9 -f loadgen.py 2>/dev/null; conntrack -F 2>/dev/null || true; rm -f /tmp/server.log",
        "bg servernic pkill -x servernic-dpdk 2>/dev/null; pkill -f 'servernic/scapy' 2>/dev/null; rm -f /tmp/servernic.log;",
        "run clientnic pkill -f clientnic-dpdk-forwarder 2>/dev/null; pkill -f clientnic-dpdk 2>/dev/null; pkill tcpdump",
        # NIC builds
        f"run clientnic export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; cd {repo}/src/clientnic/dpdk-forwarder; "
        "rm -rf builddir; /usr/local/bin/meson setup builddir",
        f"run servernic export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; cd {repo}/src/servernic/dpdk; "
        "rm -rf builddir; /usr/local/bin/meson setup builddir",
        *_server_start(repo),
        # ServerNIC start
        "bg servernic SKIP_BUILD=1 PORT_COUNT=4 CLIENTNIC_GW_MAC=mac-clientnic-eth1 SERVER_GW_MAC=mac-server-eth0 "
        "CLIENT_PORT_MAC=mac-servernic-eth1 SERVER_PORT_MAC=mac-servernic-eth2 REPO_REF=main WAN_DELAY_US=50000 "
        f"setsid bash {repo}/experiments/nodes/servernic.sh",
        "stdout servernic pgrep -f servernic-dpdk && echo RUNNING || echo NOT_RUNNING",
        "stdout servernic cat /proc/sys/net/ipv4/ip_forward",
        # ClientNIC start
        "bg clientnic iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true",
        "bg clientnic SKIP_BUILD=1 PORT_COUNT=4 REPO_REF=main CLIENT_PORT_MAC=mac-clientnic-eth2 "
        "SERVER_PORT_MAC=mac-clientnic-eth1 WAN_DELAY_US=50000 "
        f"setsid bash {repo}/experiments/nodes/clientnic.sh mac-servernic-eth1",
        "stdout clientnic cat /proc/sys/net/ipv4/ip_forward",
        "stdout clientnic pgrep -f clientnic-dpdk-forwarder && echo RUNNING || echo NOT_RUNNING",
        *_CAPTURE_START,
        *([_CLIENT_LOAD] if client_load else []),
        *_CAPTURE_STOP,
        # NIC stop
        "run clientnic pkill tcpdump 2>/dev/null || true; sleep 1",
        "run clientnic pkill -f clientnic-dpdk-forwarder 2>/dev/null || true; sleep 2",
        "run servernic pkill -f servernic-dpdk 2>/dev/null || true; sleep 2",
        # Server log, then NIC log collection
        "stdout server cat /tmp/server.log",
        "stdout servernic cat /tmp/servernic.log 2>/dev/null || echo '(no log)'",
        "stdout clientnic cat /tmp/clientnic.log",
        *_analyze(repo),
    ]


def _baseline(repo):
    return [
        *_sync(repo),
        # NIC pre-flight: kernel forwarding and static routes
        "stdout clientnic cat /proc/sys/net/ipv4/ip_forward",
        "stdout servernic cat /proc/sys/net/ipv4/ip_forward",
        "stdout clientnic ip route show 10.1.2.0/24 2>/dev/null || echo MISSING",
        "stdout servernic ip route show 10.1.0.0/24 2>/dev/null || echo MISSING",
        "bg server pkill -f loadgen.py 2>/dev/null; rm -f /tmp/server.log",
        *_ENDPOINT_TUNE,
        # netem on the middle leg
        "run clientnic command -v tc >/dev/null || yum install -y iproute-tc 2>&1 | tail -2",
        "run servernic command -v tc >/dev/null || yum install -y iproute-tc 2>&1 | tail -2",
        "bg clientnic tc qdisc del dev eth1 root 2>/dev/null || true; "
        "tc qdisc add dev eth1 root netem delay 50ms limit 1000000 2>/dev/null || true",
        "bg servernic tc qdisc del dev eth0 root 2>/dev/null || true; "
        "tc qdisc add dev eth0 root netem delay 50ms limit 1000000 2>/dev/null || true",
        "stdout clientnic tc qdisc show dev eth1 2>&1",
        "stdout servernic tc qdisc show dev eth0 2>&1",
        *_server_start(repo),
        *_CAPTURE_START,
        _CLIENT_LOAD,
        *_CAPTURE_STOP,
        "bg server pkill -f loadgen.py 2>/dev/null || true",
        *_analyze(repo),
        "stdout server cat /tmp/server.log",
    ]


# (stack, transport) -> (exit code, call sequence), recorded from the old runner.
EXPECTED = {
    ("0rtt", "ssm"): (0, _zero_rtt(_SSM_REPO, _SSM_PROLOGUE)),
    # No client-load call and exit 1, exactly as proxmox/run_experiment.sh:
    # measure.sh's run_ttfb_measurement calls ssm_run, which the SSH transport
    # does not define, so the load step fails with "command not found".
    ("0rtt", "ssh"): (1, _zero_rtt(_SSH_REPO, _SSH_PROLOGUE, client_load=False)),
    ("baseline", "ssm"): (0, _baseline(_SSM_REPO)),
}


@pytest.mark.parametrize("stack,transport", list(EXPECTED))
def test_remote_call_sequence_matches_the_old_runner(stack, transport):
    rc, calls = _calls("../run.sh", stack, transport)
    want_rc, want = EXPECTED[(stack, transport)]
    # Cut each matching call down to its pinned prefix, so a plain list
    # comparison — and pytest's diff of it — shows only real departures:
    # a dropped, added, reordered or retargeted call.
    cut = [w if c.startswith(w) else c for c, w in zip(calls, want)] + list(calls[len(want):])
    assert cut == want
    assert rc == want_rc


def test_baseline_issues_no_nic_build_or_start():
    """STACK=baseline has no data plane: the NIC VMs are plain kernel routers."""
    _, calls = _calls("../run.sh", "baseline", "ssm")
    nic = [c for c in calls if re.search(r"meson setup|nodes/(client|server)nic\.sh|nic-dpdk", c)]
    assert nic == []


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
