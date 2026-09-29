"""
Pins where run.sh's report writer (write_run_report in experiments/lib/report.sh)
puts each report: under experiments/reports/<stack>/, with the filename the
matching pre-run.sh runner used, and nowhere else.

The writer resolves the reports root from its own location, so the test copies
lib/ into a temp experiments/ tree, calls it with stubbed CORE_* results, and
inspects every file that appeared. No AWS, no SSH.
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

_LIB = Path(__file__).parent.parent / "lib"

# PATH-resolved bash by full path: a bare "bash" on Windows can hit the WSL launcher.
_BASH = shutil.which("bash")

pytestmark = pytest.mark.skipif(_BASH is None, reason="bash not available on this host")

_SCRIPT = r"""
set -u
source experiments/lib/output.sh
source experiments/lib/report.sh
FAILURES=0 CONNECTIONS=1 LOAD_PARALLEL=100 LOAD_PORTS=4 LOAD_BYTES=1024 LOAD_RATE=2000
LOAD_CONCURRENCY=2000 NETEM_RTT_MS=100 LAB_GATEWAY=gw CLIENT_STDOUT=client-out
CORE_METRICS_SUMMARY=metrics-sentinel CORE_ENDPOINT_METRICS=endpoint-out
CORE_SERVER_LOG=server-log CORE_SERVERNIC_LOG=servernic-log CORE_CLIENTNIC_LOG=clientnic-log
write_run_report "$1" "$2"
"""

_DATE = r"\d{4}-\d{2}-\d{2}"


@pytest.mark.parametrize("stack,transport,name,title", [
    ("0rtt", "ssm", rf"integration-test-report-{_DATE}\.md", "# Integration Test Report — "),
    ("0rtt", "ssh", rf"proxmox-test-report-{_DATE}\.md", "# Proxmox 0-RTT Test Report — "),
    ("baseline", "ssm", rf"baseline-report-{_DATE}-\d{{6}}\.md", "# Baseline TCP Report — "),
    ("baseline", "ssh", rf"baseline-report-{_DATE}-\d{{6}}\.md", "# Baseline TCP Report — "),
])
def test_report_lands_under_reports_stack(tmp_path, stack, transport, name, title):
    lib = tmp_path / "experiments" / "lib"
    lib.mkdir(parents=True)
    for f in ("output.sh", "report.sh"):
        shutil.copy(_LIB / f, lib / f)

    r = subprocess.run([_BASH, "-c", _SCRIPT, "report", stack, transport],
                       cwd=str(tmp_path), capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0, r.stderr

    written = [p.relative_to(tmp_path).as_posix() for p in tmp_path.rglob("*")
               if p.is_file() and lib not in p.parents]
    assert len(written) == 1, written
    assert re.fullmatch(rf"experiments/reports/{stack}/{name}", written[0]), written[0]

    body = (tmp_path / written[0]).read_text(encoding="utf-8")
    assert body.startswith(title)
    assert "metrics-sentinel" in body
