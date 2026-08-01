#!/usr/bin/env python3
"""Structural check on every Hermes profile distribution under a directory.

Catches the breakages that would only surface at `hermes profile install` time:
malformed cron JSON, a missing SOUL/config, an env var declared in
distribution.yaml but absent from .env.EXAMPLE (or vice versa), and a committed
secret.

  ./check_distributions.py [dir]   # default: cwd

Copy it next to the profiles so it runs as a repo check, or run it in place.
"""

import json
import re
import sys
from pathlib import Path

HERE = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
REQUIRED = ("distribution.yaml", "SOUL.md", "config.yaml", ".env.EXAMPLE")


def profiles():
    """A profile dir is any dir holding a distribution.yaml."""
    return sorted(p.parent for p in HERE.glob("*/distribution.yaml")) or sorted(
        p.parent for p in HERE.glob("distribution.yaml")
    )


def declared_env(manifest: Path) -> set[str]:
    # ponytail: regex over `- name: FOO` instead of a pyyaml dep. env_requires is
    # the only list of `name:` keys in the manifest, so this is unambiguous here.
    return set(re.findall(r"^\s*-\s*name:\s*([A-Z0-9_]+)\s*$", manifest.read_text(), re.M))


def example_env(env_file: Path) -> set[str]:
    return {
        line.split("=", 1)[0].strip()
        for line in env_file.read_text().splitlines()
        if "=" in line and not line.lstrip().startswith("#")
    }


def check(profile: Path) -> list[str]:
    errs = []
    for name in REQUIRED:
        if not (profile / name).is_file():
            errs.append(f"missing {name}")
    if (profile / ".env").exists():
        errs.append("SECRET COMMITTED: .env present — remove it")

    manifest, example = profile / "distribution.yaml", profile / ".env.EXAMPLE"
    if manifest.is_file() and example.is_file():
        declared, present = declared_env(manifest), example_env(example)
        if missing := declared - present:
            errs.append(f"declared in manifest but not in .env.EXAMPLE: {sorted(missing)}")
        if extra := present - declared:
            errs.append(f"in .env.EXAMPLE but not declared in manifest: {sorted(extra)}")

    jobs = profile / "cron" / "jobs.json"
    if jobs.is_file():
        try:
            parsed = json.loads(jobs.read_text())
        except json.JSONDecodeError as e:
            errs.append(f"cron/jobs.json is not valid JSON: {e}")
        else:
            if not isinstance(parsed, list):
                errs.append("cron/jobs.json must be a bare array of job objects")
            else:
                for job in parsed:
                    for field in ("id", "name", "prompt", "schedule", "enabled"):
                        if field not in job:
                            errs.append(f"cron job {job.get('name', '?')!r} missing {field!r}")
                    # 5-field POSIX cron; Hermes also takes intervals, but every
                    # schedule in this repo is cron, so hold the line here.
                    if len(str(job.get("schedule", "")).split()) != 5:
                        errs.append(f"cron job {job.get('name', '?')!r}: schedule is not 5 fields")
    return errs


def main() -> int:
    found = profiles()
    if not found:
        print("FAIL: no profile distributions found", file=sys.stderr)
        return 1

    failed = False
    for profile in found:
        errs = check(profile)
        print(f"{'FAIL' if errs else 'ok  '}  {profile.name}")
        for err in errs:
            print(f"        {err}")
        failed |= bool(errs)

    print(f"\n{len(found)} distributions checked")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
