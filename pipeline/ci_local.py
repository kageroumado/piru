#!/usr/bin/env python3
"""Run CI's Python job locally, by reading the workflow rather than restating it.

Why parse `.github/workflows/ci.yml` instead of listing the checks here: a second
copy of the list is a copy that drifts. `structural_dupes.py --gate` was added to
CI and sat there broken for six commits because nothing local ran it; the SMILES
invariants passed on CI for a while by silently skipping. Both are the same bug —
a check that exists in one place and not the other. Reading the workflow means a
gate added to CI is a gate that runs before the next push, with no second edit.

Usage:
    python3 pipeline/ci_local.py           # every check except the slow one
    python3 pipeline/ci_local.py --all     # including identifier integrity (~200s)
    python3 pipeline/ci_local.py --only identifier_integrity

Wired as a pre-push hook in .pre-commit-config.yaml. Exits non-zero if any check
fails, which is what blocks the push.

TWO DELIBERATE DIVERGENCES FROM THE WORKFLOW TEXT, both to make the local run see
what CI sees rather than to run something weaker:

1. **ruff is scoped to git-tracked files.** CI runs `ruff format --check .` over a
   fresh checkout, so it only ever sees tracked files. Locally that `.` also walks
   `Specs/`, which is git-IGNORED (this repo is public; the specs are not) and
   holds 5 unformatted files and 13 lint errors. Run verbatim, this hook would
   fail on every push forever over files CI cannot see.
2. **Environment setup steps are skipped** — `pip install`, `apt-get`, `brew`. Your
   machine is not a fresh runner and we are not going to install packages behind
   your back.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[1]
WORKFLOW = REPO / ".github/workflows/ci.yml"
# The job whose steps we mirror. The Swift jobs need a simulator and ~6 minutes;
# `swiftformat --lint` already runs pre-push via its own hook, and the build+test
# is left to CI deliberately (see the pre-push comment in .pre-commit-config.yaml).
JOB = "python"

# Steps that provision a fresh runner. Matched on the command's first word.
_SETUP_PREFIXES = ("pip", "sudo", "brew", "python -m pip", "python3 -m pip")

# Costs ~200s because it shells out to obabel once per row, against ~6.5s for
# every other check combined. Path-gated in the pre-push config instead of being
# run on every push: it reads only the bundled SQLite and its own checker, so a
# push touching neither cannot newly fail it.
SLOW = "test_identifier_integrity"


def workflow_steps() -> list[tuple[str, str]]:
    """(name, command) for each runnable step of the mirrored job, in order."""
    data = yaml.safe_load(WORKFLOW.read_text())
    steps = data["jobs"][JOB]["steps"]
    out: list[tuple[str, str]] = []
    for step in steps:
        command = (step.get("run") or "").strip()
        if not command:
            continue  # `uses:` steps — checkout, setup-python
        if command.startswith(_SETUP_PREFIXES):
            continue
        out.append((step.get("name") or command, command))
    return out


def tracked_python_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "*.py"], cwd=REPO, capture_output=True, text=True, check=True
    )
    return [line for line in result.stdout.splitlines() if line]


def as_argv(command: str) -> list[str]:
    """The command as a real argv, with ruff's `.` replaced by the tracked set."""
    parts = command.split()
    if parts and parts[0] == "ruff" and parts[-1] == ".":
        return parts[:-1] + tracked_python_files()
    return parts


def run(name: str, command: str) -> tuple[bool, float, str]:
    started = time.monotonic()
    result = subprocess.run(as_argv(command), cwd=REPO, capture_output=True, text=True, check=False)
    elapsed = time.monotonic() - started
    output = (result.stdout or "") + (result.stderr or "")
    return result.returncode == 0, elapsed, output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--all", action="store_true", help=f"also run the slow {SLOW} check (~200s)"
    )
    parser.add_argument("--only", help="run just the steps whose command contains this string")
    args = parser.parse_args()

    if not WORKFLOW.exists():
        print(f"ci-local: {WORKFLOW} not found", file=sys.stderr)
        return 1

    steps = workflow_steps()
    if args.only:
        steps = [s for s in steps if args.only in s[1]]
        if not steps:
            print(f"ci-local: no step matches {args.only!r}", file=sys.stderr)
            return 1
    elif not args.all:
        steps = [s for s in steps if SLOW not in s[1]]

    print(f"ci-local: {len(steps)} check(s) from {WORKFLOW.relative_to(REPO)} [{JOB}]\n")
    failures: list[tuple[str, str]] = []
    for name, command in steps:
        ok, elapsed, output = run(name, command)
        print(f"  {'✓' if ok else '✗'} {elapsed:6.1f}s  {name}")
        if not ok:
            failures.append((name, output))

    if failures:
        for name, output in failures:
            print(f"\n{'─' * 72}\nFAILED: {name}\n{'─' * 72}")
            # Tail only — these checks print full findings lists on failure and the
            # actionable part is at the end.
            tail = [line for line in output.splitlines() if line.strip()][-40:]
            print("\n".join(tail))
        print(f"\nci-local: {len(failures)} of {len(steps)} check(s) FAILED", file=sys.stderr)
        return 1

    skipped = "" if args.all or args.only else f" (skipped {SLOW}; --all to include)"
    print(f"\nci-local: all {len(steps)} check(s) passed{skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
