"""Receptor-target name normalization shared by the build and the audits.

Piru carries 22 spellings of the mu-opioid receptor, 17 of GABA-A and 14 of
NMDA, because every source writes it its own way and half of them append the
assay. `normalize_target` folds a spelling onto a `TargetName`: `base` is the
receptor with every qualifier removed (what `bindings.target_base` stores and
the tolerance engine collapses on), `cell` is `base` plus the entity/subtype
qualifiers that keep genuinely different measurements apart (what the
adjudicator keys its cells by). `pipeline/audit/binding_target_map.json` is the
map this produces over the shipped DB, regenerated with
`adjudicate.py --write-target-map`.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

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
