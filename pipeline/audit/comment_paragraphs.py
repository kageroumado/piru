#!/usr/bin/env python3
"""Extract the repo's code comments as whole paragraphs for prose linting.

A prose scanner reading a source file sees one comment line at a time, so a
sentence wrapped across three `///` lines reaches it as three fragments. This
joins each run of consecutive whole-line comments (`///`, `//`, `/* */` in
Swift; `#` in Python) and each Python docstring into one paragraph, split at
blank comment lines, and writes them one per line.

Usage:
    pipeline/audit/comment_paragraphs.py OUT_DIR [PATH ...]

Writes `OUT_DIR/paragraphs.txt` (one paragraph per line, so a scanner's line
number indexes the paragraph) and `OUT_DIR/anchors.tsv` (line number →
`file:line` of the paragraph's first source line). PATH defaults to every
tracked `.swift` and `.py` file.
"""

from __future__ import annotations

import ast
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

#: Comment lines that are directives or section markers, never prose.
_DIRECTIVE = re.compile(
    r"^(MARK|TODO|FIXME|swiftlint|swiftformat|noqa|type:|pragma|ruff|fmt:)\b|^!|^#|^-+$|^=+$"
)
_SWIFT_LINE = re.compile(r"^\s*///?\s?(.*)$")
_PY_LINE = re.compile(r"^\s*#\s?(.*)$")


def _paragraphs(lines: list[tuple[int, str]]) -> list[tuple[int, str]]:
    """Group (line number, comment text) pairs into paragraphs at blank or
    non-consecutive lines."""
    out: list[tuple[int, str]] = []
    start, buf, prev = 0, [], -2
    for number, text in lines:
        text = text.strip()
        if number != prev + 1 or not text or _DIRECTIVE.match(text):
            if buf:
                out.append((start, " ".join(buf)))
            buf = []
            if text and not _DIRECTIVE.match(text):
                start, buf = number, [text]
        else:
            if not buf:
                start = number
            buf.append(text)
        prev = number
    if buf:
        out.append((start, " ".join(buf)))
    return out


def swift_comments(source: str) -> list[tuple[int, str]]:
    lines: list[tuple[int, str]] = []
    in_block = False
    for number, raw in enumerate(source.splitlines(), 1):
        stripped = raw.strip()
        if in_block:
            end = stripped.find("*/")
            lines.append((number, (stripped if end < 0 else stripped[:end]).lstrip("* ")))
            in_block = end < 0
            continue
        if stripped.startswith("/*"):
            body = stripped[2:].lstrip("*")
            end = body.find("*/")
            lines.append((number, body if end < 0 else body[:end]))
            in_block = end < 0
            continue
        if match := _SWIFT_LINE.match(raw):
            lines.append((number, match.group(1)))
    return _paragraphs(lines)


def python_comments(source: str) -> list[tuple[int, str]]:
    lines = [
        (n, m.group(1))
        for n, raw in enumerate(source.splitlines(), 1)
        if (m := _PY_LINE.match(raw))
    ]
    found = _paragraphs(lines)
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return found
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        body = node.body
        if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant):
            value = body[0].value.value
            if isinstance(value, str):
                first = body[0].lineno
                doc_lines = [(first + i, text) for i, text in enumerate(value.splitlines())]
                found.extend(_paragraphs(doc_lines))
    return sorted(found)


def tracked_sources() -> list[Path]:
    listed = subprocess.run(
        ["git", "-C", str(REPO), "ls-files", "-z", "*.swift", "*.py"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    names = [name for name in listed.split("\0") if name]
    return [
        REPO / name for name in names if (REPO / name).is_file() and not (REPO / name).is_symlink()
    ]


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = [Path(p).resolve() for p in sys.argv[2:]] or tracked_sources()
    with (
        (out_dir / "paragraphs.txt").open("w") as text,
        (out_dir / "anchors.tsv").open("w") as anchors,
    ):
        line = 0
        for path in paths:
            source = path.read_text(encoding="utf-8", errors="replace")
            extract = swift_comments if path.suffix == ".swift" else python_comments
            for number, paragraph in extract(source):
                line += 1
                text.write(paragraph.replace("\n", " ") + "\n")
                anchors.write(f"{line}\t{path.relative_to(REPO)}:{number}\n")
    print(f"{line} paragraphs → {out_dir}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
