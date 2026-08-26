#!/usr/bin/env python3
"""Seed a half-life from the paper DrugBank cites — never from DrugBank itself.

DrugBank knows where the numbers came from; that is the only thing taken from
it. For every substance with no `half_lives` row whose DrugBank record states a
half-life and cites a PubMed id, the cited paper is fetched into the local
`papers` cache, scanned for its own half-life sentence, and the two are
compared. A paper that independently states a consistent value yields a curated
row carrying **the paper's** number and **the paper's** citation. Anything else
stays on the work-list with the reason, and nothing DrugBank wrote enters the
repo.

The comparison is the safety property: a resolvable citation is not an on-topic
one, so the paper has to say the thing before its identifier may be attached to
a number.

    python3 pipeline/audit/halflife_from_primary.py            # report only
    python3 pipeline/audit/halflife_from_primary.py --fetch     # + fill the papers cache
    python3 pipeline/audit/halflife_from_primary.py --fetch --write

`--write` merges resolved rows into `data/curated/half-lives.json`, which
`pipeline/build.sh fast` then ingests under the `peer-review-primary` source.
Re-running is idempotent: a substance that already has a row is no longer a
candidate.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
CURATED = REPO / "data/curated/half-lives.json"
ADJUDICATIONS = REPO / "data/curated/drugbank-adjudications.json"
CACHE = Path.home() / "Developer/piru-data/drugbank-extract.json"

sys.path.insert(0, str(REPO / "pipeline/build"))
sys.path.insert(0, str(REPO / "pipeline/fetch/brushers"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import normalize_quantity_text  # noqa: E402
from compare_to_drugbank import (  # noqa: E402
    _REJECT_WORDS,
    _UNIT_MINUTES,
    build_indices,
    inchikey_relation,
    strip_citation_tokens,
)
from europepmc import client as europepmc  # noqa: E402
from sqlite import normalise  # noqa: E402

#: How far apart two independently stated values may be and still count as the
#: same claim. Papers and label summaries round differently and quote different
#: study arms; beyond a quarter they are describing different things.
AGREEMENT_RATIO = 1.25

#: A sentence is about elimination when it says so. `t½`/`t1/2` included because
#: pharmacokinetic papers use the symbol far more often than the words.
_HALF_LIFE = re.compile(r"half[-\s]?li(?:fe|ves)|t\s*(?:1/2|½)|t½", re.IGNORECASE)

_QTY = re.compile(
    r"(?P<n1>\d+(?:\.\d+)?)\s*"
    r"(?:(?P<sep>to|and|[-–—±])\s*(?P<n2>\d+(?:\.\d+)?)\s*)?"
    r"(?P<unit>seconds?|minutes?|mins?|min|hours?|hrs?|hr|h|days?|weeks?)\b",
    re.IGNORECASE,
)

#: Sentence enders, kept crude on purpose: a split that occasionally keeps two
#: clauses together costs a wider quote, while an aggressive one severs a value
#: from the drug name that qualifies it.
_SENTENCE = re.compile(r"(?<=[.!?])\s+(?=[A-Z(])|\n{2,}")

#: A value measured under a condition is not the population value. Every one of
#: these was a wrong row in the first run: amiodarone's 100 days is its half-life
#: *after withdrawal of long-term treatment*, which is why it is 2× the figure
#: any label carries.
_CONDITIONAL = re.compile(
    r"withdrawal|discontinuation|cessation|long[-\s]?term|chronic(?:ally)?|overdose|poisoning",
    re.IGNORECASE,
)

#: Human PK only. A number measured in a rat is not a number for a person, and
#: an abstract that says so says so in one of these words.
_NONHUMAN = re.compile(
    r"\brats?\b|\bmice\b|\bmouse\b|\brabbits?\b|\bdogs?\b|\bcanine\b|\bmonkeys?\b"
    r"|non[-\s]?human primates?|\bprimates?\b|\bin vitro\b|\bporcine\b|\bbovine\b|\bequine\b",
    re.IGNORECASE,
)

#: The phase modifiers that mean the number is NOT the elimination half-life.
#: "absorbed with a half-life of 1 to 4 hours" is an absorption constant; a
#: distribution or alpha-phase half-life is the fast limb of a biphasic curve.
_WRONG_PHASE = re.compile(
    r"(?:absorb\w*|absorption|distribution|distributive|alpha|α|initial|first|rapid)"
    r"[^.]{0,30}$",
    re.IGNORECASE,
)

#: Where the half-life's own clause ends. A quantity past one of these belongs to
#: a different parameter — mefloquine's "time to peak concentration of 7 to 24
#: hours" sat two words after a half-life and was read as one.
_OTHER_PARAMETER = re.compile(
    r"\b(?:t\s*max|c\s*max|auc|mrt|clearance|volume|residence|peak|onset|duration|bioavailab\w*"
    r"|concentration|dose[ds]?|interval|weeks? of|days? of|suggest\w*|indicat\w*)\b",
    re.IGNORECASE,
)

#: A salt or ester is a different molecule with its own kinetics. When the only
#: sentence backing a number names one, the number is not the parent's.
_MODIFIER = re.compile(
    r"\s+(?:acetonide|hexacetonide|acetate|propionate|dipropionate|furoate|valerate"
    r"|decanoate|enanthate|palmitate|pivalate|succinate|phosphate|tromethamine"
    r"|besylate|mesylate|maleate|tartrate|citrate|fumarate)\b",
    re.IGNORECASE,
)

#: How far past the words "half-life" a value may sit and still be its value.
_CLAUSE_WINDOW = 60


def _to_minutes(unit: str) -> float:
    return _UNIT_MINUTES[unit.lower().rstrip("s")]


def sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENTENCE.split(text or "") if s.strip()]


def name_tokens(name: str) -> set[str]:
    """Stems a paper would spell the drug with, ignoring salts and short words.

    'Losartan potassium' -> {'losartan'}. Words under five letters are dropped:
    they collide with ordinary prose ('acid', 'oil') far more often than they
    identify a drug.
    """
    parts = re.split(r"[^a-z0-9]+", name.lower())
    drop = {"acid", "sodium", "potassium", "hydrochloride", "sulfate", "salt", "free", "base"}
    return {p for p in parts if len(p) >= 5 and p not in drop}


def _quantity(match: re.Match[str]) -> tuple[float, float] | None:
    factor = _to_minutes(match.group("unit"))
    n1 = float(match.group("n1"))
    if match.group("n2") is None:
        lo = hi = n1
    elif match.group("sep") == "±":
        spread = float(match.group("n2"))
        lo, hi = n1 - spread, n1 + spread
    else:
        lo, hi = sorted((n1, float(match.group("n2"))))
    if lo <= 0 or hi <= 0:
        return None
    return (lo * factor, hi * factor)


def names_bare_drug(sentence: str, tokens: set[str]) -> bool:
    """The sentence names the drug itself, not one of its esters."""
    lowered = sentence.lower()
    for token in tokens:
        for m in re.finditer(re.escape(token), lowered):
            if not _MODIFIER.match(lowered[m.end() :]):
                return True
    return False


def claims(text: str, tokens: set[str], require_name: bool) -> list[tuple[float, float, str]]:
    """Half-life intervals a text states, in minutes, with the sentence each came from.

    A quantity counts only when it sits in the half-life's own clause: after the
    words, before whatever names a different parameter, within
    ``_CLAUSE_WINDOW`` characters. Reading every quantity in the sentence
    instead is how a Tmax, a sampling window and a monkey's response duration
    all became half-lives on the first run.

    `require_name` gates on the drug being named — used for papers, which
    discuss more than one compound. A DrugBank half-life field is already about
    one drug and rarely repeats the name, so it does not take the gate.
    """
    found: list[tuple[float, float, str]] = []
    for sentence in sentences(text):
        clean = normalize_quantity_text(strip_citation_tokens(sentence))
        if _REJECT_WORDS.search(clean) or _CONDITIONAL.search(clean) or _NONHUMAN.search(clean):
            continue
        if require_name and not names_bare_drug(clean, tokens):
            continue
        for phrase in _HALF_LIFE.finditer(clean):
            if _WRONG_PHASE.search(clean[: phrase.start()]):
                continue
            window = clean[phrase.end() : phrase.end() + _CLAUSE_WINDOW]
            boundary = _OTHER_PARAMETER.search(window)
            if boundary:
                window = window[: boundary.start()]
            quantity = _QTY.search(window)
            if quantity is None:
                continue
            parsed = _quantity(quantity)
            if parsed:
                found.append((*parsed, clean))
    return found


def agrees(a: tuple[float, float, str], b: tuple[float, float, str]) -> bool:
    """Two stated intervals describe the same value."""
    alo, ahi, _ = a
    blo, bhi, _ = b
    if alo <= bhi and blo <= ahi:
        return True
    amid, bmid = (alo * ahi) ** 0.5, (blo * bhi) ** 0.5
    hi, lo = max(amid, bmid), min(amid, bmid)
    return lo > 0 and hi / lo <= AGREEMENT_RATIO


def midpoint(interval: tuple[float, float, str]) -> float:
    lo, hi, _ = interval
    value = lo if lo == hi else (lo * hi) ** 0.5
    return round(value, 1 if value < 60 else 0)


# ── the papers cache ─────────────────────────────────────────────────────


def paper_path(pmid: str, fetch: bool) -> Path | None:
    if shutil.which("papers") is None:
        return None
    if fetch:
        subprocess.run(
            ["papers", "get", f"pmid:{pmid}"],
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
        )
    got = subprocess.run(
        ["papers", "path", f"pmid:{pmid}"], capture_output=True, text=True, check=False
    )
    if got.returncode != 0:
        return None
    path = Path(got.stdout.strip())
    return path if path.is_file() else None


def front_matter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    fields = {}
    for line in text[3:end].splitlines():
        if ":" in line:
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip().strip('"')
    return fields


def paper_text(pmid: str, fetch: bool) -> tuple[str, str]:
    """Everything readable for a paper, and where it came from.

    The papers cache first: it holds full text where a copy could be got. Most
    of the pharmacokinetics DrugBank cites is 1980s journal material behind a
    paywall, which the cache records as `closed` with no text at all — for those
    Europe PMC's abstract is what a reader can actually see, and a half-life is
    one of the few numbers an abstract reliably states. The provenance is
    returned alongside so the report never implies a paper was read whole.
    """
    path = paper_path(pmid, fetch)
    if path is not None:
        text = path.read_text(encoding="utf-8", errors="replace")
        if len(text) > 2000:
            return text, front_matter(text).get("status", "ok")
    record = europepmc().by_id(pmid=pmid)
    if record is None:
        return "", "unreachable"
    text = europepmc().text_for(record)
    return text, ("open access" if record.pmcid and record.full_text else "abstract")


# ── candidates ───────────────────────────────────────────────────────────


def candidates(db_path: Path, cache_path: Path) -> list[dict]:
    """Substances with no half-life, whose DrugBank record cites a PubMed id."""
    data = json.loads(cache_path.read_text(encoding="utf-8"))
    _by_ik, by_name = build_indices(data["drugs"])
    by_ik = {d["inchikey"]: d for d in data["drugs"] if d["inchikey"]}

    unresolvable: set[str] = set()
    if ADJUDICATIONS.exists():
        adj = json.loads(ADJUDICATIONS.read_text(encoding="utf-8"))
        unresolvable = {normalise(e["substance"]) for e in adj.get("half_life_unresolvable", [])}

    db = sqlite3.connect(str(db_path))
    db.row_factory = sqlite3.Row
    has_half_life = {r[0] for r in db.execute("SELECT DISTINCT substance_id FROM half_lives")}
    aliases = defaultdict(list)
    for r in db.execute("SELECT substance_id, alias_normalized FROM aliases"):
        aliases[r["substance_id"]].append(r["alias_normalized"])

    out = []
    for s in db.execute(
        "SELECT id, canonical_name, COALESCE(display_name, canonical_name) AS name,"
        "       inchikey, popularity FROM substances"
    ):
        if s["id"] in has_half_life or normalise(s["canonical_name"]) in unresolvable:
            continue
        drug = by_ik.get(s["inchikey"]) if s["inchikey"] else None
        matched_by = "inchikey"
        if drug is None:
            for key in [normalise(s["canonical_name"]), normalise(s["name"]), *aliases[s["id"]]]:
                held = by_name.get(key)
                if held:
                    drug, matched_by = held[1], "name"
                    break
        if drug is None or not drug["hl_pmids"]:
            continue
        # A name match on chemically different records is a false match; letting
        # it through is how one drug's literature gets attached to another.
        if (
            matched_by == "name"
            and s["inchikey"]
            and drug["inchikey"]
            and inchikey_relation(s["inchikey"], drug["inchikey"]) == "mismatch"
        ):
            continue
        stated = claims(drug["half_life"], set(), require_name=False)
        if not stated:
            continue
        out.append(
            {
                "substance": s["canonical_name"],
                "display": s["name"],
                "popularity": s["popularity"] or 0,
                "pmids": drug["hl_pmids"],
                "stated": stated,
                "tokens": name_tokens(s["canonical_name"]) | name_tokens(drug["name"]),
            }
        )
    out.sort(key=lambda c: (-c["popularity"], c["substance"]))
    return out


def resolve(candidate: dict, fetch: bool) -> dict:
    """Compare each cited paper against the statement it was cited for."""
    reasons = []
    for pmid in candidate["pmids"]:
        text, provenance = paper_text(pmid, fetch)
        if not text:
            reasons.append(f"pmid:{pmid} unreachable")
            continue
        found = claims(text, candidate["tokens"], require_name=True)
        if not found:
            reasons.append(f"pmid:{pmid} states no half-life for it ({provenance})")
            continue
        for paper_claim in found:
            if any(agrees(paper_claim, stated) for stated in candidate["stated"]):
                return {
                    "substance": candidate["substance"],
                    "half_life_minutes": midpoint(paper_claim),
                    "citation": f"pmid:{pmid}",
                    "quote": paper_claim[2][:400],
                    "read": provenance,
                }
        reasons.append(f"pmid:{pmid} disagrees ({fmt(found[0])}, {provenance})")
    return {"substance": candidate["substance"], "reasons": reasons}


def fmt(interval: tuple[float, float, str]) -> str:
    lo, hi, _ = interval

    def one(v: float) -> str:
        return f"{v / 60:.1f}h" if v >= 60 else f"{v:.0f}m"

    return one(lo) if lo == hi else f"{one(lo)}–{one(hi)}"


def merge_curated(rows: list[dict]) -> tuple[int, int]:
    payload = {"entries": []}
    if CURATED.exists():
        payload = json.loads(CURATED.read_text(encoding="utf-8"))
    held = {normalise(e["substance"]): e for e in payload.get("entries", [])}
    added = updated = 0
    for row in rows:
        key = normalise(row["substance"])
        if key in held:
            if held[key] != row:
                held[key] = row
                updated += 1
        else:
            held[key] = row
            added += 1
    payload["entries"] = sorted(held.values(), key=lambda e: e["substance"].lower())
    CURATED.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return added, updated


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", type=Path, default=DB)
    ap.add_argument("--cache", type=Path, default=CACHE)
    ap.add_argument("--fetch", action="store_true", help="fill the papers cache as it goes")
    ap.add_argument("--write", action="store_true", help="merge resolved rows into curated JSON")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    if not args.cache.exists():
        print(
            f"no DrugBank cache at {args.cache} — this needs the piru-data checkout",
            file=sys.stderr,
        )
        return 2

    pending = candidates(args.db, args.cache)
    if args.limit:
        pending = pending[: args.limit]
    print("# Half-life seeding from cited primary sources\n", file=sys.stderr)
    print(f"{len(pending)} candidate substance(s) with a cited statement.\n", file=sys.stderr)

    resolved, unresolved = [], []
    for i, candidate in enumerate(pending, 1):
        print(f"  [{i}/{len(pending)}] {candidate['substance']}", file=sys.stderr)
        result = resolve(candidate, args.fetch)
        (resolved if "half_life_minutes" in result else unresolved).append(result)

    print(f"## Resolved ({len(resolved)})\n")
    print(
        "Value and citation both come from the paper; DrugBank only pointed at it. "
        "`Read` says how much of the paper backs the number — `abstract` means the "
        "sentence quoted is all a reader can reach.\n"
    )
    print("| Substance | Half-life | Citation | Read |")
    print("|---|---:|---|---|")
    for r in sorted(resolved, key=lambda r: r["substance"].lower()):
        minutes = r["half_life_minutes"]
        pretty = f"{minutes / 60:.1f} h" if minutes >= 60 else f"{minutes:g} min"
        print(f"| {r['substance']} | {pretty} | {r['citation']} | {r['read']} |")

    print(f"\n## Not resolved ({len(unresolved)})\n")
    print("| Substance | Why |")
    print("|---|---|")
    for r in sorted(unresolved, key=lambda r: r["substance"].lower()):
        print(f"| {r['substance']} | {'; '.join(r['reasons']) or 'no cited paper reachable'} |")

    europepmc().save()
    if args.write and resolved:
        rows = [
            {k: v for k, v in r.items() if k != "read"}
            for r in sorted(resolved, key=lambda r: r["substance"].lower())
        ]
        added, updated = merge_curated(rows)
        print(f"\n{added} added, {updated} updated in {CURATED.relative_to(REPO)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
