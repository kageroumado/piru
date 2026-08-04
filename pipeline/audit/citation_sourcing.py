#!/usr/bin/env python3
"""Does the cited paper contain the number the row claims — and if not, which paper does?

Three checks now stand between a curated number and the app, and they answer
strictly different questions:

    verify_citations.py    does this identifier RESOLVE to a real paper?
    citation_topicality.py is that paper ABOUT the substance citing it?
    citation_sourcing.py   does that paper CONTAIN this row's value?          ← here

The third is the one that catches a citation which passes both earlier gates and
is still wrong. Ephenidine's NMDA Kᵢ of 66.4 nM is a real measurement from a real
paper (Kang 2017, Neuropharmacology 112:144-149) — but the row cited
`pmid:27623219`, which resolves perfectly to *"A 'Shark Encounter': Delayed
Primary Closure of a Great White Shark Bite"*. The identifier was invented at
enrichment time, and it happened to land on something real.

Why a number is stronger evidence than a name
---------------------------------------------
Topicality asks whether a *word* appears, and words are ambiguous — a paper about
the α1β2γ2 receptor legitimately names no drug, so absence there is a question.
A value is not ambiguous. "66.4" adjacent to "nM" is either in the paper or it is
not, and a curated Kᵢ that appears nowhere in its own source is a defect with no
innocent reading available. That is what makes this check deterministic in a way
name matching cannot be.

Units are the whole difficulty, and they are handled by *canonicalising both
sides* rather than by string matching. A row holding `ki_nm = 66.4` must match a
paper writing "66.4 nM", "0.0664 μM", "66.4 ± 3.7 nM", or "pKi 7.18" — so every
quantity in the text is parsed to a canonical unit and compared numerically.
Adjacency to a unit is **required**: bare "14" occurs in every full text ever
written, and matching it would make the check useless.

    # every numeric row whose citation we can read
    python3 pipeline/audit/citation_sourcing.py --check

    # only the rows citation_topicality flagged, and hunt for replacements
    python3 pipeline/audit/citation_sourcing.py --from /tmp/topi.json --propose

    python3 pipeline/audit/citation_sourcing.py --check --gate   # exit 1 on a
                                                                 # full-text miss
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audit.citation_topicality import (  # noqa: E402
    PHARMACOLOGICAL_QUALIFIERS,
    TARGET_STOPWORDS,
    target_keys,
)
from audit.europepmc import Record, client  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
USER_AGENT = "piru-citation-sourcing/1.0 (https://github.com/kageroumado/piru)"


# --------------------------------------------------------------- quantities


#: Multipliers onto the canonical unit of each class. Canonical units are chosen
#: to match how the DB stores the column, so a row's value needs no conversion.
CONCENTRATION_NM = {
    "m": 1e9,
    "mol/l": 1e9,
    "molar": 1e9,
    "mm": 1e6,
    "mmol/l": 1e6,
    "um": 1e3,
    "μm": 1e3,
    "µm": 1e3,
    "umol/l": 1e3,
    "μmol/l": 1e3,
    "micromolar": 1e3,
    "nm": 1.0,
    "nmol/l": 1.0,
    "nanomolar": 1.0,
    "pm": 1e-3,
    "pmol/l": 1e-3,
    "picomolar": 1e-3,
}

TIME_MINUTES = {
    "s": 1 / 60,
    "sec": 1 / 60,
    "secs": 1 / 60,
    "second": 1 / 60,
    "seconds": 1 / 60,
    "min": 1.0,
    "mins": 1.0,
    "minute": 1.0,
    "minutes": 1.0,
    "h": 60.0,
    "hr": 60.0,
    "hrs": 60.0,
    "hour": 60.0,
    "hours": 60.0,
    "d": 1440.0,
    "day": 1440.0,
    "days": 1440.0,
}

PERCENT = {"%": 1.0, "percent": 1.0}

VOLUME_PER_KG = {"l/kg": 1.0, "liters/kg": 1.0, "litres/kg": 1.0, "ml/kg": 1e-3}

CLEARANCE = {
    "ml/min/kg": 1.0,
    "ml min-1 kg-1": 1.0,
    "l/h/kg": 1000.0 / 60.0,
    "ml/h/kg": 1 / 60.0,
}

UNIT_TABLES: dict[str, dict[str, float]] = {
    "concentration": CONCENTRATION_NM,
    "time": TIME_MINUTES,
    "percent": PERCENT,
    "volume_per_kg": VOLUME_PER_KG,
    "clearance": CLEARANCE,
}

#: `pKi 7.18` is the same measurement as `Kᵢ 66 nM`, and review tables print the
#: log form as often as the linear one. Handled separately because the
#: conversion is exponential, not a multiplier.
LOG_PREFIXES = {"pki", "pkd", "pic50", "pec50", "pa2", "pkb"}

_NUMBER = r"[-+]?\d{1,3}(?:,\d{3})*(?:\.\d+)?|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?"
#: A number, an optional ± error term, then a unit. The error term is skipped
#: over rather than parsed: papers write "66.4 ± 3.7 nM" and the unit belongs to
#: the leading value.
QUANTITY_RE = re.compile(
    rf"(?P<value>{_NUMBER})"
    r"(?:\s*(?:±|\+/-|\+-)\s*[\d.]+)?"
    r"\s*(?P<unit>%|[a-zA-Zµμ][a-zA-Zµμ0-9/·\-]{0,12})",
    re.UNICODE,
)
LOG_RE = re.compile(
    rf"\b(?P<kind>p[KI][ida]?(?:50)?|pEC50|pIC50|pKi|pKd|pA2|pKB)\s*(?:value)?\s*"
    rf"(?:of|=|:|was|were)?\s*(?P<value>{_NUMBER})",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Quantity:
    """One number from a paper, in the canonical unit of its class."""

    value: float
    unit_class: str
    raw: str


def _clean_unit(unit: str) -> str:
    text = unicodedata.normalize("NFKD", unit).lower().strip(" .,;:)")
    return text.replace("μ", "u").replace("µ", "u")


def extract_quantities(text: str) -> list[Quantity]:
    """Every number in `text` that carries a unit we understand.

    Numbers without a unit are deliberately dropped. They are the overwhelming
    majority of tokens in a full text (years, sample sizes, table indices, page
    numbers), and admitting them would let any row match any paper.
    """
    if not text:
        return []
    found: list[Quantity] = []
    for match in QUANTITY_RE.finditer(text):
        try:
            value = float(match.group("value").replace(",", ""))
        except ValueError:
            continue
        unit = _clean_unit(match.group("unit"))
        # "uM" normalises to "um", which also spells a lowercase micrometre; the
        # concentration table wins because no PK/binding row is ever in microns.
        for unit_class, table in UNIT_TABLES.items():
            factor = table.get(unit)
            if factor is not None:
                found.append(Quantity(value * factor, unit_class, match.group(0).strip()))
                break
    for match in LOG_RE.finditer(text):
        kind = _clean_unit(match.group("kind"))
        if kind not in LOG_PREFIXES:
            continue
        try:
            logged = float(match.group("value"))
        except ValueError:
            continue
        if 0 < logged < 16:  # a pKi outside this range is a parse artifact
            found.append(Quantity(10 ** (9 - logged), "concentration", match.group(0).strip()))
    return found


def _significant_figures(value: float) -> int:
    text = f"{value:g}"
    digits = re.sub(r"[-.eE+]|^0+", "", text.split("e")[0])
    return max(1, len(digits.rstrip("0")) or 1)


def match_strength(target: float, unit_class: str) -> str:
    """How much a match on this number would actually prove.

    Presence and absence are not symmetric evidence, and pretending otherwise is
    the fastest way to make this check lie. `Kᵢ = 66.4 nM` appearing in a paper is
    nearly conclusive — nothing else in the literature is 66.4 nM by accident.
    `bioavailability = 50%` appearing in a paper is worth nothing: an early run of
    this tool "confirmed" nine citations on matches like "50%", "75%" and "20
    percent", every one of them a coincidence in an unrelated abstract.

    So a match is `high` only when the number carries enough entropy to identify
    a measurement, and `low` otherwise. Only `high` may be reported as
    corroboration; `low` is recorded and ignored.
    """
    figures = _significant_figures(target)
    magnitude = abs(target)
    if unit_class == "percent":
        # Percentages live in a 0–100 box that every clinical abstract samples
        # from, so only an oddly precise one discriminates: 54.5 % can identify a
        # study, 50 % cannot.
        return "high" if figures >= 3 and magnitude % 5 != 0 else "low"
    if figures <= 1:
        return "low"
    # A round order of magnitude (100 nM, 10 min) is a default, not a measurement.
    if magnitude and math.log10(magnitude) % 1 == 0:
        return "low"
    return "high"


def corroboration_strength(target: float, unit_class: str, found: Quantity) -> str:
    """How much this particular match proves — judged on BOTH numbers.

    `match_strength` asks whether the row's value is distinctive. That is not
    enough on its own, because tolerance is two-sided: a row holding 99 nM
    matched a paper's "0.1 μM", and a row holding 120 min matched a throwaway
    "2 h". The row's number was specific; the paper's was a round default, and
    the pairing proved nothing. Both sides must be discriminating.
    """
    if match_strength(target, unit_class) == "low":
        return "low"
    return match_strength(found.value, unit_class)


def value_matches(target: float, unit_class: str, quantities: list[Quantity]) -> Quantity | None:
    """The first quantity in the paper that is this row's value.

    Tolerance is derived from how precisely the row states the number rather than
    being a flat percentage. A row holding 66.4 is claiming three significant
    figures and should match "66.4" but not "66"; a row holding 400 is claiming
    one or two and must still match a paper's "398 ± 21". Deriving it this way is
    what keeps the check from either missing rounded restatements or matching
    anything in the neighbourhood.
    """
    if target is None or not math.isfinite(target) or target == 0:
        return None
    figures = _significant_figures(target)
    tolerance = max(abs(target) * (0.5 * 10 ** -(figures - 1)), abs(target) * 0.005)
    for quantity in quantities:
        if quantity.unit_class != unit_class:
            continue
        if abs(quantity.value - target) <= tolerance:
            return quantity
    return None


# ------------------------------------------------------------------- DB rows


#: Which columns hold a checkable number, and in which unit class. Only columns
#: whose unit is fixed by the schema appear here — `concentration_effects` keeps
#: its unit in a sibling column, so its values are read dynamically below.
CHECKABLE: dict[str, dict[str, str]] = {
    "bindings": {
        "ki_nm": "concentration",
        "kd_nm": "concentration",
        "ec50_nm": "concentration",
        "ic50_nm": "concentration",
        "emax_pct": "percent",
        "intrinsic_activity_pct": "percent",
    },
    "functional_assays": {
        "ec50_nm": "concentration",
        "ic50_nm": "concentration",
        "emax_pct": "percent",
    },
    "off_targets": {"ki_or_ic50_nm": "concentration"},
    "pk_routes": {
        "half_life_min": "time",
        "tmax_min": "time",
        "bioavailability_pct": "percent",
        "protein_binding_pct": "percent",
        "vd_l_per_kg": "volume_per_kg",
        "clearance_ml_per_min_per_kg": "clearance",
    },
    "half_lives": {"half_life_minutes": "time"},
    "metabolism": {
        "fraction_of_clearance_pct": "percent",
        "formation_fraction_pct": "percent",
        "metabolite_potency_vs_parent_pct": "percent",
        "metabolite_half_life_min": "time",
        "metabolite_tmax_min": "time",
    },
}

#: Free-text columns that name what a row is about, used to build a replacement
#: query. First non-empty wins.
SUBJECT_COLUMNS = ["target", "enzyme", "readout", "effect", "gene", "with_substance"]


@dataclass
class Row:
    table: str
    row_id: int
    substance: str
    citation_id: int
    identifier: str
    subject: str
    values: list[tuple[str, float, str]] = field(default_factory=list)
    notes: str = ""
    #: The substance's InChIKey, when known. This is the only *exact* identity
    #: link out of this database — a name search guesses, an InChIKey does not.
    inchikey: str = ""


def load_rows(conn: sqlite3.Connection, only_citations: set[int] | None = None) -> list[Row]:
    substances = dict(conn.execute("SELECT id, canonical_name FROM substances"))
    inchikeys = {
        sid: key for sid, key in conn.execute("SELECT id, inchikey FROM substances") if key
    }
    identifiers = {}
    for cid, doi, pmid, url in conn.execute("SELECT id, doi, pmid, url FROM citations"):
        identifiers[cid] = f"doi:{doi}" if doi else (f"pmid:{pmid}" if pmid else (url or "—"))

    rows: list[Row] = []
    for table, columns in CHECKABLE.items():
        present = {info[1] for info in conn.execute(f'PRAGMA table_info("{table}")')}
        if not {"citation_id", "substance_id"} <= present:
            continue
        wanted = [c for c in columns if c in present]
        subject = next((c for c in SUBJECT_COLUMNS if c in present), None)
        identity = "id" if "id" in present else "rowid"
        selected = [identity, "substance_id", "citation_id"] + wanted
        if subject:
            selected.append(subject)
        if "notes" in present:
            selected.append("notes")
        query = (
            f'SELECT {", ".join(selected)} FROM "{table}" WHERE citation_id IS NOT NULL '
            f"AND ({' OR '.join(f'{c} IS NOT NULL' for c in wanted)})"
        )
        for record in conn.execute(query):
            data = dict(zip(selected, record, strict=True))
            cid = data["citation_id"]
            if only_citations is not None and cid not in only_citations:
                continue
            values = [
                (column, float(data[column]), columns[column])
                for column in wanted
                if data.get(column) is not None
            ]
            if not values:
                continue
            rows.append(
                Row(
                    table=table,
                    row_id=data[identity],
                    substance=substances.get(data["substance_id"], "?"),
                    citation_id=cid,
                    identifier=identifiers.get(cid, "—"),
                    subject=str(data.get(subject) or "") if subject else "",
                    values=values,
                    notes=str(data.get("notes") or ""),
                    inchikey=inchikeys.get(data["substance_id"], ""),
                )
            )
    return rows


# -------------------------------------------------------------------- ChEMBL


CHEMBL_BASE = "https://www.ebi.ac.uk/chembl/api/data"
CHEMBL_CACHE = REPO / "data/sources/chembl-cache.json"

#: Which ChEMBL `standard_type` may satisfy which of our columns. Kd is allowed
#: to answer a Kᵢ because curators file displacement constants under either, but
#: an IC50 may not — it is assay-conditional and not an affinity.
CHEMBL_TYPES = {
    "ki_nm": ("Ki", "Kd"),
    "kd_nm": ("Kd", "Ki"),
    "ec50_nm": ("EC50",),
    "ic50_nm": ("IC50",),
    "ki_or_ic50_nm": ("Ki", "IC50", "Kd"),
}


class ChEMBL:
    """The one source here that knows which paper a NUMBER came from.

    Every other repair route works backwards — take a value, guess at papers,
    hope one contains it. ChEMBL's curators already did the forward version:
    they read the primary literature and recorded each measured constant against
    the document it was extracted from. So a row claiming `Kᵢ = 66.4 nM` can be
    matched to the activity record holding 66.4 nM, and that record names its
    own source.

    Identity comes from the InChIKey rather than the name wherever possible. A
    name search for "MDMA" or "4-CMC" returns whatever ChEMBL's synonym table
    happens to hold; an InChIKey is the compound.
    """

    def __init__(self, offline: bool = False) -> None:
        self.offline = offline
        self._cache: dict = {}
        self._dirty = False
        if CHEMBL_CACHE.exists():
            try:
                self._cache = json.loads(CHEMBL_CACHE.read_text())
            except ValueError:
                self._cache = {}

    def save(self) -> None:
        if self._dirty:
            CHEMBL_CACHE.parent.mkdir(parents=True, exist_ok=True)
            CHEMBL_CACHE.write_text(json.dumps(self._cache, indent=1, sort_keys=True) + "\n")
            self._dirty = False

    def _get(self, key: str, path: str):
        if key in self._cache:
            return self._cache[key]
        if self.offline:
            return None
        request = urllib.request.Request(
            f"{CHEMBL_BASE}/{path}", headers={"User-Agent": USER_AGENT}
        )
        payload = None
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.loads(response.read())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError):
            payload = None
        self._cache[key] = payload
        self._dirty = True
        time.sleep(0.15)
        return payload

    def molecule_id(self, inchikey: str, name: str) -> str | None:
        if inchikey:
            payload = self._get(
                f"mol:key:{inchikey}",
                f"molecule?molecule_structures__standard_inchi_key={urllib.parse.quote(inchikey)}&format=json",
            )
            molecules = (payload or {}).get("molecules") or []
            if molecules:
                return molecules[0].get("molecule_chembl_id")
        if name:
            payload = self._get(
                f"mol:name:{name.lower()}",
                f"molecule/search?q={urllib.parse.quote(name)}&format=json",
            )
            molecules = (payload or {}).get("molecules") or []
            if molecules:
                return molecules[0].get("molecule_chembl_id")
        return None

    def activities(self, molecule_id: str) -> list[dict]:
        out: list[dict] = []
        for offset in (0, 1000):
            payload = self._get(
                f"act:{molecule_id}:{offset}",
                f"activity?molecule_chembl_id={molecule_id}&limit=1000&offset={offset}&format=json",
            )
            chunk = (payload or {}).get("activities") or []
            out.extend(chunk)
            if len(chunk) < 1000:
                break
        return out

    def document(self, document_id: str) -> dict | None:
        return self._get(f"doc:{document_id}", f"document/{document_id}?format=json")


_SUBTYPE = re.compile(r"(\d+[a-z]?)$")


def _identifying_words(terms: set[str]) -> set[str]:
    return {
        word
        for term in terms
        for word in re.split(r"[^a-z0-9]+", term.lower())
        if len(word) >= 3 and word not in TARGET_STOPWORDS
    }


def target_agrees(subject: str, other: str) -> bool:
    """Whether a foreign target name denotes the same protein as ours.

    Two failure modes pull in opposite directions and both are real:

        KOR   vs "Kappa-type opioid receptor"   — share no word, same protein
        CB1   vs "Cannabinoid receptor 2"       — share every word, different one

    So the test is word overlap *through the synonym expansion*, plus a veto on
    disagreeing subtype markers. The veto is what stops a CB2 Kᵢ of 39.3 nM being
    offered as the source of THC's CB1 row, and an hERG row is rejected outright
    for sharing nothing with "Sigma non-opioid intracellular receptor 1".
    """
    grams, phrases = target_keys(subject)
    # "receptor", "transporter", "channel" are shared by almost every protein
    # name in the corpus, so an overlap on them alone means nothing: it is what
    # made NET agree with "Sodium-dependent DOPAMINE transporter".
    ours = _identifying_words(grams | phrases | {subject.lower()})
    theirs = _identifying_words({other})
    if not ours & theirs:
        return False

    our_subtype = next(
        (match.group(1) for key in sorted(grams) if (match := _SUBTYPE.search(key))), None
    )
    if our_subtype:
        their_subtypes = set(re.findall(r"\b(\d+[a-z]?)\b", other.lower()))
        if their_subtypes and our_subtype not in their_subtypes:
            return False
    return True


def chembl_sources(row: Row, api: ChEMBL) -> list[dict]:
    """The papers ChEMBL says reported this row's exact value at this target.

    Returns one entry per distinct document, best first. An empty list means
    ChEMBL holds no activity matching the value — which is informative in its
    own right for a well-covered compound, and meaningless for a research
    chemical ChEMBL has never seen.
    """
    molecule_id = api.molecule_id(row.inchikey, row.substance)
    if not molecule_id:
        return []

    proposals: dict[str, dict] = {}
    for activity in api.activities(molecule_id):
        standard_type = activity.get("standard_type")
        units = (activity.get("standard_units") or "").lower()
        raw_value = activity.get("standard_value")
        document_id = activity.get("document_chembl_id")
        if not (standard_type and raw_value and document_id) or units not in CONCENTRATION_NM:
            continue
        try:
            measured = float(raw_value) * CONCENTRATION_NM[units]
        except (TypeError, ValueError):
            continue

        for column, value, unit_class in row.values:
            if unit_class != "concentration":
                continue
            if standard_type not in CHEMBL_TYPES.get(column, ()):
                continue
            if (
                corroboration_strength(value, unit_class, Quantity(measured, unit_class, ""))
                != "high"
            ):
                continue
            if not value_matches(value, unit_class, [Quantity(measured, unit_class, "")]):
                continue

            document = api.document(document_id)
            if not document:
                continue
            identifier = (
                f"doi:{document['doi']}"
                if document.get("doi")
                else f"pmid:{document['pubmed_id']}"
                if document.get("pubmed_id")
                else None
            )
            if not identifier or identifier in proposals:
                continue
            # The target must AGREE, and this was learned the expensive way.
            # Scoring it and taking the best anyway proposed a CB2 Kᵢ of 39.3 nM
            # as the source of THC's CB1 row (41 nM), and a sigma-1 Kᵢ of 5070 nM
            # as the source of dextromethorphan's hERG row (5100 nM). Both are
            # real measurements of the right compound at the wrong protein, and
            # a near-miss number made them look like confirmations.
            target_name = activity.get("target_pref_name") or ""
            if row.subject and not target_agrees(row.subject, target_name):
                continue
            proposals[identifier] = {
                "identifier": identifier,
                "score": 100.0,
                "why": (
                    f"ChEMBL records {standard_type} {raw_value} {units} for this compound"
                    + (f" at {target_name}" if target_name else "")
                    + f", extracted from this paper (matches {column}={value:g})"
                ),
                "cite": f"{document.get('journal', '')} {document.get('year', '')} — {document.get('title', '')}"[
                    :160
                ],
            }
    return sorted(proposals.values(), key=lambda p: -p["score"])[:3]


# ----------------------------------------------------------------- searching


GREEK = {
    "α": "alpha",
    "β": "beta",
    "γ": "gamma",
    "δ": "delta",
    "κ": "kappa",
    "μ": "mu",
    "σ": "sigma",
}


def target_terms(subject: str) -> list[str]:
    """Searchable phrases for a target string.

    `GABA-A α1β2γ2` has to become `GABA-A` before any search engine will find the
    paper: subunit stoichiometry is written a dozen ways and pins the query to
    zero results. The subunit is kept as a second, weaker term.
    """
    if not subject:
        return []
    text = subject
    for greek, latin in GREEK.items():
        text = text.replace(greek, latin)
    terms: list[str] = []
    head = re.split(r"\s*(?:alpha|beta|gamma|delta)\d", text)[0].strip(" -–(")
    if len(head) >= 3:
        terms.append(head)
    if text != head and len(text) < 40:
        terms.append(text)
    return terms[:2]


def propose_sources(row: Row, api, limit: int = 6) -> list[tuple[float, Record, str]]:
    """Candidate replacement papers, ranked by evidence rather than relevance.

    The ranking is deliberately dominated by whether the paper *contains the
    row's number*: a search engine's own relevance score is an opinion, and a
    matching value under a matching unit is a fact.
    """
    queries: list[str] = []
    name = row.substance.replace('"', "")
    for term in target_terms(row.subject):
        queries.append(f'"{name}" AND "{term}"')
    queries.append(f'"{name}"')

    seen: dict[str, Record] = {}
    for query in queries:
        for record in api.search(query, page_size=limit):
            if record.identifier and record.identifier not in seen:
                seen[record.identifier] = record
        if len(seen) >= limit * 2:
            break

    ranked: list[tuple[float, Record, str]] = []
    for record in seen.values():
        text = api.text_for(record)
        quantities = extract_quantities(text)
        matched = [
            (column, quantity, corroboration_strength(value, unit_class, quantity))
            for column, value, unit_class in row.values
            if (quantity := value_matches(value, unit_class, quantities))
        ]
        # A discriminating value is the only thing here that outranks a name; a
        # round percentage is barely a tiebreak.
        score = sum(3.0 if strength == "high" else 0.25 for _, _, strength in matched)
        lowered = f"{record.title} {record.abstract}".lower()
        # A candidate must NAME THE SUBSTANCE IN ITS TITLE. Without that, ranking
        # by value alone proposed *ACS Macro Letters* on adhesives as the source
        # of MDEA's Tmax, on the strength of a shared "2 h". Search relevance is
        # an opinion; a title is a claim about what the paper is.
        if name.lower() not in record.title.lower():
            continue
        score += 2.0
        if any(term.lower() in lowered for term in target_terms(row.subject)):
            score += 1.0
        if record.pmcid:
            score += 0.25  # full text read, so a miss here means more
        why = (
            ", ".join(f"{c}={q.raw}" for c, q, strength in matched if strength == "high")
            or "names the substance"
        )
        ranked.append((score, record, why))
    ranked.sort(key=lambda item: -item[0])
    return ranked[:3]


# ------------------------------------------------------- prose-cited sources


#: `Kang et al. 2017 (Neuropharmacology 112:144-149)` — the curator wrote the
#: real reference into `notes` and a fabricated identifier into `reference`. That
#: pairing is recoverable: the prose names a paper, and a paper has exactly one
#: identifier. Author names are constrained to a leading capital and no trailing
#: possessive so that "Table 1" and "Figure 2A" cannot pass as authors.
PROSE_CITE_RE = re.compile(
    # Up to three surnames may precede the year, and capturing ALL of them is
    # what makes the match checkable. "Wallner, Hanchar, Olsen 2003" parsed to
    # its LAST surname alone resolved to a Danish cancer cohort — which really
    # does have an author named Olsen. One surname plus a year identifies a
    # paper far less often than it looks.
    r"\b(?P<authors>[A-Z][A-Za-zÀ-ɏ'-]{2,}"
    r"(?:\s*(?:,|&|/|\band\b)\s*[A-Z][A-Za-zÀ-ɏ'-]{2,}){0,2})"
    r"(?:\s*(?:et\s+al\.?|and\s+colleagues))?"
    r"[,.]?\s*\(?(?P<year>(?:19|20)\d{2})\)?"
)
#: Words that pass the author pattern but never name a person.
NOT_AUTHORS = {
    "table",
    "figure",
    "fig",
    "note",
    "see",
    "the",
    "this",
    "study",
    "data",
    "human",
    "rat",
    "mouse",
    "since",
    "from",
    "per",
    "ref",
    "reference",
    "版",
}


@dataclass
class ProseCitation:
    authors: tuple[str, ...]
    year: str
    raw: str

    @property
    def author(self) -> str:
        """The surname to query on. The rest are used to check the answer."""
        return self.authors[0]


def parse_prose_citation(notes: str) -> ProseCitation | None:
    for match in PROSE_CITE_RE.finditer(notes or ""):
        surnames = tuple(
            name.strip()
            for name in re.split(r"\s*(?:,|&|/|\band\b)\s*", match.group("authors"))
            if name.strip() and name.strip().lower() not in NOT_AUTHORS
        )
        if not surnames:
            continue
        return ProseCitation(authors=surnames, year=match.group("year"), raw=match.group(0))
    return None


def resolve_prose(row: Row, api) -> tuple[str, str, Record | None]:
    """Find the paper the row's own notes name, and say whether it is the one cited.

    This is the highest-yield repair available, because it needs no judgment: the
    curator already recorded which paper the number came from, in prose, next to
    an identifier that does not point at it. Resolving the prose recovers the
    intended source exactly rather than guessing a plausible one.
    """
    prose = parse_prose_citation(row.notes)
    if not prose:
        return "NO_PROSE", "notes name no author/year", None

    name = row.substance.replace('"', "")
    for query in (
        f'AUTH:"{prose.author}" AND PUB_YEAR:{prose.year} AND "{name}"',
        f'AUTH:"{prose.author}" AND PUB_YEAR:[{int(prose.year) - 1} TO {int(prose.year) + 1}] AND "{name}"',
    ):
        hits = [
            candidate
            for candidate in api.search(query, page_size=5)
            if _wrote_it(candidate, prose.authors) and _plausible_source(candidate)
        ]
        if not hits:
            continue
        best = hits[0]
        if best.identifier == row.identifier:
            return "PROSE_AGREES", f"“{prose.raw}” resolves to the cited paper", best
        return (
            "PROSE_DISAGREES",
            f"“{prose.raw}” resolves to {best.identifier}, not {row.identifier}",
            best,
        )
    return "PROSE_UNRESOLVED", f"“{prose.raw}” matched no paper naming {name}", None


def _wrote_it(record: Record, surnames: tuple[str, ...]) -> bool:
    """Whether this paper is actually by the author the notes named.

    Europe PMC's AUTH field is a hint, not a filter: `AUTH:"Wallner" AND
    PUB_YEAR:2003 AND "alcohol"` returned a Tjønneland epidemiology paper, and
    `AUTH:"Zadina" ... "endomorphin"` returned one by Champion. Both were then
    offered as replacement sources — which would have swapped one fabricated
    citation for another, differently wrong one. The surname the curator wrote
    has to appear in the author list, or the hit is not the paper they meant.
    """
    listed = (record.authors or "").lower()
    return all(surname.lower() in listed for surname in surnames)


def _plausible_source(record: Record) -> bool:
    """Whether a search hit could be anyone's pharmacology source at all.

    An author-and-year query is a blunt instrument: "Tjønneland 2003" plus
    "alcohol" returned *"Alcohol intake, drinking patterns…"* in Cancer Causes &
    Control, and the resolver offered that epidemiology paper as the source of
    ethanol's GABA-A affinity. Reusing the MeSH domain rule here costs nothing
    and rejects exactly that shape — a real paper, the right author, the right
    year, and not a pharmacology paper.
    """
    if not record.mesh:
        return True  # unindexed says nothing; refusing here would punish preprints
    return bool(record.mesh_qualifiers & PHARMACOLOGICAL_QUALIFIERS)


# ------------------------------------------------------------------ checking


@dataclass
class Result:
    row: Row
    verdict: str
    coverage: str
    detail: str
    prose: str = "NOT_CHECKED"
    prose_detail: str = ""
    proposals: list[dict] = field(default_factory=list)

    def line(self) -> str:
        values = ", ".join(f"{c}={v:g}" for c, v, _ in self.row.values)
        head = (
            f"[{self.verdict}/{self.coverage}] {self.row.substance} "
            f"{self.row.table}.{self.row.row_id} ({values}) cites {self.row.identifier}"
        )
        lines = [head, f"        {self.detail}"]
        if self.prose in {"PROSE_DISAGREES", "PROSE_AGREES"}:
            lines.append(f"        {self.prose}: {self.prose_detail}")
        for proposal in self.proposals:
            lines.append(
                f"        → {proposal['identifier']}  {proposal['why']}  {proposal['cite']}"
            )
        return "\n".join(lines)


def check_row(row: Row, api, propose: bool, read_notes: bool = True, chembl=None) -> Result:
    pmid = row.identifier[5:] if row.identifier.startswith("pmid:") else None
    doi = row.identifier[4:] if row.identifier.startswith("doi:") else None
    record = api.by_id(pmid=pmid, doi=doi)
    text = api.text_for(record)

    # Coverage is reported, not inferred from the verdict, because "the number is
    # not in this paper" and "we only ever saw the title" print identically
    # otherwise — and only the first is evidence. A Kᵢ lives in Table 2, so an
    # absence read off an abstract means almost nothing and must never gate.
    if record and record.pmcid and record.full_text:
        coverage = "fulltext"
    elif record and record.abstract:
        coverage = "abstract"
    elif text:
        coverage = "title"
    else:
        coverage = "none"

    if coverage == "none":
        verdict = "NO_TEXT"
        detail = "no abstract or full text available — the value could not be checked"
    elif coverage == "title":
        verdict = "NO_TEXT"
        detail = "title only, no abstract — the value could not be checked"
    else:
        quantities = extract_quantities(text)
        matched = [
            (column, quantity, corroboration_strength(value, unit_class, quantity))
            for column, value, unit_class in row.values
            if (quantity := value_matches(value, unit_class, quantities))
        ]
        strong = [(c, q) for c, q, strength in matched if strength == "high"]
        if strong:
            verdict = "VALUE_PRESENT"
            detail = "; ".join(f"{column} appears as “{q.raw}”" for column, q in strong)
        elif matched:
            verdict = "VALUE_WEAK"
            detail = (
                "only non-discriminating values matched ("
                + "; ".join(f"{column}≈“{q.raw}”" for column, q, _ in matched)
                + ") — a round percentage matches any abstract"
            )
        else:
            verdict = "VALUE_ABSENT"
            wanted = ", ".join(f"{c}={v:g}" for c, v, _ in row.values)
            detail = (
                f"none of {wanted} appears in the {coverage} "
                f"({len(quantities)} quantit{'y' if len(quantities) == 1 else 'ies'} read)"
            )

    result = Result(row=row, verdict=verdict, coverage=coverage, detail=detail)

    if read_notes and verdict != "VALUE_PRESENT":
        result.prose, result.prose_detail, recovered = resolve_prose(row, api)
        if recovered and result.prose == "PROSE_DISAGREES":
            # The curator's own prose is a better lead than any search ranking,
            # so it goes first and carries the reason it was trusted.
            result.proposals.append(
                {
                    "identifier": recovered.identifier,
                    "score": 99.0,
                    "why": "named in the row's own notes",
                    "cite": recovered.cite(),
                }
            )

    if chembl is not None and verdict != "VALUE_PRESENT":
        # ChEMBL first, unconditionally: it is the only route that knows the
        # value-to-paper link rather than inferring it.
        for proposal in chembl_sources(row, chembl):
            if not any(p["identifier"] == proposal["identifier"] for p in result.proposals):
                result.proposals.append(proposal)

    if propose and verdict != "VALUE_PRESENT":
        for score, candidate, why in propose_sources(row, api):
            if any(p["identifier"] == candidate.identifier for p in result.proposals):
                continue
            result.proposals.append(
                {
                    "identifier": candidate.identifier,
                    "score": round(score, 2),
                    "why": why,
                    "cite": candidate.cite(),
                }
            )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument(
        "--from",
        dest="findings",
        type=Path,
        help="a citation_topicality --json file; restrict to the citations it flagged",
    )
    parser.add_argument("--check", action="store_true", help="check every checkable row")
    parser.add_argument("--propose", action="store_true", help="hunt for replacement sources")
    parser.add_argument(
        "--chembl",
        action="store_true",
        help="ask ChEMBL which paper reported this row's value. The strongest "
        "repair route available: its curators recorded each constant against the "
        "document they read it from, so this recovers a source instead of guessing one.",
    )
    parser.add_argument(
        "--no-notes",
        action="store_true",
        help="skip resolving the bibliographic reference a row's notes spell out",
    )
    parser.add_argument(
        "--offline", action="store_true", help="cache only; never reach the network"
    )
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--json", type=Path)
    parser.add_argument(
        "--gate",
        action="store_true",
        help="exit 1 when a value is absent from a paper whose FULL TEXT we read. "
        "Absence from an abstract alone never gates — a Ki lives in Table 2.",
    )
    args = parser.parse_args()

    if not args.check and not args.findings:
        parser.error("pass --check, or --from <topicality json>")

    conn = sqlite3.connect(args.db)
    try:
        only: set[int] | None = None
        if args.findings:
            flagged = json.loads(args.findings.read_text())
            only = {f["citation_id"] for f in flagged}
        rows = load_rows(conn, only)
    finally:
        conn.close()

    if args.limit:
        rows = rows[: args.limit]

    api = client(offline=args.offline)
    chembl = ChEMBL(offline=args.offline) if args.chembl else None
    results: list[Result] = []
    try:
        for index, row in enumerate(rows, 1):
            results.append(
                check_row(row, api, args.propose, read_notes=not args.no_notes, chembl=chembl)
            )
            if index % 25 == 0:
                api.save()
                if chembl:
                    chembl.save()
                print(f"  … {index}/{len(rows)}", file=sys.stderr)
    finally:
        api.save()
        if chembl:
            chembl.save()

    counts: dict[str, int] = {}
    for result in results:
        counts[result.verdict] = counts.get(result.verdict, 0) + 1
    print(f"\ncitation-sourcing: {len(results)} numeric row(s) checked")
    for verdict in ("VALUE_PRESENT", "VALUE_WEAK", "VALUE_ABSENT", "NO_TEXT"):
        if counts.get(verdict):
            print(f"  {verdict}: {counts[verdict]}")

    for result in results:
        if result.verdict != "VALUE_PRESENT":
            print(f"\n  {result.line()}")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(
                [
                    {
                        "table": r.row.table,
                        "row_id": r.row.row_id,
                        "substance": r.row.substance,
                        "identifier": r.row.identifier,
                        "subject": r.row.subject,
                        "values": [{"column": c, "value": v} for c, v, _ in r.row.values],
                        "verdict": r.verdict,
                        "coverage": r.coverage,
                        "detail": r.detail,
                        "prose": r.prose,
                        "prose_detail": r.prose_detail,
                        "notes": r.row.notes,
                        "proposals": r.proposals,
                    }
                    for r in results
                ],
                indent=1,
            )
            + "\n"
        )
        print(f"\nfull result → {args.json}")

    if args.gate:
        failures = [r for r in results if r.verdict == "VALUE_ABSENT" and r.coverage == "fulltext"]
        if failures:
            print(
                f"\ncitation-sourcing: FAILED — {len(failures)} row(s) claim a number that is "
                "absent from the full text of the paper they cite:",
                file=sys.stderr,
            )
            for result in failures[:20]:
                print(
                    f"  {result.row.substance} {result.row.table} → {result.row.identifier}",
                    file=sys.stderr,
                )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
