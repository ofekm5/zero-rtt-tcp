"""Every path the harness hands to bash or to a VM must exist in the repo.

A moved script otherwise only fails mid-run on live VMs ("No such file").
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = [p for p in (ROOT / "experiments").rglob("*.sh") if "reports" not in p.parts]
WORKFLOWS = list((ROOT / ".github" / "workflows").glob("*.yml"))

# source "$(dirname "$0")/X" or source "$(dirname "${BASH_SOURCE[0]}")/X" — relative to the script
LOCAL_SOURCE = re.compile(r'^\s*source "\$\(dirname "\$(?:0|\{BASH_SOURCE\[0\]\})"\)/([^"]+)"', re.M)
# $REPO_PATH/experiments/... or $repo/experiments/... — the repo clone on the VM
REMOTE_PATH = re.compile(r"\$\{?(?:REPO_PATH|repo)\}?/(experiments/[\w./-]+)")
# source experiments/... in a workflow step — relative to the checkout root
WORKFLOW_SOURCE = re.compile(r"^\s*source (experiments/\S+)", re.M)


def test_scripts_parse():
    for s in SCRIPTS:
        # POSIX-relative path: Git Bash on Windows mangles backslashed absolute paths
        r = subprocess.run(["bash", "-n", s.relative_to(ROOT).as_posix()],
                           capture_output=True, text=True, cwd=ROOT)
        assert r.returncode == 0, f"{s.relative_to(ROOT)}: {r.stderr}"


def test_sourced_paths_resolve():
    for s in SCRIPTS:
        for rel in LOCAL_SOURCE.findall(s.read_text(encoding="utf-8")):
            assert (s.parent / rel).resolve().is_file(), f"{s.relative_to(ROOT)} sources missing {rel}"


def test_remote_repo_paths_resolve():
    for s in SCRIPTS:
        for rel in REMOTE_PATH.findall(s.read_text(encoding="utf-8")):
            assert (ROOT / rel).is_file(), f"{s.relative_to(ROOT)} names missing {rel}"


def test_workflow_sources_resolve():
    for w in WORKFLOWS:
        for rel in WORKFLOW_SOURCE.findall(w.read_text(encoding="utf-8")):
            assert (ROOT / rel).is_file(), f"{w.relative_to(ROOT)} sources missing {rel}"
