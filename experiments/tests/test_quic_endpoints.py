"""
Tests for the PROTO switch in experiments/nodes/client.sh and server.sh.

The scripts are run for real under bash, with every external command they
reach (python3, openssl, sudo, pkill, hostname, aws) replaced by a PATH stub
that records its argv. The assertions are on the recorded calls: which load
generator ran, with which flags, and whether aioquic was pip-installed.

No AWS, no network, no aioquic needed.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

_NODES_DIR = Path(__file__).parent.parent / "nodes"

pytestmark = pytest.mark.skipif(
    shutil.which("bash") is None, reason="bash not available on this host"
)

_STUB = '#!/bin/sh\necho "$(basename "$0") $*" >> "$STUB_LOG"\n'
# `python3 -c "import aioquic"` must report the module missing, so the
# scripts take the install branch.
_PY_STUB = _STUB + '[ "$1" = "-c" ] && exit 1\nexit 0\n'

# PROTO / QUIC_RESUME travel as ARGUMENTS and are exported inside bash: some
# bash builds sanitize the inherited environment (see test_endpoint_sh.py).
_DRIVER = """\
unset PROTO QUIC_RESUME
export STUB_LOG="$PWD/calls.log" PATH="$PWD/stubs:$PATH"
[ "$2" != "-" ] && export PROTO="$2"
[ "$3" != "-" ] && export QUIC_RESUME="$3"
script="$1"; shift 3
bash "$script" "$@"
"""


def _run(tmp_path, script, proto="-", resume="-", args=()):
    """Run a copy of a node script with stubbed commands; return recorded calls."""
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    for name in ("openssl", "sudo", "pkill", "hostname", "aws", "pip", "pip3"):
        (stubs / name).write_text(_STUB, newline="\n")
        (stubs / name).chmod(0o755)
    (stubs / "python3").write_text(_PY_STUB, newline="\n")
    (stubs / "python3").chmod(0o755)
    shutil.copy(_NODES_DIR / script, tmp_path / script)
    # A driver file rather than an inline command string: Windows argv quoting
    # mangles a string with embedded double quotes.
    (tmp_path / "driver.sh").write_text(_DRIVER, newline="\n")

    result = subprocess.run(
        ["bash", "driver.sh", script, proto, resume, *args],
        capture_output=True, text=True, cwd=str(tmp_path),
        encoding="utf-8", errors="replace",  # the scripts print box-drawing chars
        input="\n",  # client.sh: one Enter = one flow, then EOF ends the loop
        timeout=60,
    )
    assert result.returncode == 0, (
        f"{script} exited {result.returncode}\nstdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )
    log = tmp_path / "calls.log"
    return log.read_text().splitlines() if log.exists() else []


def _loadgen_calls(calls):
    return [c for c in calls if c.startswith("python3 ") and "loadgen" in c]


def _pip_installs(calls):
    return [c for c in calls if "pip install" in c and "aioquic" in c]


class TestServer:
    def test_quic_runs_loadgen_quic_with_cert_and_key(self, tmp_path):
        calls = _run(tmp_path, "server.sh", proto="quic")
        (run,) = _loadgen_calls(calls)
        argv = run.split()
        assert argv[1].endswith("/loadgen_quic.py")
        assert argv[argv.index("--mode") + 1] == "server"
        cert = argv[argv.index("--cert") + 1]
        key = argv[argv.index("--key") + 1]

        # The cert and key passed are the ones openssl was asked to write.
        (gen,) = [c for c in calls if c.startswith("openssl ")]
        gen_argv = gen.split()
        assert "req -x509 -newkey rsa:2048 -nodes -days 1" in gen
        assert gen_argv[gen_argv.index("-out") + 1] == cert
        assert gen_argv[gen_argv.index("-keyout") + 1] == key
        assert cert.startswith("/tmp/") and key.startswith("/tmp/")
        assert calls.index(gen) < calls.index(run), "cert must exist before serve"

    def test_quic_pip_installs_aioquic(self, tmp_path):
        calls = _run(tmp_path, "server.sh", proto="quic")
        (install,) = _pip_installs(calls)
        assert calls.index(install) < calls.index(_loadgen_calls(calls)[0])

    def test_proto_unset_falls_back_to_loadgen(self, tmp_path):
        calls = _run(tmp_path, "server.sh")
        (run,) = _loadgen_calls(calls)
        argv = run.split()
        assert argv[1].endswith("/loadgen.py")
        assert "--cert" not in argv and "--key" not in argv
        assert not _pip_installs(calls)
        assert not [c for c in calls if c.startswith("openssl ")]


class TestClient:
    def test_quic_runs_loadgen_quic(self, tmp_path):
        calls = _run(tmp_path, "client.sh", proto="quic", args=["10.1.2.4"])
        (run,) = _loadgen_calls(calls)
        argv = run.split()
        assert argv[1].endswith("/loadgen_quic.py")
        assert argv[argv.index("--mode") + 1] == "client"
        assert argv[argv.index("--host") + 1] == "10.1.2.4"
        assert "--resume" not in argv

    def test_quic_resume_1_adds_resume(self, tmp_path):
        calls = _run(tmp_path, "client.sh", proto="quic", resume="1",
                     args=["10.1.2.4"])
        (run,) = _loadgen_calls(calls)
        assert "--resume" in run.split()

    def test_quic_resume_0_omits_resume(self, tmp_path):
        calls = _run(tmp_path, "client.sh", proto="quic", resume="0",
                     args=["10.1.2.4"])
        (run,) = _loadgen_calls(calls)
        assert "--resume" not in run.split()

    def test_quic_passes_only_flags_loadgen_quic_accepts(self, tmp_path):
        """loadgen_quic.py has no --think-ms / --concurrency-limit; argparse
        would reject them on the VM and the flow would never start."""
        calls = _run(tmp_path, "client.sh", proto="quic", resume="1",
                     args=["10.1.2.4"])
        (run,) = _loadgen_calls(calls)
        source = (_NODES_DIR / "loadgen_quic.py").read_text(encoding="utf-8")
        for flag in (a for a in run.split() if a.startswith("--")):
            assert f'"{flag}"' in source, f"{flag} is not a loadgen_quic.py flag"

    def test_quic_pip_installs_aioquic(self, tmp_path):
        calls = _run(tmp_path, "client.sh", proto="quic", args=["10.1.2.4"])
        (install,) = _pip_installs(calls)
        assert calls.index(install) < calls.index(_loadgen_calls(calls)[0])

    def test_proto_unset_falls_back_to_loadgen(self, tmp_path):
        calls = _run(tmp_path, "client.sh", resume="1", args=["10.1.2.4"])
        (run,) = _loadgen_calls(calls)
        argv = run.split()
        assert argv[1].endswith("/loadgen.py")
        assert "--resume" not in argv
        assert "--think-ms" in argv and "--concurrency-limit" in argv
        assert not _pip_installs(calls)
