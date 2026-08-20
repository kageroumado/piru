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
  - enzyme coverage: DrugBank calls the substance a substrate of an enzyme no
    `metabolism` row names. This one reports an ABSENCE with a user-visible
    consequence: the app joins its modulator catalog (grapefruit/CYP3A4,
    smoking/CYP1A2, ...) against that table on the substrate side, so a
    substance with no row shows no modulator card at all — silently, with no
    empty state anyone could notice.
  - metabolizer status: a CYP2D6 substrate with no `pharmacogenetics` row, so
    the poor/rapid readout codeine has cannot fire for it
  - metabolite coverage: products of a DrugBank reaction FROM the substance
    that no `metabolism` row names (conjugates excluded — excretion products,
    not pharmacology)
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
ADJUDICATIONS = REPO / "data/curated/drugbank-adjudications.json"
#: Bumped whenever `extract` starts capturing a new field. A cache written by an
#: older version is re-extracted rather than read: the checks below report
#: ABSENCE, so a cache silently missing a field would report "nothing to fix".
CACHE_VERSION = 2
PIRU_DATA = Path.home() / "Developer/piru-data"
XML_DEFAULT = PIRU_DATA / "external_database.xml"
CACHE_DEFAULT = PIRU_DATA / "drugbank-extract.json"

sys.path.insert(0, str(REPO / "pipeline/build"))  # canonical name normalization
from sqlite import normalise  # noqa: E402

NS = "{http://www.drugbank.ca}"

#: The enzymes Piru's readouts key on, mapped to the token that must appear in a
#: `metabolism.enzyme` cell and to what the user loses when no row names it.
#: These mirror `MetabolicModulation.Enzyme` in the app: the modulator catalog
#: (grapefruit/3A4, smoking/1A2, ...) is joined against the metabolism table on
#: the SUBSTRATE side, so a substance with no row for an enzyme silently shows
#: no modulator card at all -- an absence no in-app check can see.
UI_ENZYMES = {
    "CYP3A4": "grapefruit / ritonavir / carbamazepine modulators",
    "CYP1A2": "smoking modulator",
    "CYP2D6": "metabolizer-status readout",
    "CYP2C19": "modulator readout",
    "CYP2C9": "modulator readout",
    "CYP2B6": "modulator readout",
}

#: DrugBank writes enzymes out in full ("Cytochrome P450 3A4"); the metabolism
#: table and the app both key on the short gene token.
_CYP_NAME = re.compile(r"cytochrome\s+p450\s+([0-9]+[a-z]+[0-9]+)", re.IGNORECASE)


#: Stereo/positional descriptors that are pure spelling: DrugBank writes
#: "Dextroamphetamine" where the catalog writes "d-amphetamine", and
#: "m-chlorophenylpiperazine" where it writes "meta-chlorophenylpiperazine".
#: Only forms that are unambiguously the SAME compound belong here. N- and O-
#: are deliberately absent: N-desmethyltramadol and O-desmethyltramadol are
#: different metabolites (one is the active opioid, one is not), and collapsing
#: them would report a metabolite as covered when a different one is.
_METABOLITE_PREFIX = [
    ("dextro", "d"),
    ("levo", "l"),
    ("meta-", "m"),
    ("para-", "p"),
]


def metabolite_key(name: str) -> set[str]:
    """Comparable keys for a metabolite name, spelling folded out.

    Returns more than one key when the name carries a parenthetical short form —
    "m-chlorophenylpiperazine (m-CPP)" is filed under both the long name and
    "mcpp", because either side may use either.
    """
    raw = (name or "").strip().lower()
    if not raw:
        return set()
    parts = [re.sub(r"\([^)]*\)", " ", raw)] + re.findall(r"\(([^)]*)\)", raw)
    keys = set()
    for part in parts:
        text = part.strip()
        for long_form, short in _METABOLITE_PREFIX:
            if text.startswith(long_form):
                text = short + text[len(long_form) :]
        text = re.sub(r"[^a-z0-9]+", "", text)
        if len(text) >= 3:
            keys.add(text)
    return keys


def cyp_token(drugbank_enzyme_name: str) -> str | None:
    """'Cytochrome P450 3A4' -> 'CYP3A4'. None when it is not a CYP."""
    m = _CYP_NAME.search(drugbank_enzyme_name or "")
    return f"CYP{m.group(1).upper()}" if m else None


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

        enzymes = []
        for enz in el.findall(f"{NS}enzymes/{NS}enzyme"):
            actions = [a.text.strip() for a in enz.findall(f"{NS}actions/{NS}action") if a.text]
            enzymes.append({"name": txt(enz, "name"), "actions": sorted(set(actions))})

        reactions = []
        for rx in el.findall(f"{NS}reactions/{NS}reaction"):
            left, right = rx.find(f"{NS}left-element"), rx.find(f"{NS}right-element")
            reactions.append(
                {
                    "from": txt(left, "name") if left is not None else "",
                    "to": txt(right, "name") if right is not None else "",
                    "enzymes": sorted(
                        {
                            txt(x, "name")
                            for x in rx.findall(f"{NS}enzymes/{NS}enzyme")
                            if txt(x, "name")
                        }
                    ),
                }
            )

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
                "enzymes": enzymes,
                "reactions": reactions,
                "food": [
                    f.text.strip()
                    for f in el.findall(f"{NS}food-interactions/{NS}food-interaction")
                    if f.text
                ],
                "snp_genes": sorted(
                    {
                        txt(s, "gene-symbol")
                        for s in el.findall(f"{NS}snp-effects/{NS}effect")
                        if txt(s, "gene-symbol")
                    }
                ),
            }
        )
        el.clear()

    drugs.sort(key=lambda d: d["id"])
    cache_path.write_text(
        json.dumps(
            {
                "cache_version": CACHE_VERSION,
                "exported_on": exported_on,
                "drug_count": len(drugs),
                "drugs": drugs,
            },
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

    stale = False
    if args.cache.exists() and not args.re_extract:
        try:
            cached = json.loads(args.cache.read_text(encoding="utf-8"))
            stale = cached.get("cache_version", 1) < CACHE_VERSION
        except (json.JSONDecodeError, OSError):
            stale = True
        if stale:
            print(
                f"cache predates CACHE_VERSION {CACHE_VERSION} — re-extracting so the "
                "absence checks read real data",
                file=sys.stderr,
            )
    if args.re_extract or stale or not args.cache.exists():
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

    # Settled questions stay settled: a divergence we already checked against a
    # primary source, and a substance that honestly has no single half-life, are
    # not new work. Delete an entry to put its substance back on the list.
    adjudicated_div: set[str] = set()
    adjudicated_gap: set[str] = set()
    adjudicated_enzyme: set[str] = set()
    adjudicated_metabolite: set[str] = set()
    adjudicated_metabolizer: set[str] = set()
    if ADJUDICATIONS.exists():
        adj = json.loads(ADJUDICATIONS.read_text(encoding="utf-8"))
        adjudicated_div = {normalise(e["substance"]) for e in adj.get("half_life_divergences", [])}
        adjudicated_gap = {normalise(e["substance"]) for e in adj.get("half_life_unresolvable", [])}
        adjudicated_enzyme = {normalise(e["substance"]) for e in adj.get("enzyme_coverage", [])}
        adjudicated_metabolizer = {
            normalise(e["substance"]) for e in adj.get("metabolizer_coverage", [])
        }
        adjudicated_metabolite = {
            normalise(e["substance"]) for e in adj.get("metabolite_coverage", [])
        }

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

    metabolism = defaultdict(list)
    for r in db.execute("SELECT substance_id, enzyme, metabolite_name FROM metabolism"):
        metabolism[r["substance_id"]].append((r["enzyme"] or "", r["metabolite_name"] or ""))
    pgx_genes = defaultdict(set)
    for r in db.execute("SELECT substance_id, gene FROM pharmacogenetics"):
        pgx_genes[r["substance_id"]].add((r["gene"] or "").upper())

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
    enzyme_gaps, metabolite_gaps, pgx_gaps = [], [], []
    ik_conflicts, cas_conflicts, ik_backfill, cas_backfill = [], [], [], []
    hl_compared = 0
    n_adjudicated_div = n_adjudicated_gap = 0

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
                    if normalise(s["name"]) in adjudicated_div:
                        n_adjudicated_div += 1
                    else:
                        hl_divergent.append((s, d, how, via, resolved, parsed, ratio))
        elif parsed:
            if normalise(s["name"]) in adjudicated_gap:
                n_adjudicated_gap += 1
            else:
                hl_gaps.append((s, d, how, via, parsed))
        elif d["half_life"]:
            hl_prose_gaps.append((s, d))

        # ── Enzyme coverage: what the app can no longer say ──────────────
        # Only a DrugBank *substrate* role means this enzyme clears the drug;
        # inhibitor/inducer rows describe what it does to OTHER drugs and would
        # point the modulator readout the wrong way round.
        db_substrate_cyps = {
            tok
            for e in d.get("enzymes", ())
            if "substrate" in e.get("actions", ())
            for tok in [cyp_token(e.get("name", ""))]
            if tok in UI_ENZYMES
        }
        ours = " ".join(enz for enz, _ in metabolism.get(s["id"], ())).upper()
        missing = sorted(tok for tok in db_substrate_cyps if tok not in ours)
        if missing and normalise(s["name"]) not in adjudicated_enzyme:
            grapefruit = any("grapefruit" in f.lower() for f in d.get("food", ()))
            # Two different findings wear the same shape. A substance naming NO
            # UI enzyme has every modulator readout silently switched off, and
            # that is a defect. One that names some, where DrugBank lists more,
            # is usually DrugBank cataloguing a minor pathway -- alprazolam is
            # 3A4-cleared and already shows its grapefruit card, so a "2C9
            # substrate" row changes nothing a reader would see. Keep the two
            # apart or the real ones drown.
            covered = {tok for tok in UI_ENZYMES if tok in ours}
            tier = "none" if not covered else "partial"
            # Grapefruit is CYP3A4's card specifically, so it can only be
            # missing when 3A4 itself is unnamed.
            blocks_grapefruit = grapefruit and "CYP3A4" not in ours
            enzyme_gaps.append((s, d, missing, blocks_grapefruit, tier))

        # ── Metabolites DrugBank names and we do not carry ────────────────
        parent = normalise(d["name"])
        ours_metab: set[str] = set()
        for _, metabolite in metabolism.get(s["id"], ()):
            ours_metab |= metabolite_key(metabolite)
        fresh = sorted(
            {
                rx["to"]
                for rx in d.get("reactions", ())
                if rx.get("to")
                and normalise(rx.get("from", "")) == parent
                and not (metabolite_key(rx["to"]) & ours_metab)
                # A glucuronide/sulfate conjugate is an excretion product, not a
                # metabolite with pharmacology worth showing.
                and not re.search(r"glucuronide|sulfate|conjugate", rx["to"], re.IGNORECASE)
            }
        )
        if fresh and normalise(s["name"]) not in adjudicated_metabolite:
            metabolite_gaps.append((s, d, fresh))

        # ── Pharmacogenetics the enzyme data implies ──────────────────────
        # CYP2D6 is the gene the app has a metabolizer readout for, so a 2D6
        # substrate with no pharmacogenetics row is a missing toggle. Adjudicate
        # under `metabolizer_coverage` where the substance is a 2D6 substrate only
        # in the in-vitro sense: many are, and for them the honest row is the one
        # naming the gene that does move the drug (nicotine's CYP2A6, simvastatin's
        # SLCO1B1) or none at all.
        if (
            "CYP2D6" in db_substrate_cyps
            and "CYP2D6" not in pgx_genes.get(s["id"], set())
            and normalise(s["name"]) not in adjudicated_metabolizer
        ):
            pgx_gaps.append((s, d))

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
    if n_adjudicated_div:
        print(
            f"{n_adjudicated_div} further divergence(s) are adjudicated in "
            "`data/curated/drugbank-adjudications.json` and not listed.\n"
        )
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
    if n_adjudicated_gap:
        print(
            f"{n_adjudicated_gap} further gap(s) are adjudicated as having no honest "
            "single value in `data/curated/drugbank-adjudications.json` and not listed.\n"
        )
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

    uncovered = [g for g in enzyme_gaps if g[4] == "none"]
    partial = [g for g in enzyme_gaps if g[4] == "partial"]
    blocked = [g for g in enzyme_gaps if g[3]]
    print(f"\n## Enzyme coverage gaps ({len(uncovered)} with no coverage at all)\n")
    print(
        "DrugBank lists the substance as a **substrate**, and no `metabolism` row "
        "names any enzyme the app keys on. The modulator catalog is joined against "
        "that table on the substrate side, so every readout is silently switched "
        "off — no warning, no empty state, nothing to notice. "
        f"⚠ marks the {len(blocked)} where DrugBank's food-interaction text names "
        "grapefruit outright and no CYP3A4 row exists to hang the card on.\n"
    )
    print(
        "| Pop. | Substance | DrugBank says substrate of | What the app cannot show | DrugBank id |"
    )
    print("|---:|---|---|---|---|")
    for s, d, missing, grapefruit, _tier in sorted(
        uncovered, key=lambda x: (not x[3], -pop(x[0]), x[0]["name"])
    ):
        loses = " · ".join(sorted({UI_ENZYMES[t] for t in missing}))
        flag = " ⚠ grapefruit" if grapefruit else ""
        print(f"| {pop(s):.0f} | {s['name']} | {', '.join(missing)}{flag} | {loses} | {d['id']} |")
    print(
        f"\nA further {len(partial)} substance(s) already name a UI enzyme where "
        "DrugBank lists additional ones. Advisory only: DrugBank catalogs minor "
        "pathways, and a drug already showing its modulator card gains nothing a "
        "reader would see.\n"
    )

    print(f"\n## Metabolizer-status gaps ({len(pgx_gaps)})\n")
    print(
        "A CYP2D6 substrate with no `pharmacogenetics` row: the poor/rapid "
        "metabolizer readout has nothing to key on, though the enzyme that makes "
        "it matter is the same one codeine's toggle uses.\n"
    )
    print("| Pop. | Substance | DrugBank id |")
    print("|---:|---|---|")
    for s, d in sorted(pgx_gaps, key=lambda x: (-pop(x[0]), x[0]["name"]))[:60]:
        print(f"| {pop(s):.0f} | {s['name']} | {d['id']} |")

    print(f"\n## Metabolite coverage gaps ({len(metabolite_gaps)})\n")
    print(
        "Products of a DrugBank metabolic reaction FROM this substance that no "
        "`metabolism` row names. Conjugates are excluded — they are excretion "
        "products, not pharmacology. A metabolite that is itself a substance we "
        "carry should be LINKED (`metabolite_substance_id`), not copied.\n"
    )
    print("| Pop. | Substance | Metabolites DrugBank names | DrugBank id |")
    print("|---:|---|---|---|")
    for s, d, fresh in sorted(metabolite_gaps, key=lambda x: (-pop(x[0]), x[0]["name"]))[:60]:
        print(f"| {pop(s):.0f} | {s['name']} | {', '.join(fresh[:4])} | {d['id']} |")

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
