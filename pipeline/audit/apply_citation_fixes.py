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

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build.sqlite import parse_reference  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
#: Every place a `reference` may be authored. `data/curated/*.json` is included
#: at the top level because the flagship pharmacology file lives there, not
#: under `substances/` — a narrower glob silently skipped four repairs.
SOURCE_GLOBS = (
    "data/enrichment/raw/*.json",
    "data/curated/*.json",
    "data/curated/substances/*.json",
)


def canonical_reference(reference: str | None) -> str:
    """A reference string reduced to the identifier the build would derive.

    Matching on the raw text does not work, because one identifier is spelled
    several ways across the sources — `pmid:25578256`, `PMID 25578256`,
    `doi:10.1007/PL00005315`, and a bare DOI all name one paper, and the SQLite
    lowercases DOIs on the way in. Reusing the BUILD's own parser rather than a
    second regex means a repair matches exactly what the pipeline matched; a
    private rule here would drift from it silently.
    """
    doi, pmid, url, _title = parse_reference(reference)
    if doi:
        return f"doi:{doi.lower()}"
    if pmid:
        return f"pmid:{pmid}"
    return (url or "").strip().lower()


def read_source(path: Path) -> tuple[object, bool, bool]:
    """Parse a source file and remember how it was written.

    Formatting is per-file and must survive the round trip: these files differ
    in whether non-ASCII is escaped, and rewriting one in the other style turns
    a two-line repair into a whole-file diff nobody can review.
    """
    text = path.read_text(encoding="utf-8")
    escaped = not any(ord(character) > 127 for character in text)
    return json.loads(text), escaped, text.endswith("\n")


def serialize(data: object, escaped: bool, trailing_newline: bool) -> str:
    return json.dumps(data, indent=2, ensure_ascii=escaped) + ("\n" if trailing_newline else "")


def reproduces_original(text: str, data: object, escaped: bool, trailing_newline: bool) -> bool:
    """Whether re-serializing the parsed file gives back the file.

    Two styles live in these sources. Most are plain `indent=2`. But
    `pharmacology-flagship.json` is a hybrid — outer objects indented, each
    binding record written on ONE line — and re-serializing it turned a
    one-token repair into a 1153-line diff nobody could review.

    So the round trip is *tested* rather than assumed, and a file that fails the
    test is edited textually instead. Style is not cosmetic here: an
    unreviewable diff is how a bad edit gets waved through.
    """
    return serialize(data, escaped, trailing_newline) == text


def replace_reference_textually(
    text: str, substance: str | None, old: str, new: str
) -> tuple[str, int]:
    """Swap a reference inside one substance's slice of the file, as text.

    The slice runs from this substance's `"name"` key to the next one, which is
    what keeps a shared wrong identifier from being rewritten under a substance
    whose replacement has not been adjudicated.
    """
    start = 0
    end = len(text)
    if substance:
        marker = f'"name": "{substance}"'
        start = text.find(marker)
        if start < 0:
            return text, 0
        following = text.find('"name": "', start + len(marker))
        end = following if following > 0 else len(text)

    needle = f'"reference": "{old}"'
    segment = text[start:end]
    count = segment.count(needle)
    if not count:
        return text, 0
    return text[:start] + segment.replace(needle, f'"reference": "{new}"') + text[end:], count


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


def matches_scope(record: dict, fix: dict) -> bool:
    """Whether a fix's `where` clause selects this record.

    Substance-level scoping is too coarse and quietly over-applies. Quetiapine
    has four rows citing one fabricated PMID, and the evidence recovered for it
    covers only the H1 row — the D2, 5-HT2A and α1 values still have no source.
    Fenfluramine has six, of which exactly one is the PK route the recovered
    paper actually reports. Without `where`, one adjudicated repair silently
    becomes five unadjudicated ones.
    """
    for field_name, expected in (fix.get("where") or {}).items():
        if str(record.get(field_name) or "") != str(expected):
            return False
    return True


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
        by_identifier.setdefault(canonical_reference(fix["identifier"]), []).append(fix)

    applied = 0
    unmatched = {fix["identifier"] for fix in fixes}
    for pattern in SOURCE_GLOBS:
        for path in sorted(REPO.glob(pattern)):
            text = path.read_text(encoding="utf-8")
            data, escaped, trailing = read_source(path)
            structural = reproduces_original(text, data, escaped, trailing)
            changed = False
            for record, substance in walk_records(data):
                for fix in by_identifier.get(canonical_reference(record.get("reference")), []):
                    # Matched case-insensitively against the name in the SOURCE,
                    # which is not always the DB's canonical name: the sources
                    # spell it "HARMINE", "endomorphin-1", and "Marinol".
                    if (
                        fix.get("substance")
                        and fix["substance"].lower() != (substance or "").lower()
                    ):
                        continue
                    if not matches_scope(record, fix):
                        continue
                    if not structural:
                        # Style-fragile file: edit the reference in place rather
                        # than round-tripping the whole document.
                        if "replace" not in fix:
                            print(
                                f"  SKIPPED {path.relative_to(REPO)} [{substance}] — only a "
                                "'replace' can be applied textually to this file's format",
                                file=sys.stderr,
                            )
                            continue
                        text, hits = replace_reference_textually(
                            text, substance, record["reference"], fix["replace"]
                        )
                        if not hits:
                            continue
                        changed = True
                        applied += hits
                        unmatched.discard(fix["identifier"])
                        print(
                            f"  {path.relative_to(REPO)}  [{substance}]  reference "
                            f"{record['reference']} → {fix['replace']} (textual)"
                        )
                        continue
                    described = apply_fix(record, fix)
                    if not described:
                        continue
                    changed = True
                    applied += 1
                    unmatched.discard(fix["identifier"])
                    print(f"  {path.relative_to(REPO)}  [{substance}]  {described}")
            if changed and not arguments.dry_run:
                path.write_text(
                    text if not structural else serialize(data, escaped, trailing),
                    encoding="utf-8",
                )

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
