#!/usr/bin/env python3
"""Rewrite bare style literals in Piru's SwiftUI views as design tokens.

Every rule is *value-preserving*: a literal is replaced by a token whose value is
identical, so the rendered build is pixel-identical and the diff is reviewable as
a pure vocabulary change. A rule that cannot prove the value is unchanged does
not belong here.

    python3 design-system/migrate_tokens.py --dry-run PATH...   # per-rule counts
    python3 design-system/migrate_tokens.py --write   PATH...   # rewrite in place
    python3 design-system/migrate_tokens.py --check   PATH...   # exit 1 if any remain

PATH may be a file or a directory (recursed, ``*.swift`` only). Only files under
``Piru/`` are touched: ``Shared/`` and the widget targets do not compile the
token files and would fail to build.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Directories under Piru/ that the tokens are not visible from, or that are not
# ours to rewrite.
EXCLUDED_PARTS = {"DesignSystem"}

SPACING = {2: "xxs", 4: "xs", 6: "sm", 8: "md", 10: "lg", 12: "xl", 16: "xxl", 24: "xxxl"}
CORNER = {22: "card", 16: "container", 12: "medium", 10: "inner", 8: "input", 3: "tiny"}
OPACITY = {
    "0.08": "hairline",
    "0.1": "tint",
    "0.10": "tint",
    "0.18": "tintActive",
    "0.25": "emphasis",
    "0.4": "muted",
    "0.5": "dimmed",
    "0.8": "strong",
}
ICON = {44: "touchTarget", 34: "icon", 28: "iconSmall", 24: "iconCompact", 22: "iconMini", 8: "dot"}

FONT_ROLES = {
    ".font(.system(size: 9))": ".font(.chartAnnotation)",
    ".font(.system(size: 10, weight: .semibold))": ".font(.chartLabel)",
    ".font(.system(size: 38, weight: .bold))": ".font(.heroStat)",
    ".font(.system(size: 17, weight: .semibold))": ".font(.sectionTitle)",
}

TEXT_ROLES = {
    ".font(.subheadline.weight(.semibold))": ".sectionLabel()",
    ".font(.headline)": ".cardTitle()",
    ".font(.title3.weight(.semibold))": ".screenTitle()",
}


# --- masking -----------------------------------------------------------------


def code_mask(line: str) -> list[bool]:
    """True at each index that is real code — outside string literals and comments.

    Swift string interpolation (``\\(expr)``) is deliberately treated as string:
    a literal inside an interpolation is rare and rewriting it risks a wrong edit
    for no gain.
    """
    mask = [True] * len(line)
    in_string = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            mask[i] = False
            if ch == "\\" and i + 1 < len(line):
                mask[i + 1] = False
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            mask[i] = False
            i += 1
            continue
        if ch == "/" and line.startswith("//", i):
            for j in range(i, len(line)):
                mask[j] = False
            break
        i += 1
    return mask


def in_code(mask: list[bool], start: int, end: int) -> bool:
    return all(mask[start:end])


# --- rules -------------------------------------------------------------------


@dataclass
class Rule:
    """One line-local rewrite, applied over the code-only span of each line."""

    name: str
    pattern: re.Pattern[str]
    repl: object  # callable(match) -> str | None

    def apply(self, line: str) -> tuple[str, int]:
        mask = code_mask(line)
        out: list[str] = []
        cursor = 0
        hits = 0
        for m in self.pattern.finditer(line):
            if not in_code(mask, m.start(), m.end()):
                continue
            replacement = self.repl(m)
            if replacement is None:
                continue
            out.append(line[cursor : m.start()])
            out.append(replacement)
            cursor = m.end()
            hits += 1
        if not hits:
            return line, 0
        out.append(line[cursor:])
        return "".join(out), hits


def _ladder(table: dict[int, str], prefix: str):
    def repl(m: re.Match[str]) -> str | None:
        name = table.get(int(m.group("n")))
        if name is None:
            return None
        return m.group(0).replace(m.group("n"), f"{prefix}.{name}", 1)

    return repl


def spacing_rule() -> Rule:
    return Rule(
        "spacing:",
        re.compile(r"\bspacing:\s*(?P<n>\d+)\b(?!\s*\.)"),
        _ladder(SPACING, "Spacing"),
    )


def padding_rule() -> Rule:
    # .padding(N) / .padding(.edge, N) / .padding([.a, .b], N)
    pattern = re.compile(
        r"\.padding\(\s*(?P<edges>\.[A-Za-z]+\s*,\s*|\[[^\]]*\]\s*,\s*)?(?P<n>\d+)\s*\)",
    )

    def repl(m: re.Match[str]) -> str | None:
        name = SPACING.get(int(m.group("n")))
        if name is None:
            return None
        edges = m.group("edges") or ""
        return f".padding({edges}Spacing.{name})"

    return Rule(".padding(N)", pattern, repl)


def corner_rule() -> Rule:
    return Rule(
        "cornerRadius:",
        re.compile(r"\bcornerRadius:\s*(?P<n>\d+)\b(?!\s*\.)"),
        _ladder(CORNER, "Theme.CornerRadius"),
    )


def opacity_rule() -> Rule:
    pattern = re.compile(r"\.opacity\(\s*(?P<v>0?\.\d+)\s*\)")

    def repl(m: re.Match[str]) -> str | None:
        key = m.group("v")
        key = key if key.startswith("0") else "0" + key
        name = OPACITY.get(key)
        if name is None:
            return None
        return f".opacity(Theme.Opacity.{name})"

    return Rule(".opacity(V)", pattern, repl)


def frame_rule() -> Rule:
    pattern = re.compile(
        r"\.frame\(\s*width:\s*(?P<w>\d+)\s*,\s*height:\s*(?P<h>\d+)\s*\)",
    )

    def repl(m: re.Match[str]) -> str | None:
        if m.group("w") != m.group("h"):
            return None
        name = ICON.get(int(m.group("w")))
        if name is None:
            return None
        return f".frame(width: IconSize.{name}, height: IconSize.{name})"

    return Rule(".frame(square)", pattern, repl)


def font_role_rule(literal: str, token: str, name: str) -> Rule:
    return Rule(name, re.compile(re.escape(literal)), lambda _m, t=token: t)


def secondary_style_rule() -> Rule:
    return Rule(
        ".foregroundStyle(.secondary)",
        re.compile(r"\.foregroundStyle\(\.secondary\)"),
        lambda _m: ".foregroundStyle(Theme.secondaryLabel)",
    )


LINE_RULES: list[Rule] = [
    spacing_rule(),
    padding_rule(),
    corner_rule(),
    opacity_rule(),
    frame_rule(),
    *[font_role_rule(lit, tok, f"font role {tok}") for lit, tok in FONT_ROLES.items()],
    *[font_role_rule(lit, tok, f"text role {tok}") for lit, tok in TEXT_ROLES.items()],
    secondary_style_rule(),
]


# --- multi-line (adjacent modifier) rules ------------------------------------


@dataclass
class Pair:
    """Two adjacent chained modifiers collapsed into one.

    Matched across the whole file text rather than per line, because the pair is
    normally split over two lines with the indentation of the chain between them.
    """

    name: str
    pattern: re.Pattern[str]
    token: str

    def apply(self, text: str) -> tuple[str, int]:
        hits = 0

        def repl(m: re.Match[str]) -> str:
            nonlocal hits
            line_start = text.rfind("\n", 0, m.start()) + 1
            line_end = text.find("\n", m.start())
            line = text[line_start : line_end if line_end != -1 else len(text)]
            if not code_mask(line)[m.start() - line_start]:
                return m.group(0)
            hits += 1
            return self.token

        return self.pattern.sub(repl, text), hits


PAIR_RULES: list[Pair] = [
    Pair(
        ".captionSecondary()",
        re.compile(
            r"\.font\(\.caption\)[ \t]*\r?\n?[ \t]*"
            r"\.foregroundStyle\((?:Theme\.secondaryLabel|\.secondary)\)",
        ),
        ".captionSecondary()",
    ),
    Pair(
        ".themedPage()",
        re.compile(
            r"\.scrollContentBackground\(\.hidden\)[ \t]*\r?\n?[ \t]*"
            r"\.background\(Theme\.background\)",
        ),
        ".themedPage()",
    ),
]


# --- driver ------------------------------------------------------------------


@dataclass
class Report:
    counts: dict[str, int] = field(default_factory=dict)
    files_changed: set[str] = field(default_factory=set)

    def add(self, rule: str, n: int, path: Path) -> None:
        if n:
            self.counts[rule] = self.counts.get(rule, 0) + n
            self.files_changed.add(str(path))

    @property
    def total(self) -> int:
        return sum(self.counts.values())


def migrate(text: str) -> tuple[str, dict[str, int]]:
    counts: dict[str, int] = {}

    # Pair rules first: collapsing `.font(.caption)` + `.foregroundStyle(...)`
    # must happen before the standalone `.foregroundStyle(.secondary)` rule
    # rewrites the second half out from under it.
    for pair in PAIR_RULES:
        text, n = pair.apply(text)
        if n:
            counts[pair.name] = counts.get(pair.name, 0) + n

    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        for rule in LINE_RULES:
            line, n = rule.apply(line)
            if n:
                counts[rule.name] = counts.get(rule.name, 0) + n
        lines[i] = line
    return "".join(lines), counts


def swift_files(paths: list[str]) -> list[Path]:
    found: list[Path] = []
    for raw in paths:
        p = Path(raw).resolve()
        if p.is_dir():
            found.extend(sorted(p.rglob("*.swift")))
        elif p.suffix == ".swift":
            found.append(p)
    return found


def in_scope(path: Path) -> bool:
    try:
        rel = path.relative_to(REPO_ROOT)
    except ValueError:
        return False
    parts = rel.parts
    if not parts or parts[0] != "Piru":
        return False
    return not EXCLUDED_PARTS.intersection(parts)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="report only")
    mode.add_argument("--write", action="store_true", help="rewrite in place")
    mode.add_argument("--check", action="store_true", help="exit 1 if anything is migratable")
    ap.add_argument("paths", nargs="+")
    args = ap.parse_args()

    report = Report()
    skipped: list[Path] = []

    for path in swift_files(args.paths):
        if not in_scope(path):
            skipped.append(path)
            continue
        original = path.read_text(encoding="utf-8")
        migrated, counts = migrate(original)
        for rule, n in counts.items():
            report.add(rule, n, path.relative_to(REPO_ROOT))
        if args.write and migrated != original:
            path.write_text(migrated, encoding="utf-8")

    for rule in sorted(report.counts, key=lambda r: (-report.counts[r], r)):
        print(f"{report.counts[rule]:6d}  {rule}")
    print(f"{report.total:6d}  TOTAL across {len(report.files_changed)} file(s)")
    if skipped:
        print(
            f"        (skipped {len(skipped)} file(s) outside Piru/ or in DesignSystem/)",
            file=sys.stderr,
        )

    if args.check and report.total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
