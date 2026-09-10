#!/usr/bin/env python3
"""Score every source's claim about every comparable number, and say which ones
are probably wrong.

Piru resolves each field by one global source ranking: whichever enabled source
sits highest in `sources.default_priority` wins, for every substance, every
route, every value. That ranking encodes an average — and a source that is
excellent at dose ladders can be poor at receptor affinities, correct about
morphine and wrong about pregabalin. The ranking cannot express any of that,
so it silently ships the wrong number whenever the average is not the case.

This replaces the ranking with numbers computed from the data:

    RELIABILITY   each source gets a weight per column, iterated from its own
                  outlier rate against the consensus it helps form. Uniform
                  start; a source that is usually the odd one out ends light.
    CONSENSUS     a weighted median over *independent* claims. Values that
                  match to within a tolerance are one claim that several
                  sources repeat, not several claims — copying is the dominant
                  failure mode here (freeodwiki and dose.wiki both carry
                  PsychonautWiki's ladders verbatim), and counting copies as
                  votes is how a single upstream error becomes a majority.
    CLASS PRIOR   what the same column looks like across the substance's class
                  peers, in log space, leave-one-out, as a robust z. Fentanyl
                  analogs cluster inside a decade, so a 100 mg member is a
                  finding. A compound with no class, or a class of one, gets no
                  such signal and the cell says so rather than inventing one.
    CONSISTENCY   what one row can say about itself: ladders that stop rising,
                  ranges that run backwards, min == max point estimates, a
                  route ordering that needs more drug the more direct it gets,
                  ratios that are exactly 1000x (a ug/mg slip), an InChIKey
                  that disagrees with its own SMILES, a CAS check digit that
                  does not check.

Those become a feature vector per source-value, and a weighted logistic over it
becomes an error probability. Every weight and threshold lives in
`adjudicator_weights.json`; the raw features are written out beside each
probability, so calibrating this is editing numbers in a file and refitting,
never editing code.

**It decides nothing.** The output is evidence for a resolution table a human
writes: which values disagree, by how much, with what support on each side, and
which ones nothing in the data can settle. `resolution-candidates.json` is that
table's shape, and no part of the pipeline reads it.

    python3 pipeline/audit/adjudicate.py                       # everything
    python3 pipeline/audit/adjudicate.py --top-substances 100  # the popular end
    python3 pipeline/audit/adjudicate.py --column binding --min-prob 0.7
    python3 pipeline/audit/adjudicate.py --substance Morphine
    python3 pipeline/audit/adjudicate.py --source freeodwiki

Offline and deterministic. It reads the built SQLite, the ChEMBL cache, the
dose.wiki evidence records, and RDKit; nothing it writes is read back by the
build.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
import statistics
import sys
import time
import unicodedata
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))  # pipeline/audit — for dose_sanity
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # pipeline/ — for chem_ids
import dose_sanity  # noqa: E402
from chem_ids import UNSPECIFIED_STEREO_BLOCK, inchikey_block1, inchikey_block2  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
DEFAULT_WEIGHTS = Path(__file__).resolve().parent / "adjudicator_weights.json"
DEFAULT_OUT = REPO / "data/adjudication"
TARGET_MAP_PATH = Path(__file__).resolve().parent / "binding_target_map.json"

CHEMBL_CACHE = REPO / "data/sources/chembl-cache.json"
DOSEWIKI_SOURCE = REPO / "data/sources/dosewiki.json"
DOSEWIKI_API = REPO / "Specs/evidence/dosewiki/api"
DOSEWIKI_MAPPING = REPO / "Specs/evidence/dosewiki/mapping.json"

COLUMNS = ("dose", "duration", "halflife", "binding", "chemistry")

#: Virtual sources. They carry no row in `sources`, so they have no priority and
#: the app never shows them — they exist to give a cell something to disagree
#: with. `piru-stored` is what the app *does* show for chemistry.
VIRTUAL_SOURCES = {
    "piru-stored": "the identifier columns on `substances`, i.e. what the app shows",
    "rdkit-smiles": "recomputed from the substance's own stored SMILES",
    "chembl-cache": "ChEMBL, joined on the InChIKey connectivity block",
    "dosewiki-api": "dose.wiki API records, joined through mapping.json by Piru row id",
}

# --------------------------------------------------------------------- weights


class Weights:
    """The tunables, read once. Attribute access with a default keeps a missing
    key from turning into a silent zero weight."""

    def __init__(self, data: dict):
        self.data = data
        self.features: dict[str, float] = {
            k: v for k, v in data["features"].items() if not k.startswith("_")
        }
        self.bias: float = float(data["bias"])
        self.thresholds: dict[str, float] = data["thresholds"]
        self.clustering: dict = data["clustering"]
        self.reliability: dict = data["reliability"]
        self.class_prior: dict = data["class_prior"]
        self.slips: dict = data["slips"]
        self.citation: dict = data["citation"]
        self.dosewiki: dict = data["dosewiki"]
        self.evidence_levels: dict = data["evidence_levels"]
        self.dependencies: dict[str, str] = {
            k: v for k, v in data.get("source_dependencies", {}).items() if not k.startswith("_")
        }
        self.pinned: dict[str, float] = {
            k: float(v) for k, v in data.get("pinned_weights", {}).items() if not k.startswith("_")
        }

    def threshold(self, name: str) -> float:
        return float(self.thresholds[name])

    @classmethod
    def load(cls, path: Path) -> Weights:
        with path.open() as handle:
            return cls(json.load(handle))


# ------------------------------------------------------------- normalization


GREEK = {
    "μ": "mu",
    "µ": "mu",
    "κ": "kappa",
    "δ": "delta",
    "σ": "sigma",
    "α": "alpha",
    "β": "beta",
    "γ": "gamma",
    "ω": "omega",
    "ε": "epsilon",
    "ρ": "rho",
    "θ": "theta",
    "π": "pi",
    "τ": "tau",
    "−": "-",
    "–": "-",
    "—": "-",
    "‑": "-",
}

#: Qualifier tokens that describe how a number was measured rather than what was
#: measured. A qualifier made only of these is dropped: `MOR (human)` and
#: `MOR (rat brain)` are the same target.
ASSAY_WORDS = {
    "human",
    "humans",
    "rat",
    "rats",
    "mouse",
    "mice",
    "murine",
    "porcine",
    "bovine",
    "guinea",
    "pig",
    "monkey",
    "cynomolgus",
    "recombinant",
    "native",
    "brain",
    "whole",
    "cortex",
    "cortical",
    "cerebellum",
    "striatum",
    "hippocampus",
    "membrane",
    "membranes",
    "synaptosomes",
    "synaptosomal",
    "tissue",
    "cell",
    "cells",
    "hek293",
    "hek",
    "cho",
    "in",
    "vitro",
    "vivo",
    "functional",
    "assay",
    "and",
    "or",
    "current",
    "inhibition",
    "channel",
    "combined",
    "non",
    "selective",
    "nonselective",
    "subtype",
    "postsynaptic",
    "presynaptic",
    "peripheral",
    "central",
    "downstream",
    "indirect",
    "low",
    "high",
    "affinity",
    "site",
    "sites",
    "binding",
    "estimated",
    "approx",
    "cerebral",
    "subunit",
    "subunits",
    "containing",
    "from",
    "of",
    "determined",
    "measured",
    "3h",
    "da",
    "ne",
    "ht",
    "hmor",
    "hdor",
    "hkor",
    "striatal",
}

#: Spellings of one qualifier folded together, so `(benzo site)` and
#: `(benzodiazepine site)` do not describe two different places on GABA-A.
QUALIFIER_SYNONYMS = {
    "benzo": "benzodiazepine",
    "bzd": "benzodiazepine",
    "bz": "benzodiazepine",
    "bz1": "benzodiazepine-omega1",
    "omega1": "benzodiazepine-omega1",
    "mk801": "mk-801",
}

#: Receptors whose subunit composition is written inline rather than in
#: parentheses — `GABA-A α1β2γ2`, `α4β2 nAChR`, which are the same target
#: written from either end. Only these families are split that way: outside them
#: a greek-letter-plus-digit is part of the receptor's own name (`α2δ-1`).
SUBUNIT_FAMILIES = {"gaba-a", "gabaa", "gaba", "nachr", "nicotinic", "nicotinic-nachr"}
#: A run of subunit names. The trailing letter is the `S` of `α1β2γ2S` and must
#: not eat the `b` of `α4β2` — hence the lookahead.
_SUBUNIT_RUN = re.compile(
    r"(?:(?:alpha|beta|gamma|delta|epsilon|rho|omega|pi|theta)[\s-]*\d+"
    r"(?:[a-z](?![a-z]))?[\s-]*)+",
    re.IGNORECASE,
)
#: Binding sites named inline in the target rather than parenthesized.
_INLINE_SITE = re.compile(r"\b(benzodiazepine|benzo|bzd|bz)\s*site\b", re.IGNORECASE)

#: Words that mean the parenthetical names a *different chemical entity* — a
#: metabolite, an enantiomer, the parent drug. Those are not the same
#: measurement and must not share a cell with the unqualified target.
ENTITY_MARKERS = (
    "enantiomer",
    "racemate",
    "racemic",
    "metabolite",
    "parent",
    "prodrug",
    "via ",
    "as ",
    "after conversion",
    "-methadone",
    "-tramadol",
    "-o-dsmt",
    "tilidine",
    "levorphanol",
    "norpropoxyphene",
    "psilocin",
    "morphine",
    "phenibut",
    "meprobamate",
    "am404",
    "tce",
)

#: Canonical target names. The key is the *canonicalized* spelling (greek folded
#: to latin, lowercased, punctuation collapsed); the value is the name a cell key
#: and a report use. Everything not listed keeps its canonicalized spelling, so
#: this table only has to carry the genuine synonym families.
TARGET_SYNONYMS = {
    "mor": "MOR",
    "mu-opioid": "MOR",
    "mu-opioid-mor": "MOR",
    "mu1": "MOR",
    "mu": "MOR",
    "kor": "KOR",
    "kappa-opioid": "KOR",
    "kappa-opioid-kor": "KOR",
    "kappa": "KOR",
    "dor": "DOR",
    "delta-opioid": "DOR",
    "delta": "DOR",
    "nop": "NOP",
    "nop-orl-1": "NOP",
    "orl-1": "NOP",
    "nmda": "NMDA",
    "gaba-a": "GABA-A",
    "gabaa": "GABA-A",
    "gaba-b": "GABA-B",
    "gabab": "GABA-B",
    "sigma": "sigma",
    "sigma-1": "sigma-1",
    "sigma1": "sigma-1",
    "sigma-2": "sigma-2",
    "sigma2": "sigma-2",
    "dat": "DAT",
    "net": "NET",
    "sert": "SERT",
    "vmat2": "VMAT2",
    "taar1": "TAAR1",
    "htaar1": "TAAR1",
    "5-ht1a": "5-HT1A",
    "5-ht2a": "5-HT2A",
    "5-ht2b": "5-HT2B",
    "5-ht2c": "5-HT2C",
    "5-ht3": "5-HT3",
    "5-ht6": "5-HT6",
    "5-ht7": "5-HT7",
    "h1": "H1",
    "h2": "H2",
    "h4": "H4",
    "d1": "D1",
    "d2": "D2",
    "d3": "D3",
    "d4": "D4",
    "d5": "D5",
    "m1": "M1",
    "m1-muscarinic": "M1",
    "m2": "M2",
    "m3": "M3",
    "m4": "M4",
    "m4-muscarinic": "M4",
    "m5": "M5",
    "muscarinic": "muscarinic",
    "nachr": "nAChR",
    "alpha1": "alpha-1",
    "alpha1-adrenergic": "alpha-1",
    "alpha1a": "alpha-1A",
    "alpha1b": "alpha-1B",
    "alpha2-adrenergic": "alpha-2",
    "alpha2-adrenoceptor": "alpha-2",
    "alpha2a": "alpha-2A",
    "alpha2a-adrenergic": "alpha-2A",
    "beta1": "beta-1",
    "beta2": "beta-2",
    "beta2-adrenergic": "beta-2",
    "beta3-adrenergic": "beta-3",
    "cb1": "CB1",
    "cb2": "CB2",
    "mao-a": "MAO-A",
    "mao-b": "MAO-B",
    "ampa": "AMPA",
    "alpha2delta-1": "alpha-2-delta-1",
    "alpha2delta-1-cacna2d1": "alpha-2-delta-1",
    "alpha2delta-2": "alpha-2-delta-2",
    "alpha2delta-2-cacna2d2": "alpha-2-delta-2",
    "herg": "hERG",
}

_DASH_TAIL = re.compile(r"\s+[-]{1,2}\s+.*$")


def split_parentheticals(text: str) -> tuple[str, list[str]]:
    """`(base, [top-level parentheticals])`, nesting included in the group.

    `α4β2 nAChR (HS, (α4)₂(β2)₃)` nests, and a regex that only matches innermost
    pairs leaves the outer brackets behind in the base — where they become part
    of the receptor's name and it never matches anything again.
    """
    base: list[str] = []
    groups: list[str] = []
    current: list[str] = []
    depth = 0
    for char in text:
        if char == "(":
            depth += 1
            if depth == 1:
                current = []
                continue
        elif char == ")":
            if depth > 0:
                depth -= 1
                if depth == 0:
                    groups.append("".join(current).strip())
                    continue
            else:
                continue
        (current if depth else base).append(char)
    if depth and current:
        groups.append("".join(current).strip())
    return "".join(base), [group for group in groups if group]


def fold_greek(text: str) -> str:
    out = []
    for char in unicodedata.normalize("NFKC", text):
        out.append(GREEK.get(char, char))
    return "".join(out)


def canonical_token(text: str) -> str:
    """Lowercase, greek folded, `receptor`/`the` dropped, punctuation collapsed."""
    folded = fold_greek(text).lower()
    folded = re.sub(r"\breceptors?\b", " ", folded)
    folded = re.sub(r"[^a-z0-9]+", "-", folded)
    return folded.strip("-")


def strip_assay_tokens(qualifier: str) -> str:
    """A qualifier with its assay words removed and its spellings folded.

    `DAT (uptake inhibition, human)` and `DAT (uptake)` describe the same
    measurement in two registries' house styles; what separates them is which
    incidentals each chose to write down.
    """
    tokens = [
        token
        for token in re.split(r"[^a-z0-9]+", canonical_token(qualifier))
        if token and token not in ASSAY_WORDS
    ]
    folded = [QUALIFIER_SYNONYMS.get(token, token) for token in tokens]
    return "-".join(dict.fromkeys(folded))


def split_inline_qualifiers(text: str) -> tuple[str, list[str]]:
    """Pull a subunit composition or a named site out of an unparenthesized target.

    `GABA-A α1β2γ2` and `α4β2 nAChR` write the composition on either side of the
    receptor; `GABA-A benzodiazepine site` writes the site with no brackets at
    all. All three have to reach the same shape as the parenthesized spelling or
    they never meet.
    """
    extra: list[str] = []
    site = _INLINE_SITE.search(text)
    if site:
        extra.append(site.group(0))
        text = _INLINE_SITE.sub(" ", text)
    runs = _SUBUNIT_RUN.findall(text)
    if runs:
        remainder = _SUBUNIT_RUN.sub(" ", text)
        if canonical_token(remainder) in SUBUNIT_FAMILIES:
            extra.extend(run.strip() for run in runs)
            text = remainder
    return text, extra


def classify_qualifier(qualifier: str, base_canonical: str) -> str:
    """`drop`, `entity`, or `subtype` for one parenthetical.

    `drop` — assay context; the same target measured somewhere else.
    `entity` — a different molecule (a metabolite, one enantiomer, the parent).
    `subtype` — a subunit composition or a distinct site on the same protein.

    An unrecognized qualifier is a `subtype`: keeping two rows apart costs a
    comparison, merging two different things costs a false finding.
    """
    canonical = canonical_token(qualifier)
    if not canonical or canonical == base_canonical:
        return "drop"
    if TARGET_SYNONYMS.get(canonical) and TARGET_SYNONYMS.get(canonical) == TARGET_SYNONYMS.get(
        base_canonical
    ):
        return "drop"
    lowered = fold_greek(qualifier).lower()
    if any(marker in lowered for marker in ENTITY_MARKERS):
        return "entity"
    tokens = [token for token in re.split(r"[^a-z0-9]+", lowered) if token]
    if tokens and all(token in ASSAY_WORDS for token in tokens):
        return "drop"
    return "subtype"


@dataclass
class TargetName:
    raw: str
    base: str  #: canonical target with every qualifier removed
    cell: str  #: the target a cell is keyed by (base + entity/subtype suffixes)
    kept: list[str] = field(default_factory=list)
    dropped: list[str] = field(default_factory=list)


def normalize_target(raw: str) -> TargetName:
    """Fold one of the DB's many spellings of a receptor onto a canonical name.

    Piru carries 22 spellings of the mu-opioid receptor, 17 of GABA-A and 14 of
    NMDA, because every source writes it its own way and half of them append
    the assay. Two rows can only be compared once they agree what they are
    about.
    """
    text = _DASH_TAIL.sub("", fold_greek(raw).strip())
    outside, qualifiers = split_parentheticals(text)
    stripped, inline = split_inline_qualifiers(outside)
    qualifiers.extend(inline)
    base_canonical = canonical_token(stripped)
    base = TARGET_SYNONYMS.get(base_canonical, base_canonical or canonical_token(raw))
    kept: list[str] = []
    dropped: list[str] = []
    for qualifier in qualifiers:
        kind = classify_qualifier(qualifier, base_canonical)
        if kind == "drop":
            dropped.append(qualifier)
        else:
            folded = strip_assay_tokens(qualifier)
            if folded:
                kept.append(f"{kind}:{folded}")
            else:
                dropped.append(qualifier)
    kept = sorted(set(kept))
    cell = base if not kept else base + " [" + "; ".join(kept) + "]"
    return TargetName(raw=raw, base=base, cell=cell, kept=kept, dropped=dropped)


#: Duration phase spellings → the DB's own phase names.
PHASE_ALIASES = {
    "come_up": "comeup",
    "comeup": "comeup",
    "come-up": "comeup",
    "onset": "onset",
    "peak": "peak",
    "offset": "offset",
    "after_effects": "afterglow",
    "afterglow": "afterglow",
    "after-effects": "afterglow",
    "total_duration": "total",
    "total": "total",
}

#: Time units → minutes.
TIME_UNITS = {
    "second": 1 / 60,
    "seconds": 1 / 60,
    "sec": 1 / 60,
    "s": 1 / 60,
    "minute": 1.0,
    "minutes": 1.0,
    "min": 1.0,
    "mins": 1.0,
    "m": 1.0,
    "hour": 60.0,
    "hours": 60.0,
    "hr": 60.0,
    "hrs": 60.0,
    "h": 60.0,
    "day": 1440.0,
    "days": 1440.0,
    "d": 1440.0,
}

#: Concentration units → nanomolar.
CONC_UNITS = {"pm": 0.001, "nm": 1.0, "um": 1000.0, "µm": 1000.0, "μm": 1000.0, "mm": 1e6}


def normalize_unit(unit: str) -> tuple[str | None, float, bool]:
    """`(dimension, factor-to-base, qualified)` for a dose unit.

    A qualified unit ("mg THC", "mg (salt)") measures a different thing than
    plain mg. It is recognized for its dimension so the row is not lost, and
    marked so nothing compares it to an unqualified neighbour.
    """
    dimension, factor = dose_sanity.normalize_unit(unit)
    if dimension is not None:
        return dimension, factor, False
    head = re.split(r"[\s(]", (unit or "").strip(), maxsplit=1)[0]
    dimension, factor = dose_sanity.normalize_unit(head)
    return dimension, factor, dimension is not None


def parse_duration_text(text: str | None) -> tuple[float, float] | None:
    """`2-3 hours` / `90 minutes` → (min, max) in minutes."""
    if not text:
        return None
    cleaned = fold_greek(text).lower().replace("–", "-").replace("~", " ")
    match = re.search(
        r"(\d+(?:\.\d+)?)\s*(?:-|to)\s*(\d+(?:\.\d+)?)\s*([a-z]+)|(\d+(?:\.\d+)?)\s*([a-z]+)",
        cleaned,
    )
    if not match:
        return None
    if match.group(3):
        unit = TIME_UNITS.get(match.group(3))
        if unit is None:
            return None
        return float(match.group(1)) * unit, float(match.group(2)) * unit
    unit = TIME_UNITS.get(match.group(5) or "")
    if unit is None:
        return None
    value = float(match.group(4)) * unit
    return value, value


_AFFINITY = re.compile(
    r"\b(ki|kd|ec50|ic50)\b\s*[=:~]?\s*(\d+(?:\.\d+)?)"
    r"(?:\s*(?:-|to)\s*(\d+(?:\.\d+)?))?\s*(pm|nm|um|µm|μm|mm)\b",
    re.IGNORECASE,
)


def parse_affinity(text: str | None) -> tuple[str, float, bool] | None:
    """`Ki 4519 nM` → (`Ki`, 4519.0, is_range). A range becomes its geometric
    mean, marked, because affinities are log-scale quantities."""
    if not text:
        return None
    # Micro stays a letter here. `fold_greek` would turn µM into "muM", and the
    # unit is the whole point of the number.
    normalized = unicodedata.normalize("NFKC", text).replace("μ", "u").replace("\xb5", "u")
    match = _AFFINITY.search(normalized)
    if not match:
        return None
    measure = match.group(1).lower()
    measure = {"ki": "Ki", "kd": "Kd", "ec50": "EC50", "ic50": "IC50"}[measure]
    factor = CONC_UNITS[match.group(4).lower()]
    low = float(match.group(2)) * factor
    if match.group(3):
        high = float(match.group(3)) * factor
        return measure, math.sqrt(low * high), True
    return measure, low, False


def cas_check_digit_ok(cas: str | None) -> bool | None:
    """Whether a CAS number's trailing check digit checks. `None` when the
    string is not shaped like a CAS number at all."""
    if not cas:
        return None
    match = re.fullmatch(r"(\d{2,7})-(\d{2})-(\d)", cas.strip())
    if not match:
        return None
    digits = (match.group(1) + match.group(2))[::-1]
    total = sum(int(digit) * (index + 1) for index, digit in enumerate(digits))
    return total % 10 == int(match.group(3))


# ------------------------------------------------------------------ the model


@dataclass
class Value:
    """One source's claim about one cell."""

    source: str
    numeric: float | None
    text: str | None
    provenance: dict[str, Any]
    features: dict[str, float] = field(default_factory=dict)
    cluster: int = -1
    probability: float = 0.0
    reasons: list[str] = field(default_factory=list)

    @property
    def display(self) -> str:
        if self.text is not None:
            return self.text
        if self.numeric is None:
            return "—"
        return format_number(self.numeric)


@dataclass
class Cell:
    column: str
    key: str
    substance_id: int
    substance_uid: str | None
    substance: str
    popularity: float
    values: list[Value] = field(default_factory=list)
    consensus: float | None = None
    consensus_text: str | None = None
    n_clusters: int = 0
    evidence_level: str = "none"
    class_level: str | None = None
    class_members: int = 0
    #: Sources standing behind this cell's consensus. A class prior built out of
    #: peers whose consensus rests on one source cannot then judge that source.
    consensus_sources: frozenset[str] = field(default_factory=frozenset)
    flags: list[str] = field(default_factory=list)
    unit: str = ""

    @property
    def cell_id(self) -> str:
        return f"{self.substance_uid or self.substance_id}|{self.key}"

    @property
    def max_probability(self) -> float:
        return max((value.probability for value in self.values), default=0.0)

    @property
    def spread(self) -> float:
        """Largest ratio between any two independent numeric claims."""
        numbers = [value.numeric for value in self.values if value.numeric and value.numeric > 0]
        if len(numbers) < 2:
            return 1.0
        return max(numbers) / min(numbers)


def format_number(value: float) -> str:
    if value == 0:
        return "0"
    magnitude = abs(value)
    if magnitude >= 100:
        return f"{value:,.0f}"
    if magnitude >= 1:
        return f"{value:.3g}"
    return f"{value:.3g}"


# ------------------------------------------------------------------- loading


@dataclass
class Substance:
    id: int
    uid: str | None
    name: str
    popularity: float
    inchikey: str | None
    cas: str | None
    formula: str | None
    molecular_weight: float | None
    smiles: str | None
    drug_class: str | None
    #: The molecule this preparation's numbers are really about, when it is a
    #: preparation. Cannabis dosed in grams of plant against THC dosed in
    #: milligrams is a basis difference, not a thousandfold disagreement.
    active_ingredient_id: int | None = None
    classes: list[str] = field(default_factory=list)
    interaction_classes: list[str] = field(default_factory=list)
    categories: list[str] = field(default_factory=list)


def load_substances(conn: sqlite3.Connection) -> dict[int, Substance]:
    out: dict[int, Substance] = {}
    for row in conn.execute(
        "SELECT id, substance_uid, canonical_name, popularity, inchikey, cas, formula, "
        "molecular_weight, smiles, drug_class, active_ingredient_substance_id FROM substances"
    ):
        out[row[0]] = Substance(
            id=row[0],
            uid=row[1],
            name=row[2],
            popularity=float(row[3] or 0.0),
            inchikey=row[4],
            cas=row[5],
            formula=row[6],
            molecular_weight=row[7],
            smiles=row[8],
            drug_class=row[9],
            active_ingredient_id=row[10],
        )
    for substance_id, slug in conn.execute(
        "SELECT sc.substance_id, cc.slug FROM substance_classes sc "
        "JOIN class_contexts cc ON cc.id = sc.class_context_id"
    ):
        if substance_id in out:
            out[substance_id].classes.append(slug)
    for substance_id, drug_class in conn.execute(
        "SELECT substance_id, drug_class FROM substance_interaction_classes "
        "WHERE substance_id IS NOT NULL"
    ):
        if substance_id in out:
            out[substance_id].interaction_classes.append(drug_class)
    for substance_id, category in conn.execute("SELECT substance_id, category FROM categories"):
        if substance_id in out and category not in out[substance_id].categories:
            out[substance_id].categories.append(category)
    return out


def load_sources(conn: sqlite3.Connection) -> dict[int, tuple[str, int, bool]]:
    return {
        row[0]: (row[1], row[2], bool(row[3]))
        for row in conn.execute("SELECT id, slug, default_priority, default_enabled FROM sources")
    }


def load_citations(conn: sqlite3.Connection) -> dict[int, dict]:
    return {
        row[0]: {"doi": row[1], "pmid": row[2], "is_review": bool(row[3]), "year": row[4]}
        for row in conn.execute("SELECT id, doi, pmid, is_review, year FROM citations")
    }


# ---------------------------------------------------------------- dose.wiki


@dataclass
class DoseWikiRecord:
    slug: str
    substance_id: int
    relationship: str
    confidence: str
    expert_reviewed: bool
    data: dict


DOSEWIKI_IDS = REPO / "data/curated/dosewiki-ids.json"


def load_dosewiki(
    weights: Weights, conn: sqlite3.Connection | None = None
) -> tuple[list[DoseWikiRecord], str]:
    """dose.wiki records joined to Piru rows by structure, never by name.

    Prefers the committed snapshot `data/sources/dosewiki.json`, whose records
    are keyed by dose.wiki slug and joined through the hand-reviewed
    `data/curated/dosewiki-ids.json` (slug -> substance_uid) against the DB;
    falls back to the evidence API records joined through `mapping.json`. An
    absent join is not an error — the ingest may not have landed.
    """
    if DOSEWIKI_SOURCE.exists() and conn is not None:
        with DOSEWIKI_SOURCE.open() as handle:
            payload = json.load(handle)
        records = payload.get("records", []) if isinstance(payload, dict) else payload
        uid_by_slug: dict[str, str] = {}
        if DOSEWIKI_IDS.exists():
            with DOSEWIKI_IDS.open() as handle:
                for slug, entry in json.load(handle).items():
                    if isinstance(entry, dict) and entry.get("substance_uid"):
                        uid_by_slug[slug] = entry["substance_uid"]
        id_by_uid = {
            uid: int(row_id)
            for row_id, uid in conn.execute(
                "SELECT id, substance_uid FROM substances WHERE substance_uid IS NOT NULL"
            )
        }
        id_by_slug = {
            slug: int(row_id)
            for row_id, slug in conn.execute(
                "SELECT id, dosewiki_slug FROM substances WHERE dosewiki_slug IS NOT NULL"
            )
        }
        out = []
        for entry in records:
            slug = entry.get("slug", "")
            substance_id = id_by_uid.get(uid_by_slug.get(slug, "")) or id_by_slug.get(slug)
            if not substance_id:
                continue
            out.append(
                DoseWikiRecord(
                    slug=slug,
                    substance_id=substance_id,
                    relationship="identical",
                    confidence="high",
                    expert_reviewed=bool(entry.get("expert_reviewed")),
                    data=entry,
                )
            )
        return out, str(DOSEWIKI_SOURCE)
    if not (DOSEWIKI_MAPPING.exists() and DOSEWIKI_API.is_dir()):
        return [], "absent"
    with DOSEWIKI_MAPPING.open() as handle:
        mapping = json.load(handle)
    out = []
    for entry in mapping:
        substance_id = entry.get("piru_id")
        slug = entry.get("dw_slug")
        if not substance_id or not slug:
            continue
        path = DOSEWIKI_API / f"{slug}.json"
        if not path.exists():
            continue
        with path.open() as handle:
            payload = json.load(handle)
        out.append(
            DoseWikiRecord(
                slug=slug,
                substance_id=int(substance_id),
                relationship=entry.get("relationship") or "unverified",
                confidence=(entry.get("confidence") or "low").lower(),
                expert_reviewed=bool(payload.get("data", {}).get("expert_reviewed")),
                data=payload.get("data", {}),
            )
        )
    return out, str(DOSEWIKI_API)


#: The registry slug the dose.wiki ingest writes its rows under.
DOSEWIKI_DB_SLUG = "dosewiki"

#: Which table each numeric column's DB rows live in.
DOSEWIKI_DB_TABLES = {
    "dose": "dose_ranges",
    "duration": "durations",
    "halflife": "half_lives",
    "binding": "bindings",
}


def dosewiki_in_db(conn: sqlite3.Connection) -> dict[str, set[int]]:
    """Substances whose dose.wiki numbers are already ingested, per column.

    Once the ingest lands a substance's rows, the evidence records for it are the
    same claim read a second way, and counting both would have dose.wiki
    corroborating itself. Chemistry is not in this map: the ingest fills gaps
    only, so the DB never carries dose.wiki's competing identifiers, and the
    evidence records stay the only place that disagreement is visible.
    """
    row = conn.execute("SELECT id FROM sources WHERE slug = ?", (DOSEWIKI_DB_SLUG,)).fetchone()
    if row is None:
        return {}
    source_id = row[0]
    out: dict[str, set[int]] = {}
    for column, table in DOSEWIKI_DB_TABLES.items():
        out[column] = {
            record[0]
            for record in conn.execute(
                f"SELECT DISTINCT substance_id FROM {table} WHERE source_id = ?",  # noqa: S608
                (source_id,),
            )
        }
    return out


def pick_numeric_dosewiki(
    records: list[DoseWikiRecord], weights: Weights
) -> dict[int, DoseWikiRecord]:
    """At most one dose.wiki record per Piru substance for the numeric columns.

    Two dose.wiki compounds can map onto one Piru row (that is itself a finding,
    and the chemistry column reports it) — but their dose ladders describe
    different molecules, so only the best-joined one may vote on a number.
    """
    allowed = set(weights.dosewiki["numeric_relationships"])
    rank = weights.dosewiki["relationship_rank"]
    confidence_rank = weights.dosewiki["confidence_rank"]
    best: dict[int, DoseWikiRecord] = {}
    for record in records:
        if record.relationship not in allowed:
            continue
        key = (
            rank.get(record.relationship, 9),
            confidence_rank.get(record.confidence, 9),
            0 if record.expert_reviewed else 1,
            record.slug,
        )
        incumbent = best.get(record.substance_id)
        if incumbent is None:
            best[record.substance_id] = record
            continue
        incumbent_key = (
            rank.get(incumbent.relationship, 9),
            confidence_rank.get(incumbent.confidence, 9),
            0 if incumbent.expert_reviewed else 1,
            incumbent.slug,
        )
        if key < incumbent_key:
            best[record.substance_id] = record
    return best


# ------------------------------------------------------------- cell builders


def dose_cell_key(
    route: str, salt: str | None, isomer: str | None, context: str, dimension: str, band: str
) -> str:
    return f"dose|{route}|{salt or ''}|{isomer or ''}|{context}|{dimension}|{band}"


def duration_cell_key(
    route: str, salt: str | None, isomer: str | None, phase: str, bound: str
) -> str:
    return f"duration|{route}|{salt or ''}|{isomer or ''}|{phase}|{bound}"


def build_dose_cells(
    conn: sqlite3.Connection,
    substances: dict[int, Substance],
    sources: dict[int, tuple[str, int, bool]],
    citations: dict[int, dict],
    dosewiki: dict[int, DoseWikiRecord],
    ingested: set[int],
) -> list[Cell]:
    columns = ", ".join(dose_sanity.LADDER)
    rows = list(
        conn.execute(
            f"SELECT id, substance_id, route, source_id, unit, salt_form, isomer, "  # noqa: S608
            f"dose_context, citation_id, {columns} FROM dose_ranges"
        )
    )
    cells: dict[tuple[int, str], Cell] = {}
    # What the app shows per (substance, route): lowest default_priority among
    # enabled sources, exactly as `SubstanceStore` resolves it.
    resolved: dict[tuple[int, str], tuple[int, int, str]] = {}
    contexts: dict[tuple[int, str], set[str]] = defaultdict(set)
    for row in rows:
        slug, priority, enabled = sources[row[3]]
        route = dose_sanity.normalize_route(row[2])
        contexts[(row[1], route)].add(row[7])
        if not enabled:
            continue
        key = (row[1], route)
        if key not in resolved or (priority, row[0]) < (resolved[key][0], resolved[key][1]):
            resolved[key] = (priority, row[0], row[7])

    def add(
        substance_id: int,
        route: str,
        salt: str | None,
        isomer: str | None,
        context: str,
        dimension: str,
        band: str,
        source: str,
        value: float,
        unit: str,
        provenance: dict,
    ) -> None:
        substance = substances.get(substance_id)
        if substance is None:
            return
        key = dose_cell_key(route, salt, isomer, context, dimension, band)
        cell = cells.get((substance_id, key))
        if cell is None:
            cell = Cell(
                column="dose",
                key=key,
                substance_id=substance_id,
                substance_uid=substance.uid,
                substance=substance.name,
                popularity=substance.popularity,
                unit={"mass": "mg", "mass_per_kg": "mg/kg", "volume": "mL", "iu": "IU"}.get(
                    dimension, dimension
                ),
            )
            cells[(substance_id, key)] = cell
        cell.values.append(Value(source=source, numeric=value, text=None, provenance=provenance))

    for row in rows:
        (row_id, substance_id, raw_route, source_id, unit, salt, isomer, context, citation_id) = (
            row[:9]
        )
        slug, priority, enabled = sources[source_id]
        route = dose_sanity.normalize_route(raw_route)
        dimension, factor, qualified = normalize_unit(unit)
        if dimension is None:
            continue
        ladder = {
            name: float(value) * factor
            for name, value in zip(dose_sanity.LADDER, row[9:], strict=True)
            if value is not None
        }
        violations = ladder_violations(ladder)
        route_violation = route_order_violation(
            substance_id, route, ladder, resolved, rows, sources, substances
        )
        context_conflict = (
            context == "therapeutic"
            and resolved.get((substance_id, route), (None, None, None))[1] == row_id
            and "recreational" in contexts[(substance_id, route)]
        )
        for band, value in ladder.items():
            add(
                substance_id,
                route,
                salt,
                isomer,
                context,
                dimension,
                band,
                slug,
                value,
                unit,
                {
                    "row_id": row_id,
                    "unit": unit,
                    "unit_qualified": qualified,
                    "priority": priority,
                    "enabled": enabled,
                    "resolves_in_app": resolved.get((substance_id, route), (None, None, None))[1]
                    == row_id,
                    "citation_id": citation_id,
                    "citation": citations.get(citation_id),
                    "ladder_break": band in violations["break"],
                    "bounds_inverted": band in violations["inverted"],
                    "point_estimate": band in violations["point"],
                    "route_order_violation": route_violation,
                    "context_conflict": context_conflict,
                    "dose_context": context,
                },
            )

    for substance_id, record in dosewiki.items():
        if substance_id in ingested:
            continue  # its dose.wiki numbers are already DB rows
        if substance_id not in substances:
            continue
        for route_entry in (record.data.get("dosage") or {}).get("routes") or []:
            route = dose_sanity.normalize_route(route_entry.get("route") or "")
            ladder, unit = dosewiki_ladder(route_entry)
            if not ladder:
                continue
            violations = ladder_violations(ladder)
            for band, value in ladder.items():
                add(
                    substance_id,
                    route,
                    None,
                    None,
                    "recreational",
                    "mass",
                    band,
                    "dosewiki-api",
                    value,
                    unit,
                    {
                        "row_id": None,
                        "slug": record.slug,
                        "unit": unit,
                        "unit_qualified": False,
                        "priority": None,
                        "enabled": False,
                        "resolves_in_app": False,
                        "citation_id": None,
                        "citation": None,
                        "ladder_break": band in violations["break"],
                        "bounds_inverted": band in violations["inverted"],
                        "point_estimate": band in violations["point"],
                        "route_order_violation": False,
                        "context_conflict": False,
                        "dose_context": "recreational",
                        "join_relationship": record.relationship,
                    },
                )
    built = list(cells.values())
    attach_context_alternatives(built)
    mark_unit_basis(built, substances)
    return built


def mark_unit_basis(cells: list[Cell], substances: dict[int, Substance]) -> None:
    """Mark the cells whose claims are not counted in the same thing.

    Psilocybin mushrooms oral: piru-curated says 2.5 stored as `g`, PsychonautWiki
    says 2.5 stored as `mg`. Both numbers are 2.5 — one counts dried fruiting
    body and the other counts psilocybin, and folding them to milligrams turns a
    disagreement about the *basis* into a hundredfold disagreement about a dose.
    The fix is to settle which unit the row should carry, so it must not be
    scored as though someone typed a wrong number.
    """
    for cell in cells:
        units = {
            (value.provenance.get("unit") or "").strip().lower()
            for value in cell.values
            if value.provenance.get("unit")
        }
        substance = substances.get(cell.substance_id)
        preparation = bool(substance and substance.active_ingredient_id)
        # Clustering has not run yet, so the preparation arm reads the raw
        # spread: two claims about a preparation that are far apart are the
        # plant and the molecule, not two opinions about the plant.
        if len(units) > 1 or (preparation and cell.spread >= 2.0):
            for value in cell.values:
                value.provenance["unit_basis_mismatch"] = True
                value.provenance["stored_units"] = sorted(units)


def attach_context_alternatives(cells: list[Cell]) -> None:
    """Put the recreational numbers beside a therapeutic ladder that outranks them.

    The two contexts are separate cells on purpose — a clinical range and a
    recreational one are different quantities and comparing them manufactures
    outliers. But when the therapeutic row is the one the app resolves, the
    reader deciding what to do about it needs the range it displaced, and it
    lives in a cell they would otherwise have to go and find.
    """
    recreational: dict[tuple[int, str, str, str], list[tuple[str, float]]] = defaultdict(list)
    for cell in cells:
        _, route, _salt, _isomer, context, dimension, band = cell.key.split("|")
        if context != "recreational":
            continue
        for value in cell.values:
            if value.numeric is not None:
                recreational[(cell.substance_id, route, dimension, band)].append(
                    (value.source, value.numeric)
                )
    for cell in cells:
        _, route, _salt, _isomer, context, dimension, band = cell.key.split("|")
        if context != "therapeutic":
            continue
        alternatives = recreational.get((cell.substance_id, route, dimension, band))
        if not alternatives:
            continue
        for value in cell.values:
            if value.provenance.get("context_conflict"):
                value.provenance["recreational_alternative"] = [
                    f"{source} {format_number(number)}" for source, number in sorted(alternatives)
                ]


#: dose.wiki tier names → Piru's ladder columns.
DOSEWIKI_TIERS = (
    ("threshold", "min", "threshold"),
    ("light", "min", "light_lower"),
    ("light", "max", "light_upper"),
    ("moderate", "min", "common_lower"),
    ("moderate", "max", "common_upper"),
    ("strong", "min", "strong_lower"),
    ("strong", "max", "strong_upper"),
    ("heavy", "min", "heavy"),
)


def dosewiki_ladder(route_entry: dict) -> tuple[dict[str, float], str]:
    """dose.wiki's `dose_ranges` block as a Piru ladder in mg."""
    ranges = route_entry.get("dose_ranges") or {}
    ladder: dict[str, float] = {}
    unit_seen = "mg"
    for tier, bound, band in DOSEWIKI_TIERS:
        block = ranges.get(tier) or {}
        raw = block.get(bound)
        if raw is None:
            continue
        dimension, factor, _ = normalize_unit(block.get("unit") or "mg")
        if dimension != "mass":
            continue
        unit_seen = block.get("unit") or "mg"
        ladder[band] = float(raw) * factor
    return ladder, unit_seen


def ladder_violations(ladder: dict[str, float]) -> dict[str, set[str]]:
    """Which bands of one ladder contradict the rest of that same ladder."""
    out = {"break": set(), "inverted": set(), "point": set()}
    for _label, sequence in dose_sanity.LADDER_SEQUENCES:
        present = [(name, ladder[name]) for name in sequence if name in ladder]
        for (name, value), (next_name, next_value) in zip(present, present[1:], strict=False):
            if next_value < value:
                out["break"].update({name, next_name})
    for _tier, lower, upper in dose_sanity.TIER_BOUNDS:
        if lower in ladder and upper in ladder:
            if ladder[upper] < ladder[lower]:
                out["inverted"].update({lower, upper})
            elif ladder[upper] == ladder[lower]:
                out["point"].update({lower, upper})
    return out


def route_order_violation(
    substance_id: int,
    route: str,
    ladder: dict[str, float],
    resolved: dict,
    rows: list,
    sources: dict,
    substances: dict,
) -> bool:
    """True when this route's common tier exceeds a *less* bioavailable route's.

    The ordering table is `dose_sanity.ROUTE_RANK` — a route that reaches the
    blood more completely cannot need more drug.
    """
    rank = dose_sanity.ROUTE_RANK.get(route)
    if rank is None:
        return False
    mine = tier_midpoint(ladder, "common_lower", "common_upper")
    if mine is None:
        return False
    for other in rows:
        if other[1] != substance_id:
            continue
        other_route = dose_sanity.normalize_route(other[2])
        other_rank = dose_sanity.ROUTE_RANK.get(other_route)
        if other_rank is None or other_rank <= rank:
            continue
        dimension, factor, _ = normalize_unit(other[4])
        if dimension != "mass":
            continue
        other_ladder = {
            name: float(value) * factor
            for name, value in zip(dose_sanity.LADDER, other[9:], strict=True)
            if value is not None
        }
        theirs = tier_midpoint(other_ladder, "common_lower", "common_upper")
        if theirs and theirs > 0 and mine / theirs > 1.5:
            return True
    return False


def tier_midpoint(ladder: dict[str, float], lower: str, upper: str) -> float | None:
    bounds = [ladder[name] for name in (lower, upper) if name in ladder]
    return sum(bounds) / len(bounds) if bounds else None


def build_duration_cells(
    conn: sqlite3.Connection,
    substances: dict[int, Substance],
    sources: dict[int, tuple[str, int, bool]],
    citations: dict[int, dict],
    dosewiki: dict[int, DoseWikiRecord],
    ingested: set[int],
) -> list[Cell]:
    cells: dict[tuple[int, str], Cell] = {}

    def add(substance_id, route, salt, isomer, phase, bound, source, value, provenance):
        substance = substances.get(substance_id)
        if substance is None or value is None or value <= 0:
            return
        key = duration_cell_key(route, salt, isomer, phase, bound)
        cell = cells.get((substance_id, key))
        if cell is None:
            cell = Cell(
                column="duration",
                key=key,
                substance_id=substance_id,
                substance_uid=substance.uid,
                substance=substance.name,
                popularity=substance.popularity,
                unit="min",
            )
            cells[(substance_id, key)] = cell
        cell.values.append(
            Value(source=source, numeric=float(value), text=None, provenance=provenance)
        )

    for row in conn.execute(
        "SELECT id, substance_id, route, source_id, phase, min_minutes, max_minutes, "
        "salt_form, isomer, citation_id FROM durations"
    ):
        (
            row_id,
            substance_id,
            raw_route,
            source_id,
            phase,
            low,
            high,
            salt,
            isomer,
            citation_id,
        ) = row
        slug, priority, enabled = sources[source_id]
        route = dose_sanity.normalize_route(raw_route)
        phase = PHASE_ALIASES.get((phase or "").lower(), (phase or "").lower())
        point = low == high
        inverted = high < low
        for bound, value in (("min", low), ("max", high)):
            add(
                substance_id,
                route,
                salt,
                isomer,
                phase,
                bound,
                slug,
                value,
                {
                    "row_id": row_id,
                    "priority": priority,
                    "enabled": enabled,
                    "citation_id": citation_id,
                    "citation": citations.get(citation_id),
                    "point_estimate": point,
                    "bounds_inverted": inverted,
                },
            )

    for substance_id, record in dosewiki.items():
        if substance_id in ingested:
            continue  # its dose.wiki numbers are already DB rows
        if substance_id not in substances:
            continue
        for route_entry in (record.data.get("duration") or {}).get("routes") or []:
            route = dose_sanity.normalize_route(route_entry.get("route") or "")
            for raw_phase, block in (route_entry.get("stages") or {}).items():
                phase = PHASE_ALIASES.get(raw_phase.lower())
                if phase is None or not isinstance(block, dict):
                    continue
                factor = TIME_UNITS.get((block.get("unit") or "minutes").lower())
                if factor is None:
                    continue
                low, high = block.get("min"), block.get("max")
                point = low is not None and low == high
                for bound, value in (("min", low), ("max", high)):
                    if value is None:
                        continue
                    add(
                        substance_id,
                        route,
                        None,
                        None,
                        phase,
                        bound,
                        "dosewiki-api",
                        float(value) * factor,
                        {
                            "row_id": None,
                            "slug": record.slug,
                            "priority": None,
                            "enabled": False,
                            "citation_id": None,
                            "citation": None,
                            "point_estimate": point,
                            "bounds_inverted": False,
                            "join_relationship": record.relationship,
                        },
                    )
    return list(cells.values())


def build_halflife_cells(
    conn: sqlite3.Connection,
    substances: dict[int, Substance],
    sources: dict[int, tuple[str, int, bool]],
    citations: dict[int, dict],
    dosewiki: dict[int, DoseWikiRecord],
    ingested: set[int],
) -> list[Cell]:
    cells: dict[int, Cell] = {}

    def cell_for(substance_id: int) -> Cell | None:
        substance = substances.get(substance_id)
        if substance is None:
            return None
        cell = cells.get(substance_id)
        if cell is None:
            cell = Cell(
                column="halflife",
                key="halflife",
                substance_id=substance_id,
                substance_uid=substance.uid,
                substance=substance.name,
                popularity=substance.popularity,
                unit="min",
            )
            cells[substance_id] = cell
        return cell

    for substance_id, source_id, minutes, citation_id in conn.execute(
        "SELECT substance_id, source_id, half_life_minutes, citation_id FROM half_lives "
        "WHERE half_life_minutes > 0"
    ):
        cell = cell_for(substance_id)
        if cell is None:
            continue
        slug, priority, enabled = sources[source_id]
        cell.values.append(
            Value(
                source=slug,
                numeric=float(minutes),
                text=None,
                provenance={
                    "priority": priority,
                    "enabled": enabled,
                    "citation_id": citation_id,
                    "citation": citations.get(citation_id),
                },
            )
        )

    for substance_id, record in dosewiki.items():
        if substance_id in ingested:
            continue  # its dose.wiki numbers are already DB rows
        stated: list[float] = []
        for route_entry in (record.data.get("duration") or {}).get("routes") or []:
            parsed = parse_duration_text(route_entry.get("half_life"))
            if parsed:
                stated.append(math.sqrt(parsed[0] * parsed[1]))
        if not stated:
            continue
        cell = cell_for(substance_id)
        if cell is None:
            continue
        cell.values.append(
            Value(
                source="dosewiki-api",
                numeric=statistics.median(stated),
                text=None,
                provenance={
                    "slug": record.slug,
                    "priority": None,
                    "enabled": False,
                    "citation_id": None,
                    "citation": None,
                    "join_relationship": record.relationship,
                },
            )
        )
    return list(cells.values())


BINDING_MEASURES = (("ki_nm", "Ki"), ("ec50_nm", "EC50"), ("ic50_nm", "IC50"))


def build_binding_cells(
    conn: sqlite3.Connection,
    substances: dict[int, Substance],
    sources: dict[int, tuple[str, int, bool]],
    citations: dict[int, dict],
    dosewiki: dict[int, DoseWikiRecord],
    ingested: set[int],
    target_map: dict[str, TargetName],
) -> list[Cell]:
    cells: dict[tuple[int, str], Cell] = {}

    def add(substance_id, target: TargetName, measure, source, value, provenance):
        substance = substances.get(substance_id)
        if substance is None or not value or value <= 0:
            return
        key = f"binding|{target.cell}|{measure}"
        cell = cells.get((substance_id, key))
        if cell is None:
            cell = Cell(
                column="binding",
                key=key,
                substance_id=substance_id,
                substance_uid=substance.uid,
                substance=substance.name,
                popularity=substance.popularity,
                unit="nM",
            )
            cells[(substance_id, key)] = cell
        provenance = dict(provenance)
        provenance["target_raw"] = target.raw
        provenance["target_base"] = target.base
        cell.values.append(
            Value(source=source, numeric=float(value), text=None, provenance=provenance)
        )

    for row in conn.execute(
        "SELECT id, substance_id, target, action, ki_nm, ec50_nm, ic50_nm, source_id, "
        "citation_id, is_review, confidence, species, assay_system FROM bindings"
    ):
        (
            row_id,
            substance_id,
            raw_target,
            action,
            ki,
            ec50,
            ic50,
            source_id,
            citation_id,
            is_review,
            confidence,
            species,
            assay,
        ) = row
        slug, priority, enabled = sources[source_id]
        target = target_map.setdefault(raw_target, normalize_target(raw_target))
        provenance = {
            "row_id": row_id,
            "action": action,
            "priority": priority,
            "enabled": enabled,
            "citation_id": citation_id,
            "citation": citations.get(citation_id),
            "is_review": bool(is_review),
            "confidence": confidence,
            "assay_context": bool(species) and bool(assay),
            "species": species,
            "assay_system": assay,
        }
        for column, measure in zip(
            ("ki_nm", "ec50_nm", "ic50_nm"), ("Ki", "EC50", "IC50"), strict=True
        ):
            value = {"ki_nm": ki, "ec50_nm": ec50, "ic50_nm": ic50}[column]
            if value:
                add(substance_id, target, measure, slug, value, provenance)

    for substance_id, record in dosewiki.items():
        if substance_id in ingested:
            continue  # its dose.wiki numbers are already DB rows
        pharmacology = record.data.get("pharmacology") or {}
        for entry in pharmacology.get("binding_sites") or []:
            raw_target = entry.get("target") or entry.get("receptor")
            if not raw_target:
                continue
            parsed = parse_affinity(entry.get("affinity"))
            if not parsed:
                continue
            measure, value, is_range = parsed
            if measure not in ("Ki", "EC50", "IC50"):
                continue
            target = target_map.setdefault(raw_target, normalize_target(raw_target))
            add(
                substance_id,
                target,
                measure,
                "dosewiki-api",
                value,
                {
                    "row_id": None,
                    "slug": record.slug,
                    "action": entry.get("tag"),
                    "priority": None,
                    "enabled": False,
                    "citation_id": None,
                    "citation": None,
                    "is_review": False,
                    "confidence": None,
                    "assay_context": False,
                    "species": None,
                    "assay_system": None,
                    "affinity_is_range": is_range,
                    "join_relationship": record.relationship,
                },
            )
    built = list(cells.values())
    mark_assay_context(built)
    return built


def mark_assay_context(cells: list[Cell]) -> None:
    """Mark binding cells whose claims were measured in different systems.

    MDMA's DAT EC50 is 22,000 nM in human recombinant cells and 51.2 nM in rat
    synaptosomes. That is a four-hundredfold gap and both numbers are right —
    the reader has to see the systems named or they will read it as a
    transcription error and 'fix' one of them.
    """
    for cell in cells:
        systems = {
            (value.provenance.get("species"), value.provenance.get("assay_system"))
            for value in cell.values
        }
        stated = {pair for pair in systems if pair != (None, None)}
        if len(stated) < 2:
            continue
        for value in cell.values:
            value.provenance["assay_context_differs"] = True
            value.provenance["assay_systems"] = sorted(
                f"{species or '?'}/{system or '?'}" for species, system in stated
            )


CHEMISTRY_FIELDS = ("inchikey", "connectivity", "cas", "formula", "molecular_weight")


def build_chemistry_cells(
    substances: dict[int, Substance],
    dosewiki_all: list[DoseWikiRecord],
    chembl: dict[str, dict],
    rdkit_keys: dict[int, tuple[str | None, str | None, float | None]],
) -> list[Cell]:
    """Chemistry identity, with every claim about the molecule side by side.

    Unlike the numeric columns this takes *every* dose.wiki record mapped to a
    Piru row. Two dose.wiki compounds claiming one row is not a join to
    disambiguate — it is the finding (Piru's `4-AcO-MET` holds 4-AcO-MiPT's
    structure, so dose.wiki's `4-aco-met` and `4-aco-mipt` both point at it).
    """
    by_substance: dict[int, list[DoseWikiRecord]] = defaultdict(list)
    for record in dosewiki_all:
        by_substance[record.substance_id].append(record)

    cells: list[Cell] = []
    for substance in substances.values():
        claims: list[tuple[str, dict, dict]] = []
        derived_key, derived_formula, derived_weight = rdkit_keys.get(
            substance.id, (None, None, None)
        )
        stored_check = cas_check_digit_ok(substance.cas)
        claims.append(
            (
                "piru-stored",
                {
                    "inchikey": substance.inchikey,
                    "connectivity": inchikey_block1(substance.inchikey),
                    "cas": substance.cas,
                    "formula": substance.formula,
                    "molecular_weight": substance.molecular_weight,
                },
                {"cas_checkdigit_ok": stored_check, "smiles": substance.smiles},
            )
        )
        if derived_key or derived_formula:
            claims.append(
                (
                    "rdkit-smiles",
                    {
                        "inchikey": derived_key,
                        "connectivity": inchikey_block1(derived_key),
                        "cas": None,
                        "formula": derived_formula,
                        "molecular_weight": derived_weight,
                    },
                    {"cas_checkdigit_ok": None},
                )
            )
        chembl_entry = None
        for candidate in (inchikey_block1(substance.inchikey), inchikey_block1(derived_key)):
            if candidate and candidate in chembl:
                chembl_entry = chembl[candidate]
                break
        if chembl_entry:
            claims.append(("chembl-cache", chembl_entry, {"cas_checkdigit_ok": None}))
        for record in sorted(by_substance.get(substance.id, []), key=lambda r: r.slug):
            identification = record.data.get("identification") or {}
            cas = (identification.get("cas_number") or "").strip() or None
            claims.append(
                (
                    "dosewiki-api",
                    {
                        "inchikey": (identification.get("inchi_key") or "").strip() or None,
                        "connectivity": inchikey_block1(identification.get("inchi_key")),
                        "cas": cas,
                        "formula": (identification.get("molecular_formula") or "").strip() or None,
                        "molecular_weight": parse_molecular_weight(
                            identification.get("molecular_weight")
                        ),
                    },
                    {
                        "cas_checkdigit_ok": cas_check_digit_ok(cas),
                        "join_relationship": record.relationship,
                        "slug": record.slug,
                    },
                )
            )
        if len(claims) < 2 and not any(
            extra.get("cas_checkdigit_ok") is False for _source, _payload, extra in claims
        ):
            continue
        for field_name in CHEMISTRY_FIELDS:
            values = []
            for source, payload, extra in claims:
                raw = payload.get(field_name)
                if raw in (None, ""):
                    continue
                provenance = dict(extra)
                provenance["field"] = field_name
                if field_name != "cas":
                    # The check digit is evidence about the CAS number and
                    # nothing else; carrying it onto the formula's row would
                    # score a good formula down for a bad registry number.
                    provenance.pop("cas_checkdigit_ok", None)
                if field_name == "molecular_weight":
                    values.append(
                        Value(source=source, numeric=float(raw), text=None, provenance=provenance)
                    )
                else:
                    values.append(
                        Value(source=source, numeric=None, text=str(raw), provenance=provenance)
                    )
            # A CAS number checks itself, so one of them is already a cell even
            # with nothing to compare against: a failing check digit says the
            # string is wrong without any second opinion.
            self_checking = field_name == "cas" and any(
                value.provenance.get("cas_checkdigit_ok") is False for value in values
            )
            if len(values) < 2 and not self_checking:
                continue
            cells.append(
                Cell(
                    column="chemistry",
                    key=f"chemistry|{field_name}",
                    substance_id=substance.id,
                    substance_uid=substance.uid,
                    substance=substance.name,
                    popularity=substance.popularity,
                    values=values,
                    unit="g/mol" if field_name == "molecular_weight" else "",
                )
            )
    return cells


def stereo_specified(inchikey: str | None) -> bool:
    """Whether an InChIKey names a particular stereoisomer.

    `UHFFFAOYSA` in block 2 means the structure it came from carried no
    stereochemistry — a representation choice, not a claim about which
    enantiomer this is.
    """
    block = inchikey_block2(inchikey)
    return bool(block) and block != UNSPECIFIED_STEREO_BLOCK


def same_inchikey_claim(left: str | None, right: str | None) -> bool:
    """Whether two InChIKeys are one claim about the molecule.

    Same skeleton and same stereo layer, or same skeleton with one side flat:
    a flat SMILES against a stereo key is the tolerance
    `build/check_identifier_integrity.py` already draws, and drawing a different
    one here would report several hundred representation choices as conflicts.
    """
    if not left or not right:
        return False
    if inchikey_block1(left) != inchikey_block1(right):
        return False
    if not (stereo_specified(left) and stereo_specified(right)):
        return True
    return inchikey_block2(left) == inchikey_block2(right)


def parse_molecular_weight(text: Any) -> float | None:
    if text is None:
        return None
    if isinstance(text, int | float):
        return float(text)
    match = re.search(r"(\d+(?:\.\d+)?)", str(text))
    return float(match.group(1)) if match else None


def load_chembl(path: Path) -> dict[str, dict]:
    """ChEMBL molecule records keyed by InChIKey connectivity block."""
    if not path.exists():
        return {}
    with path.open() as handle:
        payload = json.load(handle)
    out: dict[str, dict] = {}
    for key, entry in payload.items():
        if not key.startswith("mol:"):
            continue
        for molecule in entry.get("molecules") or []:
            structures = molecule.get("molecule_structures") or {}
            properties = molecule.get("molecule_properties") or {}
            inchikey = structures.get("standard_inchi_key")
            connectivity = inchikey_block1(inchikey)
            if not connectivity or connectivity in out:
                continue
            out[connectivity] = {
                "inchikey": inchikey,
                "connectivity": connectivity,
                "cas": None,
                "formula": properties.get("full_molformula"),
                "molecular_weight": parse_molecular_weight(properties.get("full_mwt")),
            }
    return out


def compute_rdkit_keys(
    substances: dict[int, Substance],
) -> tuple[dict[int, tuple[str | None, str | None, float | None]], bool]:
    """InChIKey, formula and average molecular weight recomputed from each
    substance's own stored SMILES. Empty when RDKit is unavailable."""
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem import Descriptors, rdMolDescriptors
    except ImportError:
        return {}, False
    RDLogger.DisableLog("rdApp.*")
    out: dict[int, tuple[str | None, str | None, float | None]] = {}
    for substance in substances.values():
        if not substance.smiles:
            continue
        molecule = Chem.MolFromSmiles(substance.smiles)
        if molecule is None:
            continue
        try:
            key = Chem.MolToInchiKey(molecule)
        except Exception:
            key = None
        out[substance.id] = (
            key or None,
            rdMolDescriptors.CalcMolFormula(molecule),
            round(Descriptors.MolWt(molecule), 3),
        )
    return out, True


# ---------------------------------------------------------------- clustering


def cluster_values(cell: Cell, weights: Weights) -> int:
    """Group values that say the same thing, and return the cluster count.

    Copying is what makes a wrong number look corroborated: freeodwiki repeats
    PsychonautWiki's ladders exactly, dose.wiki repeats them too, and TripSit
    and PsychonautWiki have copied each other in both directions. Three copies
    are one claim.

    A *derived* source is folded into its parent even when the two disagree —
    `rdkit-smiles` is recomputed from `piru-stored`'s own SMILES and can only
    ever restate or contradict it, never corroborate it independently.
    """
    tolerance = float(weights.clustering["relative_tolerance"])
    representatives: list[tuple[float | None, str | None]] = []
    for value in cell.values:
        placed = False
        for index, (number, text) in enumerate(representatives):
            if value.numeric is not None and number is not None:
                if number > 0 and abs(value.numeric - number) / number <= tolerance:
                    value.cluster = index
                    placed = True
                    break
                if number == 0 and value.numeric == 0:
                    value.cluster = index
                    placed = True
                    break
            elif value.text is not None and text is not None:
                if cell.key.endswith("|inchikey"):
                    if same_inchikey_claim(value.text, text):
                        value.cluster = index
                        placed = True
                        break
                    continue
                left = value.text.strip()
                right = text.strip()
                if weights.clustering.get("string_case_insensitive"):
                    left, right = left.lower(), right.lower()
                if left == right:
                    value.cluster = index
                    placed = True
                    break
        if not placed:
            value.cluster = len(representatives)
            representatives.append((value.numeric, value.text))
    fold_same_source(cell)
    fold_dependents(cell, weights)
    cell.n_clusters = len({value.cluster for value in cell.values})
    return cell.n_clusters


def fold_same_source(cell: Cell) -> None:
    """One source is one vote, however many rows it carries.

    drug.community publishes two inhalation rows for JWH-018, 0.25 mg and
    0.2 mg. Left apart they are two clusters that between them outvote the three
    sources saying 1 mg, and the curated value is then reported as the lone
    dissenter from a consensus one source invented by disagreeing with itself.

    The fold key is source *and* upstream record: two dose.wiki articles that
    both claim one Piru row are two claims about which molecule it is, not one
    article listing two numbers.
    """
    groups: dict[tuple[str, str | None], list[Value]] = defaultdict(list)
    for value in cell.values:
        groups[(value.source, value.provenance.get("slug"))].append(value)
    for members in groups.values():
        if len(members) < 2:
            continue
        target = min(member.cluster for member in members)
        numbers = [m.numeric for m in members if m.numeric and m.numeric > 0]
        spread = max(numbers) / min(numbers) if len(numbers) > 1 else None
        if spread is None and len({(m.text or "").strip() for m in members}) > 1:
            spread = float("inf")
        for member in members:
            member.cluster = target
            if spread is not None and spread > 1.0:
                member.provenance["within_source_spread"] = (
                    "different values" if spread == float("inf") else round(spread, 4)
                )


def fold_dependents(cell: Cell, weights: Weights) -> None:
    """Move every derived value into its parent's cluster, and renumber.

    Where a derived value contradicts the source it was derived from, the
    disagreement is recorded on the *parent* — `piru-stored`'s stated InChIKey
    against the one RDKit computes from `piru-stored`'s own SMILES is a fact
    about that row, and says nothing about whoever else is in the cell.
    """
    parents = {
        value.source: value.cluster
        for value in cell.values
        if value.source in set(weights.dependencies.values())
    }
    for value in cell.values:
        parent_source = weights.dependencies.get(value.source)
        if parent_source is None or parent_source not in parents:
            continue
        if value.cluster != parents[parent_source]:
            for other in cell.values:
                if other.source == parent_source:
                    other.provenance["derived_disagrees"] = True
                    other.provenance["derived_value"] = value.display
        value.cluster = parents[parent_source]
        value.provenance["derived_from"] = parent_source
    order = {old: new for new, old in enumerate(sorted({v.cluster for v in cell.values}))}
    for value in cell.values:
        value.cluster = order[value.cluster]


def backing_sources(cell: Cell, settled: float | str | None, weights: Weights) -> frozenset[str]:
    """The sources whose own value is the cell's consensus.

    Derived sources do not count: they restate the row they were computed from.
    """
    if settled is None:
        return frozenset()
    threshold = float(weights.reliability["outlier_log_delta"])
    return frozenset(
        value.source
        for value in cell.values
        if "derived_from" not in value.provenance
        and (compare(value, settled) or 0.0) <= threshold
        and compare(value, settled) is not None
    )


def cluster_members(cell: Cell) -> dict[int, list[Value]]:
    out: dict[int, list[Value]] = defaultdict(list)
    for value in cell.values:
        out[value.cluster].append(value)
    return out


def cluster_weight(
    members: list[Value], source_weights: dict[str, float], weights: Weights
) -> float:
    """One vote for the claim, plus a small increment for each repetition."""
    increment = float(weights.clustering["copy_vote_increment"])
    scores = sorted((source_weights.get(value.source, 1.0) for value in members), reverse=True)
    if not scores:
        return 0.0
    return scores[0] + increment * sum(scores[1:])


def weighted_median(pairs: list[tuple[float, float]]) -> float | None:
    """Median of `(value, weight)`, in the order the values sort."""
    usable = [(value, weight) for value, weight in pairs if weight > 0]
    if not usable:
        return None
    usable.sort()
    total = sum(weight for _value, weight in usable)
    running = 0.0
    for value, weight in usable:
        running += weight
        if running >= total / 2:
            return value
    return usable[-1][0]


def cell_consensus(
    cell: Cell, source_weights: dict[str, float], weights: Weights, exclude_cluster: int | None
) -> float | str | None:
    """The consensus over independent claims, optionally leaving one out.

    Leaving a value out means leaving its whole cluster out: a copy carries no
    independent information about the value it copied, so keeping the copies
    while dropping the original would let one upstream error corroborate itself.
    """
    members = cluster_members(cell)
    numeric: list[tuple[float, float]] = []
    textual: dict[str, float] = defaultdict(float)
    for cluster, values in members.items():
        if cluster == exclude_cluster:
            continue
        weight = cluster_weight(values, source_weights, weights)
        # A derived value never speaks for its cluster: it was folded in whether
        # or not it agrees, so letting it set the cluster's value would let a
        # recomputation overwrite the number the source actually publishes.
        speaking = [v for v in values if "derived_from" not in v.provenance] or values
        representative = speaking[0]
        if representative.numeric is not None:
            numbers = [value.numeric for value in speaking if value.numeric is not None]
            numeric.append((statistics.median(numbers), weight))
        elif representative.text is not None:
            textual[representative.text] += weight
    if numeric:
        return weighted_median(numeric)
    if textual:
        return max(sorted(textual), key=lambda key: textual[key])
    return None


# --------------------------------------------------------------- class prior


@dataclass
class ClassPrior:
    level: str
    members: int
    median_log: float
    mad_log: float

    def z(self, value: float) -> float:
        return 0.6745 * (math.log10(value) - self.median_log) / self.mad_log


def class_keys(substance: Substance, weights: Weights) -> list[tuple[str, str]]:
    """`(level, key)` most specific first."""
    out: list[tuple[str, str]] = []
    for slug in sorted(substance.classes):
        out.append(("class_context", slug))
    if substance.drug_class:
        out.append(("drug_class", substance.drug_class))
    for name in sorted(substance.interaction_classes):
        out.append(("interaction_class", name))
    for name in sorted(substance.categories):
        out.append(("category", name))
    order = {level: index for index, level in enumerate(weights.class_prior["levels"])}
    out.sort(key=lambda pair: order.get(pair[0], 99))
    return out


def build_class_priors(
    cells: list[Cell], substances: dict[int, Substance], weights: Weights
) -> dict[tuple[str, str, str], dict[int, tuple[float, frozenset[str]]]]:
    """`(level, class key, cell key) -> {substance_id: (consensus, backing sources)}`.

    For binding columns the cell key is folded to the *base* target, so subunit
    and site variants of one receptor still populate one distribution. Each peer
    carries who stands behind its number, because a distribution assembled out
    of one source's rows cannot be used to judge that source.
    """
    out: dict[tuple[str, str, str], dict[int, tuple[float, frozenset[str]]]] = defaultdict(dict)
    for cell in cells:
        if cell.consensus is None or cell.consensus <= 0:
            continue
        substance = substances.get(cell.substance_id)
        if substance is None:
            continue
        key = prior_cell_key(cell)
        for level, class_key in class_keys(substance, weights):
            out[(level, class_key, key)][cell.substance_id] = (
                cell.consensus,
                cell.consensus_sources,
            )
    return out


def prior_cell_key(cell: Cell) -> str:
    if cell.column != "binding":
        return cell.key
    bases = {
        value.provenance.get("target_base")
        for value in cell.values
        if value.provenance.get("target_base")
    }
    base = sorted(bases)[0] if bases else cell.key
    measure = cell.key.rsplit("|", 1)[-1]
    return f"binding-base|{base}|{measure}"


def class_prior_for(
    cell: Cell,
    substance: Substance,
    priors: dict[tuple[str, str, str], dict[int, tuple[float, frozenset[str]]]],
    weights: Weights,
) -> ClassPrior | None:
    """The peer distribution for this cell, and how many peers stand apart from it.

    `members` counts only peers that are not simply this argument's own
    participants restated. Heroin's intravenous come-up has five classical-opioid
    peers, and three of them are a number drug.community published alone — a
    prior fitted on those then rules for drug.community against the two sources
    contradicting it, which is the source deciding its own case. Such a peer is
    dropped from the count, and a class left thin says `class_signal_thin`
    instead of scoring anybody.
    """
    minimum = int(weights.class_prior["min_members"])
    floor = float(weights.class_prior["mad_floor_decades"])
    parties = {value.source for value in cell.values}
    key = prior_cell_key(cell)
    for level, class_key in class_keys(substance, weights):
        peers = priors.get((level, class_key, key))
        if not peers:
            continue
        values: list[float] = []
        independent = 0
        for substance_id, (value, backing) in peers.items():
            if substance_id == cell.substance_id or value <= 0:
                continue
            values.append(math.log10(value))
            if len(backing) > 1 or not backing or not backing <= parties:
                independent += 1
        if len(values) < minimum:
            continue
        median = statistics.median(values)
        deviations = [abs(value - median) for value in values]
        mad = max(statistics.median(deviations), floor)
        return ClassPrior(level=level, members=independent, median_log=median, mad_log=mad)
    return None


# --------------------------------------------------------- reliability weights


def iterate_reliability(
    cells_by_column: dict[str, list[Cell]], weights: Weights
) -> dict[str, dict[str, dict[str, float]]]:
    """Per-source, per-column weights, from each source's own outlier rate.

    Uniform start; each round recomputes the consensus with the current weights,
    counts how often each source lands more than `outlier_log_delta` decades
    away from it, and turns that rate back into a weight. The rate is smoothed
    by a Beta prior so a source with four values cannot earn an extreme weight
    off a coin flip.
    """
    settings = weights.reliability
    iterations = int(settings["iterations"])
    threshold = float(settings["outlier_log_delta"])
    rate_cap = float(settings["rate_cap"])
    min_weight = float(settings["min_weight"])
    prior_outliers = float(settings["prior_outliers"])
    prior_observations = float(settings["prior_observations"])

    out: dict[str, dict[str, dict[str, float]]] = {}
    for column, cells in cells_by_column.items():
        sources = sorted({value.source for cell in cells for value in cell.values})
        source_weights = dict.fromkeys(sources, 1.0)
        counts: dict[str, tuple[int, int]] = {}
        for _round in range(iterations):
            observed: dict[str, int] = defaultdict(int)
            outliers: dict[str, int] = defaultdict(int)
            for cell in cells:
                if cell.n_clusters < 2:
                    continue
                # The consensus here is the median of *everyone*, unlike the
                # per-value feature, which leaves the value's cluster out. On a
                # cell split two ways, leave-one-out flips the median and makes
                # both sides the outlier from the other — which would tell every
                # source it is always wrong and drive every weight to the floor.
                reference = cell_consensus(cell, source_weights, weights, None)
                deltas = {id(value): compare(value, reference) for value in cell.values}
                # Only a cell whose consensus more than one source stands behind
                # can teach anything about a source. Where two claims simply
                # disagree, whichever side the median falls on is an artifact of
                # the weights being fitted, and counting it hardens the first
                # round's accident into a verdict.
                #
                # Sources, not clusters, on purpose: being out of step with a
                # figure the field repeats is a fact about a source even when
                # the repetition is copying, and the report says so by counting
                # "outlier in" over contested cells rather than over all of them.
                agreeing = {
                    value.source
                    for value in cell.values
                    if deltas[id(value)] is not None
                    and deltas[id(value)] <= threshold
                    and "derived_from" not in value.provenance
                }
                if len(agreeing) < 2:
                    continue
                for value in cell.values:
                    delta = deltas[id(value)]
                    if delta is None:
                        continue
                    observed[value.source] += 1
                    if delta > threshold:
                        outliers[value.source] += 1
            new_weights = {}
            for source in sources:
                total = observed.get(source, 0)
                rate = (outliers.get(source, 0) + prior_outliers) / (total + prior_observations)
                scaled = min(rate, rate_cap) / rate_cap
                new_weights[source] = (1.0 - scaled) * (1.0 - min_weight) + min_weight
                counts[source] = (outliers.get(source, 0), total)
            derived = dict(new_weights)
            # Pins are applied inside the loop, so the pinned source votes at its
            # pinned strength in the next round's consensus too.
            new_weights.update({s: w for s, w in weights.pinned.items() if s in new_weights})
            source_weights = new_weights
        out[column] = {
            source: {
                "weight": round(source_weights[source], 4),
                "pinned": source in weights.pinned,
                "derived_weight": round(derived[source], 4),
                "outlier_in": counts.get(source, (0, 0))[0],
                "contested_cells": counts.get(source, (0, 0))[1],
                "outlier_rate": round(counts.get(source, (0, 0))[0] / counts[source][1], 4)
                if counts.get(source, (0, 0))[1]
                else None,
            }
            for source in sources
        }
    return out


def compare(value: Value, reference: float | str | None) -> float | None:
    """Distance from a consensus, in decades for a number and 0/1 for a string."""
    if reference is None:
        return None
    if value.numeric is not None and isinstance(reference, int | float):
        if value.numeric <= 0 or reference <= 0:
            return None
        return abs(math.log10(value.numeric / reference))
    if value.text is not None and isinstance(reference, str):
        return 0.0 if value.text.strip().lower() == reference.strip().lower() else 1.0
    return None


# ------------------------------------------------------------------ features


def citation_quality(provenance: dict, weights: Weights) -> float:
    scores = weights.citation
    citation = provenance.get("citation") or {}
    total = 0.0
    if citation.get("doi") or citation.get("pmid"):
        total += scores["has_identifier"]
    if citation.get("is_review") or provenance.get("is_review"):
        total += scores["is_review"]
    confidence = (provenance.get("confidence") or "").upper()
    total += {
        "HIGH": scores["confidence_high"],
        "MEDIUM": scores["confidence_medium"],
        "LOW": scores["confidence_low"],
    }.get(confidence, 0.0)
    if provenance.get("assay_context"):
        total += scores["assay_context"]
    return min(total, 1.0)


def within_source_feature(value: Value) -> float:
    """How far one source's own rows for this cell are from each other.

    A source that publishes 0.25 mg and 0.2 mg for the same band has an
    editorial disagreement with itself, and a duplicated row is often the reason.
    Scaled in decades like `log_delta`; a mismatch between two strings is a full
    decade, since there is no distance between two spellings of an identifier.
    """
    spread = value.provenance.get("within_source_spread")
    if spread is None:
        return 0.0
    if not isinstance(spread, int | float):
        return 1.0 / 3.0
    return min(math.log10(spread), 3.0) / 3.0 if spread > 1 else 0.0


def slip_features(delta_ratio: float | None, weights: Weights) -> dict[str, float]:
    """Whether a value is almost exactly a power-of-ten multiple of consensus."""
    out = {"slip_1000x": 0.0, "slip_100x": 0.0, "slip_10x": 0.0}
    if not delta_ratio or delta_ratio <= 0:
        return out
    tolerance = float(weights.slips["relative_tolerance"])
    ratio = max(delta_ratio, 1 / delta_ratio)
    for candidate in weights.slips["ratios"]:
        if abs(ratio - candidate) / candidate <= tolerance:
            out[f"slip_{int(candidate)}x"] = 1.0
    return out


def score_cell(
    cell: Cell,
    substance: Substance,
    source_weights: dict[str, float],
    priors: dict[tuple[str, str, str], dict[int, float]],
    weights: Weights,
) -> None:
    """Fill in every value's feature vector and error probability."""
    members = cluster_members(cell)
    prior = None
    if cell.column != "chemistry":
        prior = class_prior_for(cell, substance, priors, weights)
    if prior:
        cell.class_level = prior.level
        cell.class_members = prior.members
    z_cap = float(weights.class_prior["z_cap"])
    min_class_members = int(weights.class_prior["min_class_members"])
    tie_ratio = weights.threshold("tie_ratio")

    largest_cluster = max((len(values) for values in members.values()), default=0)
    # How many *independent* claims land on the consensus. A cluster being a
    # singleton is not dissent when nothing else agrees either: three sources
    # naming three different InChIKeys are three claims and no majority, and
    # calling each of them the odd one out is a verdict the data cannot support.
    settled = cell_consensus(cell, source_weights, weights, None)
    outlier_threshold = float(weights.reliability["outlier_log_delta"])
    corroborating = {
        cluster
        for cluster, values in members.items()
        if any(
            (compare(v, settled) or 0.0) <= outlier_threshold
            for v in values
            if compare(v, settled) is not None
        )
    }
    majority = len(corroborating) >= 2
    unit_basis = any(value.provenance.get("unit_basis_mismatch") for value in cell.values)

    for value in cell.values:
        reference = cell_consensus(cell, source_weights, weights, value.cluster)
        delta = compare(value, reference)
        ratio = None
        if (
            value.numeric
            and isinstance(reference, int | float)
            and reference > 0
            and value.numeric > 0
        ):
            ratio = value.numeric / reference
        others_agree = majority and value.cluster not in corroborating

        features: dict[str, float] = {
            "log_delta": 0.0
            if unit_basis
            else (min((delta or 0.0), 3.0) / 3.0 if delta is not None else 0.0),
            "sole_dissenter": 1.0 if others_agree else 0.0,
            "no_corroboration": 1.0 if cell.n_clusters < 2 else 0.0,
            "copy_only_support": 1.0 if cell.n_clusters == 1 and largest_cluster > 1 else 0.0,
            "class_z": 0.0,
            "citation_missing": 1.0 - citation_quality(value.provenance, weights),
            "source_unreliability": 1.0 - source_weights.get(value.source, 1.0),
            "ladder_break": 1.0 if value.provenance.get("ladder_break") else 0.0,
            "bounds_inverted": 1.0 if value.provenance.get("bounds_inverted") else 0.0,
            "point_estimate": 1.0 if value.provenance.get("point_estimate") else 0.0,
            "route_order_violation": 1.0 if value.provenance.get("route_order_violation") else 0.0,
            "unit_qualified": 1.0 if value.provenance.get("unit_qualified") else 0.0,
            "context_conflict": 1.0 if value.provenance.get("context_conflict") else 0.0,
            "identity_skeleton_mismatch": 0.0,
            "identity_stereo_mismatch": 0.0,
            "cas_checkdigit_fail": 1.0
            if value.provenance.get("cas_checkdigit_ok") is False
            else 0.0,
            "inchikey_smiles_mismatch": 1.0 if value.provenance.get("derived_disagrees") else 0.0,
            "unit_basis_mismatch": 1.0 if unit_basis else 0.0,
            "within_source_disagreement": within_source_feature(value),
            "assay_context_differs": 1.0 if value.provenance.get("assay_context_differs") else 0.0,
            "class_signal_thin": 0.0,
        }
        # A slip is a claim about a *number*. When the two sides are not
        # counting the same thing, the ratio is the unit factor and says
        # nothing about anyone's arithmetic.
        features.update(
            dict.fromkeys(("slip_1000x", "slip_100x", "slip_10x"), 0.0)
            if unit_basis
            else slip_features(ratio, weights)
        )
        if unit_basis and delta is not None:
            value.provenance["log_delta_unscored"] = round(delta, 3)

        # A class prior compares this substance to its peers on the peers' basis.
        # A row counted in a different thing is not on that basis, and a class
        # of four peers is an opinion rather than a distribution — it says so
        # instead of scoring, so it cannot settle an argument it cannot see.
        if prior and value.numeric and value.numeric > 0 and not unit_basis:
            if prior.members < min_class_members:
                features["class_signal_thin"] = 1.0
                value.provenance["class_members"] = prior.members
            else:
                z = abs(prior.z(value.numeric))
                features["class_z"] = min(z, z_cap) / z_cap
                value.provenance["class_z"] = round(prior.z(value.numeric), 3)

        if cell.column == "chemistry" and cell.key.endswith("inchikey"):
            reference_text = reference if isinstance(reference, str) else None
            if reference_text and value.text:
                if inchikey_block1(value.text) != inchikey_block1(reference_text):
                    features["identity_skeleton_mismatch"] = 1.0
                elif not same_inchikey_claim(value.text, reference_text):
                    features["identity_stereo_mismatch"] = 1.0

        value.features = features
        value.probability = logistic(features, weights)
        scored = [
            name
            for name, magnitude in sorted(
                features.items(), key=lambda item: -item[1] * weights.features.get(item[0], 0.0)
            )
            if magnitude > 0 and weights.features.get(name, 0.0) > 0
        ][:4]
        # A feature weighted zero still belongs in `why`: it explains the gap
        # rather than blaming anyone for it, and a reader who cannot see
        # `assay_context_differs` reads a rat number against a human one as a
        # typo and corrects the wrong row.
        explanatory = [
            name
            for name, magnitude in sorted(features.items())
            if magnitude > 0 and weights.features.get(name, 0.0) == 0
        ]
        value.reasons = scored + explanatory

    cell.consensus = None
    cell.consensus_text = None
    settled = cell_consensus(cell, source_weights, weights, None)
    if isinstance(settled, int | float):
        cell.consensus = float(settled)
    elif isinstance(settled, str):
        cell.consensus_text = settled
    cell.consensus_sources = backing_sources(cell, settled, weights)

    levels = weights.evidence_levels
    for name in ("strong", "moderate", "weak", "single", "none"):
        if cell.n_clusters >= int(levels[name]):
            cell.evidence_level = name
            break

    flags: list[str] = []
    if cell.max_probability >= weights.threshold("needs_manual_probability"):
        flags.append("needs_manual")
    # A standoff nothing settles: two or more claims, no corroborated majority,
    # and no tiebreaker. With three mutually disagreeing InChIKeys there is no
    # majority either, and naming one of them the error would be a verdict.
    numeric_standoff = cell.consensus is not None and cell.spread >= tie_ratio
    categorical_standoff = cell.consensus is None and cell.n_clusters >= 2
    if not majority and (numeric_standoff or categorical_standoff):
        if not tie_broken(cell, weights):
            flags.append("unresolved_disagreement")
            if "needs_manual" not in flags:
                flags.append("needs_manual")
    if cell.n_clusters <= 1 and prior:
        violation = max(
            (abs(value.provenance.get("class_z", 0.0)) for value in cell.values), default=0.0
        )
        if violation >= weights.threshold("class_violation_z"):
            flags.append("class_prior_violation")
            if "needs_manual" not in flags:
                flags.append("needs_manual")
    if cell.column == "chemistry" and any(
        value.features.get("identity_skeleton_mismatch") for value in cell.values
    ):
        flags.append("skeleton_conflict")
    if cell.column == "chemistry" and any(
        value.features.get("identity_stereo_mismatch") for value in cell.values
    ):
        flags.append("stereo_conflict")
    if any(value.provenance.get("context_conflict") for value in cell.values):
        # A therapeutic ladder that outranks a recreational one is what the app
        # shows next to a logged dose, which is a shipping decision and not a
        # question about which number is true. Always a human's call.
        flags.append("therapeutic_resolves")
        if "needs_manual" not in flags:
            flags.append("needs_manual")
    if unit_basis:
        flags.append("unit_basis_mismatch")
        if "needs_manual" not in flags:
            flags.append("needs_manual")
    if any(value.provenance.get("assay_context_differs") for value in cell.values):
        flags.append("assay_context_differs")
    if any(value.provenance.get("within_source_spread") for value in cell.values):
        flags.append("within_source_disagreement")
    if any(value.features.get("class_signal_thin") for value in cell.values):
        flags.append("class_signal_thin")
    if any(value.provenance.get("derived_disagrees") for value in cell.values):
        flags.append("inchikey_smiles_mismatch")
    if any(
        value.provenance.get("join_relationship") in ("different", "no_piru_match")
        for value in cell.values
    ):
        # Which molecule this row is about is contested. Not scored against
        # anyone: the relationship was itself derived by comparing these very
        # identifiers, so using it as evidence would be circular.
        flags.append("identity_join_conflict")
    if cell.n_clusters < 2:
        flags.append("unanimous" if len(cell.values) > 1 else "single_value")
    if prior is None and cell.column != "chemistry":
        flags.append("no_class_signal")
    if cell.popularity == 0:
        # The Wikipedia-pageview score is 0 for a substance with no chemical
        # article, which includes real ones (Zolpidem, A-PVP, alpha-PHP). It
        # means "unranked", never "obscure", and the top-100 worksheet silently
        # excludes every one of them.
        flags.append("popularity_missing")
    if "unresolved_disagreement" in flags:
        symmetrize(cell, weights)
        if cell.max_probability >= weights.threshold("needs_manual_probability"):
            if "needs_manual" not in flags:
                flags.append("needs_manual")
    cell.flags = flags


#: Features that describe the *source* rather than this value. In a standoff
#: they are the only thing left that could separate the sides, and separating
#: the sides is exactly what the data does not support.
SOURCE_PRIOR_FEATURES = ("source_unreliability", "citation_missing")


def symmetrize(cell: Cell, weights: Weights) -> None:
    """Equalize the source-level features across a standoff nothing settles.

    When two claims disagree, nothing corroborates either, and no tiebreaker
    exists, which one is wrong is undetermined — so the output must say
    "undetermined" and not quietly rank them by how a source scored elsewhere.
    A reliability weight is a prior about a source, not evidence about this
    value, and letting it decide here manufactures a verdict out of an average.
    """
    if not cell.values:
        return
    shared = {
        name: sum(value.features.get(name, 0.0) for value in cell.values) / len(cell.values)
        for name in SOURCE_PRIOR_FEATURES
    }
    for value in cell.values:
        value.features.update(shared)
        value.probability = logistic(value.features, weights)
        value.provenance["symmetrized"] = True


def tie_broken(cell: Cell, weights: Weights) -> bool:
    """Whether anything separates a two-cluster standoff.

    A class prior that rejects one side, a citation that only one side carries,
    or an internal contradiction on one side is a tiebreaker. Nothing at all is
    the case worth a human's time.
    """
    margin = weights.threshold("tie_citation_margin")
    qualities = defaultdict(float)
    consistency = defaultdict(float)
    class_z = defaultdict(float)
    for value in cell.values:
        qualities[value.cluster] = max(
            qualities[value.cluster], citation_quality(value.provenance, weights)
        )
        consistency[value.cluster] = max(
            consistency[value.cluster],
            max(
                value.features.get(name, 0.0)
                for name in (
                    "ladder_break",
                    "bounds_inverted",
                    "route_order_violation",
                    "point_estimate",
                    "within_source_disagreement",
                    "slip_1000x",
                    "slip_10x",
                )
            ),
        )
        class_z[value.cluster] = max(class_z[value.cluster], value.features.get("class_z", 0.0))
    if len(qualities) < 2:
        return True
    quality_values = sorted(qualities.values())
    if quality_values[-1] - quality_values[0] >= margin:
        return True
    if max(consistency.values()) > 0 and min(consistency.values()) == 0:
        return True
    z_values = sorted(class_z.values())
    return z_values[-1] - z_values[0] >= 0.25


def logistic(features: dict[str, float], weights: Weights) -> float:
    total = weights.bias
    for name, magnitude in features.items():
        total += weights.features.get(name, 0.0) * magnitude
    return round(1.0 / (1.0 + math.exp(-total)), 4)


# ------------------------------------------------------------------- outputs


def write_cells_jsonl(path: Path, cells: list[Cell]) -> None:
    with path.open("w") as handle:
        for cell in sorted(cells, key=lambda c: (-c.max_probability, c.substance, c.key)):
            handle.write(json.dumps(cell_payload(cell), ensure_ascii=False, sort_keys=True))
            handle.write("\n")


def cell_payload(cell: Cell) -> dict:
    return {
        "cell_id": cell.cell_id,
        "column": cell.column,
        "key": cell.key,
        "substance_uid": cell.substance_uid,
        "substance_id": cell.substance_id,
        "substance": cell.substance,
        "popularity": round(cell.popularity, 4),
        "unit": cell.unit,
        "consensus": cell.consensus,
        "consensus_text": cell.consensus_text,
        "independent_clusters": cell.n_clusters,
        "evidence_level": cell.evidence_level,
        "class_level": cell.class_level,
        "class_members": cell.class_members,
        "spread": round(cell.spread, 4),
        "flags": cell.flags,
        "values": [
            {
                "source": value.source,
                "value": value.numeric if value.numeric is not None else value.text,
                "cluster": value.cluster,
                "probability": value.probability,
                "top_features": value.reasons,
                # Only the features that fired. Everything named in
                # adjudicator_weights.json and absent here is zero — a refit can
                # reconstruct the dense vector from that list.
                "features": {
                    name: round(number, 5) for name, number in value.features.items() if number
                },
                "provenance": {
                    name: number for name, number in value.provenance.items() if name != "citation"
                },
            }
            for value in sorted(cell.values, key=lambda v: (-v.probability, v.source))
        ],
    }


def popularity_tier(popularity: float) -> str:
    if popularity >= 0.85:
        return "top (>=0.85)"
    if popularity >= 0.5:
        return "known (0.50-0.85)"
    if popularity > 0:
        return "long tail (>0)"
    return "unranked (0)"


def unjoined_dosewiki_articles() -> list[tuple[str, str]]:
    """The slugs the curated join maps to nothing, with the reason recorded there."""
    if not DOSEWIKI_IDS.exists():
        return []
    with DOSEWIKI_IDS.open() as handle:
        entries = json.load(handle)
    return sorted(
        (slug, str(entry.get("note") or ""))
        for slug, entry in entries.items()
        if isinstance(entry, dict) and not entry.get("substance_uid")
    )


def write_summary(
    path: Path,
    cells: list[Cell],
    reliability: dict,
    weights: Weights,
    top_ids: set[int],
    elapsed: float,
    notes: list[str],
) -> None:
    flagged = [cell for cell in cells if "needs_manual" in cell.flags]
    by_column: dict[str, list[Cell]] = defaultdict(list)
    for cell in cells:
        by_column[cell.column].append(cell)

    lines: list[str] = []
    lines.append("# Adjudication summary")
    lines.append("")
    lines.append(
        f"{len(cells):,} cells over {len({cell.substance_id for cell in cells}):,} substances; "
        f"{len(flagged):,} flagged `needs_manual` "
        f"({len(flagged) / max(len(cells), 1):.1%}). Computed in {elapsed:.1f}s."
    )
    lines.append("")
    for note in notes:
        lines.append(f"- {note}")
    if notes:
        lines.append("")

    lines.append("## By column")
    lines.append("")
    lines.append(
        "| column | cells | flagged | top-100 cells | top-100 flagged | median P | P>=0.9 |"
    )
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for column in COLUMNS:
        group = by_column.get(column, [])
        if not group:
            continue
        group_flagged = [cell for cell in group if "needs_manual" in cell.flags]
        top = [cell for cell in group if cell.substance_id in top_ids]
        top_flagged = [cell for cell in top if "needs_manual" in cell.flags]
        probabilities = sorted(cell.max_probability for cell in group)
        lines.append(
            f"| {column} | {len(group):,} | {len(group_flagged):,} | {len(top):,} | "
            f"{len(top_flagged):,} | {statistics.median(probabilities):.3f} | "
            f"{sum(1 for p in probabilities if p >= 0.9):,} |"
        )
    lines.append("")

    lines.append("## Probability distribution")
    lines.append("")
    lines.append("| bucket | cells |")
    lines.append("|---|---:|")
    buckets = [(0.0, 0.2), (0.2, 0.4), (0.4, 0.55), (0.55, 0.7), (0.7, 0.9), (0.9, 1.01)]
    for low, high in buckets:
        count = sum(1 for cell in cells if low <= cell.max_probability < high)
        lines.append(f"| {low:.2f}–{high:.2f} | {count:,} |")
    lines.append("")

    lines.append("## Evidence level")
    lines.append("")
    lines.append("| level | independent claims | cells | flagged |")
    lines.append("|---|---|---:|---:|")
    for level in ("none", "single", "weak", "moderate", "strong"):
        group = [cell for cell in cells if cell.evidence_level == level]
        claims = weights.evidence_levels[level]
        lines.append(
            f"| {level} | {claims}{'+' if level == 'strong' else ''} | {len(group):,} | "
            f"{sum(1 for cell in group if 'needs_manual' in cell.flags):,} |"
        )
    lines.append("")

    lines.append("## Flags by popularity tier")
    lines.append("")
    tiers = defaultdict(lambda: [0, 0])
    for cell in cells:
        entry = tiers[popularity_tier(cell.popularity)]
        entry[0] += 1
        if "needs_manual" in cell.flags:
            entry[1] += 1
    lines.append("| tier | cells | flagged |")
    lines.append("|---|---:|---:|")
    for tier in ("top (>=0.85)", "known (0.50-0.85)", "long tail (>0)", "unranked (0)"):
        cells_count, flagged_count = tiers[tier]
        lines.append(f"| {tier} | {cells_count:,} | {flagged_count:,} |")
    lines.append("")
    unranked = {cell.substance for cell in cells if cell.popularity == 0}
    unranked_flagged = {
        cell.substance for cell in cells if cell.popularity == 0 and "needs_manual" in cell.flags
    }
    lines.append(
        f"**{len(unranked):,} substance(s) here score 0** — `substances.popularity` is "
        "English-Wikipedia pageviews, and 0 means no chemical article rather than no "
        f"users. Zolpidem, A-PVP and alpha-PHP are among them; {len(unranked_flagged):,} "
        "of them have a flagged cell. The top-100 worksheet cannot see any of them, so "
        "read it as 'the 100 most *documented*', and use `--substance` for the rest. "
        "Cells from an unranked substance carry `popularity_missing`."
    )
    lines.append("")

    lines.append("## Widest gaps")
    lines.append("")
    lines.append("The largest ratio between two independent claims about one quantity.")
    lines.append("")
    lines.append("| substance | cell | spread | claims | P |")
    lines.append("|---|---|---:|---|---:|")
    widest = sorted(
        (cell for cell in cells if cell.n_clusters >= 2 and cell.column != "chemistry"),
        key=lambda cell: -cell.spread,
    )[:25]
    for cell in widest:
        claims = "; ".join(
            f"{value.source} {value.display}"
            for value in sorted(cell.values, key=lambda v: v.source)
        )
        lines.append(
            f"| {cell.substance} | `{cell.key}` | {cell.spread:.0f}x | {claims[:160]} | "
            f"{cell.max_probability:.2f} |"
        )
    lines.append("")

    lines.append("## Most-flagged substances")
    lines.append("")
    counts: dict[tuple[str, float], int] = defaultdict(int)
    for cell in flagged:
        counts[(cell.substance, cell.popularity)] += 1
    lines.append("| substance | popularity | flagged cells |")
    lines.append("|---|---:|---:|")
    for (substance, popularity), count in sorted(
        counts.items(), key=lambda item: (-item[1], item[0][0])
    )[:30]:
        lines.append(f"| {substance} | {popularity:.3f} | {count} |")
    lines.append("")

    unjoined = unjoined_dosewiki_articles()
    if unjoined:
        lines.append("## Unjoined dose.wiki articles")
        lines.append("")
        lines.append(
            "Articles `data/curated/dosewiki-ids.json` deliberately leaves unmapped, "
            "so nothing above has voted on them. Each is a claim Piru cannot place: "
            "usually a structure that belongs to a different compound on one side."
        )
        lines.append("")
        lines.append("| dose.wiki slug | why it is unjoined |")
        lines.append("|---|---|")
        for slug, note in unjoined:
            lines.append(f"| `{slug}` | {note[:200]} |")
        lines.append("")

    lines.append("## Source reliability")
    lines.append("")
    lines.append(
        "Converged weight per source per column: 1.0 is never the outlier, "
        f"{weights.reliability['min_weight']} is the floor. The rate is counted over "
        "**contested** cells only — the ones where sources disagreed at all — so it answers "
        "'when there is an argument, how often is this source the one away from the middle', "
        "not 'how much of this source is wrong'."
    )
    lines.append("")
    for column in COLUMNS:
        table = reliability.get(column)
        if not table:
            continue
        lines.append(f"### {column}")
        lines.append("")
        lines.append("| source | weight | outlier in / contested | rate |")
        lines.append("|---|---:|---:|---:|")
        for source, entry in sorted(table.items(), key=lambda item: -item[1]["weight"]):
            rate = entry["outlier_rate"]
            lines.append(
                f"| {source} | {entry['weight']:.3f} | {entry['outlier_in']:,} / "
                f"{entry['contested_cells']:,} | {'—' if rate is None else f'{rate:.3f}'} |"
            )
        lines.append("")

    path.write_text("\n".join(lines) + "\n")


def write_source_reports(directory: Path, cells: list[Cell], weights: Weights) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    minimum = weights.threshold("report_min_probability")
    by_source: dict[str, list[tuple[Cell, Value]]] = defaultdict(list)
    for cell in cells:
        for value in cell.values:
            if value.probability >= minimum:
                by_source[value.source].append((cell, value))
    for source, entries in by_source.items():
        entries.sort(key=lambda pair: -pair[1].probability)
        slug = re.sub(r"[^a-z0-9._-]+", "-", source.lower())
        lines = [f"# {source} — probable errors", ""]
        lines.append(
            f"{len(entries):,} value(s) at P >= {minimum}. Each row shows what this source "
            "says and what every other source says about the same quantity."
        )
        lines.append("")
        lines.append("| P | substance | cell | this source | competing claims | why |")
        lines.append("|---:|---|---|---|---|---|")
        for cell, value in entries[:500]:
            competing = "; ".join(
                f"{other.source} {other.display}"
                for other in sorted(cell.values, key=lambda v: v.source)
                if other is not value
            )
            lines.append(
                f"| {value.probability:.2f} | {cell.substance} | `{cell.key}` | "
                f"{value.display} {cell.unit} | {competing[:200] or '—'} | "
                f"{', '.join(value.reasons)} |"
            )
        if len(entries) > 500:
            lines.append("")
            lines.append(f"… and {len(entries) - 500:,} more; see `cells.jsonl`.")
        lines.append("")
        (directory / f"{slug}.md").write_text("\n".join(lines) + "\n")


def write_calibration(path: Path, cells: list[Cell], top_ids: set[int]) -> None:
    flagged = [
        cell for cell in cells if cell.substance_id in top_ids and "needs_manual" in cell.flags
    ]
    flagged.sort(key=lambda cell: (-cell.popularity, cell.substance, cell.column, cell.key))
    lines = [
        "# Calibration worksheet — the 100 most popular substances",
        "",
        "Every flagged cell among the top 100 by `substances.popularity`, with all",
        "claims side by side. Fill in **verdict** with the source slug whose value is",
        "right (or `none` when they all are wrong, or `ok` when the flag is a false",
        "positive), and **note** with why. Nothing reads this file; it is the input to",
        "a hand-written resolution table and to refitting the weights.",
        "",
        f"{len(flagged):,} flagged cell(s) over "
        f"{len({cell.substance_id for cell in flagged})} substance(s).",
        "",
        "| substance | column | cell | claims | consensus | evidence | P | flags | verdict | note |",
        "|---|---|---|---|---|---|---:|---|---|---|",
    ]
    for cell in flagged:
        claims = "; ".join(
            f"**{value.source}** {value.display}"
            for value in sorted(cell.values, key=lambda v: -v.probability)
        )
        consensus = (
            cell.consensus_text
            if cell.consensus_text
            else (format_number(cell.consensus) if cell.consensus is not None else "—")
        )
        lines.append(
            f"| {cell.substance} | {cell.column} | `{cell.key}` | {claims[:240]} | "
            f"{consensus} {cell.unit} | {cell.evidence_level} | {cell.max_probability:.2f} | "
            f"{', '.join(cell.flags)} |  |  |"
        )
    path.write_text("\n".join(lines) + "\n")


def write_resolution_candidates(path: Path, cells: list[Cell]) -> None:
    """The shape a hand-written resolution table would take. Nothing reads it."""
    payload = {
        "_readme": (
            "Proposal only — no part of the pipeline reads this file. Each entry names "
            "the source whose value the evidence currently favours for one cell, with "
            "the probability that value is wrong and how much independent evidence "
            "there was. A `needs_manual` entry has no defensible winner yet."
        ),
        "cells": {},
    }
    for cell in sorted(cells, key=lambda c: c.cell_id):
        best = min(cell.values, key=lambda value: (value.probability, value.source))
        payload["cells"][cell.cell_id] = {
            "column": cell.column,
            "key": cell.key,
            "substance": cell.substance,
            "proposed_source": best.source,
            "proposed_value": best.numeric if best.numeric is not None else best.text,
            "unit": cell.unit,
            "error_probability": best.probability,
            "evidence_level": cell.evidence_level,
            "independent_clusters": cell.n_clusters,
            "needs_manual": "needs_manual" in cell.flags,
            "flags": cell.flags,
        }
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


def write_target_map(path: Path, target_map: dict[str, TargetName]) -> None:
    payload = {
        "_readme": (
            "Receptor-target spellings folded onto canonical names, produced by "
            "pipeline/audit/adjudicate.py --write-target-map. `cell` is the name two "
            "values must share before they may be compared; `base` is the receptor with "
            "every qualifier removed, which is what a class-level prior groups by. A "
            "`dropped` qualifier described the assay (species, tissue, radioligand); a "
            "`kept` one named a different entity or a different subunit/site and so "
            "keeps the rows apart."
        ),
        "targets": {
            raw: {
                "base": target.base,
                "cell": target.cell,
                "kept": target.kept,
                "dropped": target.dropped,
            }
            for raw, target in sorted(target_map.items())
        },
    }
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True) + "\n")


# ----------------------------------------------------------------------- CLI


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="path to the built SQLite")
    parser.add_argument("--weights", type=Path, default=DEFAULT_WEIGHTS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--min-popularity", type=float, default=0.0)
    parser.add_argument(
        "--top-substances", type=int, default=0, help="keep only the N most popular substances"
    )
    parser.add_argument(
        "--column", choices=COLUMNS, action="append", help="limit to one column (repeatable)"
    )
    parser.add_argument("--substance", action="append", help="limit to a substance (repeatable)")
    parser.add_argument(
        "--min-prob", type=float, default=0.0, help="drop cells whose worst value scores below this"
    )
    parser.add_argument("--source", action="append", help="keep only cells this source claims")
    parser.add_argument("--json", action="store_true", help="write only the JSON artifacts")
    parser.add_argument("--md", action="store_true", help="write only the Markdown artifacts")
    parser.add_argument(
        "--write-target-map",
        action="store_true",
        help=f"refresh {TARGET_MAP_PATH.name} from the database and exit",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    started = time.time()
    if not args.db.exists():
        print(
            f"adjudicate: DB not found at {args.db} — run pipeline/fetch-db.sh first",
            file=sys.stderr,
        )
        return 2
    weights = Weights.load(args.weights)
    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    notes: list[str] = []

    substances = load_substances(conn)
    sources = load_sources(conn)
    citations = load_citations(conn)
    target_map: dict[str, TargetName] = {}

    if args.write_target_map:
        for (raw,) in conn.execute("SELECT DISTINCT target FROM bindings"):
            target_map[raw] = normalize_target(raw)
        records, _origin = load_dosewiki(weights, conn)
        for record in records:
            for entry in (record.data.get("pharmacology") or {}).get("binding_sites") or []:
                raw = entry.get("target") or entry.get("receptor")
                if raw and raw not in target_map:
                    target_map[raw] = normalize_target(raw)
        write_target_map(TARGET_MAP_PATH, target_map)
        print(
            f"wrote {TARGET_MAP_PATH} — {len(target_map):,} spellings, "
            f"{len({t.cell for t in target_map.values()}):,} cells, "
            f"{len({t.base for t in target_map.values()}):,} receptors"
        )
        return 0

    dosewiki_all, dosewiki_origin = load_dosewiki(weights, conn)
    if dosewiki_all:
        notes.append(
            f"dose.wiki: {len(dosewiki_all):,} record(s) joined by structure from "
            f"`{Path(dosewiki_origin).name}`."
        )
    else:
        notes.append("dose.wiki: no records available; it contributes nothing to this run.")
    dosewiki_numeric = pick_numeric_dosewiki(dosewiki_all, weights)
    ingested = dosewiki_in_db(conn)
    if ingested:
        notes.append(
            "dose.wiki is an ingested source; its evidence records are skipped for "
            + ", ".join(
                f"{column} ({len(rows):,} substance(s))"
                for column, rows in sorted(ingested.items())
                if rows
            )
            + " so it does not vote twice."
        )

    wanted = set(args.column) if args.column else set(COLUMNS)
    cells: list[Cell] = []
    if "dose" in wanted:
        cells += build_dose_cells(
            conn, substances, sources, citations, dosewiki_numeric, ingested.get("dose", set())
        )
    if "duration" in wanted:
        cells += build_duration_cells(
            conn, substances, sources, citations, dosewiki_numeric, ingested.get("duration", set())
        )
    if "halflife" in wanted:
        cells += build_halflife_cells(
            conn, substances, sources, citations, dosewiki_numeric, ingested.get("halflife", set())
        )
    if "binding" in wanted:
        cells += build_binding_cells(
            conn,
            substances,
            sources,
            citations,
            dosewiki_numeric,
            ingested.get("binding", set()),
            target_map,
        )
    if "chemistry" in wanted:
        chembl = load_chembl(CHEMBL_CACHE)
        if not chembl:
            notes.append("ChEMBL cache absent; it contributes no chemistry claims.")
        rdkit_keys, rdkit_available = compute_rdkit_keys(substances)
        if not rdkit_available:
            notes.append(
                "RDKit unavailable; structures were not recomputed from SMILES, so an "
                "InChIKey that disagrees with its own SMILES cannot be seen this run."
            )
        cells += build_chemistry_cells(substances, dosewiki_all, chembl, rdkit_keys)
    conn.close()

    for cell in cells:
        cluster_values(cell, weights)

    cells_by_column: dict[str, list[Cell]] = defaultdict(list)
    for cell in cells:
        cells_by_column[cell.column].append(cell)
    reliability = iterate_reliability(cells_by_column, weights)

    # A first pass with the converged weights settles each cell's consensus,
    # which is what the class-level distributions are then built from.
    for cell in cells:
        column_weights = {
            source: entry["weight"] for source, entry in reliability[cell.column].items()
        }
        settled = cell_consensus(cell, column_weights, weights, None)
        cell.consensus = float(settled) if isinstance(settled, int | float) else None
        cell.consensus_sources = backing_sources(cell, settled, weights)
    priors = build_class_priors(cells, substances, weights)

    for cell in cells:
        column_weights = {
            source: entry["weight"] for source, entry in reliability[cell.column].items()
        }
        substance = substances[cell.substance_id]
        score_cell(cell, substance, column_weights, priors, weights)

    ranked = sorted(substances.values(), key=lambda s: (-s.popularity, s.name))
    top_ids = {substance.id for substance in ranked[:100]}

    selected = cells
    if args.top_substances:
        keep = {substance.id for substance in ranked[: args.top_substances]}
        selected = [cell for cell in selected if cell.substance_id in keep]
    if args.min_popularity:
        selected = [cell for cell in selected if cell.popularity >= args.min_popularity]
    if args.substance:
        names = {name.lower() for name in args.substance}
        selected = [cell for cell in selected if cell.substance.lower() in names]
    if args.source:
        wanted_sources = set(args.source)
        selected = [
            cell
            for cell in selected
            if any(value.source in wanted_sources for value in cell.values)
        ]
    if args.min_prob:
        selected = [cell for cell in selected if cell.max_probability >= args.min_prob]

    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    want_json = args.json or not args.md
    want_md = args.md or not args.json

    if want_json:
        write_cells_jsonl(out / "cells.jsonl", selected)
        (out / "sources.json").write_text(
            json.dumps(
                {
                    "_readme": (
                        "Per-source, per-column reliability. `weight` is what the "
                        "consensus multiplies this source's vote by; it is derived from "
                        "`outlier_rate`, smoothed by the Beta prior in "
                        "adjudicator_weights.json. `contested_cells` counts only the "
                        "cells where the sources disagreed at all, and `outlier_in` how "
                        "many of those this source was the one away from the middle in — "
                        "so a low rate means 'rarely the odd one out in an argument', not "
                        "'rarely wrong'. Virtual sources carry no priority because the "
                        "app never shows them."
                    ),
                    "virtual_sources": VIRTUAL_SOURCES,
                    "columns": reliability,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )
        write_resolution_candidates(out / "resolution-candidates.json", selected)
    if want_md:
        write_summary(
            out / "summary.md",
            selected,
            reliability,
            weights,
            top_ids,
            time.time() - started,
            notes,
        )
        write_source_reports(out / "sources", selected, weights)
        write_calibration(out / "calibration-top100.md", selected, top_ids)

    flagged = sum(1 for cell in selected if "needs_manual" in cell.flags)
    top_flagged = sum(
        1 for cell in selected if cell.substance_id in top_ids and "needs_manual" in cell.flags
    )
    print(
        f"adjudicate: {len(selected):,} cells, {flagged:,} flagged "
        f"({top_flagged:,} in the top 100) — {out} in {time.time() - started:.1f}s"
    )
    for note in notes:
        print(f"  note: {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
