"""Shared helpers for brushing external substance datasets into a CSV
shape that mirrors Piru's `Substance` model.

The CSV schema is intentionally flat (one row per unique substance) so the
output is easy to scan in a spreadsheet. Per-route fields collapse to
semicolon-joined strings whose order matches `ROUTES_HEADER`.
"""

from __future__ import annotations

import csv
import html
import re
from collections.abc import Iterable
from pathlib import Path

OUTPUT_DIR = Path(__file__).resolve().parents[3] / "data" / "sources" / "brushers"

CSV_COLUMNS: list[str] = [
    "source",
    "source_id",
    "name",
    "aliases",
    "raw_classes",
    "piru_category",
    "default_route",
    "routes",
    "units",
    "dose_threshold",
    "dose_light",
    "dose_common",
    "dose_strong",
    "dose_heavy",
    "onset",
    "peak",
    "total_duration",
    "half_life_min",
    "mechanism_summary",
    "effects",
    "indications",
    "contraindications",
    "regulatory_status",
    "cas_no",
    "chemical_formula",
    "tags",
    "sources_count",
    "notes",
]


# Piru's `SubstanceCategory` raw values plus the tripsit/openfda strings that
# `SubstanceCategory.from(tripSitCategory:)` recognises. The mapping is best
# effort — anything unknown falls back to "Other".
_PIRU_CATEGORY_MAP: dict[str, str] = {
    "stimulant": "Stimulant",
    "sympathomimetic": "Stimulant",
    "central nervous system stimulant": "Stimulant",
    "psychedelic": "Psychedelic",
    "hallucinogen": "Psychedelic",
    "dissociative": "Dissociative",
    "dysdelic": "Dysdelic",
    "kappa-agonist": "Dysdelic",
    "opioid": "Opioid",
    "opiate": "Opioid",
    "opioid agonist": "Opioid",
    "benzodiazepine": "Benzodiazepine",
    "depressant": "Depressant",
    "barbiturate": "Depressant",
    "sedative": "Depressant",
    "anxiolytic": "Depressant",
    "hypnotic": "Depressant",
    "empathogen": "Empathogen",
    "entactogen": "Empathogen",
    "cannabinoid": "Cannabinoid",
    "nootropic": "Nootropic",
    "ampakine": "AMPAkine",
    "eugeroic": "Eugeroic",
    "ssri": "Antidepressant",
    "snri": "Antidepressant",
    "maoi": "Antidepressant",
    "antidepressant": "Antidepressant",
    "serotonin reuptake inhibitor": "Antidepressant",
    "antipsychotic": "Antipsychotic",
    "atypical antipsychotic": "Antipsychotic",
    "antihistamine": "Antihistamine",
    "deliriant": "Antihistamine",
    "analgesic": "Analgesic",
    "nonsteroidal anti-inflammatory drug": "Analgesic",
    "supplement": "Supplement",
    "vitamin": "Supplement",
    # Glucocorticoids/corticosteroids are an endocrine drug class, not dietary
    # supplements. (Inhaled/topical steroids still read better under Endocrine
    # than Supplement; the brusher can't see route here.)
    "steroid": "Endocrine",
    "corticosteroid": "Endocrine",
    "peptide": "Peptide",
    "gabapentinoid": "GABAergic",
    "gabaergic": "GABAergic",
    "anticonvulsant": "Anticonvulsant",
    "mood-stabilizer": "Anticonvulsant",
    "mood stabilizer": "Anticonvulsant",
    "anti-epileptic agent": "Anticonvulsant",
    "antiepileptic": "Anticonvulsant",
    "cardiovascular": "Cardiovascular",
    "antimicrobial": "Antimicrobial",
    "antibiotic": "Antimicrobial",
    "antifungal": "Antimicrobial",
    "antiviral": "Antimicrobial",
    "gastrointestinal": "Gastrointestinal",
    "respiratory": "Respiratory",
    "endocrine": "Endocrine",
    "immunological": "Immunological",
}


def piru_category(raw_classes: Iterable[str]) -> str:
    """Pick the most-specific Piru category from a bag of raw class strings.
    Order matters: specific buckets win over the generic "depressant" /
    "stimulant" labels that DailyMed and TripSit both apply liberally."""
    pool = [c.lower().strip() for c in raw_classes if c and isinstance(c, str)]
    if not pool:
        return "Other"
    # Specific overrides take priority — first hit wins.
    priority = [
        "benzodiazepine",
        "opioid agonist",
        "opioid",
        "opiate",
        "ssri",
        "snri",
        "maoi",
        "atypical antipsychotic",
        "antipsychotic",
        "cannabinoid",
        "empathogen",
        "entactogen",
        "psychedelic",
        "hallucinogen",
        "dissociative",
        "deliriant",
        "antihistamine",
        "eugeroic",
        "nootropic",
        "ampakine",
        "gabapentinoid",
        "peptide",
        "anticonvulsant",
        "central nervous system stimulant",
        "sympathomimetic",
        "stimulant",
        "antidepressant",
        "serotonin reuptake inhibitor",
        "nonsteroidal anti-inflammatory drug",
        "analgesic",
        "corticosteroid",
        "steroid",
        "vitamin",
        "supplement",
        "depressant",
        "sedative",
        "anxiolytic",
        "hypnotic",
        "antimicrobial",
        "antibiotic",
        "antifungal",
        "antiviral",
        "cardiovascular",
        "respiratory",
        "gastrointestinal",
        "endocrine",
        "immunological",
    ]
    for key in priority:
        for raw in pool:
            if key in raw:
                return _PIRU_CATEGORY_MAP[key]
    return "Other"


# Maps raw route strings (from any source) to Piru `RouteOfAdministration`
# raw values. Anything unrecognised becomes "other".
_ROUTE_MAP: dict[str, str] = {
    "oral": "oral",
    "po": "oral",
    "buccal": "buccal",
    "buccally": "buccal",
    "sublingual": "sublingual",
    "sl": "sublingual",
    "insufflated": "insufflation",
    "insufflation": "insufflation",
    "intranasal": "insufflation",
    "nasal": "insufflation",
    "inhaled": "inhalation",
    "inhalation": "inhalation",
    "respiratory (inhalation)": "inhalation",
    "smoked": "inhalation",
    "vaporized": "inhalation",
    "vapourized": "inhalation",
    "intravenous": "intravenous",
    "iv": "intravenous",
    "intramuscular": "intramuscular",
    "im": "intramuscular",
    "subcutaneous": "subcutaneous",
    "sc": "subcutaneous",
    "transdermal": "transdermal",
    "topical": "transdermal",
    "cutaneous": "transdermal",
    "rectal": "rectal",
    "plugged": "rectal",
}


def piru_route(raw: str) -> str:
    """Map a raw route string to a Piru `RouteOfAdministration` raw value."""
    key = (raw or "").lower().strip()
    if not key:
        return ""
    if key in _ROUTE_MAP:
        return _ROUTE_MAP[key]
    # Hot path for combined route strings like "Oral, Intrathecal" or "IM, IV".
    for token in re.split(r"[,/]+", key):
        token = token.strip()
        if token in _ROUTE_MAP:
            return _ROUTE_MAP[token]
    return "other"


_HTML_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")


def strip_html(text: str | None) -> str:
    """Collapse the HTML strings DailyMed/pyrls embed into plain text."""
    if not text:
        return ""
    cleaned = _HTML_TAG_RE.sub(" ", text)
    cleaned = html.unescape(cleaned)
    cleaned = _WHITESPACE_RE.sub(" ", cleaned).strip()
    return cleaned


def join_unique(items: Iterable[str], sep: str = "; ") -> str:
    """Stable-order dedupe + join. Empty/None entries are dropped."""
    seen: dict[str, None] = {}
    for item in items:
        if not item:
            continue
        cleaned = item.strip()
        if cleaned and cleaned not in seen:
            seen[cleaned] = None
    return sep.join(seen)


#: Characters that mean the same thing as an ASCII one the quantity patterns
#: expect. Sources write a range separator six ways and a micro prefix two, and
#: a pattern that misses one does not refuse the value — it matches the leading
#: number alone and drops the unit with the upper bound, which ships `10` where
#: the source said `10—20 mg`. Normalizing first is what keeps a miss loud.
_QUANTITY_CHARS = {
    "\u2013": "-",  # en dash
    "\u2014": "-",  # em dash
    "\u2212": "-",  # minus sign
    "\u2010": "-",  # hyphen
    "\u2011": "-",  # non-breaking hyphen
    "\u2012": "-",  # figure dash
    "\u2015": "-",  # horizontal bar
    "\uff0d": "-",  # fullwidth hyphen-minus
    "\u03bc": "\u00b5",  # GREEK SMALL LETTER MU -> MICRO SIGN
    "\u00a0": " ",  # no-break space
    "\u2009": " ",  # thin space
    "\u202f": " ",  # narrow no-break space
}
_QUANTITY_TABLE = str.maketrans(_QUANTITY_CHARS)


def normalize_quantity_text(text: str | None) -> str:
    """Fold the confusable characters in a quantity string onto one spelling.

    Call this before matching any numeric/unit pattern. Every substitution here
    was found in a real source string.
    """
    return (text or "").translate(_QUANTITY_TABLE).replace("+/-", "\u00b1").replace("+-", "\u00b1")


_RANGE_RE = re.compile(
    r"""
    (?P<lo>\d+(?:[.,]\d+)?)        # lower number
    (?:\s*[-–to]+\s*               # range separator (-, –, "to")
       (?P<hi>\d+(?:[.,]\d+)?))?   # optional upper number
    \s*
    (?P<unit>µg|ug|mcg|mg|g|kg|ml|iu|hours?|hrs?|h|minutes?|mins?|m)?
    """,
    re.IGNORECASE | re.VERBOSE,
)


def parse_range(text: str | None) -> tuple[str, str, str]:
    """Best-effort parse of a "0.5-1.5mg" or "5-8 hours" string.
    Returns (lower, upper, unit) as plain strings — empty for missing parts.
    Numbers are normalised (commas → dots) but kept as strings so the CSV
    preserves the original precision."""
    if not text:
        return "", "", ""
    m = _RANGE_RE.search(normalize_quantity_text(text).replace(",", "."))
    if not m:
        return "", "", ""
    lo = (m.group("lo") or "").strip()
    hi = (m.group("hi") or "").strip()
    unit = (m.group("unit") or "").strip().lower()
    # Normalise mcg/ug → µg to match Piru's preferred unit string.
    if unit in ("ug", "mcg", "\u03bcg"):
        unit = "µg"
    return lo, hi, unit


def open_csv(path: Path):
    """Open `path` in write mode with the standard CSV column header."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fh = path.open("w", newline="", encoding="utf-8")
    writer = csv.DictWriter(fh, fieldnames=CSV_COLUMNS, extrasaction="ignore")
    writer.writeheader()
    return fh, writer


def empty_row(source: str) -> dict[str, str]:
    """A blank row pre-filled with the column keys so any missing column is
    serialised as an empty string rather than `None`."""
    row = dict.fromkeys(CSV_COLUMNS, "")
    row["source"] = source
    return row
