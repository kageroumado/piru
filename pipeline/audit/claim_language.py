"""The claim-language gate for the mechanism prose Piru ships.

Two vocabularies, because two different things are being policed.

`MEDICAL_CLAIM` is what no shipped mechanism row may say, whoever wrote it — a
reader cannot tell a sentence lifted from a product label from one Piru composed,
so an efficacy claim, an indication, or an instruction about what to do reads the
same either way. It applies to every English `mechanisms_summary` row in the built
database and to every curated file here.

`AUTHORED_ONLY` is the narrower register Piru's own one-sentence lines hold
themselves to: a target and an action, nothing about amounts, nothing addressed to
a reader, nothing about liability to use. These words are legitimate pharmacology
in a paragraph describing a recreational compound — "at higher doses it depletes
serotonin" is a fact, and a note that a compound carries high abuse liability is a
description — so they gate only what Piru writes, not what Piru reports.

    python3 pipeline/audit/claim_language.py            # report
    python3 pipeline/audit/claim_language.py --gate     # exit 1 on any hit

The build runs it with ``--gate`` (pipeline/build.sh), after the database exists.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LINES_PATH = REPO / "data/curated/mechanism-lines.json"
DB_PATH = REPO / "Piru/Data/piru-substances.sqlite"

# One mechanism line is a headline, not a paragraph.
MAX_LINE_WORDS = 25

# The objects in mechanism-lines.json that hold Piru's own one-sentence lines, and
# so answer to AUTHORED_ONLY as well as MEDICAL_CLAIM.
AUTHORED_OBJECTS = ("lines", "medtap_lines")
# Replacement paragraphs for rows Piru cannot edit at their source: full prose, held
# to MEDICAL_CLAIM only.
OVERRIDE_OBJECT = "overrides"

# (label, pattern). Word-bounded and case-insensitive; stems catch the inflections
# ("treats", "prevention", "prescription", "titrated").
MEDICAL_CLAIM: tuple[tuple[str, str], ...] = (
    ("treat", r"\btreat(?:s|ed|ing|ment|ments)?\b"),
    ("therapy", r"\btherap\w*"),
    ("cure", r"\bcur(?:e|es|ed|ing|ative)\b"),
    ("prevent", r"\bprevent\w*"),
    ("prescribe", r"\bprescri\w*"),
    ("indicated for", r"\b(?:is|are)\s+indicated\b|\bindicated\s+(?:for|in|as)\b"),
    ("diagnosis", r"\bdiagnos\w*"),
    ("first-line", r"\bfirst[-\s]line\b"),
    ("second-line", r"\bsecond[-\s]line\b"),
    ("adjunct", r"\badjunct\w*"),
    ("efficacy", r"\befficac\w*"),
    ("effective", r"\beffective\w*"),
    ("safe", r"\bsafe(?:ly|r|st)?\b"),
    ("recommended", r"\brecommend\w*"),
    ("patients", r"\bpatients?\b"),
    ("titrate", r"\btitrat\w*"),
    ("taper", r"\btaper\w*"),
    ("clinical trial", r"\bclinical\s+trials?\b"),
    ("FDA-approved", r"\bfda[-\s]approved\b"),
    ("approved for", r"\bapproved\s+(?:for|dose)\w*\b"),
    ("off-label", r"\boff[-\s]label\b"),
    ("contraindicated", r"\bcontraindicat\w*"),
    ("warning", r"\bwarnings?\b"),
    # Directed guidance, as opposed to a mechanism that happens to use "must": the
    # NMDA channel "must remain open" is a description, "should be taken into
    # consideration when combining" is advice.
    (
        "advice",
        r"\b(?:should|must|do\s+not|don't|never|always)\s+(?:be\s+|being\s+)?"
        r"(?:take|taken|taking|use|used|using|combine|combined|combining|mix|mixed|"
        r"mixing|avoid|avoided|avoiding|consider|considered|given|administered)\b",
    ),
    ("advice", r"\btaken?\s+into\s+consideration\b"),
    ("advice", r"\bconsult\b|\bseek\s+medical\b"),
    # Dosing instructions, as opposed to dose-dependent pharmacology.
    ("dosing instruction", r"\b(?:recommended|usual|starting|daily|maximum|target)\s+dos\w*"),
    ("dosing instruction", r"\bdos(?:e|age)\s+(?:range|adjustment|schedule)\b"),
)

# Additional terms for Piru's own one-sentence lines.
AUTHORED_ONLY: tuple[tuple[str, str], ...] = (
    ("dose", r"\bdos(?:e|es|ed|ing|age|ages)\b"),
    ("mg", r"\d\s*mg\b|\bmg\b"),
    ("should", r"\bshould\b"),
    ("must", r"\bmust\b"),
    ("abuse", r"\babus\w*"),
    ("addiction", r"\baddict\w*"),
    ("recreational", r"\brecreational\w*"),
    ("overdose", r"\boverdos\w*"),
    ("second person", r"\byou(?:r|rs|rself|'re|'ll|'ve)?\b"),
)


def _compile(terms: tuple[tuple[str, str], ...]) -> tuple[tuple[str, re.Pattern[str]], ...]:
    return tuple((label, re.compile(pattern, re.IGNORECASE)) for label, pattern in terms)


_CLAIM = _compile(MEDICAL_CLAIM)
_AUTHORED = _compile(MEDICAL_CLAIM + AUTHORED_ONLY)


def banned_hits(text: str, *, authored: bool = False) -> list[str]:
    """The banned terms `text` contains, by label, in list order, deduplicated."""
    out: list[str] = []
    for label, rx in _AUTHORED if authored else _CLAIM:
        if rx.search(text or "") and label not in out:
            out.append(label)
    return out


def check_line(line: str) -> list[str]:
    """Every reason one Piru-authored mechanism line fails, empty when it passes."""
    problems = [f"banned: {h}" for h in banned_hits(line, authored=True)]
    if len(line.split()) > MAX_LINE_WORDS:
        problems.append(f"more than {MAX_LINE_WORDS} words")
    if not line.endswith("."):
        problems.append("not one sentence ending in a period")
    elif re.search(r"[.!?]\s+\S", line):
        problems.append("more than one sentence")
    return problems


def check_files(lines_path: Path = LINES_PATH) -> list[tuple[str, str, str]]:
    """(file, key, problem) for every failing entry in the curated file."""
    out: list[tuple[str, str, str]] = []
    doc = json.loads(lines_path.read_text())
    for obj in AUTHORED_OBJECTS:
        for key, line in doc.get(obj, {}).items():
            out += [(lines_path.name, f"{obj}/{key}", f"{line!r}: {p}") for p in check_line(line)]
    for key, prose in doc.get(OVERRIDE_OBJECT, {}).items():
        out += [
            (lines_path.name, f"{OVERRIDE_OBJECT}/{key}", f"{prose!r}: banned: {h}")
            for h in banned_hits(prose)
        ]
    return out


def check_db(db_path: Path = DB_PATH) -> list[tuple[str, str, str]]:
    """(table, substance, problem) for every English mechanism row the database ships.

    Every source, not only Piru's own: a reader cannot tell who wrote a sentence, so
    an efficacy claim inherited from a label reads exactly like one Piru made up. Rows
    still attributed to `pyrls` must be none — its prose is evidence, never shipped.
    """
    out: list[tuple[str, str, str]] = []
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    n = con.execute(
        "SELECT COUNT(*) FROM mechanisms_summary t JOIN sources s ON s.id = t.source_id "
        "WHERE s.slug = 'pyrls'"
    ).fetchone()[0]
    if n:
        out.append(("mechanisms_summary", "*", f"{n} row(s) still attributed to pyrls"))
    for name, summary in con.execute(
        "SELECT sub.canonical_name, m.summary FROM mechanisms_summary m "
        "JOIN sources s ON s.id = m.source_id JOIN substances sub ON sub.id = m.substance_id "
        "WHERE m.language = 'en'"
    ):
        out += [
            ("mechanisms_summary", name, f"{summary!r}: banned: {h}") for h in banned_hits(summary)
        ]
    con.close()
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gate", action="store_true", help="exit 1 on any hit")
    ap.add_argument("--no-db", action="store_true", help="check the curated files only")
    args = ap.parse_args()
    problems = check_files()
    if not args.no_db and DB_PATH.exists():
        problems += check_db()
    for where, key, problem in problems:
        print(f"  {where} / {key}: {problem}")
    print(f"claim-language: {len(problems)} problem(s)")
    return 1 if (problems and args.gate) else 0


if __name__ == "__main__":
    sys.exit(main())
