#!/usr/bin/env python3
"""Remove named type members (4-space-indented var/func/let) from a Swift file,
brace-aware, including each member's immediately-preceding doc/comment/attribute
trivia. Then apply literal string replacements. Assumes no triple-quoted strings.
"""

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
names = sys.argv[2].split(",")  # member names to remove
# replacements: "OLD===NEW" pairs after the names arg
repls = [a.split("===", 1) for a in sys.argv[3:]]

lines = path.read_text().split("\n")


def depth_after(line, state):
    depth, in_block = state
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
            break
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
    return (depth, in_block)


def member_start(line, name):
    return re.match(
        r"^    (?:@\w+(?:\([^)]*\))?\s+)*(?:private\s+|fileprivate\s+|static\s+|internal\s+)*(?:func|var|let)\s+"
        + re.escape(name)
        + r"\b",
        line,
    )


remove = set()
for name in names:
    name = name.strip()
    idx = next((i for i, ln in enumerate(lines) if member_start(ln, name)), None)
    if idx is None:
        print(f"WARN: member {name!r} not found")
        continue
    # find end: brace-match if the member opens a brace, else single line
    start = idx
    if "{" in lines[idx].split("//")[0]:
        state = (0, False)
        end = idx
        for j in range(idx, len(lines)):
            state = depth_after(lines[j], state)
            if state[0] == 0:
                end = j
                break
    else:
        end = idx  # one-liner (e.g. `let x = 6`)
    # absorb preceding contiguous trivia (doc/comment/attribute lines)
    t = start
    while t - 1 >= 0 and re.match(r"^\s*(///|//|@|\*|/\*)", lines[t - 1]):
        t -= 1
    for k in range(t, end + 1):
        remove.add(k)

kept = [ln for i, ln in enumerate(lines) if i not in remove]
text = "\n".join(kept)

for old, new in repls:
    assert text.count(old) == 1, f"replacement {old!r} matched {text.count(old)}×"
    text = text.replace(old, new)

# collapse any 3+ consecutive blank lines left behind into one
text = re.sub(r"\n{3,}", "\n\n", text)
path.write_text(text)
print(f"removed {len(names)} members ({len(remove)} lines), applied {len(repls)} replacements")
