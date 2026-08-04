#!/usr/bin/env python3
"""Apply adjudicated citation repairs to the enrichment sources.

Every wrong citation in this repo lives in `data/enrichment/raw/*.json` or
`data/curated/`, as a `reference` field beside the value it is supposed to
support. The shipped SQLite is a build artifact, so a repair edits the source
and the DB is rebuilt — hand-editing the `.sqlite` hides pipeline bugs and is
clobbered on the next run.

Three repairs, and the second and third are not the same thing:

    replace  the number is right, the identifier points at the wrong paper.
             Swap the identifier; the value stays.
    drop     no source can be established for the number. Null the value. A
             value with no source is worse than an absent one — the app renders
             absence honestly and renders a wrong number authoritatively.
    unsource the number is defensible but the identifier is fabricated. Clear
             the reference only. Use this ONLY where the pipeline can still show
             provenance some other way; otherwise it is `drop` wearing a hat.

Fixes are supplied as a JSON list so they can be reviewed as a batch, and every
entry must carry a `why`. Nothing here searches for a source: a fix file is the
*output* of adjudication, never a guess made at apply time.

    python3 pipeline/audit/apply_citation_fixes.py fixes.json --dry-run
    python3 pipeline/audit/apply_citation_fixes.py fixes.json

Fix entries:

    {"identifier": "pmid:27623219", "replace": "pmid:27520396",
     "substance": "Ephenidine", "why": "Kang 2017, the paper the notes name"}
    {"identifier": "pmid:9700761", "drop": ["half_life_h"],
     "substance": "Harmine", "why": "no source establishes this value"}
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE_GLOBS = ("data/enrichment/raw/*.json", "data/curated/substances/*.json")


def read_source(path: Path) -> tuple[object, bool, bool]:
    """Parse a source file and remember how it was written.

    Formatting is per-file and must survive the round trip: these files differ
    in whether non-ASCII is escaped, and rewriting one in the other style turns
    a two-line repair into a whole-file diff nobody can review.
    """
    text = path.read_text(encoding="utf-8")
    escaped = not any(ord(character) > 127 for character in text)
    return json.loads(text), escaped, text.endswith("\n")


def write_source(path: Path, data: object, escaped: bool, trailing_newline: bool) -> None:
    text = json.dumps(data, indent=2, ensure_ascii=escaped)
    path.write_text(text + ("\n" if trailing_newline else ""), encoding="utf-8")


def walk_records(node: object, substance: str | None = None):
    """Yield every dict carrying a `reference`, with the substance it sits under.

    The enrichment schema nests citable records at many depths (pharmacology
    .binding[], metabolism[], human_pk.routes[]), and it gains new ones as the
    pipeline grows. Walking for the `reference` key rather than for known paths
    means a repair reaches a table nobody remembered to list.
    """
    if isinstance(node, dict):
        name = node.get("name") if isinstance(node.get("name"), str) else substance
        if "reference" in node:
            yield node, name
        for value in node.values():
            yield from walk_records(value, name)
    elif isinstance(node, list):
        for item in node:
            yield from walk_records(item, substance)


def apply_fix(record: dict, fix: dict) -> str | None:
    """Mutate one record. Returns a description of what changed, or None."""
    if "replace" in fix:
        was = record["reference"]
        record["reference"] = fix["replace"]
        return f"reference {was} → {fix['replace']}"
    if fix.get("drop"):
        cleared = [column for column in fix["drop"] if record.get(column) is not None]
        if not cleared:
            return None
        for column in cleared:
            record[column] = None
        # The reference goes with the value. Leaving a citation behind on a
        # nulled row leaves a claim that the paper supports something the row no
        # longer says.
        record["reference"] = None
        return f"dropped {', '.join(cleared)} and its reference"
    if fix.get("unsource"):
        if record.get("reference") is None:
            return None
        was = record["reference"]
        record["reference"] = None
        return f"cleared reference {was}"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixes", type=Path, help="JSON list of adjudicated repairs")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    arguments = parser.parse_args()

    fixes = [fix for fix in json.loads(arguments.fixes.read_text()) if isinstance(fix, dict)]
    missing_reason = [fix for fix in fixes if not fix.get("why")]
    if missing_reason:
        print(
            f"apply-citation-fixes: {len(missing_reason)} fix(es) carry no 'why'. "
            "Every repair has to say what it rests on.",
            file=sys.stderr,
        )
        return 2

    by_identifier: dict[str, list[dict]] = {}
    for fix in fixes:
        by_identifier.setdefault(fix["identifier"], []).append(fix)

    applied = 0
    unmatched = {fix["identifier"] for fix in fixes}
    for pattern in SOURCE_GLOBS:
        for path in sorted(REPO.glob(pattern)):
            data, escaped, trailing = read_source(path)
            changed = False
            for record, substance in walk_records(data):
                for fix in by_identifier.get(record.get("reference") or "", []):
                    if fix.get("substance") and fix["substance"] != substance:
                        continue
                    described = apply_fix(record, fix)
                    if not described:
                        continue
                    changed = True
                    applied += 1
                    unmatched.discard(fix["identifier"])
                    print(f"  {path.relative_to(REPO)}  [{substance}]  {described}")
            if changed and not arguments.dry_run:
                write_source(path, data, escaped, trailing)

    print(f"\napply-citation-fixes: {applied} record(s) changed across the sources")
    if unmatched:
        print(
            f"apply-citation-fixes: {len(unmatched)} identifier(s) matched nothing — "
            "they may already be repaired, or live in a source not covered here:",
            file=sys.stderr,
        )
        for identifier in sorted(unmatched):
            print(f"  {identifier}", file=sys.stderr)
    if arguments.dry_run:
        print("(dry run — nothing written)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
