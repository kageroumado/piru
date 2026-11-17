#!/usr/bin/env python3
"""Grow PiruCore's source set to the closure of the types it uses.

Builds the package, reads the compiler's "cannot find 'X'" errors, finds the app file that
declares each X, and symlinks it in. Files that import a UI or persistence framework are
not pulled in: they are reported as the boundary, which is the list of seams the core
still crosses. Repeats until a build adds nothing new.
"""

import re
import shlex
import subprocess
import sys
from pathlib import Path

from android_paths import BUILD

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / "android/PiruCore"
SRC = PKG / "Sources/Piru"
SCRATCH = BUILD / "PiruCore-mac"
SEARCH = [ROOT / "Shared", ROOT / "Piru"]
BLOCKED = {"SwiftUI", "UIKit", "AppKit", "WidgetKit", "ActivityKit", "Charts", "TipKit"}
MISSING = re.compile(r"cannot find (?:type )?'([A-Za-z_][A-Za-z0-9_]*)' in scope")
ENV = ROOT / "android/tools/env.sh"


def declarations():
    """Every top-level type and free function name → the files declaring it."""
    decl = re.compile(
        r"^(?:[a-z@()]+\s+)*(?:class|struct|enum|protocol|actor|typealias|func|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)",
        re.M,
    )
    index: dict[str, list[Path]] = {}
    for base in SEARCH:
        for f in base.rglob("*.swift"):
            if "+macOS" in f.name or f.parts[-2] == "iOS":
                continue
            for m in decl.finditer(f.read_text(errors="ignore")):
                index.setdefault(m.group(1), []).append(f)
    return index


def imports(f: Path) -> set[str]:
    return set(re.findall(r"^import\s+(\w+)", f.read_text(errors="ignore"), re.M))


def build() -> str:
    cmd = (
        f". {shlex.quote(str(ENV))} && swift build --scratch-path {shlex.quote(str(SCRATCH))} 2>&1"
    )
    out = subprocess.run(["zsh", "-c", cmd], cwd=PKG, capture_output=True, text=True).stdout
    return re.sub(r"\x1b\[[0-9;]*m", "", out)


def main():
    index = declarations()
    boundary: dict[str, set[str]] = {}
    unresolved: set[str] = set()
    for round_ in range(1, 40):
        out = build()
        names = set(MISSING.findall(out))
        linked = {p.resolve() for p in SRC.glob("*.swift")}
        added = []
        for n in sorted(names):
            files = index.get(n)
            if not files:
                unresolved.add(n)
                continue
            f = files[0]
            if f.resolve() in linked:
                continue
            blocked = imports(f) & BLOCKED
            if blocked:
                boundary.setdefault(str(f.relative_to(ROOT)), set()).add(n)
                continue
            (SRC / f.name).symlink_to(Path("../../../..") / f.relative_to(ROOT))
            linked.add(f.resolve())
            added.append(f.relative_to(ROOT))
        errors = len(re.findall(r"error:", out))
        print(
            f"round {round_}: {errors} errors, +{len(added)} files",
            *[f"  + {a}" for a in added],
            sep="\n",
        )
        if not added:
            break
    print("\n== boundary (declares a needed name but imports a UI/persistence framework)")
    for f, ns in sorted(boundary.items()):
        print(
            f"  {f}  [{', '.join(sorted(imports(ROOT / f) & BLOCKED))}]  needed for: {', '.join(sorted(ns))}"
        )
    print("\n== unresolved names:", ", ".join(sorted(unresolved)) or "none")
    SCRATCH.mkdir(parents=True, exist_ok=True)
    (SCRATCH / "last-build.log").write_text(out)


if __name__ == "__main__":
    sys.exit(main())
