#!/usr/bin/env python3
"""Catch citations that resolve perfectly but are about the wrong substance.

`verify_citations.py` answers "does this identifier exist, and does the paper
share *any* vocabulary with the claim?". It cleared the citations that resolved
to nothing. It cannot catch the next class, because these resolve beautifully:

    2-FDCK `pk_routes` cites doi:10.1093/jat/bkae003 — a real, well-formed,
    peer-reviewed paper about **fentanyl** in workplace urine screening.

A ketamine analog's pharmacokinetics sourced to an opioid forensics paper. The
identifier is fine; the subject is somebody else's. So this asks the two
questions a reviewer would ask when handed the paper:

  1. **Is the citing substance mentioned at all?** Canonical name, display name,
     every alias, plus abbreviation expansions. If none of a substance's names
     appear in the title (or abstract), the paper is probably not about it.
  2. **Does a *different* known substance dominate instead?** Every name in the
     DB is indexed, so "2-FDCK cites a paper whose title says fentanyl" is read
     as what it is — much harder evidence than a mere absence.

Verdicts, in descending severity:

    WRONG_SUBSTANCE   another substance — from an unrelated class — is named in
                      the title, and the citing substance is nowhere. This is
                      the 2-FDCK/fentanyl shape.
    ANALOG_SUBSTANCE  another substance is named, but it is a plausible parent
                      or sibling (shared skeleton, class, or category). A
                      ketamine paper *can* be the right source for a 2-FDCK
                      claim about the shared NMDA mechanism, so this is a
                      question, not an accusation.
    ABSENT            the substance is not mentioned and no other substance was
                      recognized — the 1,4-butanediol/plant-genetics shape.
    OK                the substance (or a synonym) is in the paper.

Every finding carries a 0–1 score built from named reasons, and output is ranked
worst-first, so the top of the list is where a reviewer should start.

Chemical naming is the whole difficulty. "2-FDCK", "2-Fluorodeschloroketamine",
"2F-ketamine" and "2-Fl-2'-oxo-PCM" are one compound, while "ketamine",
"esketamine" and "deschloroketamine" are three. Matching is therefore
deliberately **asymmetric**: generous when looking for the substance's own name
(a missed match becomes a false accusation), strict when naming a different
substance (a loose match becomes a libel). See `_matches_citing` vs `_others_in`.

Titles alone are thin evidence. `--fetch` pulls abstracts into a *separate*
cache — `data/sources/citation-abstract-cache.json`, never the verify cache CI
gates on — and absence-across-an-abstract scores higher than absence-across-a-title.

    python3 pipeline/audit/citation_topicality.py                # offline, cached
    python3 pipeline/audit/citation_topicality.py --fetch        # + fetch abstracts
    python3 pipeline/audit/citation_topicality.py --gate         # exit 1 on WRONG_SUBSTANCE
    python3 pipeline/audit/citation_topicality.py --json out.json --limit 200
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audit.verify_citations import SYNONYMS, load_cache  # noqa: E402
from build.sqlite import normalise  # noqa: E402

# PubMed's efetch speaks XML. Prefer defusedxml (entity-expansion and XXE hard
# off); the rest of the pipeline is stdlib-only, so fall back rather than add a
# dependency — stdlib ElementTree refuses undefined entities and never fetches
# external ones, which covers the payload we accept from NCBI.
try:
    from defusedxml import ElementTree as ET  # type: ignore[import-not-found]
except ImportError:
    import xml.etree.ElementTree as ET  # type: ignore[no-redef]

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
#: Written by `--fetch`. Deliberately NOT citation-verify-cache.json — CI gates
#: on that file's contents and a second writer would fight it.
ABSTRACT_CACHE = REPO / "data/sources/citation-abstract-cache.json"
#: Adjudicated findings that should stop failing `--gate`. See `load_allowlist`.
ALLOWLIST = REPO / "data/curated/citation-topicality-allowlist.json"
#: Known-real defects awaiting re-sourcing. See `load_backlog`.
BACKLOG = REPO / "data/curated/citation-topicality-backlog.json"
USER_AGENT = "piru-citation-topicality/1.0 (https://github.com/kageroumado/piru)"

#: Extends `verify_citations.SYNONYMS` with the expansions this check needs:
#: there, a claim term is matched against a paper; here, a *substance name* is.
#: Only entries that map a DB name to how a paper would write it belong here.
NAME_SYNONYMS: dict[str, tuple[str, ...]] = {
    "ghb": ("gammahydroxybutyrate", "4hydroxybutanoate", "oxybate", "hydroxybutyrate"),
    "gbl": ("gammabutyrolactone", "butyrolactone"),
    "14butanediol": ("bd", "butanediol", "14bd"),
    "pcp": ("phencyclidine",),
    "2cb": ("bromodimethoxyphenethylamine",),
    "dom": ("stp",),
    "mdpv": ("methylenedioxypyrovalerone",),
    "4ho-dmt": ("psilocin",),
    "psilocin": ("4hodmt", "hydroxydimethyltryptamine"),
    "psilocybin": ("psilocybe", "4pomt"),
    "thc": ("tetrahydrocannabinol", "dronabinol"),
    "cbd": ("cannabidiol",),
    "ketamine": ("esketamine", "arketamine"),
    "amphetamine": ("amfetamine",),
    "methamphetamine": ("metamfetamine",),
    "heroin": ("diacetylmorphine", "diamorphine"),
    "buprenorphine": ("suboxone", "subutex"),
    "alprazolam": ("xanax",),
    "diazepam": ("valium",),
    "methylphenidate": ("ritalin", "concerta"),
    "nitrousoxide": ("n2o",),
    "salvinorina": ("salvia", "salvinorin"),
    "ibogaine": ("iboga",),
    "mescaline": ("peyote", "trimethoxyphenethylamine"),
    "lsd": ("lysergide", "lysergic", "lsd25"),
}

#: Names that are ordinary English (or ordinary lab vocabulary) before they are
#: drugs. Every one of these is a real row in `substances`, and every one of them
#: fires on unrelated titles ("ice-cold buffer", "speed of onset", "acid
#: hydrolysis"). Excluded from the *accusation* index only — a paper may still be
#: matched to them as the citing substance.
AMBIGUOUS_NAMES = {
    "acid",
    "bees",
    "blue",
    "brown",
    "bump",
    "candy",
    "crystal",
    "dust",
    "energy",
    "gas",
    "gold",
    "green",
    "ice",
    "iron",
    "lean",
    "line",
    "molly",
    "moon",
    "poppers",
    "rock",
    "salt",
    "sass",
    "snow",
    "speed",
    "star",
    "sugar",
    "tea",
    "water",
    "white",
    # Laboratory and mechanism abbreviations that are ALSO substance rows in this
    # DB — "NET" (a real row) versus the norepinephrine transporter, "TRIS"
    # versus the buffer, "DA"/"5-HT" versus the neurotransmitters. Each of these
    # appears capitalized in perfectly ordinary titles, so the caps rule that
    # protects the other short names cannot save them.
    "net",
    "dat",
    "sert",
    "comt",
    "mao",
    "ugt",
    "5ht",
    "ht",
    "da",
    "pea",
    "tris",
    "iris",
    "don",
    "vip",
    "elm",
    "met",
    "neb",
    "cake",
    "pst",
    "bron",
}

#: Endogenous ligands and bulk ions. They are legitimate `substances` rows, but a
#: title says "dopamine" to name a *system*, not a drug under study, in the
#: overwhelming majority of pharmacology papers. Never the basis of a
#: WRONG_SUBSTANCE accusation; still counted as "a substance was recognized", so
#: they suppress a bare ABSENT.
ENDOGENOUS_NAMES = {
    "acetylcholine",
    "adenosine",
    "adrenaline",
    "anandamide",
    "calcium",
    "cortisol",
    "dopamine",
    "epinephrine",
    "estradiol",
    "gaba",
    "glucose",
    "glutamate",
    "glycine",
    "histamine",
    "insulin",
    "magnesium",
    "melatonin",
    "noradrenaline",
    "norepinephrine",
    "oxytocin",
    "serotonin",
    "taurine",
    "testosterone",
}

#: A name followed by one of these is naming a *mechanism*, not a compound:
#: "dopamine transporter", "serotonin syndrome", "glutamate receptor". Matching
#: on the head word there is the single largest source of false accusations.
MECHANISM_FOLLOWERS = {
    "receptor",
    "receptors",
    "transporter",
    "transporters",
    "system",
    "systems",
    "neuron",
    "neurons",
    "neurotransmission",
    "release",
    "reuptake",
    "uptake",
    "pathway",
    "pathways",
    "signaling",
    "signalling",
    "syndrome",
    "level",
    "levels",
    "concentration",
    "concentrations",
    "agonist",
    "agonists",
    "antagonist",
    "antagonists",
    "receptor-mediated",
    "ergic",
    "deficiency",
    "metabolism",
    "turnover",
    "synthesis",
    "efflux",
    "binding",
    "channel",
    "channels",
}

#: Tables whose rows are a *number attached to one compound*. A citation under
#: one of these must be about that compound; there is no "general background"
#: reading available. Findings here are scored up.
NUMERIC_TABLES = {
    "bindings",
    "pk_routes",
    "metabolism",
    "half_lives",
    "dose_ranges",
    "durations",
    "durations_of_action",
    "functional_assays",
    "biased_agonism",
    "concentration_effects",
    "off_targets",
    "pharmacogenetics",
    "drug_interactions_pk",
    "protocol_dosing",
    "diazepam_equivalents",
}

#: Tables whose rows are prose or a whole-substance pointer. A background
#: reference is a defensible reading, so absence is scored down.
NARRATIVE_TABLES = {
    "descriptions",
    "mechanisms_summary",
    "substance_citations",
    "effects",
    "subjective_effects",
    "tolerance",
}


# ------------------------------------------------------------------ name keys


def strict_key(name: str) -> str:
    """The identity key for a chemical name: everything but letters and digits
    removed, after the pipeline's own `normalise()` (Greek look-alikes folded,
    stereo prefixes and salts stripped). "2-FDCK" and "2f-DCK" → "2fdck"."""
    return re.sub(r"[^a-z0-9]+", "", normalise(name))


def loose_key(name: str) -> str:
    """`strict_key` with digits dropped, for the locants chemists omit in prose:
    "2-FDCK" → "fdck". Collides by design ("4-HO-MET" and "5-HO-MET" both →
    "homet"), so it is used ONLY to credit a substance with being mentioned,
    never to accuse a different one."""
    return re.sub(r"\d+", "", strict_key(name))


def word_key(name: str) -> str:
    """Normalized name with word boundaries kept, for multi-word names."""
    return re.sub(r"[^a-z0-9]+", " ", normalise(name)).strip()


@dataclass
class TextIndex:
    """One paper's title/abstract, pre-chewed into every form a name can match.

    `grams` holds tokens plus punctuation-joined runs, so a title writing
    "3,4-methylenedioxymethamphetamine" or "5-MeO-DMT" yields "34methylenedioxy…"
    and "5meodmt". Joins are made only across punctuation, never across a space —
    joining space-separated words invents compounds that were never written.
    """

    raw: str = ""
    tokens: list[str] = field(default_factory=list)
    grams: set[str] = field(default_factory=set)
    phrases: set[str] = field(default_factory=set)
    caps: set[str] = field(default_factory=set)

    def __bool__(self) -> bool:
        return bool(self.raw)


def build_index(text: str | None) -> TextIndex:
    if not text:
        return TextIndex()
    lowered = normalise(text)
    index = TextIndex(raw=text)

    # Split into runs separated by whitespace; inside a run, punctuation is a
    # chemical-name separator ("2-fdck", "3,4-mdma") and gets joined over.
    for run in re.split(r"\s+", lowered):
        parts = [p for p in re.split(r"[^a-z0-9]+", run) if p]
        index.tokens.extend(parts)
        for start in range(len(parts)):
            for end in range(start + 1, min(start + 5, len(parts)) + 1):
                index.grams.add("".join(parts[start:end]))

    # Multi-word names ("nitrous oxide", "sodium oxybate") need space-joined
    # bigrams/trigrams — kept in a separate set so single-word names can never
    # match a run-on of two unrelated words.
    words = index.tokens
    for start in range(len(words)):
        for end in range(start + 2, min(start + 3, len(words)) + 1):
            index.phrases.add(" ".join(words[start:end]))
    index.phrases |= set(words)

    # Original-case ALL-CAPS tokens. A 3–4 character name (MDMA, LSD, GHB) is
    # only believable as a drug reference when the paper wrote it in caps —
    # otherwise "bees", "dust" and "doi" start accusing people.
    for token in re.findall(r"[A-Za-z0-9][A-Za-z0-9\-,']*", text):
        letters = re.sub(r"[^A-Za-z]", "", token)
        if letters and letters.isupper():
            index.caps.add(re.sub(r"[^a-z0-9]+", "", token.lower()))
    return index


# ------------------------------------------------------------------ DB loading


@dataclass
class SubstanceNames:
    substance_id: int
    canonical: str
    #: Every key this substance answers to, DB names plus synonym expansions.
    strict: set[str] = field(default_factory=set)
    #: DB names only. The accusation index is built from these — an expansion is
    #: a guess, and a guess must never be the reason a row gets called wrong.
    literal: set[str] = field(default_factory=set)
    loose: set[str] = field(default_factory=set)
    phrases: set[str] = field(default_factory=set)
    categories: set[str] = field(default_factory=set)
    classes: set[int] = field(default_factory=set)
    skeleton: str | None = None


def load_substances(conn: sqlite3.Connection) -> dict[int, SubstanceNames]:
    """Every substance with every name it answers to, plus the fields that decide
    whether two substances are relatives."""
    out: dict[int, SubstanceNames] = {}
    for sid, canonical, display, inchikey in conn.execute(
        "SELECT id, canonical_name, display_name, inchikey FROM substances"
    ):
        names = SubstanceNames(
            substance_id=sid,
            canonical=canonical,
            # InChIKey block 1 is the connectivity skeleton: salts, stereoisomers
            # and isotopologues of one compound share it.
            skeleton=(inchikey or "")[:14] or None,
        )
        for raw in (canonical, display):
            if raw:
                _add_name(names, raw)
        out[sid] = names

    for sid, alias in conn.execute("SELECT substance_id, alias FROM aliases"):
        if sid in out:
            _add_name(out[sid], alias)

    for sid, category in conn.execute("SELECT substance_id, category FROM categories"):
        if sid in out and category:
            out[sid].categories.add(category.strip().lower())

    for sid, class_id in conn.execute(
        "SELECT substance_id, class_context_id FROM substance_classes"
    ):
        if sid in out:
            out[sid].classes.add(class_id)
    return out


def _add_name(names: SubstanceNames, raw: str) -> None:
    strict = strict_key(raw)
    if len(strict) < 3:
        return
    names.strict.add(strict)
    names.literal.add(strict)
    names.loose.add(loose_key(raw))
    for extra in SYNONYMS.get(strict, ()) + NAME_SYNONYMS.get(strict, ()):
        key = strict_key(extra)
        if len(key) >= 4:
            names.strict.add(key)
            names.loose.add(loose_key(extra))
    word = word_key(raw)
    if " " in word:
        names.phrases.add(word)


@dataclass
class Attachment:
    """One (citation, substance) pair and the tables it was cited under."""

    citation_id: int
    substance_id: int
    tables: set[str] = field(default_factory=set)


def load_attachments(conn: sqlite3.Connection) -> dict[tuple[int, int], Attachment]:
    """Walk every table carrying both a citation_id and a substance_id.

    Discovered from the schema rather than hardcoded: the pipeline gains
    pharmacology tables regularly, and a hardcoded list would quietly stop
    covering the newest one — which is exactly where fresh enrichment lands.
    """
    pairs: dict[tuple[int, int], Attachment] = {}
    tables = [
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    ]
    for table in tables:
        cols = {row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')}
        if not {"citation_id", "substance_id"} <= cols:
            continue
        for cid, sid in conn.execute(
            f'SELECT citation_id, substance_id FROM "{table}" '
            "WHERE citation_id IS NOT NULL AND substance_id IS NOT NULL"
        ):
            pairs.setdefault((cid, sid), Attachment(cid, sid)).tables.add(table)
    return pairs


def load_citations(conn: sqlite3.Connection) -> dict[int, dict]:
    return {
        row[0]: dict(zip(("id", "doi", "pmid", "url", "title", "is_review"), row, strict=True))
        for row in conn.execute("SELECT id, doi, pmid, url, title, is_review FROM citations")
    }


# --------------------------------------------------------------------- network


def _get(url: str, timeout: int = 25) -> bytes | None:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError):
        return None


def fetch_pubmed_abstracts(pmids: list[int]) -> dict[str, str]:
    """efetch in batches; PubMed returns structured abstracts as several
    <AbstractText> children, so they are concatenated."""
    out: dict[str, str] = {}
    for i in range(0, len(pmids), 100):
        chunk = pmids[i : i + 100]
        payload = _get(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=pubmed&retmode=xml&id={','.join(str(p) for p in chunk)}"
        )
        if payload:
            try:
                root = ET.fromstring(payload)
            except ET.ParseError:
                root = None
            for article in root.iter("PubmedArticle") if root is not None else ():
                pmid_el = article.find(".//PMID")
                if pmid_el is None or not pmid_el.text:
                    continue
                parts = ["".join(node.itertext()) for node in article.iter("AbstractText")]
                out[pmid_el.text.strip()] = " ".join(p for p in parts if p).strip()
        for pmid in chunk:
            out.setdefault(str(pmid), "")
        time.sleep(0.4)  # NCBI asks for ≤3 requests/second without an API key
    return out


def fetch_crossref_abstract(doi: str) -> str:
    """Crossref stores abstracts as JATS XML in a single field, when at all."""
    payload = _get(f"https://api.crossref.org/works/{urllib.parse.quote(doi)}")
    if not payload:
        return ""
    try:
        message = json.loads(payload.decode("utf-8", "replace")).get("message", {})
    except ValueError:
        return ""
    return re.sub(r"<[^>]+>", " ", message.get("abstract") or "").strip()


# --------------------------------------------------------------------- matching


def _matches_citing(names: SubstanceNames, index: TextIndex) -> str | None:
    """Generous: any evidence the paper names this substance. Returns the name
    that matched, or None. A miss here becomes an accusation, so every plausible
    spelling gets a chance — including bidirectional substring containment, which
    is what lets a "…ketamine metabolites" paper count for hydroxynorketamine."""
    if not index:
        return None
    for key in names.strict:
        if key in index.grams and (len(key) >= 5 or key in index.caps):
            return key
    for phrase in names.phrases:
        if phrase in index.phrases:
            return phrase
    for key in names.loose:
        if len(key) >= 5 and key in index.grams:
            return key
    # Containment either way, e.g. substance "2fluorodeschloroketamine" against a
    # title token "ketamine", or substance "ketamine" against "esketamine".
    for key in names.strict:
        if len(key) < 6:
            continue
        for gram in index.grams:
            if len(gram) >= 6 and (key in gram or gram in key):
                return f"{key}~{gram}"
    return None


def _names_a_mechanism(index: TextIndex, name_key: str) -> bool:
    """True when the matched name reads as a system, not a compound —
    "dopamine transporter", "glutamate receptor", "serotonin syndrome"."""
    for position, token in enumerate(index.tokens):
        if token != name_key and token != f"{name_key}s":
            continue
        nxt = index.tokens[position + 1] if position + 1 < len(index.tokens) else ""
        if nxt in MECHANISM_FOLLOWERS:
            return True
    return False


def _others_in(
    index: TextIndex,
    accusable: dict[str, set[int]],
    exclude: set[int],
    self_names: set[str],
) -> list[tuple[str, int]]:
    """Strict: the substances a paper plainly names, other than the citing one.

    Exact gram equality only — no fuzz, no containment, no locant stripping.
    Anything looser and the tail of 5,700 aliases starts matching prose."""
    hits: list[tuple[str, int]] = []
    seen: set[int] = set()
    # Both loops iterate SORTED, and that is load-bearing rather than tidiness.
    # `index.grams` and `ids` are sets, so their iteration order varies with
    # PYTHONHASHSEED between processes. The caller keeps only one representative
    # of `hits` as the finding's `other_label`, and the score depends on which —
    # so unsorted iteration made `--gate` pass or fail on identical data
    # depending on the run (measured: 1 red in 4, and exactly reproducible per
    # seed). A gate that flips on its own teaches people to re-run it.
    for key in sorted(index.grams):
        ids = accusable.get(key)
        if not ids or key in self_names:
            continue
        if len(key) <= 4 and key not in index.caps:
            continue  # short abbreviations must have been written in caps
        if _names_a_mechanism(index, key):
            continue
        for sid in sorted(ids):
            if sid not in exclude and sid not in seen:
                seen.add(sid)
                hits.append((key, sid))
    return hits


def _relationship(a: SubstanceNames, b: SubstanceNames) -> str | None:
    """How `b` is related to `a`, or None if they are strangers.

    A parent compound legitimately backs an analog's claim about a shared
    mechanism, so this is the difference between "look at this" and "this is
    wrong". Checked cheapest-first."""
    if a.skeleton and a.skeleton == b.skeleton:
        return "same molecular skeleton"
    for key_a in a.strict:
        if len(key_a) < 6:
            continue
        for key_b in b.strict:
            if len(key_b) >= 6 and (key_b in key_a or key_a in key_b):
                return f"name contains {key_b}"
    if a.classes & b.classes:
        return "shared pharmacological class"
    if a.categories & b.categories:
        return f"same category ({sorted(a.categories & b.categories)[0]})"
    return None


# ---------------------------------------------------------------------- verdict


@dataclass
class Finding:
    citation_id: int
    identifier: str
    substance: str
    verdict: str
    score: float
    title: str
    reasons: list[str]
    other: str | None
    tables: list[str]
    #: Whether the absence was checked against a full abstract or only a title.
    #: The single fact that separates hard evidence from a naming artifact — a
    #: generic title ("…a Synthetic Cannabinoid Receptor Agonist") names no
    #: compound even when the panel is in Table 1.
    has_abstract: bool = False
    #: Whether the citing row is a per-compound number rather than prose.
    numeric: bool = False

    @property
    def is_hard_absence(self) -> bool:
        """An ABSENT that is evidence rather than a title artifact.

        Both conditions are load-bearing. Without the abstract this is the Yano
        false positive (a real CB1 efficacy panel whose title names nothing);
        without the numeric table it is defensible background reading.
        """
        return self.verdict == "ABSENT" and self.has_abstract and self.numeric

    def line(self) -> str:
        other = f" → paper names {self.other}" if self.other else ""
        return (
            f"[{self.score:.2f}] {self.substance} ({', '.join(self.tables)}) "
            f"cites {self.identifier}{other}\n"
            f"        “{self.title[:110]}”\n"
            f"        {'; '.join(self.reasons)}"
        )


def evaluate(
    attachment: Attachment,
    citation: dict,
    names: SubstanceNames,
    substances: dict[int, SubstanceNames],
    index: TextIndex,
    has_abstract: bool,
    fanout: int,
    siblings_mentioned: bool,
    accusable: dict[str, set[int]],
) -> Finding | None:
    identifier = (
        f"doi:{citation['doi']}"
        if citation["doi"]
        else f"pmid:{citation['pmid']}"
        if citation["pmid"]
        else citation["url"] or "—"
    )
    title = citation.get("_title") or ""

    if _matches_citing(names, index):
        return None

    reasons = [
        "substance name absent from "
        + ("title and abstract" if has_abstract else "title (no abstract available)")
    ]
    others = _others_in(index, accusable, {attachment.substance_id}, names.strict)
    # Endogenous ligands prove the paper is pharmacological but never carry an
    # accusation; separate them before picking the dominant compound.
    real_others = [(k, s) for k, s in others if k not in ENDOGENOUS_NAMES]

    score = 0.0
    verdict = "ABSENT"
    other_label: str | None = None

    if real_others:
        # Rank candidates: an unrelated compound is the finding we want at the
        # top; a relative is a question about sourcing, not a wrong paper.
        ranked = sorted(
            ((k, s, _relationship(names, substances[s])) for k, s in real_others),
            key=lambda item: (item[2] is not None, len(item[0]) * -1),
        )
        key, sid, relation = ranked[0]
        other_label = f"{substances[sid].canonical} (“{key}”)"
        if relation is None:
            verdict = "WRONG_SUBSTANCE"
            score = 0.80
            reasons.append(f"title names {substances[sid].canonical}, an unrelated compound")
            mine = sorted(names.categories) or ["uncategorized"]
            theirs = sorted(substances[sid].categories) or ["uncategorized"]
            reasons.append(f"category {'/'.join(mine)} vs {'/'.join(theirs)}")
        else:
            verdict = "ANALOG_SUBSTANCE"
            score = 0.45
            reasons.append(f"title names {substances[sid].canonical} — {relation}")
    elif others:
        score = 0.30
        reasons.append("only endogenous ligands named — paper may be mechanistic background")
    else:
        score = 0.40
        reasons.append("no substance recognized in the paper at all")

    numeric = attachment.tables & NUMERIC_TABLES
    if numeric:
        score += 0.10
        reasons.append(f"cited for a per-compound number ({sorted(numeric)[0]})")
    elif attachment.tables & NARRATIVE_TABLES:
        score -= 0.12
        reasons.append("cited under prose, where background reading is defensible")

    if has_abstract:
        score += 0.12
        reasons.append("absence confirmed against the abstract, not just the title")

    if citation.get("is_review"):
        score -= 0.10
        reasons.append("flagged as a review — generic titles are expected")

    if fanout >= 5:
        score -= 0.15
        reasons.append(f"shared by {fanout} substances, so it reads as a class reference")

    if siblings_mentioned:
        score -= 0.15
        reasons.append("another citing substance IS named — looks like a borrowed analog source")

    return Finding(
        citation_id=attachment.citation_id,
        identifier=identifier,
        substance=names.canonical,
        verdict=verdict,
        score=max(0.0, min(1.0, score)),
        title=title,
        reasons=reasons,
        other=other_label,
        tables=sorted(attachment.tables),
        has_abstract=has_abstract,
        numeric=bool(numeric),
    )


# ------------------------------------------------------------------------ main


def load_allowlist() -> set[str]:
    """Findings a human has already adjudicated as fine, keyed
    "<identifier>|<canonical name>". `--gate` ignores these; the report still
    lists them so an allowlist entry stays visible rather than silently rotting."""
    if not ALLOWLIST.exists():
        return set()
    try:
        return set(json.loads(ALLOWLIST.read_text()))
    except (ValueError, OSError):
        return set()


def load_backlog() -> set[str]:
    """Findings already adjudicated as **real defects**, awaiting re-sourcing.

    Deliberately a different file from the allowlist, because they mean opposite
    things and a reader must never have to guess which. The allowlist says "the
    checker is wrong here". This says "the checker is right here, and the row is
    still broken" — it exists only so a known backlog doesn't block unrelated
    work while it burns down.

    The consequence is the ratchet: a citation added *tomorrow* with the same
    defect fails immediately, because it isn't in this file and nothing may be
    added to it.
    """
    if not BACKLOG.exists():
        return set()
    try:
        return {k for k in json.loads(BACKLOG.read_text()) if not k.startswith("_")}
    except (ValueError, OSError):
        return set()


def load_abstracts(path: Path) -> dict[str, str]:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except ValueError:
            return {}
    return {}


def save_abstracts(path: Path, abstracts: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(abstracts, indent=1, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="path to the built SQLite")
    parser.add_argument(
        "--offline",
        action="store_true",
        default=True,
        help="use only cached metadata (the default)",
    )
    parser.add_argument(
        "--fetch",
        dest="offline",
        action="store_false",
        help="fetch missing abstracts and cache them",
    )
    parser.add_argument(
        "--abstract-cache", type=Path, default=ABSTRACT_CACHE, help="abstract cache location"
    )
    parser.add_argument("--gate", action="store_true", help="exit 1 on a confident WRONG_SUBSTANCE")
    parser.add_argument(
        "--gate-absent",
        action="store_true",
        help="also fail on a hard ABSENT — absence confirmed against the abstract, "
        "on a row citing a per-compound number. Catches the misattribution that "
        "names no rival compound, which WRONG_SUBSTANCE structurally cannot see.",
    )
    parser.add_argument(
        "--gate-absent-threshold",
        type=float,
        default=0.60,
        help="minimum score a hard ABSENT must reach to fail --gate-absent",
    )
    parser.add_argument(
        "--gate-threshold",
        type=float,
        default=0.70,
        help="minimum score a WRONG_SUBSTANCE must reach to fail --gate",
    )
    parser.add_argument("--limit", type=int, default=0, help="check at most N citations")
    parser.add_argument("--top", type=int, default=25, help="how many findings to print per bucket")
    parser.add_argument("--json", type=Path, help="write the full ranked result here")
    args = parser.parse_args()

    if not args.db.exists():
        print(f"citation-topicality: no database at {args.db}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(args.db)
    try:
        substances = load_substances(conn)
        citations = load_citations(conn)
        attachments = load_attachments(conn)
    finally:
        conn.close()

    meta = load_cache()  # data/sources/citation-verify-cache.json — read only
    abstracts = load_abstracts(args.abstract_cache)

    wanted = sorted({cid for cid, _ in attachments})
    if args.limit:
        wanted = wanted[: args.limit]
        attachments = {k: v for k, v in attachments.items() if k[0] in set(wanted)}

    if not args.offline:
        want_pmids = [
            citations[c]["pmid"]
            for c in wanted
            if citations.get(c, {}).get("pmid") and f"pmid:{citations[c]['pmid']}" not in abstracts
        ]
        if want_pmids:
            print(f"Fetching {len(want_pmids)} abstract(s) from PubMed…", file=sys.stderr)
            for pmid, text in fetch_pubmed_abstracts(want_pmids).items():
                abstracts[f"pmid:{pmid}"] = text
            save_abstracts(args.abstract_cache, abstracts)
        want_dois = [
            citations[c]["doi"]
            for c in wanted
            if citations.get(c, {}).get("doi") and f"doi:{citations[c]['doi']}" not in abstracts
        ]
        if want_dois:
            print(f"Fetching {len(want_dois)} abstract(s) from Crossref…", file=sys.stderr)
            for n, doi in enumerate(want_dois, 1):
                abstracts[f"doi:{doi}"] = fetch_crossref_abstract(doi)
                if n % 50 == 0:
                    print(f"  {n}/{len(want_dois)}", file=sys.stderr)
                    save_abstracts(args.abstract_cache, abstracts)
                time.sleep(0.12)
            save_abstracts(args.abstract_cache, abstracts)

    # The accusation index: name → substances answering to it, minus every name
    # too short, too English, or too generic to survive contact with a title.
    accusable: dict[str, set[int]] = defaultdict(set)
    for sid, names in substances.items():
        for key in names.strict:
            if len(key) >= 3 and key not in AMBIGUOUS_NAMES:
                accusable[key].add(sid)
    # A name shared by many substances is a family label ("amphetamines"), not an
    # identification, and it points nowhere useful.
    accusable = {k: v for k, v in accusable.items() if len(v) <= 3}

    fanout: dict[int, int] = defaultdict(int)
    for cid, _sid in attachments:
        fanout[cid] += 1

    indexes: dict[int, tuple[TextIndex, bool, str]] = {}
    unchecked: list[str] = []
    for cid in wanted:
        citation = citations.get(cid)
        if not citation:
            continue
        key = (
            f"doi:{citation['doi']}"
            if citation["doi"]
            else f"pmid:{citation['pmid']}"
            if citation["pmid"]
            else None
        )
        record = meta.get(key) if key else None
        # The DB's own `citations.title` is the fallback when the paper was never
        # resolved — better than skipping the row entirely.
        title = (record or {}).get("title") or citation.get("title") or ""
        abstract = abstracts.get(key or "", "")
        if not title and not abstract:
            if key:
                unchecked.append(f"[{cid}] {key}")
            continue
        journal = (record or {}).get("journal") or ""
        indexes[cid] = (build_index(f"{title}. {journal}. {abstract}"), bool(abstract), title)

    # Which citations already name at least one of their citing substances? Used
    # to soften the finding for the *other* substances hanging off the same paper.
    mentioned_by: dict[int, set[int]] = defaultdict(set)
    for (cid, sid), _att in attachments.items():
        entry = indexes.get(cid)
        if entry and sid in substances and _matches_citing(substances[sid], entry[0]):
            mentioned_by[cid].add(sid)

    allow = load_allowlist()
    findings: list[Finding] = []
    for (cid, sid), attachment in attachments.items():
        entry = indexes.get(cid)
        if not entry or sid not in substances:
            continue
        index, has_abstract, title = entry
        citation = dict(citations[cid], _title=title)
        finding = evaluate(
            attachment,
            citation,
            substances[sid],
            substances,
            index,
            has_abstract,
            fanout[cid],
            siblings_mentioned=bool(mentioned_by[cid] - {sid}),
            accusable=accusable,
        )
        if finding:
            findings.append(finding)

    findings.sort(key=lambda f: -f.score)
    buckets: dict[str, list[Finding]] = defaultdict(list)
    for finding in findings:
        buckets[finding.verdict].append(finding)

    checked = len(indexes)
    print(
        f"\ncitation-topicality: {len(attachments)} (citation, substance) pair(s) over "
        f"{checked} resolvable citation(s) in {args.db.name}"
    )
    for verdict in ("WRONG_SUBSTANCE", "ANALOG_SUBSTANCE", "ABSENT"):
        rows = buckets.get(verdict, [])
        if not rows:
            continue
        print(f"\n{verdict}: {len(rows)}")
        for finding in rows[: args.top]:
            print(f"  {finding.line()}")
        if len(rows) > args.top:
            print(f"  … and {len(rows) - args.top} more (see --json)")
    if unchecked:
        print(f"\nUNCHECKED: {len(unchecked)} citation(s) with no title anywhere")
        for row in unchecked[:10]:
            print(f"  {row}")

    print(f"\non topic: {len(attachments) - len(findings)} pair(s); flagged: {len(findings)}")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps([finding.__dict__ for finding in findings], indent=1) + "\n"
        )
        print(f"full result → {args.json}")

    if args.gate:
        failures = [
            f
            for f in buckets.get("WRONG_SUBSTANCE", [])
            if f.score >= args.gate_threshold and f"{f.identifier}|{f.substance}" not in allow
        ]
        # A hard absence is the shape that shipped a *nursing-ethics bibliography*
        # (PMID 8632377) as cannabis's CB1 Kᵢ source, and an HIV-cytokine paper
        # (PMID 9700761) as the half-life of three β-carbolines. Nothing named a
        # rival compound, so WRONG_SUBSTANCE never fired and the gate stayed green
        # over both. Off by default only because the standing backlog is large;
        # see --gate-absent.
        if args.gate_absent:
            backlog = load_backlog()
            hard = [
                f
                for f in buckets.get("ABSENT", [])
                if f.is_hard_absence and f.score >= args.gate_absent_threshold
            ]
            failures += [
                f
                for f in hard
                if f"{f.identifier}|{f.substance}" not in allow
                and f"{f.identifier}|{f.substance}" not in backlog
            ]
            # The ratchet only holds if the backlog shrinks. Report both
            # directions: what is still owed, and which entries have been fixed
            # and should now be deleted from the file.
            outstanding = {f"{f.identifier}|{f.substance}" for f in hard} & backlog
            if outstanding:
                print(
                    f"\ncitation-topicality: {len(outstanding)} known defect(s) still on the backlog."
                )
            if stale := backlog - {f"{f.identifier}|{f.substance}" for f in hard}:
                print(
                    f"citation-topicality: {len(stale)} backlog entries no longer flagged — "
                    f"delete them from {BACKLOG.relative_to(REPO)}:",
                )
                for key in sorted(stale)[:20]:
                    print(f"  {key}")
        if failures:
            print(
                f"\ncitation-topicality: FAILED — {len(failures)} citation(s) are about a "
                f"different substance than the row citing them:",
                file=sys.stderr,
            )
            for finding in failures[:20]:
                print(f"  {finding.substance} → {finding.identifier}", file=sys.stderr)
            print(
                "\nRe-source or drop each row. If a finding is a genuine false positive, add "
                f'"<identifier>|<substance>" to {ALLOWLIST.relative_to(REPO)}.',
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
