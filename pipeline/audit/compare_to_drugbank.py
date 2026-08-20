#!/usr/bin/env python3
"""Cross-check the resolved DB against a local DrugBank XML release.

DrugBank is a verification source, never a shipping source: none of its text
or numbers enter the bundled SQLite. This audit flags where our resolved
values disagree with DrugBank (a divergence is a pointer at a possible
problem on either side, not a verdict) and where DrugBank could seed
research — every seeded number must be verified against the primary source
it cites before it becomes a curated row.

Reads (both out of repo, both optional-but-one-required):
  ~/Developer/piru-data/external_database.xml   the DrugBank full-DB export
  ~/Developer/piru-data/drugbank-extract.json   compact cache of the fields
                                                this audit uses (built from
                                                the XML on first run; ~2 min)

Checks:
  - half-life: resolved value vs DrugBank's, where DrugBank's statement is
    clean enough to parse deterministically (single value or range with an
    explicit unit; multi-phase/population prose is skipped, never guessed at)
  - identity: name-matched substances whose InChIKeys disagree (full skeleton
    mismatch = possible identity error; same skeleton = salt/stereo variant)
  - CAS number conflicts
  - gaps: matched substances with no half_life row where DrugBank has a
    parseable value + the PubMed ids it cites (a research work-list)
  - identifier backfill candidates (Piru missing InChIKey/CAS)

Run from the repo root (output is regenerable working output, kept out of
the public repo because DrugBank's license restricts redistribution):
    python3 pipeline/audit/compare_to_drugbank.py \
        > data/snapshots/verification-dump/drugbank-crosscheck.md
    python3 pipeline/audit/compare_to_drugbank.py --re-extract   # after a new XML drop
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
PIRU_DATA = Path.home() / "Developer/piru-data"
XML_DEFAULT = PIRU_DATA / "external_database.xml"
CACHE_DEFAULT = PIRU_DATA / "drugbank-extract.json"

sys.path.insert(0, str(REPO / "pipeline/build"))  # canonical name normalization
from sqlite import normalise  # noqa: E402

NS = "{http://www.drugbank.ca}"

# ── Half-life statement parsing ──────────────────────────────────────────
# Only statements that pin down one point estimate or one range with an
# explicit unit are accepted. Anything else (multi-phase, per-population,
# metabolite half-lives, unitless numbers, "less than X") returns None:
# for a verification audit a skipped comparison is free, a wrong one isn't.

_CITATION_TOKEN = re.compile(r"\[(?:[ALTF]\d+)(?:\s*,\s*[ALTF]\d+)*\]")
_NUMBER = re.compile(r"\d+(?:\.\d+)?")
_QTY = re.compile(
    r"(?P<n1>\d+(?:\.\d+)?)\s*"
    r"(?:(?P<sep>to|and|[-–—±])\s*(?P<n2>\d+(?:\.\d+)?)\s*)?"
    r"(?P<unit>seconds?|minutes?|mins?|min|hours?|hrs?|hr|h|days?|weeks?)\b",
    re.IGNORECASE,
)
_UNIT_MINUTES = {
    "second": 1 / 60,
    "minute": 1.0,
    "min": 1.0,
    "hour": 60.0,
    "hr": 60.0,
    "h": 60.0,
    "day": 1440.0,
    "week": 10080.0,
}
# Words that mean the surviving quantity is a bound or a conditional, not a
# point estimate for the parent drug.
_REJECT_WORDS = re.compile(
    r"less than|greater than|more than|up to|exceed|at least|<|>"
    r"|metabolite|children|infant|neonat|elderly|renal|hepatic|impair",
    re.IGNORECASE,
)


def strip_citation_tokens(text: str) -> str:
    """Remove DrugBank inline citation tokens like [A174292] or [L41539, A3]."""
    return _CITATION_TOKEN.sub("", text)


def unit_factor(unit: str) -> float:
    u = unit.lower().rstrip("s")
    return _UNIT_MINUTES[u if u in _UNIT_MINUTES else u]


def parse_half_life(text: str) -> tuple[float, float] | None:
    """Parse a clean half-life statement to (lo, hi) minutes, else None.

    Accepts: "10 hours" / "9-11 hours" / "1 to 3 hours" / "3.5 ± 0.5 hours",
    optionally inside one plain sentence ("The average half-life is 4 hours.").
    Rejects anything with extra numbers, bounds ("less than"), semicolons, or
    population/metabolite qualifiers.
    """
    t = strip_citation_tokens(text or "").strip()
    if not t or len(t) > 160 or ";" in t or "\n" in t:
        return None
    if _REJECT_WORDS.search(t):
        return None
    m = _QTY.search(t)
    if not m:
        return None
    # Every digit in the statement must belong to the one quantity we matched —
    # a second number means phases/populations we refuse to arbitrate.
    expected = 2 if m.group("n2") else 1
    if len(_NUMBER.findall(t)) != expected:
        return None
    factor = unit_factor(m.group("unit"))
    n1 = float(m.group("n1"))
    if m.group("n2") is None:
        lo = hi = n1
    elif m.group("sep") == "±":
        spread = float(m.group("n2"))
        lo, hi = n1 - spread, n1 + spread
    else:
        lo, hi = sorted((n1, float(m.group("n2"))))
    if lo <= 0 or hi <= 0:
        return None
    return (lo * factor, hi * factor)


def inchikey_relation(a: str, b: str) -> str:
    """'match' | 'skeleton' (same connectivity block, salt/stereo variant) | 'mismatch'."""
    if a == b:
        return "match"
    if a[:14] == b[:14]:
        return "skeleton"
    return "mismatch"


def classify_ik_conflict(piru_name: str, db_name: str) -> str:
    """Why a name-matched pair carries conflicting InChIKeys.

    'identifier-error': the two records name the same drug, so one side's
    structure is wrong — on a full mismatch that is usually our side (an
    upstream import bug) and worth a PubChem check.
    'alias-collision': the match came through a shared alias on two different
    drugs (short codes like "MTA"/"MEM" collide constantly), i.e. the match
    itself is false.
    """
    return "identifier-error" if normalise(piru_name) == normalise(db_name) else "alias-collision"


# ── Extraction: DrugBank XML → compact cache ─────────────────────────────


def extract(xml_path: Path, cache_path: Path) -> None:
    import xml.etree.ElementTree as ET

    def txt(el, tag):
        c = el.find(NS + tag)
        return (c.text or "").strip() if c is not None and c.text else ""

    drugs = []
    exported_on = ""
    depth = 0
    n = 0
    for event, el in ET.iterparse(str(xml_path), events=("start", "end")):
        if event == "start":
            depth += 1
            if el.tag == NS + "drugbank":
                exported_on = el.get("exported-on", "")
            continue
        depth -= 1
        if not (el.tag == NS + "drug" and depth == 1):
            continue
        n += 1
        if n % 2000 == 0:
            print(f"  …{n} drugs", file=sys.stderr)

        inchikey = ""
        for p in el.findall(f"{NS}calculated-properties/{NS}property"):
            if txt(p, "kind") == "InChIKey":
                inchikey = txt(p, "value")
                break

        half_life = txt(el, "half-life")
        hl_pmids: list[str] = []
        if half_life:
            # Resolve the statement's inline [A…] tokens to PubMed ids.
            tokens = set(re.findall(r"[ALTF]\d+", " ".join(_CITATION_TOKEN.findall(half_life))))
            if tokens:
                for art in el.findall(f"{NS}general-references/{NS}articles/{NS}article"):
                    if txt(art, "ref-id") in tokens:
                        pmid = txt(art, "pubmed-id")
                        if pmid:
                            hl_pmids.append(pmid)

        drugs.append(
            {
                "id": txt(el, "drugbank-id"),
                "name": txt(el, "name"),
                "type": el.get("type", ""),
                "groups": sorted(
                    (g.text or "").strip() for g in el.findall(f"{NS}groups/{NS}group")
                ),
                "inchikey": inchikey,
                "cas": txt(el, "cas-number"),
                "synonyms": sorted(
                    {s.text.strip() for s in el.findall(f"{NS}synonyms/{NS}synonym") if s.text}
                ),
                "brands": sorted(
                    {
                        txt(b, "name")
                        for b in el.findall(f"{NS}international-brands/{NS}international-brand")
                        if txt(b, "name")
                    }
                ),
                "half_life": half_life,
                "hl_pmids": sorted(set(hl_pmids)),
            }
        )
        el.clear()

    drugs.sort(key=lambda d: d["id"])
    cache_path.write_text(
        json.dumps(
            {"exported_on": exported_on, "drug_count": len(drugs), "drugs": drugs},
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"  extracted {len(drugs)} drugs → {cache_path}", file=sys.stderr)


# ── Comparison ───────────────────────────────────────────────────────────

RATIO_HI = 2.0  # same bar as compare_to_pw: within 0.5×–2× is consistent


def build_indices(drugs: list[dict]):
    """InChIKey index + tiered name index (primary name > synonym > brand)."""
    by_ik: dict[str, dict] = {}
    by_name: dict[str, tuple[int, dict]] = {}

    def put_name(key: str, tier: int, drug: dict) -> None:
        if not key:
            return
        held = by_name.get(key)
        if held is None or tier < held[0]:
            by_name[key] = (tier, drug)

    for d in drugs:
        if d["inchikey"] and d["inchikey"] not in by_ik:
            by_ik[d["inchikey"]] = d
        put_name(normalise(d["name"]), 0, d)
        for s in d["synonyms"]:
            put_name(normalise(s), 1, d)
        for b in d["brands"]:
            put_name(normalise(b), 2, d)
    return by_ik, by_name


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--xml", type=Path, default=XML_DEFAULT)
    ap.add_argument("--cache", type=Path, default=CACHE_DEFAULT)
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--re-extract", action="store_true")
    args = ap.parse_args()

    if args.re_extract or not args.cache.exists():
        if not args.xml.exists():
            print(
                f"neither cache ({args.cache}) nor DrugBank XML ({args.xml}) present — "
                "this audit needs the private piru-data checkout",
                file=sys.stderr,
            )
            return 2
        print(f"extracting {args.xml} …", file=sys.stderr)
        extract(args.xml, args.cache)

    data = json.loads(args.cache.read_text(encoding="utf-8"))
    by_ik, by_name = build_indices(data["drugs"])

    db = sqlite3.connect(str(args.db))
    db.row_factory = sqlite3.Row
    priority = {
        r["slug"]: r["default_priority"]
        for r in db.execute("SELECT slug, default_priority FROM sources")
    }

    aliases = defaultdict(list)
    for r in db.execute("SELECT substance_id, alias_normalized FROM aliases"):
        aliases[r["substance_id"]].append(r["alias_normalized"])

    half_lives = defaultdict(list)
    for r in db.execute(
        """SELECT h.substance_id, h.half_life_minutes, src.slug AS source_slug
             FROM half_lives h JOIN sources src ON src.id = h.source_id"""
    ):
        half_lives[r["substance_id"]].append(r)

    substances = db.execute(
        """SELECT id, canonical_name, COALESCE(display_name, canonical_name) AS name,
                  inchikey, cas, popularity, display_class
             FROM substances"""
    ).fetchall()

    matched = []  # (substance_row, drugbank_drug, how, via_key)
    for s in substances:
        if s["inchikey"] and s["inchikey"] in by_ik:
            matched.append((s, by_ik[s["inchikey"]], "inchikey", ""))
            continue
        own_names = [normalise(s["canonical_name"]), normalise(s["name"])]
        for key in [*own_names, *aliases[s["id"]]]:
            held = by_name.get(key)
            if held:
                # Record the matching key when it was an alias rather than the
                # substance's own name — alias-mediated matches are where the
                # false positives live, so the report shows the evidence.
                matched.append((s, held[1], "name", "" if key in own_names else key))
                break

    hl_divergent, hl_gaps, hl_prose_gaps = [], [], []
    ik_conflicts, cas_conflicts, ik_backfill, cas_backfill = [], [], [], []
    hl_compared = 0

    for s, d, how, via in matched:
        # A name match whose InChIKeys fully mismatch is either a false match
        # (alias collision) or an identifier error — either way the two records
        # are different molecules, so it contributes to the identity section
        # ONLY. Letting it into the value comparisons is how a false match
        # seeds one drug's half-life onto another.
        if how == "name" and s["inchikey"] and d["inchikey"]:
            rel = inchikey_relation(s["inchikey"], d["inchikey"])
            if rel != "match":
                ik_conflicts.append((s, d, rel, classify_ik_conflict(s["name"], d["name"])))
            if rel == "mismatch":
                if s["cas"] and d["cas"] and s["cas"] != d["cas"]:
                    cas_conflicts.append((s, d))
                continue

        parsed = parse_half_life(d["half_life"]) if d["half_life"] else None

        rows = half_lives.get(s["id"], [])
        if rows:
            resolved = min(rows, key=lambda r: priority.get(r["source_slug"], 999))
            if parsed:
                hl_compared += 1
                lo, hi = parsed
                v = resolved["half_life_minutes"]
                ratio = (lo / v) if v < lo else (v / hi) if v > hi else 1.0
                if ratio >= RATIO_HI:
                    hl_divergent.append((s, d, how, via, resolved, parsed, ratio))
        elif parsed:
            hl_gaps.append((s, d, how, via, parsed))
        elif d["half_life"]:
            hl_prose_gaps.append((s, d))

        if s["cas"] and d["cas"] and s["cas"] != d["cas"]:
            cas_conflicts.append((s, d))
        if not s["inchikey"] and d["inchikey"]:
            ik_backfill.append((s, d))
        if not s["cas"] and d["cas"]:
            cas_backfill.append((s, d))

    # ── Report ───────────────────────────────────────────────────────────
    def pop(s) -> float:
        return s["popularity"] or 0

    def hours(minutes: float) -> str:
        return f"{minutes / 60:.1f}h" if minutes >= 60 else f"{minutes:.0f}m"

    def hl_str(parsed: tuple[float, float]) -> str:
        lo, hi = parsed
        return hours(lo) if lo == hi else f"{hours(lo)}–{hours(hi)}"

    print("# DrugBank cross-check audit\n")
    print(
        f"DrugBank export {data['exported_on']}, {data['drug_count']} drugs. "
        f"Matched {len(matched)} of {len(substances)} Piru substances "
        f"({sum(1 for *_, h, _ in matched if h == 'inchikey')} by InChIKey, "
        f"{sum(1 for *_, h, _ in matched if h == 'name')} by name/alias/brand).\n"
    )
    print(
        "DrugBank is a verification source: a divergence points attention at a "
        "possible problem on either side, and a gap-list value must be verified "
        "against the primary source it cites before it becomes a curated row.\n"
    )

    print(f"## Half-life divergences ({len(hl_divergent)} of {hl_compared} comparable)\n")
    print("Resolved value ≥2× outside DrugBank's stated value/range.\n")
    print("| Pop. | Substance | Piru (source) | DrugBank | Off by | Match | DrugBank id | PMIDs |")
    print("|---:|---|---|---|---|---|---|---|")
    for s, d, how, via, resolved, parsed, ratio in sorted(
        hl_divergent, key=lambda x: (-pop(x[0]), x[0]["name"])
    ):
        match_note = f"⚠ alias “{via}”" if via else how
        print(
            f"| {pop(s):.0f} | {s['name']} "
            f"| {hours(resolved['half_life_minutes'])} ({resolved['source_slug']}) "
            f"| {hl_str(parsed)} | {ratio:.1f}× | {match_note} | {d['id']} "
            f"| {' '.join(d['hl_pmids'])} |"
        )

    print(f"\n## Identity conflicts ({len(ik_conflicts)} InChIKey, {len(cas_conflicts)} CAS)\n")
    print(
        "Name-matched but chemically different — quarantined from every value "
        "comparison above. `skeleton` = same connectivity (salt/stereo variant, "
        "usually fine). A full mismatch is classified by cause: "
        "`identifier-error` = both records name the same drug, so one side's "
        "structure is wrong (usually ours — check against PubChem); "
        "`alias-collision` = the name match itself is false (two drugs sharing "
        "a short alias).\n"
    )
    print("| Substance | Relation | Cause | Piru InChIKey | DrugBank | DrugBank id |")
    print("|---|---|---|---|---|---|")
    for s, d, rel, cause in sorted(
        ik_conflicts, key=lambda x: (x[2] != "mismatch", x[3] != "identifier-error", -pop(x[0]))
    ):
        print(
            f"| {s['name']} | {rel} | {cause if rel == 'mismatch' else ''} "
            f"| {s['inchikey']} | {d['inchikey']} | {d['id']} ({d['name']}) |"
        )
    if cas_conflicts:
        print("\n| Substance | Piru CAS | DrugBank CAS | DrugBank id |")
        print("|---|---|---|---|")
        for s, d in sorted(cas_conflicts, key=lambda x: -pop(x[0])):
            print(f"| {s['name']} | {s['cas']} | {d['cas']} | {d['id']} ({d['name']}) |")

    print(f"\n## Half-life research work-list ({len(hl_gaps)} seeds)\n")
    print(
        "Matched substances with **no** half_life row anywhere, where DrugBank "
        "states a clean value. Verify against the cited primary source "
        "(`papers get <pmid>`), then record in `data/curated/` with a "
        "`halfLifeSource` — never copy the DrugBank number itself.\n"
    )
    print("| Pop. | Substance | Class | DrugBank states | PMIDs | DrugBank id | Matched via |")
    print("|---:|---|---|---|---|---|---|")
    for s, d, _how, via, parsed in sorted(hl_gaps, key=lambda x: (-pop(x[0]), x[0]["name"])):
        via_note = f"⚠ alias “{via}”" if via else ""
        print(
            f"| {pop(s):.0f} | {s['name']} | {s['display_class'] or ''} "
            f"| {hl_str(parsed)} | {' '.join(d['hl_pmids'])} | {d['id']} ({d['name']}) "
            f"| {via_note} |"
        )
    print(
        f"\nA further {len(hl_prose_gaps)} matched substances have no half_life row "
        "and a DrugBank statement too prose-y to parse — read those by hand "
        "from the cache (grep the substance name in drugbank-extract.json)."
    )

    print(
        f"\n## Identifier backfill candidates "
        f"({len(ik_backfill)} missing InChIKey, {len(cas_backfill)} missing CAS)\n"
    )
    print("Flag-only: verify against PubChem before writing curated identifiers.\n")
    print("| Pop. | Substance | Missing | DrugBank has | DrugBank id |")
    print("|---:|---|---|---|---|")
    for s, d in sorted(ik_backfill, key=lambda x: -pop(x[0]))[:40]:
        print(
            f"| {pop(s):.0f} | {s['name']} | inchikey | {d['inchikey']} | {d['id']} ({d['name']}) |"
        )
    for s, d in sorted(cas_backfill, key=lambda x: -pop(x[0]))[:15]:
        print(f"| {pop(s):.0f} | {s['name']} | cas | {d['cas']} | {d['id']} ({d['name']}) |")

    return 0


if __name__ == "__main__":
    sys.exit(main())
