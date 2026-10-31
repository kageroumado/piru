"""Does a pharmacogenetics row's sentence speak about the gene the row is filed under?

A `pharmacogenetics` record carries one sentence and a list of relevant genes, and the build
writes one row per gene with that same sentence. A gene the sentence says nothing about
therefore gets a row whose claim belongs to another gene — the reader sees a heading naming
their gene above a finding about a different one, and a citation attached to that row vouches
for the wrong pairing.

This module answers the one question that separates the defect from a difference in spelling:
does the sentence name the row's own gene? Prose writes a gene a dozen ways, and all of these
name the gene the row is filed under —

    CYP3A4/5          one mention of two genes
    CYP2D6/CYP2C19    the same, written out
    CYP3A             the family, which covers CYP3A4 and CYP3A5
    CYP3A4-inhibited  the gene inside a compound adjective
    MAOA-uVNTR        the gene plus the variant it is typed by
    UGT2B7*2          the gene plus an allele
    HLA-B*15:02       an HLA allele, which names HLA-B
    CYP1A2*1F (rs762551)

— so the comparison is between *gene identities*, with allele, variant and rs decorations
stripped from both sides, not between literal strings.

`mismatches()` is the detector. `build/tests/test_pgx_genes.py` runs it over the shipped
database against a baseline that may only shrink, so this class of defect cannot come back.
"""

from __future__ import annotations

import re

#: Prose spellings for genes whose written form shares nothing with their symbol.
ALIASES: dict[str, str] = {
    "monoamineoxidasea": "maoa",
    "monoamineoxidaseb": "maob",
    "httlpr": "slc6a4",
    "5httlpr": "slc6a4",
    "slc6a4": "slc6a4",
    "muopioidreceptor": "oprm1",
    "pgp": "abcb1",
    "pglycoprotein": "abcb1",
    "slco1b1": "oatp1b1",
    "dihydropyrimidinedehydrogenase": "dpyd",
    "catecholomethyltransferase": "comt",
    "methylenetetrahydrofolatereductase": "mthfr",
    "methioninesynthase": "mtr",
    "transcobalamin": "tcn2",
    "narylamineacetyltransferase": "nat2",
    "flavincontainingmonooxygenase": "fmo3",
    "gsk3beta": "gsk3b",
    "glycogensynthasekinase3beta": "gsk3b",
    "maoa": "maoa",
    "maob": "maob",
}

#: A gene written as a family covers the numbered members prose spells out beneath it.
FAMILY_MEMBERS: dict[str, frozenset[str]] = {
    "cyp3a": frozenset({"cyp3a4", "cyp3a5", "cyp3a43"}),
    "cyp2c": frozenset({"cyp2c8", "cyp2c9", "cyp2c19"}),
    "cyp1a": frozenset({"cyp1a1", "cyp1a2"}),
    "cyp2b": frozenset({"cyp2b6"}),
    "cyp2d": frozenset({"cyp2d6"}),
    "ugt2b": frozenset({"ugt2b7", "ugt2b15"}),
    "ugt1a": frozenset({"ugt1a1", "ugt1a4", "ugt1a10"}),
    "adh": frozenset({"adh1a", "adh1b", "adh1c"}),
    "aldh": frozenset({"aldh1a1", "aldh2"}),
    "hla": frozenset({"hlaa", "hlab", "hlac"}),
}

#: Decorations that sit on a gene symbol without changing which gene it is.
_ALLELE = re.compile(r"\*[0-9a-z]+(?::[0-9a-z]+)?", re.I)
_PAREN = re.compile(r"\([^)]*\)")
_RSID = re.compile(r"\brs\d+\b", re.I)
_VARIANT_TAIL = re.compile(r"(?:uvntr|vntr|intron\d*)$", re.I)
#: A word that could be a gene symbol: letters then digits, or an all-letter symbol.
_TOKEN = re.compile(r"[A-Za-z][A-Za-z0-9]*(?:[/\-:*][A-Za-z0-9*:]+)*")
#: Words that look like symbols but are English.
_STOPWORDS = frozenset(
    {
        "a",
        "allele",
        "alleles",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "but",
        "by",
        "carrier",
        "carriers",
        "clearance",
        "dose",
        "doses",
        "dosing",
        "effect",
        "effects",
        "em",
        "ems",
        "exposure",
        "fast",
        "for",
        "from",
        "genotype",
        "genotypes",
        "had",
        "has",
        "have",
        "heterozygotes",
        "higher",
        "homozygotes",
        "in",
        "increased",
        "is",
        "it",
        "its",
        "lower",
        "metaboliser",
        "metabolisers",
        "metabolizer",
        "metabolizers",
        "not",
        "of",
        "on",
        "or",
        "pm",
        "pms",
        "polymorphism",
        "polymorphisms",
        "poor",
        "rapid",
        "reduced",
        "risk",
        "slow",
        "than",
        "that",
        "the",
        "then",
        "this",
        "to",
        "ultra",
        "um",
        "ums",
        "variant",
        "variants",
        "was",
        "were",
        "with",
    }
)


def _strip_decorations(token: str) -> str:
    token = _PAREN.sub(" ", token)
    token = _RSID.sub(" ", token)
    token = _ALLELE.sub("", token)
    token = re.sub(r":[0-9]+", "", token)
    token = re.sub(r"[^0-9A-Za-z]+", "", token).lower()
    return _VARIANT_TAIL.sub("", token)


def _identity(token: str) -> str:
    """One token reduced to the gene it names, or "" when it names none."""
    bare = _strip_decorations(token)
    if not bare or bare in _STOPWORDS or bare.isdigit() or len(bare) < 3:
        return ""
    if bare in ALIASES:
        return ALIASES[bare]
    # `narylamineacetyltransferase2` → the alias table's unnumbered key.
    stem = bare.rstrip("0123456789")
    if stem in ALIASES:
        return ALIASES[stem]
    return bare


def _expand_slash(token: str) -> set[str]:
    """`CYP3A4/5` → {cyp3a4, cyp3a5}; `CYP2D6/CYP2C19` → {cyp2d6, cyp2c19}.

    A slash abbreviates a shared prefix, and the right-hand side says how much of it: a tail
    that already carries its own letters is a whole symbol, while a bare `5` borrows every
    letter of the head.
    """
    parts = [p for p in token.split("/") if p.strip()]
    if len(parts) < 2:
        return set()
    head = _identity(parts[0])
    if not head:
        return set()
    out = {head}
    for part in parts[1:]:
        tail = _strip_decorations(part)
        if not tail:
            continue
        if re.match(r"^[a-z]{2,}", tail):
            # A whole symbol of its own ("cyp2c19"), or the head's letters re-stated.
            out.add(_identity(part) or tail)
        elif re.match(r"^[0-9]+[a-z]", tail):
            # `CYP2C19/2B6`: the tail restates the subfamily, so only `CYP` is shared.
            stem = re.match(r"^([a-z]+)", head)
            out.add((stem.group(1) if stem else head) + tail)
        else:
            # Digits only (`CYP3A4/5`): keep the head's letters up to its own digits.
            prefix = re.match(r"^([a-z]+(?:[0-9]+[a-z]+)*)", head)
            out.add((prefix.group(1) if prefix else head) + tail)
    return {o for o in out if len(o) >= 3}


def _keys(label: str) -> set[str]:
    """Every gene identity this label names. A label's first word is its symbol, so
    `OPRM1 A118G` and `MAO-A VNTR` key on the gene, not on the variant."""
    label = (label or "").strip()
    if not label:
        return set()
    out: set[str] = set()
    for token in _TOKEN.findall(label):
        out |= _expand_slash(token)
        ident = _identity(token)
        if ident:
            out.add(ident)
        if out:
            # Only the leading symbol of a multi-word label counts; the rest decorate it.
            break
    return out


def gene_keys(gene: str) -> set[str]:
    return _keys(gene)


def mentions(text: str) -> set[str]:
    """Every gene identity the sentence offers."""
    found: set[str] = set()
    # A spelled-out name ("monoamine oxidase A") spans words, so it is matched against the
    # whole sentence with its spacing removed. Only long names, to keep this unambiguous.
    flat = re.sub(r"[^0-9a-z]+", "", (text or "").lower())
    for alias, gene in ALIASES.items():
        if len(alias) >= 12 and alias in flat:
            found.add(gene)
    for token in _TOKEN.findall(text or ""):
        found |= _expand_slash(token)
        ident = _identity(token)
        if ident:
            found.add(ident)
        # `CYP3A4-inhibited`, `CYP2D6-dependent`: the symbol leads a compound word.
        lead = re.match(r"^([A-Za-z]+[0-9][A-Za-z0-9]*)", token)
        if lead:
            ident = _identity(lead.group(1))
            if ident:
                found.add(ident)
    return found


def _covers(one: str, other: str) -> bool:
    if one == other:
        return True
    return other in FAMILY_MEMBERS.get(one, frozenset())


def _match(a: set[str], b: set[str]) -> bool:
    return any(_covers(x, y) or _covers(y, x) for x in a for y in b)


def names_gene(text: str, gene: str) -> bool:
    keys = gene_keys(gene)
    return bool(keys) and _match(mentions(text), keys)


def same_gene(a: str, b: str) -> bool:
    return _match(gene_keys(a), gene_keys(b))


def mismatches(rows: list[tuple[str, str]]) -> list[str]:
    """The genes among one substance's rows whose sentence is about another gene.

    `rows` is (gene, sentence) for one substance. A gene is reported only when its sentence
    never names it *and* does name a sibling gene — a sentence that names no gene at all is
    thin, not misfiled, and is not this check's business.
    """
    genes = [g for g, _ in rows]
    out: list[str] = []
    for gene, text in rows:
        if names_gene(text, gene):
            continue
        if any(not same_gene(other, gene) and names_gene(text, other) for other in genes):
            out.append(gene)
    return out
