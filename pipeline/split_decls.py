#!/usr/bin/env python3
"""Lossless top-level Swift declaration mover.

Segments a .swift file into header + ordered top-level decl chunks (brace-aware,
string/line-comment/block-comment safe; assumes no triple-quoted strings), then
relocates named chunks into destination files while leaving the rest. Every line
of the original ends up in exactly one output file.

Usage: split_decls.py spec.json
spec.json = {"source": "path", "moves": {"destpath": ["DeclName", ...], ...}}
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DECL_RE = re.compile(
    r"^(?:(?:public|private|fileprivate|internal|final|open|indirect)\s+)*"
    r"(struct|class|enum|extension|protocol|actor|func|typealias)\s+([A-Za-z_]\w*)"
)


def depth_after(line, state):
    """Advance brace depth across one line, ignoring braces in strings/comments.
    state = (depth, in_block_comment). Returns (new_state, depth_at_line_start)."""
    depth, in_block = state
    start_depth = depth
    i, n = 0, len(line)
    in_str = False
    while i < n:
        c = line[i]
        if in_block:
            if c == "*" and i + 1 < n and line[i + 1] == "/":
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break  # line comment
        if c == "/" and i + 1 < n and line[i + 1] == "*":
            in_block = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return (depth, in_block), start_depth


def is_trivia(line):
    s = line.strip()
    return (
        s == ""
        or s.startswith("//")
        or s.startswith("@")
        or s.startswith("/*")
        or s.startswith("*")
    )


def segment(lines):
    """Return (header_lines, [(name, [chunk_lines]), ...])."""
    # find depth at the start of each line
    state = (0, False)
    start_depths = []
    for ln in lines:
        state, sd = depth_after(ln, state)
        start_depths.append(sd)
    # decl-start line indices (depth 0, matches decl regex)
    decl_idx = [i for i, ln in enumerate(lines) if start_depths[i] == 0 and DECL_RE.match(ln)]
    if not decl_idx:
        return lines, []
    # extend each decl start backward over immediately-preceding comment/attr trivia
    trivia_starts = []
    for di in decl_idx:
        j = di
        while j - 1 >= 0:
            prev = lines[j - 1].strip()
            if (
                prev.startswith("//")
                or prev.startswith("@")
                or prev.startswith("*")
                or prev.startswith("/*")
            ):
                j -= 1
            else:
                break
        trivia_starts.append(j)
    header = lines[: trivia_starts[0]]
    chunks = []
    for k, di in enumerate(decl_idx):
        cstart = trivia_starts[k]
        cend = trivia_starts[k + 1] if k + 1 < len(decl_idx) else len(lines)
        name = DECL_RE.match(lines[di]).group(2)
        chunks.append((name, lines[cstart:cend]))
    return header, chunks


def main():
    spec = json.loads(Path(sys.argv[1]).read_text())
    src = REPO / spec["source"]
    lines = src.read_text().split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]  # drop trailing empty from split
    header, chunks = segment(lines)
    imports = [line for line in header if line.startswith("import ")]

    moves = spec["moves"]
    name_to_dest = {}
    for dest, names in moves.items():
        for nm in names:
            name_to_dest[nm] = dest

    # sanity: every named decl exists exactly once
    chunk_names = [c[0] for c in chunks]
    for nm in name_to_dest:
        cnt = chunk_names.count(nm)
        assert cnt == 1, f"decl {nm!r} found {cnt} times (expected 1)"

    dest_chunks = {d: [] for d in moves}
    kept = []
    for name, body in chunks:
        if name in name_to_dest:
            dest_chunks[name_to_dest[name]].append((name, body))
        else:
            kept.append((name, body))

    def render(chunk_list):
        out = list(imports) + [""]
        for _, body in chunk_list:
            # trim leading/trailing blank lines of the chunk, re-add one separator
            b = body[:]
            while b and b[0].strip() == "":
                b.pop(0)
            while b and b[-1].strip() == "":
                b.pop()
            out.extend(b)
            out.append("")
        return "\n".join(out).rstrip("\n") + "\n"

    # write destinations
    for dest, cl in dest_chunks.items():
        p = REPO / dest
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(render(cl))
        print(f"  wrote {dest}  ({sum(len(b) for _, b in cl)} decl-lines, {len(cl)} decls)")
    # rewrite source with header preserved (full header, not just imports) + kept chunks
    out = list(header)
    while out and out[-1].strip() == "":
        out.pop()
    out.append("")
    for _, body in kept:
        b = body[:]
        while b and b[0].strip() == "":
            b.pop(0)
        while b and b[-1].strip() == "":
            b.pop()
        out.extend(b)
        out.append("")
    src.write_text("\n".join(out).rstrip("\n") + "\n")
    print(f"  rewrote {spec['source']}  (kept {len(kept)} decls)")


if __name__ == "__main__":
    main()
