#!/usr/bin/env python3
"""Every string the app can put on screen, checked for things that are not copy.

The bundled DB's text columns are written by extractors, by curation passes and
by research agents, and all three leak the same kinds of thing into prose a
reader eventually sees: a note to whoever curates next, an apology for missing
data, a citation token the renderer does not strip, a sentence that answers
"what did we do" rather than "what is this".

The checks are literal patterns, not judgment, and each one is here because it
was found in shipped text at least once. The report is a work-list, not a gate:
a hit is a string to look at, and `--gate` fails only on the categories that are
never acceptable (voice violations and unrendered markup).

    python3 pipeline/audit/ui_text.py                # report
    python3 pipeline/audit/ui_text.py --all          # every hit, not just 3 per rule
    python3 pipeline/audit/ui_text.py --gate         # exit 1 on a hard violation
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru" / "Data" / "piru-substances.sqlite"
USAGE = REPO / "data" / "snapshots" / "data-usage.json"

#: British spellings that turn up in pharmacology and label prose. Explicit,
#: because the endings they share (-ise, -our, -ogue) also belong to ordinary
#: words: `hours`, `dialogue`, `analogue`, `our`.
_BRITISH = (
    r"\b(?:"
    + "|".join(
        [
            r"priorit(?:ise|ised|ises|ising|isation)",
            r"organis(?:e|ed|es|ing|ation|ations)",
            r"recognis(?:e|ed|es|ing)",
            r"characteris(?:e|ed|es|ing|ation)",
            r"(?:mini|maxi|uti|norma|standardi|categori|metabo|summari|emphasi|specia|stabi)"
            r"lis(?:e|ed|es|ing|ation)",
            # `analyses` is the correct US plural of `analysis` and dominates this
            # corpus ("Pooled analyses of 199 trials"); only the verb forms are British.
            r"analys(?:e|ed|ing)",
            r"colour(?:s|ed|ing|less)?",
            r"behaviour(?:s|al|ally)?",
            r"(?:fav|flav|lab|hon|hum|od|vap|tum)our(?:s|ed|ing|able|ite|ites)?",
            r"centres?",
            r"litres?",
            r"fibres?",
            r"defence",
            r"practis(?:e|ed|es|ing)",
            r"aluminium",
            r"sulph(?:ur|ate|ates|ide|ides|onate|onates)",
            r"haemo(?:globin|lysis|rrhage|rrhagic|dynamic|dynamics)?",
            r"oedema(?:tous)?",
            r"anaemi(?:a|c)",
            r"paediatric(?:s)?",
            r"foet(?:al|us|uses)",
            r"aetiolog(?:y|ical)",
            r"oesophag(?:us|eal)",
            r"diarrhoea(?:l)?",
            r"leukaemi(?:a|c)",
            r"ageing",
            r"whilst",
            r"amongst",
            r"miscategoris(?:e|ed|es|ing)",
            r"grey(?:ish)?",
        ]
    )
    + r")\b"
)

#: (name, pattern, why, hard). `hard` categories fail `--gate`.
RULES: list[tuple[str, str, str, bool]] = [
    (
        "voice: harm reduction",
        r"\bharm[- ]reduction\b",
        "The repo's voice rule: the phrase implies the reader is guilty of "
        "something needing reducing. Banned in consumer copy (repo CLAUDE.md).",
        True,
    ),
    (
        "voice: told to consult someone",
        r"\b(consult|talk to|speak (to|with)|ask) (your |a )?(doctor|physician|"
        r"healthcare provider|pharmacist|medical professional)",
        "Piru is a reference, a record and a model — never advice. A line that "
        "closes with an instruction to go ask someone is advice-shaped filler "
        "that says nothing about the substance.",
        False,
    ),
    (
        "voice: British spelling",
        _BRITISH,
        "The repo is US English everywhere — code, comments and copy. A word "
        "list rather than a morphological rule, because -ise/-our/-ogue endings "
        "also belong to `hours`, `dialogue` and `analogue`.",
        False,
    ),
    (
        "markup: unrendered HTML",
        r"</?[a-zA-Z][a-zA-Z0-9]*(\s[^<>]{0,200})?/?>|&(amp|lt|gt|nbsp|#\d+);",
        "A tag or entity that survived extraction renders literally.",
        True,
    ),
    (
        "markup: source citation token",
        # A locant set in a systematic name — [1,2,4]triazolo, [4,3-a] — is the
        # same shape, so require the bracket to be free-standing: not glued to a
        # letter on either side, and not part of a hyphenated ring fusion.
        r"\[[AL]\d{4,}\]|\[\[?\d+(,\s*\d+)*\]\]?(?![-a-zA-Z])(?<![a-zA-Z]\[\d)"
        r"|\]\(#cite|\[需要引用\]|\[citation needed\]",
        "A source's own inline reference marker ([A174292], [[5]](#cite_note-…), "
        "[citation needed]) pointing at a bibliography the app does not ship.",
        True,
    ),
    (
        "meta: note to the next curator",
        r"\b(TODO|FIXME|XXX|TBD|NOTE:|FIXME:|see above|see below|as noted above|"
        r"needs (review|checking|a citation)|verify this|placeholder)\b",
        "Written for whoever edits next, not for a reader.",
        True,
    ),
    (
        "meta: first person / the project talking",
        # `us` needs a space in front or "en-US" and "thus" match it.
        r"(\bwe |\bour |(?<![-\w])us\b|\bPiru\b|\bthis app\b|\bthe app\b"
        r"|\bthe database\b|\bthe pipeline\b)",
        "The screen is about the substance. A sentence about what the project "
        "knows or did is the wrong subject.",
        False,
    ),
    (
        "filler: an apology for missing data",
        r"\b(no (human )?data (available|is available|yet)|not (yet )?(known|"
        r"established|characteri[sz]ed|available)|unknown at this time|"
        r"insufficient data|data (are|is) (lacking|limited|sparse))\b",
        "Saying a value is unknown is honest in a research note and noise in a "
        "list — an absent row already says it. Keep it only where a reader would "
        "otherwise assume the opposite.",
        False,
    ),
    (
        "filler: a heading stored as content",
        r"^(Mechanism [Oo]f [Aa]ction|Pharmacology|Indications?|Dosage|"
        r"Description|Overview|Effects?|Warnings?)[:\s]*$",
        "A section label ingested as the section's content.",
        True,
    ),
    (
        "shape: a paragraph where a phrase belongs",
        r"^.{400,}$",
        "Long enough that the row it sits in cannot show it. Not wrong, but it "
        "belongs in a disclosure or a summary field.",
        False,
    ),
]

#: Columns whose content is a name/identifier, where these patterns mean nothing.
SKIP_COLUMNS = {
    ("substances", "iupac_name"),
    ("substances", "smiles"),
    ("substances", "formula"),
    ("substances", "inchikey"),
    ("aliases", "alias"),
    ("aliases", "alias_normalized"),
    ("aliases", "locale"),
    ("citations", "title"),
    ("citations", "url"),
    ("molecule_shapes", "atoms_json"),
    ("molecule_shapes", "bonds_json"),
    ("spectrum_levels", "top_effects_json"),
    ("spectrum_levels", "warnings_json"),
}


def rendered_text_columns(db: sqlite3.Connection) -> list[tuple[str, str]]:
    """Every TEXT column the data-usage report says reaches a view.

    Reads that report rather than re-deriving it, so the two can't disagree
    about what is on screen. Falls back to every TEXT column when the snapshot
    is missing — over-reporting is the safe direction.
    """
    shown: set[tuple[str, str]] | None = None
    if USAGE.exists():
        report = json.loads(USAGE.read_text())
        shown = {
            (table, column)
            for table, spec in report.items()
            for column, col in spec["columns"].items()
            if col["verdict"] == "shown"
        }
    out: list[tuple[str, str]] = []
    for (table,) in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ):
        for row in db.execute(f'PRAGMA table_info("{table}")'):
            column, kind = row[1], (row[2] or "").upper()
            if "CHAR" not in kind and "TEXT" not in kind and "CLOB" not in kind:
                continue
            if (table, column) in SKIP_COLUMNS:
                continue
            if shown is not None and (table, column) not in shown:
                continue
            out.append((table, column))
    return sorted(out)


def scan(db: sqlite3.Connection, show_all: bool) -> dict[str, list[tuple[str, str, str]]]:
    hits: dict[str, list[tuple[str, str, str]]] = {name: [] for name, *_ in RULES}
    for table, column in rendered_text_columns(db):
        has_substance = any(
            r[1] == "substance_id" for r in db.execute(f'PRAGMA table_info("{table}")')
        )
        subject = (
            "(SELECT canonical_name FROM substances s WHERE s.id = t.substance_id)"
            if has_substance
            else "''"
        )
        rows = db.execute(
            f'SELECT {subject}, t."{column}" FROM "{table}" t '
            f'WHERE t."{column}" IS NOT NULL AND t."{column}" != ""'
        ).fetchall()
        for name, value in rows:
            text = str(value)
            for rule, pattern, _why, _hard in RULES:
                if re.search(pattern, text, re.IGNORECASE | re.MULTILINE):
                    if show_all or len(hits[rule]) < 3:
                        hits[rule].append((f"{table}.{column}", name or "—", text))
                    elif len(hits[rule]) == 3:
                        hits[rule].append((f"{table}.{column}", name or "—", ""))
    return hits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="every hit, not a sample")
    parser.add_argument("--gate", action="store_true", help="exit 1 on a hard violation")
    args = parser.parse_args()

    if not DB.exists():
        sys.exit(f"no database at {DB} — run pipeline/fetch-db.sh")
    db = sqlite3.connect(DB)

    # Counting needs every hit even when only a sample is printed.
    counted = scan(db, show_all=True)
    shown = counted if args.all else scan(db, show_all=False)

    hard_total = 0
    for rule, pattern, why, hard in RULES:
        found = counted[rule]
        if not found:
            continue
        if hard:
            hard_total += len(found)
        print("=" * 78)
        print(f"{rule.upper()}  —  {len(found)} string(s)" + ("   [hard]" if hard else ""))
        print(f"  {why}")
        print("=" * 78)
        for where, name, text in shown[rule]:
            if not text:
                print(f"  … and {len(found) - 3} more")
                continue
            excerpt = re.sub(r"\s+", " ", text)
            match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
            if match and len(excerpt) > 150:
                start = max(0, match.start() - 60)
                excerpt = ("…" if start else "") + excerpt[start : start + 150] + "…"
            print(f"  {where}  ({name})")
            print(f"    {excerpt}")
        print()

    total = sum(len(v) for v in counted.values())
    print(f"{total} string(s) flagged; {hard_total} in a category that is never acceptable.")
    return 1 if (args.gate and hard_total) else 0


if __name__ == "__main__":
    raise SystemExit(main())
