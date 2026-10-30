#!/usr/bin/env python3
"""Cite uncited research rows from the papers their enrichment record consulted.

Each enrichment record (`data/enrichment/raw/*.json`) lists the papers it was
written from in `references_consulted`, and the build never read that list. So
a record's downstream-signalling paragraph, its pharmacogenetics finding and
its qualitative metabolism rows ship with no citation while the papers behind
them sit one field away.

A consulted paper is not evidence for every row of its record, so each pair is
checked before anything is attached. A paper is attached to a row only when
both hold:

  1. **It is about this substance.** Its title or abstract names the substance,
     by any of the names `citation_topicality.py` credits (the same generous
     matcher, so a paper the topicality gate would call ABSENT never gets here).
  2. **It names what the row claims.** The row's own key term: the gene for a
     pharmacogenetics row, the enzyme for metabolism, the target for an
     off-target, binding, functional or bias row, the co-drug or enzyme for a
     drug interaction, the modality for imaging, and for a signalling paragraph
     a target the paragraph itself names. The term must appear in the title or
     abstract, or in a full-text paragraph that also names the substance.

Every row the uncited rows cover is qualitative (`uncited.md` §1a: the build
already nulls an enrichment number whose citation is missing), so there is no
number to find in the paper; a numeric row would need `citation_sourcing.py`'s
value check instead, and this pass skips it.

Rows that pass become entries in `data/curated/row-citations.json` with
`via: references_consulted`; rows that fail stay uncited, and the report says
why, per table. Text comes from the papers cache first (`papers get`), then the
committed abstract cache, then Europe PMC (`--fetch` allows the network).

    python3 pipeline/audit/source_consulted_references.py            # offline, report only
    python3 pipeline/audit/source_consulted_references.py --write    # + update row-citations.json
    python3 pipeline/audit/source_consulted_references.py --fetch --write
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))

import row_citations  # noqa: E402
from audit.citation_topicality import (  # noqa: E402
    ABSTRACT_CACHE,
    ENZYME_PREFIXES,
    TARGET_SYNONYMS,
    SubstanceNames,
    TextIndex,
    _canonical_target,
    _target_named,
    build_index,
    load_abstracts,
    load_substances,
    strict_key,
)
from audit.europepmc import EuropePMC  # noqa: E402
from audit.papers import papers_cache  # noqa: E402
from audit.verify_citations import load_cache as load_verify_cache  # noqa: E402
from sqlite import normalise, parse_reference  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
ENRICHMENT = REPO / "data/enrichment/raw"
SOURCE = "peer-review-primary"
VIA = "references_consulted"

#: Table → the columns that identify a row (beside substance and source), and
#: the columns whose values are the row's key terms.
TABLES: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "downstream_signalling": ((), ()),
    "pharmacogenetics": (("gene",), ("gene",)),
    "metabolism": (("enzyme", "metabolite_name", "route"), ("enzyme",)),
    "off_targets": (("target",), ("target",)),
    "drug_interactions_pk": (("with_substance", "mechanism"), ("with_substance",)),
    "bindings": (("target", "action", "species"), ("target",)),
    "functional_assays": (("target", "readout"), ("target",)),
    "neuroimaging": (("modality",), ("modality",)),
    "biased_agonism": (("target", "pathways_compared"), ("target",)),
}
#: Columns that hold a number. A row with one filled is a per-compound value
#: whose citation must contain that number, which this pass does not check.
NUMERIC = {
    "bindings": ("ki_nm", "kd_nm", "ec50_nm", "ic50_nm", "emax_pct", "intrinsic_activity_pct"),
    "functional_assays": ("ec50_nm", "ic50_nm", "emax_pct"),
    "off_targets": ("ki_or_ic50_nm",),
    "drug_interactions_pk": ("ki_um",),
    "biased_agonism": ("bias_factor_log",),
    "metabolism": (
        "fraction_of_clearance_pct",
        "metabolite_potency_vs_parent_pct",
        "metabolite_half_life_min",
        "formation_fraction_pct",
        "metabolite_tmax_min",
    ),
}
#: Enzyme and transporter spellings inside a free-text mechanism.
_ENZYME_IN_TEXT = re.compile(r"\b(?:CYP\d[A-Z]\d{1,2}|UGT\d[A-Z]\d{1,2}|P-gp|ABCB1|OATP1B[13])\b")


@dataclass
class Paper:
    ref: str
    title: str
    abstract: str
    full_text: str

    @property
    def head(self) -> str:
        return f"{self.title} {self.abstract}".strip()


class Library:
    """Every way this repo holds a paper's text, cheapest first."""

    def __init__(self, fetch: bool) -> None:
        self.papers = papers_cache()
        self.abstracts = load_abstracts(ABSTRACT_CACHE)
        self.verify = load_verify_cache()
        self.epmc = EuropePMC(offline=not fetch)
        self._seen: dict[str, Paper | None] = {}

    def get(self, ref: str) -> Paper | None:
        if ref in self._seen:
            return self._seen[ref]
        doi, pmid, _, _ = parse_reference(ref)
        paper = None
        if doi or pmid:
            key = f"doi:{doi}" if doi else f"pmid:{pmid}"
            ident = doi or str(pmid)
            title = ((self.verify.get(key) or {}).get("title")) or ""
            abstract = ""
            if pmid:
                abstract = self.abstracts.get(f"pmid:{pmid}") or self.abstracts.get(str(pmid)) or ""
            if doi and not abstract:
                abstract = self.abstracts.get(f"doi:{doi}", "")
            meta = self.papers.meta(ident)
            title = title or ((meta or {}).get("title") or "")
            full = self.papers.text(ident)
            if not abstract or not title:
                record = self.epmc.by_id(pmid=pmid) if pmid else self.epmc.by_id(doi=doi)
                if record is not None:
                    title = title or record.title
                    abstract = abstract or record.abstract
                    if not full and record.pmcid:
                        full = self.epmc.full_text(record.pmcid)
            if title or abstract:
                canonical = f"doi:{doi}" if doi else f"pmid:{pmid}"
                paper = Paper(canonical, title or "", abstract or "", full or "")
        self._seen[ref] = paper
        return paper


def consulted_by_substance(
    conn: sqlite3.Connection,
) -> tuple[dict[int, list[str]], dict[int, list[str]]]:
    """Substance id → the references its enrichment records consulted, in the
    order they were listed, across every record that resolves to it; and
    substance id → the targets those records name as primary."""
    by_name: dict[str, int] = {}
    for sid, name in conn.execute("SELECT id, canonical_name FROM substances"):
        by_name.setdefault(normalise(name), sid)
    for sid, alias in conn.execute("SELECT substance_id, alias FROM aliases"):
        by_name.setdefault(normalise(alias), sid)
    refs: dict[int, list[str]] = defaultdict(list)
    targets: dict[int, list[str]] = defaultdict(list)
    for path in sorted(ENRICHMENT.glob("*.json")):
        for record in json.loads(path.read_text()):
            if not isinstance(record, dict) or record.get("is_class_context"):
                continue
            sid = by_name.get(normalise(record.get("name") or ""))
            if sid is None:
                continue
            for ref in record.get("references_consulted") or []:
                if isinstance(ref, str) and ref.strip() and ref.strip() not in refs[sid]:
                    doi, pmid, _, _ = parse_reference(ref)
                    if doi or pmid:
                        refs[sid].append(ref.strip())
            for target in (record.get("pharmacology") or {}).get("primary_targets") or []:
                if isinstance(target, str) and target not in targets[sid]:
                    targets[sid].append(target)
    return refs, targets


#: How each table's term is looked for. A *target* must be one the topicality
#: module knows (a receptor, transporter or enzyme family), because an unknown
#: target falls back to its long words — "prodrug", "pathway" — which any paper
#: contains. A *symbol* (a gene, an imaging modality) and a *drug* (the co-drug
#: of an interaction) must appear as written.
TERM_KIND = {
    "pharmacogenetics": "symbol",
    "neuroimaging": "symbol",
    "drug_interactions_pk": "drug",
}
_SYMBOL = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{2,}")


def _symbol_key(term: str) -> str | None:
    """The leading gene/modality symbol of a term (`OPRM1 (A118G)` → `oprm1`)."""
    match = _SYMBOL.match(term.strip())
    if not match:
        return None
    token = match.group(0)
    if not (any(ch.isdigit() for ch in token) or token.upper() == token or len(token) >= 5):
        return None
    return re.sub(r"[^a-z0-9]+", "", token.lower()) or None


def checkable(term: str, kind: str) -> bool:
    if kind == "symbol":
        return _symbol_key(term) is not None
    if kind == "drug":
        return len(strict_key(term)) >= 4
    head = _canonical_target(term)
    return head in TARGET_SYNONYMS or head.startswith(ENZYME_PREFIXES)


def term_named(term: str, kind: str, index: TextIndex) -> bool:
    if kind == "symbol":
        key = _symbol_key(term)
        return bool(key) and key in index.grams and (len(key) >= 5 or key in index.caps)
    if kind == "drug":
        key = strict_key(term)
        return key in index.grams and (len(key) >= 5 or key in index.caps)
    return _target_named({term}, index) is not None


def row_terms(table: str, row: dict, targets: list[str]) -> list[str]:
    kind = TERM_KIND.get(table, "target")
    if table == "downstream_signalling":
        text = row.get("summary") or ""
        summary = build_index(text)
        candidates = targets + _ENZYME_IN_TEXT.findall(text)
        named = [t for t in candidates if checkable(t, kind) and term_named(t, kind, summary)]
        return list(dict.fromkeys(named))
    _, term_columns = TABLES[table]
    return [
        row[column] for column in term_columns if row.get(column) and checkable(row[column], kind)
    ]


def names_exactly(names: SubstanceNames, index: TextIndex) -> str | None:
    """The substance's own name in the text, or None.

    Stricter than `citation_topicality._matches_citing`, which is generous on
    purpose: there a miss becomes an accusation, so a ketamine paper is allowed
    to count for 2-FDCK through containment, and "4-HO-MET" for "5-HO-MET"
    through a locant-free key. Here a match becomes a citation, so only a name
    the substance itself answers to counts — a fentanyl paper is not a source
    for cyclopentylfentanyl."""
    if not index:
        return None
    for key in sorted(names.strict):
        if key in index.grams and (len(key) >= 5 or key in index.caps):
            return key
    for phrase in sorted(names.phrases):
        # A phrase of short fragments ("3 meo") is a piece of a name, not a name.
        if phrase in index.phrases and all(len(word) >= 4 for word in phrase.split()):
            return phrase
    return None


def supports(
    paper: Paper, names: SubstanceNames, terms: list[str], kind: str
) -> tuple[str | None, str | None, str]:
    """(matched substance name, matched term, where) — Nones when it does not."""
    head = build_index(paper.head)
    named = names_exactly(names, head)
    if not named:
        return None, None, "substance not named in title/abstract"
    for term in terms:
        if term_named(term, kind, head):
            return named, term, "title/abstract"
    for paragraph in re.split(r"\n\s*\n", paper.full_text):
        if len(paragraph) < 40:
            continue
        index = build_index(paragraph)
        if not names_exactly(names, index):
            continue
        for term in terms:
            if term_named(term, kind, index):
                return named, term, "a full-text paragraph that also names the substance"
    return named, None, "row's term not named alongside the substance"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--fetch", action="store_true", help="allow Europe PMC network lookups")
    parser.add_argument("--write", action="store_true", help="update row-citations.json")
    parser.add_argument("--json", type=Path, help="also write the proposed entries here")
    args = parser.parse_args()

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    names = load_substances(conn)
    consulted, targets_by_sid = consulted_by_substance(conn)
    library = Library(fetch=args.fetch)
    for sid, target in conn.execute(
        "SELECT DISTINCT substance_id, target FROM bindings UNION "
        "SELECT DISTINCT substance_id, target FROM off_targets"
    ):
        if target not in targets_by_sid[sid]:
            targets_by_sid[sid].append(target)

    # Rows this pass cited before are cited in the DB now, so they are not
    # proposed again; their entries are kept as they are.
    entries = row_citations.load()
    proposed: list[dict] = []
    tally: dict[str, Counter] = defaultdict(Counter)
    today = date.today().isoformat()

    for table, (match_columns, _) in TABLES.items():
        claim = row_citations.CLAIM_COLUMNS.get(table)
        rows = conn.execute(
            f"SELECT t.*, s.canonical_name AS substance_name FROM {table} t "
            "JOIN substances s ON s.id = t.substance_id "
            "JOIN sources src ON src.id = t.source_id "
            "WHERE src.slug = ? AND t.citation_id IS NULL "
            "ORDER BY s.canonical_name, t.rowid",
            (SOURCE,),
        ).fetchall()
        for raw in rows:
            row = dict(raw)
            sid = row["substance_id"]
            if any(row.get(column) is not None for column in NUMERIC.get(table, ())):
                tally[table]["skipped: carries a number"] += 1
                continue
            refs = consulted.get(sid) or []
            if not refs:
                tally[table]["rejected: record consulted no paper"] += 1
                continue
            terms = row_terms(table, row, targets_by_sid.get(sid, []))
            if not terms:
                tally[table]["rejected: row names no checkable term"] += 1
                continue
            best = None
            reasons = Counter()
            for ref in refs:
                paper = library.get(ref)
                if paper is None:
                    reasons["no text for the paper"] += 1
                    continue
                named, term, where = supports(
                    paper, names[sid], terms, TERM_KIND.get(table, "target")
                )
                if term:
                    best = (paper, named, term, where)
                    break
                reasons[where] += 1
            if best is None:
                reason = reasons.most_common(1)[0][0] if reasons else "no text for the paper"
                tally[table][f"rejected: {reason}"] += 1
                continue
            paper, named, term, where = best
            entry = {
                "table": table,
                "substance": row["substance_name"],
                "source": SOURCE,
                "match": {c: row[c] for c in match_columns},
                "ref": paper.ref,
                "accessed": today,
                "via": VIA,
                "evidence": f"consulted by the record; names the substance ({named}) and "
                f"{term} in {where}",
            }
            if claim:
                entry["claim_sha1"] = row_citations.claim_sha1(row.get(claim))
            if len(row_citations.find_rows(conn, entry)) != 1:
                tally[table]["rejected: row is not uniquely identifiable"] += 1
                continue
            proposed.append(entry)
            tally[table]["attached"] += 1

    library.epmc.save()
    conn.close()

    print(f"source-consulted-references: {len(proposed)} row(s) attachable")
    for table, counts in tally.items():
        total = sum(counts.values())
        print(f"\n{table}: {total} uncited")
        for reason, n in counts.most_common():
            print(f"  {n:5d}  {reason}")

    if args.json:
        args.json.write_text(json.dumps(proposed, indent=1, ensure_ascii=False) + "\n")
    if args.write:
        merged = {row_citations.entry_key(e): e for e in entries}
        for entry in proposed:
            key = row_citations.entry_key(entry)
            previous = merged.get(key)
            # Keep the original access date when nothing about the entry changed,
            # so a re-run leaves an empty diff.
            if previous and {k: v for k, v in previous.items() if k != "accessed"} == {
                k: v for k, v in entry.items() if k != "accessed"
            }:
                continue
            merged[key] = entry
        row_citations.save(list(merged.values()))
        print(f"\n→ {row_citations.ROW_CITATIONS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
