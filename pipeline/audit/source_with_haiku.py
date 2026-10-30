#!/usr/bin/env python3
"""Source uncited curated rows to public references, with Claude Haiku as a reader.

Many sourceless rows (`piru-curated`, `peer-review-primary` with no citation)
state textbook pharmacology that a Wikipedia article, an FDA label or a review
abstract states too. This pass finds that statement. The model reads; it never
supplies a source.

**Retrieval is deterministic.** For each row the candidate documents are fetched
before any model sees the row:

  - the substance's English Wikipedia article, resolved through its InChIKey on
    Wikidata (`P235` → the enwiki sitelink), else through an article already
    named for it (a curated `sources` link, the pageview snapshot's article),
    pinned to the revision fetched (`oldid`) and split by section;
  - the DailyMed label for every setid the database already cites for the
    substance, split by SPL section;
  - for pharmacology rows, up to three Europe PMC review abstracts from one
    fixed query: the substance's name and the row's key term, reviews only.

Passages that name none of the row's key terms are never shown. Haiku sees the
claim and the numbered passages, and answers with a verdict and up to three
verbatim quotes from one document, or `not_found`.

**Every answer then passes four gates, all deterministic. A row that fails any
of them stays uncited.**

  1. *Quote*: each quote occurs in the passage it names, after folding case,
     whitespace and punctuation; it is at most 300 characters and at least five
     words; all quotes come from one document.
  2. *Identity*: the document is about this substance. Wikipedia: the article
     is the Wikidata sitelink of the substance's InChIKey, or its title or one
     of its redirects is one of the substance's names. DailyMed: an active
     ingredient or moiety of the label states a substance name as whole words
     (never a substring), and on a multi-ingredient label the quote names the
     substance. Europe PMC: the title or abstract names the substance by its
     own names, with no analog containment.
  3. *Key term*: the quotes name the row's key term — its gene, enzyme, target,
     co-drug or modality; for a prose row, at least half of the targets and
     pathways its claim names; for a class-pair rule, both classes (the page's
     own subject counts for its class).
  4. *Number*: a numeric row (curated half-lives) has its number in the quote,
     to within 1% after unit conversion, or the quote states a range the number
     lies inside, which the evidence records as "within range X–Y".

A pharmacogenetics row whose phenotype text names another gene and not its own
is a data defect: it is listed in the report and never sourced.

Accepted rows land where each table's citation lives: `row-citations.json`
(mechanisms, signalling, pgx, metabolism, off-targets, DDI, bindings,
functional, imaging), the rule's own `citation` in `interaction-rules.json`, and
`halfLifeSource` in the substance's curated file. Each carries the quote it was
checked against. Rows Haiku answered `not_found` or `contradicted` are listed in
the report: they may be wrong claims.

Fetched pages and model answers are cached under ``$PIRU_SOURCING_CACHE``
(default ``/Volumes/Ugreen/Scratch/piru-sourcing``), so a re-run pays for nothing
it has answered. The model runs as headless Claude Code (`claude -p`, the
`claude-cli` backend), four processes at a time, with every tool and MCP server
off; spend is the sum of each call's `total_cost_usd`, and the pass stops
calling at $25. An answer that is empty or not JSON is retried once, then
recorded as `none`.

    python3 pipeline/audit/source_with_haiku.py --targets a,b,c,d --dry-run
    python3 pipeline/audit/source_with_haiku.py --targets a,b,c,d --write
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
import random
import re
import sqlite3
import subprocess
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import date
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))

import row_citations  # noqa: E402
from audit.citation_sourcing import extract_quantities  # noqa: E402
from audit.citation_topicality import (  # noqa: E402
    ENZYME_PREFIXES,
    TARGET_SYNONYMS,
    SubstanceNames,
    _canonical_target,
    build_index,
    load_substances,
    target_keys,
)
from audit.resolve_fda_label_links import _contains_run, tokens  # noqa: E402

# Label XML comes from DailyMed. Prefer defusedxml (entity expansion and XXE off);
# stdlib ElementTree refuses undefined entities and never fetches external ones,
# which covers what DailyMed serves, so it is the fallback rather than a dependency.
try:
    from defusedxml import ElementTree as ET  # type: ignore[import-not-found]
except ImportError:
    import xml.etree.ElementTree as ET  # type: ignore[no-redef]

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
CURATED = REPO / "data/curated"
RULES = CURATED / "interaction-rules.json"
SUBSTANCE_FILES = CURATED / "substances"
POPULARITY = REPO / "data/sources/wikipedia-popularity.json"
DAILYMED_NDC = REPO / "data/sources/dailymed-labels.json"
CACHE = Path(os.environ.get("PIRU_SOURCING_CACHE", "/Volumes/Ugreen/Scratch/piru-sourcing"))

MODEL = "claude-haiku-5-5"
SPEND_CAP = 25.0
TODAY = date.today().isoformat()
#: Stamped on every entry this run writes; `--via-date` pins it when a run's
#: answers were gathered on an earlier day than the write.
VIA = f"haiku-assisted {TODAY}"
UA = "Piru-Sourcing/1.0 (+https://github.com/kageroumado/piru; citation sourcing for a public drug reference)"
#: Seconds between requests to one host. Wikipedia asks for at most a few per second.
HOST_DELAY = {
    "en.wikipedia.org": 0.25,
    "query.wikidata.org": 1.0,
    "dailymed.nlm.nih.gov": 0.3,
    "www.ebi.ac.uk": 0.2,
}
MAX_QUOTE = 300
MIN_QUOTE_WORDS = 5
MAX_PASSAGES = 10
MAX_PER_DOC = 6
CHUNK = 1000
TARGET_NAMES = {
    "a": "interaction rules",
    "b": "mechanism summaries",
    "c": "pharmacology rows",
    "d": "curated half-lives",
}

# ---------------------------------------------------------------- HTTP cache


class Http:
    """GET with an on-disk cache keyed by URL and a per-host delay. A cached miss
    (`None`) is honored, so a re-run never re-asks for what a host lacks."""

    def __init__(self, root: Path, offline: bool = False) -> None:
        self.root = root / "http"
        self.root.mkdir(parents=True, exist_ok=True)
        self.offline = offline
        self._locks: dict[str, threading.Lock] = defaultdict(threading.Lock)
        self._last: dict[str, float] = {}
        self.fetched = 0

    def _path(self, url: str) -> Path:
        digest = hashlib.sha1(url.encode()).hexdigest()
        return self.root / digest[:2] / f"{digest}.json"

    def get(self, url: str, accept: str | None = None) -> str | None:
        path = self._path(url)
        if path.exists():
            return json.loads(path.read_text())["body"]
        if self.offline:
            return None
        host = urllib.parse.urlsplit(url).netloc
        body: str | None = None
        with self._locks[host]:
            wait = HOST_DELAY.get(host, 0.3) - (time.monotonic() - self._last.get(host, 0))
            if wait > 0:
                time.sleep(wait)
            headers = {"User-Agent": UA}
            if accept:
                headers["Accept"] = accept
            for attempt in range(3):
                try:
                    request = urllib.request.Request(url, headers=headers)
                    with urllib.request.urlopen(request, timeout=40) as response:
                        body = response.read().decode("utf-8", "replace")
                    break
                except urllib.error.HTTPError as error:
                    if error.code in (429, 500, 502, 503, 504) and attempt < 2:
                        time.sleep(5 * (attempt + 1))
                        continue
                    body = None
                    break
                except (urllib.error.URLError, TimeoutError, ConnectionError):
                    if attempt < 2:
                        time.sleep(3)
                        continue
                    self._last[host] = time.monotonic()
                    return None  # transport failure: not cached, retried next run
            self._last[host] = time.monotonic()
        self.fetched += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"url": url, "body": body}))
        return body

    def fetched_on(self, url: str) -> str:
        """The day this URL's cached copy was fetched: the citation's access date."""
        path = self._path(url)
        if not path.exists():
            return TODAY
        return date.fromtimestamp(path.stat().st_mtime).isoformat()

    def json(self, url: str, accept: str | None = None) -> object | None:
        body = self.get(url, accept)
        if body is None:
            return None
        try:
            return json.loads(body)
        except ValueError:
            return None


# --------------------------------------------------------------- text helpers

GREEK = {
    "α": "alpha", "β": "beta", "γ": "gamma", "δ": "delta", "ε": "epsilon", "θ": "theta",
    "κ": "kappa", "μ": "mu", "µ": "mu", "ρ": "rho", "σ": "sigma", "ω": "omega",
}  # fmt: skip


def fold(text: str | None) -> str:
    """Lowercase words joined by single spaces: punctuation, case, Unicode forms
    and Greek letters folded, so a quote matches the passage it was copied from
    however its dashes and quotation marks were rendered."""
    text = unicodedata.normalize("NFKC", text or "")
    for greek, latin in GREEK.items():
        text = text.replace(greek, f" {latin} ")
    text = text.lower()
    return " ".join(re.findall(r"[a-z0-9]+", text))


def quote_in(quote: str, passage: str) -> bool:
    needle = fold(quote)
    return bool(needle) and f" {needle} " in f" {fold(passage)} "


def grams(text: str) -> tuple[set[str], set[str]]:
    """(joined runs of 1–4 folded words, ALL-CAPS tokens) of a text."""
    words = fold(text).split()
    out: set[str] = set()
    for start in range(len(words)):
        for end in range(start + 1, min(start + 4, len(words)) + 1):
            out.add("".join(words[start:end]))
    caps = {
        re.sub(r"[^a-z0-9]", "", tok.lower())
        for tok in re.findall(r"[A-Za-z0-9][A-Za-z0-9\-]*", unicodedata.normalize("NFKC", text))
        if re.sub(r"[^A-Za-z]", "", tok).isupper()
    }
    return out, caps


@dataclass
class Text:
    """A text pre-chewed for term matching."""

    raw: str
    grams: set[str]
    caps: set[str]

    @classmethod
    def of(cls, raw: str) -> Text:
        g, c = grams(raw)
        return cls(raw, g, c)


def compact(term: str) -> str:
    return fold(term).replace(" ", "")


@dataclass(frozen=True)
class Term:
    """One key term and the spellings that count as naming it."""

    label: str
    keys: frozenset[str]

    def named_in(self, text: Text) -> bool:
        for key in self.keys:
            if len(key) <= 3:
                if key in text.caps:
                    return True
            elif key in text.grams:
                return True
        return False


#: Words that name no particular target, so they never count as a key term.
GENERIC = {
    "receptor", "receptors", "agonist", "antagonist", "inhibitor", "inhibitors", "inhibition",
    "channel", "channels", "enzyme", "enzymes", "transporter", "transporters", "release",
    "reuptake", "uptake", "binding", "activity", "activation", "modulator", "modulation",
    "blocker", "blockade", "partial", "full", "selective", "mechanism", "action", "effect",
    "effects", "site", "sites", "protein", "proteins", "cell", "cells", "brain", "neurons",
    "neuronal", "signaling", "signalling", "pathway", "pathways", "system", "systems", "human",
    "humans", "rat", "rats", "mouse", "mice", "unknown", "other", "multiple", "various",
    "metabolite", "metabolites", "metabolism", "liver", "hepatic", "renal", "plasma", "blood",
    "drug", "drugs", "compound", "compounds", "substance", "dose", "doses", "levels", "level",
    "increase", "increases", "decrease", "decreases", "reduced", "reduces", "converting",
    "synthesis", "production", "expression", "function", "functional", "clinical", "cns",
    "central", "nervous", "peripheral", "acid", "acids", "agent", "agents", "class", "type",
    "analog", "analogue", "derivative", "prodrug", "active", "potent", "weak", "strong",
}  # fmt: skip

#: Targets and systems a mechanism sentence names that the database's own
#: target columns do not spell out.
HAND_TERMS = [
    "dopamine", "serotonin", "norepinephrine", "noradrenaline", "epinephrine", "adrenaline",
    "GABA", "GABA-A", "GABA-B", "glutamate", "glycine", "acetylcholine", "histamine",
    "adenosine", "melatonin", "orexin", "hypocretin", "cannabinoid", "CB1", "CB2", "opioid",
    "mu-opioid", "kappa-opioid", "delta-opioid", "nociceptin", "NMDA", "AMPA", "kainate",
    "sigma-1", "TAAR1", "VMAT2", "monoamine oxidase", "MAO-A", "MAO-B", "sodium channel",
    "calcium channel", "potassium channel", "chloride channel", "carbonic anhydrase",
    "cyclooxygenase", "COX-1", "COX-2", "prostaglandin", "phosphodiesterase", "PDE5", "PDE4",
    "acetylcholinesterase", "cholinesterase", "muscarinic", "nicotinic", "adrenergic",
    "alpha-1", "alpha-2", "beta-1", "beta-2", "beta-adrenergic", "imidazoline", "vasopressin",
    "oxytocin", "androgen", "estrogen", "oestrogen", "progesterone", "glucocorticoid",
    "mineralocorticoid", "aromatase", "5-alpha reductase", "testosterone", "GLP-1", "GIP",
    "insulin", "glucagon", "DPP-4", "SGLT2", "angiotensin", "ACE", "renin", "aldosterone",
    "HMG-CoA reductase", "proton pump", "H2", "H1", "dopamine D2", "D1", "D2", "D3",
    "5-HT1A", "5-HT2A", "5-HT2B", "5-HT2C", "5-HT3", "SERT", "DAT", "NET", "thyroid",
    "growth hormone", "ghrelin", "GHRH", "IGF-1", "myostatin", "AMPK", "mTOR", "sirtuin",
    "NAD+", "mitochondrial", "uncoupler", "nitric oxide", "guanylate cyclase", "cGMP", "cAMP",
    "BDNF", "TrkB", "AChE", "xanthine oxidase", "uric acid", "tubulin", "DNA gyrase",
    "topoisomerase", "ribosome", "ribosomal", "penicillin-binding", "cell wall", "folate",
    "dihydrofolate reductase", "thymidylate", "reverse transcriptase", "protease", "integrase",
    "neuraminidase", "ergosterol", "lanosterol", "bile acid", "leukotriene", "thromboxane",
    "platelet", "P2Y12", "thrombin", "factor Xa", "vitamin K", "heparin", "antithrombin",
    "K+ channel", "Na+/K+-ATPase", "potassium", "sodium", "calcium", "magnesium", "zinc",
    "iron", "chloride", "bicarbonate", "osmotic", "retinoid", "retinoic acid", "vitamin D",
    "PPAR", "PPAR-gamma", "SARM", "selective androgen receptor", "estrogen receptor",
    "TRPV1", "TRPM8", "HCN", "KCNQ", "Kv7", "SV2A", "alpha-2-delta", "α2δ", "voltage-gated",
    "ryanodine", "neuromuscular", "cholinergic", "serotonergic", "dopaminergic",
    "noradrenergic", "GABAergic", "glutamatergic", "endocannabinoid", "FAAH", "MAGL",
    "anandamide", "CRF", "HPA axis", "cortisol", "prolactin", "LH", "FSH", "GnRH", "kisspeptin",
    "hypothalamic", "pituitary", "melanocortin", "MC4R", "MC1R", "leptin", "amylin",
    "calcitonin", "CGRP", "substance P", "NK1", "bradykinin", "histone", "HDAC",
]  # fmt: skip

HALF_LIFE = ["half-life", "half life", "half-lives", "t1/2", "t½", "elimination half"]

# ----------------------------------------------------------- key-term lexicon


class Lexicon:
    """Every target, enzyme, gene and system name the database knows, plus the
    hand list above, each with the spellings `target_keys` expands it to."""

    def __init__(self, conn: sqlite3.Connection) -> None:
        raw: set[str] = set(HAND_TERMS)
        for sql in (
            "SELECT DISTINCT target_base FROM bindings",
            "SELECT DISTINCT target FROM bindings",
            "SELECT DISTINCT target FROM off_targets",
            "SELECT DISTINCT target FROM functional_assays",
            "SELECT DISTINCT enzyme FROM metabolism",
            "SELECT DISTINCT gene FROM pharmacogenetics",
        ):
            raw.update(row[0] for row in conn.execute(sql) if row[0])
        raw.update(TARGET_SYNONYMS)
        self.terms: dict[str, Term] = {}
        for item in raw:
            label = re.sub(r"\([^)]*\)", " ", item).strip(" ,;/")
            if not label or len(label.split()) > 4:
                continue
            term = make_term(label)
            if term and term.label.lower() not in self.terms:
                self.terms[compact(term.label)] = term

    def find(self, text: str, exclude: set[str]) -> list[Term]:
        """The targets `text` names, one term per target family.

        Terms that share a spelling are one family and merge into one term
        (the six GABA-A subunit strings are all named by "GABA-A"; "SERT" and
        "serotonin transporter" are one target), so a claim listing subunits
        does not demand a quote per subunit. Terms whose spellings are all a
        name of the substance itself are dropped."""
        index = Text.of(text)
        hits = [t for t in self.terms.values() if t.named_in(index)]
        hits = [
            Term(t.label, frozenset(k for k in t.keys if k not in exclude))
            for t in hits
            if not t.keys <= exclude
        ]
        families: list[tuple[str, set[str]]] = []
        for term in sorted(hits, key=lambda t: -len(compact(t.label))):
            joined = [f for f in families if _overlap(f[1], term.keys)]
            if not joined:
                families.append((term.label, set(term.keys)))
                continue
            keep = joined[0]
            for other in joined[1:]:
                keep[1].update(other[1])
                families.remove(other)
            keep[1].update(term.keys)
        out = [Term(label, frozenset(keys)) for label, keys in families]
        # Only spellings the text actually uses decide the family exists, but
        # any of the family's spellings may name it in a quote.
        return [t for t in out if t.named_in(index)]


def _overlap(a: set[str] | frozenset[str], b: set[str] | frozenset[str]) -> bool:
    """Two families are one when they share a spelling, or one's spelling of
    5+ characters is inside the other's ("adrenergic" in "alpha1adrenergic",
    "serotonin" in "serotonintransporter")."""
    if a & b:
        return True
    return any((len(x) >= 5 and x in y) or (len(y) >= 5 and y in x) for x in a for y in b)


def make_term(label: str, extra: list[str] = ()) -> Term | None:
    """A term named by its own spelling, plus the literature spellings
    `target_keys` knows for it. Only a recognized target or enzyme takes those
    expansions: for anything else `target_keys` falls back to each long word
    alone, and "dihydrofolate reductase" would then be named by any "reductase"."""
    keys = {compact(label)} | {compact(e) for e in extra}
    head = _canonical_target(label)
    if head in TARGET_SYNONYMS or head.startswith(ENZYME_PREFIXES):
        grams_, phrases = target_keys(label)
        keys |= grams_ | {p.replace(" ", "") for p in phrases}
    # "α1-adrenergic receptor" is named by "α1-adrenergic receptors" and by
    # "α1-adrenergic blockade": the family is the part prose reliably writes.
    keys |= {re.sub(r"receptors?$", "", k) for k in keys}
    keys = {k for k in keys if k and k not in GENERIC and not k.isdigit()}
    # A two-character key ("d2", "h1") is too ambiguous to stand alone.
    keys = {k for k in keys if len(k) >= 3 or (len(k) == 2 and k[0].isalpha() and k[1].isdigit())}
    if not keys:
        return None
    return Term(label, frozenset(keys))


def name_keys(names: SubstanceNames | None) -> set[str]:
    if names is None:
        return set()
    return set(names.strict) | {p.replace(" ", "") for p in names.phrases}


def distinctive_terms(text: str, exclude: set[str]) -> list[Term]:
    """Fallback key terms for a claim the lexicon finds nothing in: its own
    distinctive words (6+ letters, not generic, not the substance's names)."""
    seen: dict[str, Term] = {}
    for word in fold(text).split():
        if len(word) >= 6 and word not in GENERIC and word not in exclude and not word.isdigit():
            seen.setdefault(word, Term(word, frozenset({word})))
    return list(seen.values())[:6]


# ---------------------------------------------------------------- documents


@dataclass
class Passage:
    doc: Doc
    section: str
    text: str


@dataclass
class Doc:
    kind: str  # wikipedia | dailymed | europepmc
    key: str
    label: str  # what the model is told the document is
    identity: str  # how the identity gate was met
    ref: str  # doi:/pmid:/https:// for the citation
    title: str | None  # citation label for a URL ref
    subject_classes: frozenset[str] = frozenset()
    multi_ingredient: bool = False
    passages: list[Passage] = field(default_factory=list)
    anchors: dict[str, str] = field(default_factory=dict)  # section → anchor
    accessed: str = ""  # the day the document was fetched


SKIP_SECTIONS = {
    "references", "external links", "see also", "further reading", "notes", "bibliography",
    "sources", "citations", "footnotes", "gallery",
}  # fmt: skip
VOID = {"br", "img", "meta", "link", "hr", "input", "wbr", "col", "area", "base", "source",
        "track", "embed", "param"}  # fmt: skip
SKIP_CLASSES = ("reference", "mw-editsection", "navbox", "reflist", "mw-references-wrap",
                "metadata", "noprint", "hatnote", "sistersitebox", "mw-empty-elt", "toc",
                "shortdescription", "ambox", "chemf", "mw-cite-backlink")  # fmt: skip


class _ArticleParser(HTMLParser):
    """Rendered article HTML → [(section, anchor, paragraph text)], plus the drug
    infobox as `label: value` rows."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, bool, str]] = []  # tag, skipping, role
        self.section, self.anchor = "Lead", ""
        self.blocks: list[tuple[str, str, str]] = []
        self.buffer: list[str] = []
        self.infobox: list[str] = []
        self.row: list[str] = []
        self.heading: list[str] | None = None

    def _skipping(self) -> bool:
        return any(skip for _, skip, _ in self.stack)

    def _role(self, role: str) -> bool:
        return any(r == role for _, _, r in self.stack)

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in VOID:
            if tag == "br":
                self.buffer.append(" ")
            return
        a = dict(attrs)
        classes = a.get("class") or ""
        skip = tag in ("style", "script", "sup") and ("reference" in classes or tag != "sup")
        skip = skip or any(c in classes.split() for c in SKIP_CLASSES)
        skip = skip or (tag == "span" and "mw-editsection" in classes)
        role = ""
        if tag == "table" and "infobox" in classes:
            role = "infobox"
        elif tag == "table":
            skip = skip or not self._role("infobox")
        if tag in ("h2", "h3", "h4"):
            self._flush()
            role = "heading"
            self.heading = []
            self.anchor = a.get("id") or ""
        if tag == "span" and self._role("heading") and a.get("id"):
            self.anchor = a.get("id") or self.anchor
        if tag == "tr" and self._role("infobox"):
            self.row = []
        self.stack.append((tag, skip, role))

    def handle_endtag(self, tag: str) -> None:
        if tag in VOID:
            return
        while self.stack:
            opened, _, role = self.stack.pop()
            if role == "heading" and self.heading is not None:
                self.section = " ".join("".join(self.heading).split())
                self.heading = None
            if opened == tag:
                break
        if tag == "tr" and self._role("infobox"):
            cells = [" ".join(c.split()) for c in self.row if c.strip()]
            if len(cells) >= 2:
                self.infobox.append(f"{cells[0]}: {' '.join(cells[1:])}")
            self.row = []
        if tag in ("p", "li", "dd", "dt", "div", "blockquote") and not self._role("infobox"):
            self._flush()

    def handle_data(self, data: str) -> None:
        if self._skipping():
            return
        if self.heading is not None:
            self.heading.append(data)
            return
        if self._role("infobox"):
            if self.stack and self.stack[-1][0] in ("th", "td") or self._in_cell():
                if self.stack and self.stack[-1][0] in ("th", "td") and not self.row_open():
                    self.row.append("")
                if not self.row:
                    self.row.append("")
                self.row[-1] += data
            return
        self.buffer.append(data)

    def _in_cell(self) -> bool:
        return any(t in ("th", "td") for t, _, _ in self.stack)

    def row_open(self) -> bool:
        return bool(self.row)

    def _flush(self) -> None:
        text = " ".join("".join(self.buffer).split())
        self.buffer = []
        if text and self.section.lower() not in SKIP_SECTIONS:
            self.blocks.append((self.section, self.anchor, text))


class _InfoboxCells(HTMLParser):
    """The infobox, read on its own: each row's th and td text kept apart."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.rows: list[str] = []
        self.cells: list[str] = []
        self.cell: list[str] | None = None
        self.skip = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        classes = dict(attrs).get("class") or ""
        if tag == "table" and ("infobox" in classes or self.depth):
            self.depth += 1
        if not self.depth:
            return
        if tag in ("sup", "style", "script") or "reference" in classes.split():
            self.skip += 1 if tag not in VOID else 0
        if tag == "tr":
            self.cells = []
        if tag in ("th", "td"):
            self.cell = []

    def handle_endtag(self, tag: str) -> None:
        if not self.depth:
            return
        if tag in ("sup", "style", "script") and self.skip:
            self.skip -= 1
        if tag in ("th", "td") and self.cell is not None:
            self.cells.append(" ".join("".join(self.cell).split()))
            self.cell = None
        if tag == "tr":
            cells = [c for c in self.cells if c]
            if len(cells) >= 2:
                self.rows.append(f"{cells[0]}: {' '.join(cells[1:])}")
            self.cells = []
        if tag == "table":
            self.depth -= 1

    def handle_data(self, data: str) -> None:
        if self.depth and self.cell is not None and not self.skip:
            self.cell.append(data)


def chunk(text: str, size: int = CHUNK) -> list[str]:
    if len(text) <= size:
        return [text]
    out, current = [], ""
    for sentence in re.split(r"(?<=[.;!?])\s+", text):
        if current and len(current) + len(sentence) + 1 > size:
            out.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()
    if current:
        out.append(current)
    return out


def article_passages(doc: Doc, page_html: str) -> None:
    parser = _ArticleParser()
    parser.feed(page_html)
    parser._flush()
    cells = _InfoboxCells()
    cells.feed(page_html)
    infobox = cells.rows
    if infobox:
        for piece in chunk(" · ".join(infobox)):
            doc.passages.append(Passage(doc, "Infobox", piece))
    merged: dict[tuple[str, str], list[str]] = defaultdict(list)
    order: list[tuple[str, str]] = []
    for section, anchor, text in parser.blocks:
        if (section, anchor) not in merged:
            order.append((section, anchor))
        merged[(section, anchor)].append(text)
    for section, anchor in order:
        doc.anchors.setdefault(section, anchor)
        for piece in chunk(" ".join(merged[(section, anchor)])):
            doc.passages.append(Passage(doc, section, piece))


# ------------------------------------------------------------------ Wikipedia

WP_API = "https://en.wikipedia.org/w/api.php"


def wp_url(**params: str) -> str:
    params = {"format": "json", "formatversion": "2", **params}
    return f"{WP_API}?{urllib.parse.urlencode(params)}"


def name_key(text: str) -> str:
    return compact(text)


class Wikipedia:
    def __init__(self, http: Http, conn: sqlite3.Connection, names: dict[int, SubstanceNames]):
        self.http = http
        self.conn = conn
        self.names = names
        self.docs: dict[str, Doc | None] = {}
        self.lock = threading.Lock()

    def resolve(self, sids: set[int]) -> dict[int, tuple[str, str]]:
        """substance id → (article title, how its identity was established)."""
        keys = dict(
            self.conn.execute(
                "SELECT id, inchikey FROM substances WHERE inchikey IS NOT NULL AND inchikey != ''"
            ).fetchall()
        )
        # Every key in the database, in fixed batches, rather than this run's
        # rows: the queries (and so the cached answers) then do not depend on
        # which rows are still uncited, and a re-run sees the same articles.
        wanted = sorted(set(keys.values()))
        by_key: dict[str, set[str]] = defaultdict(set)
        for start in range(0, len(wanted), 150):
            values = " ".join(f'"{k}"' for k in wanted[start : start + 150])
            query = (
                f"SELECT ?ik ?article WHERE {{ VALUES ?ik {{ {values} }} ?item wdt:P235 ?ik . "
                "?article schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> . }"
            )
            url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode(
                {"query": query, "format": "json"}
            )
            data = self.http.json(url, accept="application/sparql-results+json")
            for row in (data or {}).get("results", {}).get("bindings", []):
                title = urllib.parse.unquote(row["article"]["value"].rsplit("/wiki/", 1)[1])
                by_key[row["ik"]["value"]].add(title.replace("_", " "))
        out: dict[int, tuple[str, str]] = {}
        for sid in sids:
            titles = by_key.get(keys.get(sid, ""), set())
            if len(titles) == 1:
                out[sid] = (next(iter(titles)), f"Wikidata sitelink of InChIKey {keys[sid]}")
        popularity = json.loads(POPULARITY.read_text()) if POPULARITY.exists() else {}
        curated_links = curated_wikipedia_links()
        for sid in sids - set(out):
            names = self.names.get(sid)
            if names is None:
                continue
            candidates: list[str] = []
            for raw in [names.canonical, *sorted(all_names(self.conn, sid))]:
                if raw in popularity and popularity[raw].get("article"):
                    candidates.append(popularity[raw]["article"])
                candidates.extend(curated_links.get(raw.lower(), []))
            for title in dict.fromkeys(candidates):
                how = self.title_names_substance(title, sid)
                if how:
                    out[sid] = (title, how)
                    break
        return out

    def title_names_substance(self, title: str, sid: int) -> str | None:
        """The identity gate for an article reached by name: its title, or a
        title that redirects to it, is one of the substance's own names."""
        names = {name_key(n) for n in all_names(self.conn, sid)}
        names.add(name_key(self.names[sid].canonical))
        data = self.http.json(
            wp_url(action="query", titles=title, prop="redirects", rdlimit="max", redirects="1")
        )
        pages = ((data or {}).get("query") or {}).get("pages") or []
        if not pages or pages[0].get("missing"):
            return None
        final = pages[0]["title"]
        if name_key(final) in names:
            return f"article title '{final}' is a name of the substance"
        for redirect in pages[0].get("redirects") or []:
            if name_key(redirect["title"]) in names:
                return f"redirect '{redirect['title']}' → '{final}' is a name of the substance"
        return None

    def article(
        self, title: str, identity: str, classes: frozenset[str] = frozenset()
    ) -> Doc | None:
        with self.lock:
            if title in self.docs:
                return self.docs[title]
        url = wp_url(action="parse", page=title, prop="text|revid|displaytitle", redirects="1")
        data = self.http.json(url)
        parsed = (data or {}).get("parse")
        doc = None
        if parsed and parsed.get("revid"):
            final = parsed["title"]
            revid = parsed["revid"]
            permalink = "https://en.wikipedia.org/w/index.php?" + urllib.parse.urlencode(
                {"title": final.replace(" ", "_"), "oldid": revid}
            )
            doc = Doc(
                kind="wikipedia",
                key=f"wp:{final}",
                label=f"Wikipedia article '{final}'",
                identity=identity,
                ref=permalink,
                title=f"Wikipedia: {final} (revision {revid})",
                subject_classes=classes,
                accessed=self.http.fetched_on(url),
            )
            article_passages(doc, parsed.get("text") or "")
        with self.lock:
            self.docs[title] = doc
        return doc


def curated_wikipedia_links() -> dict[str, list[str]]:
    """Curated file name → Wikipedia article titles its `sources` link to."""
    out: dict[str, list[str]] = defaultdict(list)
    for path in SUBSTANCE_FILES.glob("*.json"):
        data = json.loads(path.read_text())
        for source in data.get("sources") or []:
            match = re.search(r"en\.wikipedia\.org/wiki/([^\s#?;]+)", str(source))
            if match:
                title = urllib.parse.unquote(match.group(1)).replace("_", " ")
                for name in (data.get("name"), data.get("displayName")):
                    if name:
                        out[name.lower()].append(title)
    return out


_NAMES_CACHE: dict[int, set[str]] = {}
_NAMES_LOCK = threading.Lock()
_BAD_ALIAS_KINDS = ("street", "malformed", "distinct_substance", "combination", "misspelling")


def all_names(conn: sqlite3.Connection, sid: int) -> set[str]:
    with _NAMES_LOCK:
        return _all_names(conn, sid)


def _all_names(conn: sqlite3.Connection, sid: int) -> set[str]:
    if sid not in _NAMES_CACHE:
        names = {
            row[0]
            for row in conn.execute(
                "SELECT canonical_name FROM substances WHERE id = ? UNION "
                "SELECT display_name FROM substances WHERE id = ? AND display_name IS NOT NULL",
                (sid, sid),
            )
        }
        marks = ",".join("?" for _ in _BAD_ALIAS_KINDS)
        names |= {
            row[0]
            for row in conn.execute(
                f"SELECT alias FROM aliases WHERE substance_id = ? "
                f"AND (kind IS NULL OR kind NOT IN ({marks}))",
                (sid, *_BAD_ALIAS_KINDS),
            )
        }
        _NAMES_CACHE[sid] = {n for n in names if n and len(compact(n)) >= 3}
    return _NAMES_CACHE[sid]


# ------------------------------------------------------------------- DailyMed

HL7 = "{urn:hl7-org:v3}"
SPL = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls/{setid}.xml"
DAILYMED_PAGE = "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid="
_SETID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)


def known_setids(conn: sqlite3.Connection) -> dict[int, set[str]]:
    """Every setid the database already cites for a substance, on any table."""
    out: dict[int, set[str]] = defaultdict(set)
    tables = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    for table in tables:
        if {"substance_id", "citation_id"} <= row_citations.table_columns(conn, table):
            for sid, url in conn.execute(
                f'SELECT t.substance_id, c.url FROM "{table}" t JOIN citations c '
                "ON c.id = t.citation_id WHERE c.url LIKE '%setid%'"
            ):
                for setid in _SETID.findall(url or ""):
                    out[sid].add(setid.lower())
    return out


def _text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return " ".join(" ".join(element.itertext()).split())


class DailyMed:
    def __init__(self, http: Http, conn: sqlite3.Connection) -> None:
        self.http = http
        self.conn = conn
        self.labels: dict[str, tuple | None] = {}

    def label(self, setid: str) -> tuple | None:
        """(SPL title, active ingredient and moiety names, [(section, text)],
        product name)."""
        if setid in self.labels:
            return self.labels[setid]
        body = self.http.get(SPL.format(setid=setid))
        result = None
        if body and body.lstrip().startswith("<"):
            try:
                root = ET.fromstring(body.encode("utf-8"))
            except ET.ParseError:
                root = None
            if root is not None:
                title = _text(root.find(f"{HL7}title"))
                ingredients = sorted(
                    {
                        _text(el)
                        for path in (
                            f".//{HL7}activeIngredientSubstance/{HL7}name",
                            f".//{HL7}activeMoiety/{HL7}activeMoiety/{HL7}name",
                            f".//{HL7}activeMoiety/{HL7}name",
                        )
                        for el in root.iterfind(path)
                    }
                    - {""}
                )
                sections = []
                for section in root.iter(f"{HL7}section"):
                    heading = _text(section.find(f"{HL7}title"))
                    text = _text(section.find(f"{HL7}text"))
                    if text:
                        sections.append((heading or "Label", text))
                product = _text(root.find(f".//{HL7}manufacturedProduct/{HL7}name"))
                result = (title, ingredients, sections, product)
        self.labels[setid] = result
        return result

    def doc(self, setid: str, sid: int, classes: frozenset[str] = frozenset()) -> Doc | None:
        label = self.label(setid)
        if label is None:
            return None
        title, ingredients, sections, product = label
        moieties = {tokens(i) for i in ingredients}
        named = sorted(
            n
            for n in all_names(self.conn, sid)
            if len("".join(tokens(n))) >= 4 and any(_contains_run(m, tokens(n)) for m in moieties)
        )
        if not named:
            return None
        # A multi-ingredient label: more than one distinct active moiety once salt
        # words are dropped.
        bases = {" ".join(t for t in tokens(i) if t not in SALT_WORDS) for i in ingredients} - {""}
        doc = Doc(
            kind="dailymed",
            key=f"dm:{setid}",
            label=f"FDA label (DailyMed) '{title[:120]}'",
            identity=f"active ingredient names '{named[0]}' as whole words",
            ref=DAILYMED_PAGE + setid,
            # SPL titles open with "These highlights do not include…", so the
            # citation names the product and its active ingredients instead.
            title=f"DailyMed: {product or title[:80]} ({', '.join(ingredients).lower()}) label",
            subject_classes=classes,
            multi_ingredient=len(_collapse_bases(bases)) > 1,
            accessed=self.http.fetched_on(SPL.format(setid=setid)),
        )
        for heading, text in sections:
            for piece in chunk(text):
                doc.passages.append(Passage(doc, heading, piece))
        return doc


SALT_WORDS = {
    "hydrochloride", "hcl", "sulfate", "sulphate", "mesylate", "maleate", "tartrate",
    "bitartrate", "citrate", "phosphate", "sodium", "potassium", "calcium", "acetate",
    "fumarate", "succinate", "besylate", "bromide", "hydrobromide", "chloride", "anhydrous",
    "monohydrate", "dihydrate", "trihydrate", "hemihydrate", "magnesium", "dimesylate",
    "dihydrochloride", "napsylate", "pamoate", "lactate", "gluconate", "oxalate", "hyclate",
    "disodium", "propionate", "valerate", "cypionate", "enanthate", "decanoate", "undecanoate",
}  # fmt: skip


def _collapse_bases(bases: set[str]) -> set[str]:
    """Moiety names with every name that contains another collapsed onto it, so
    'ketamine' and 'ketamine hydrochloride' leftovers count once."""
    kept: set[str] = set()
    for base in sorted(bases, key=len):
        if not any(_contains_run(tuple(base.split()), tuple(k.split())) for k in kept):
            kept.add(base)
    return kept


# ----------------------------------------------------------------- Europe PMC

EPMC = "https://www.ebi.ac.uk/europepmc/webservices/rest/search?"


def epmc_reviews(http: Http, names: SubstanceNames, name: str, term: str) -> list[Doc]:
    query = f'(TITLE_ABS:"{name}") AND (TITLE_ABS:"{term}") AND PUB_TYPE:"review"'
    url = EPMC + urllib.parse.urlencode(
        {"query": query, "format": "json", "pageSize": 3, "resultType": "core"}
    )
    data = http.json(url)
    out: list[Doc] = []
    for row in ((data or {}).get("resultList") or {}).get("result") or []:
        pmid, doi = row.get("pmid"), row.get("doi")
        abstract = re.sub(r"<[^>]+>", " ", html.unescape(row.get("abstractText") or ""))
        abstract = " ".join(abstract.split())
        title = " ".join(re.sub(r"<[^>]+>", " ", row.get("title") or "").split())
        if not abstract or not (pmid or doi):
            continue
        how = names_substance_strictly(names, f"{title} {abstract}")
        if not how:
            continue
        doc = Doc(
            kind="europepmc",
            key=f"epmc:{pmid or doi}",
            label=f"Review abstract '{title[:140]}' ({row.get('journalTitle') or ''} {row.get('pubYear') or ''})",
            identity=f"title/abstract names the substance ('{how}')",
            ref=f"pmid:{pmid}" if pmid else f"doi:{doi}",
            title=None,
            accessed=http.fetched_on(url),
        )
        for piece in chunk(abstract):
            doc.passages.append(Passage(doc, "Abstract", piece))
        out.append(doc)
    return out


def names_substance_strictly(names: SubstanceNames, text: str) -> str | None:
    """A name of the substance in `text`, by its own spellings only — no analog
    containment, no street slang."""
    index = build_index(text)
    for key in sorted(names.strict - names.street_only):
        if key in index.grams and (len(key) >= 5 or key in index.caps):
            return key
    for phrase in sorted(names.phrases):
        if phrase in index.phrases:
            return phrase
    return None


# --------------------------------------------------------------------- claims


@dataclass
class Claim:
    target: str  # a | b | c | d
    table: str
    sid: int | None
    substance: str
    text: str
    #: Term groups the quotes must name. `need` of them, at least.
    terms: list[Term]
    need: int
    docs: list[Doc] = field(default_factory=list)
    number_minutes: float | None = None
    entry: dict = field(default_factory=dict)  # sidecar identity / file locator
    #: Interaction rules: the two classes and their term groups.
    classes: tuple[str, str] | None = None
    class_terms: dict[str, Term] = field(default_factory=dict)
    origin: str = ""  # what the claim is, for the report
    #: zh-Hans/zh-Hant copies of a class paragraph that inherit this row's citation.
    copies: list[dict] = field(default_factory=list)
    #: Why the row itself is inconsistent, so no source can be checked against it.
    defect: str = ""

    @property
    def cid(self) -> str:
        return hashlib.sha1(json.dumps(self.entry, sort_keys=True).encode()).hexdigest()[:16]


SOURCELESS = ("piru-curated", "peer-review-primary")


def uncited(conn: sqlite3.Connection, table: str, extra: str = "") -> list[sqlite3.Row]:
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        f"SELECT t.rowid AS _rowid, t.*, s.canonical_name AS _substance, src.slug AS _source "
        f'FROM "{table}" t JOIN substances s ON s.id = t.substance_id '
        f"JOIN sources src ON src.id = t.source_id "
        f"WHERE t.citation_id IS NULL AND src.slug IN (?, ?) {extra} "
        f"ORDER BY s.canonical_name, t.rowid",
        SOURCELESS,
    ).fetchall()
    conn.row_factory = None
    return rows


#: Columns that name a row within its substance, per table.
IDENTITY = {
    "mechanisms_summary": ["language"],
    "downstream_signalling": [],
    "pharmacogenetics": ["gene"],
    "metabolism": ["enzyme", "metabolite_name", "route"],
    "off_targets": ["target"],
    "drug_interactions_pk": ["with_substance", "mechanism"],
    "bindings": ["target", "action", "species"],
    "functional_assays": ["target", "readout"],
    "neuroimaging": ["modality"],
    "biased_agonism": ["target", "pathways_compared"],
}


def entry_for(row: sqlite3.Row, table: str) -> dict:
    entry = {
        "table": table,
        "substance": row["_substance"],
        "source": row["_source"],
        "match": {c: row[c] for c in IDENTITY[table]},
    }
    if table in row_citations.CLAIM_COLUMNS:
        entry["claim_sha1"] = row_citations.claim_sha1(row[row_citations.CLAIM_COLUMNS[table]])
    return entry


def split_alternatives(text: str) -> list[str]:
    parts = re.split(r"\s*(?:/|,|;|\bor\b|\band\b|\+)\s*", re.sub(r"\([^)]*\)", " ", text or ""))
    return [p.strip() for p in parts if len(compact(p)) >= 3]


def key_term(label: str | None, lexicon: Lexicon) -> Term | None:
    """One row's key column as a term, with every alternative it lists."""
    if not label:
        return None
    alternatives = split_alternatives(label) or [label]
    keys: set[str] = set()
    for alt in alternatives:
        term = lexicon.terms.get(compact(alt)) or make_term(alt)
        if term:
            keys |= term.keys
    return Term(label, frozenset(keys)) if keys else None


def collect_c(conn, lexicon, names) -> list[Claim]:
    out: list[Claim] = []
    specs = {
        # table: (claim builder, key column builder)
        "pharmacogenetics": (
            lambda r: f"{r['gene']}: {r['phenotype_effects']}",
            lambda r: r["gene"],
        ),
        "metabolism": (
            lambda r: (
                f"{r['_substance']} is metabolized"
                + (f" by {r['enzyme']}" if r["enzyme"] else "")
                + (f" to {r['metabolite_name']}" if r["metabolite_name"] else "")
                + (" (an active metabolite)" if r["metabolite_active"] == 1 else "")
                + (f". {r['notes']}" if r["notes"] else "")
            ),
            lambda r: r["enzyme"] or r["metabolite_name"],
        ),
        "off_targets": (
            lambda r: f"Off-target: {r['target']}. {r['clinical_consequence'] or ''}".strip(),
            lambda r: r["target"],
        ),
        "drug_interactions_pk": (
            lambda r: (
                f"Interaction with {r['with_substance']}: {r['mechanism'] or ''}. "
                f"{r['clinical_effect'] or ''}"
            ).strip(),
            lambda r: r["with_substance"],
        ),
        "bindings": (
            lambda r: (
                f"{r['_substance']} acts at {r['target']} as {action_words(r['action'])}"
                + (f" ({r['species']})" if r["species"] else "")
                + (f". {r['notes']}" if r["notes"] else "")
            ),
            lambda r: r["target"],
        ),
        "functional_assays": (
            lambda r: (
                f"Functional assay at {r['target']}: {r['readout'] or ''}"
                + (f". {r['notes']}" if r["notes"] else "")
            ),
            lambda r: r["target"],
        ),
        "neuroimaging": (lambda r: f"{r['modality']}: {r['finding']}", lambda r: r["modality"]),
        "biased_agonism": (
            lambda r: (
                f"Signalling bias at {r['target']} ({r['pathways_compared']}): {r['interpretation']}"
            ),
            lambda r: r["target"],
        ),
    }
    pgx_genes = {
        gene: make_term(gene)
        for (gene,) in conn.execute("SELECT DISTINCT gene FROM pharmacogenetics")
        if gene and make_term(gene)
    }
    for table, (claim_of, key_of) in specs.items():
        extra = "AND src.slug = 'peer-review-primary'" if table == "bindings" else ""
        for row in uncited(conn, table, extra):
            term = key_term(key_of(row), lexicon)
            claim = Claim(
                target="c",
                table=table,
                sid=row["substance_id"],
                substance=row["_substance"],
                text=claim_of(row),
                terms=[term] if term else [],
                need=1,
                entry=entry_for(row, table),
                origin=table,
            )
            if table == "pharmacogenetics":
                claim.defect = gene_mismatch(row, term, pgx_genes)
            out.append(claim)
    for row in uncited(conn, "downstream_signalling"):
        out.append(prose_claim(row, "downstream_signalling", row["summary"], "", lexicon, names))
    return out


def gene_mismatch(row, own: Term | None, genes: dict[str, Term]) -> str:
    """A pharmacogenetics row whose phenotype text names another gene and not
    its own (1,4-Butanediol's ADH1B row describes ALDH2*2). Its text belongs to
    a different row; a source for the text would be cited against the wrong gene."""
    text = Text.of(row["phenotype_effects"] or "")
    if own is None or own.named_in(text):
        return ""
    others = sorted(
        g
        for g, t in genes.items()
        if g != row["gene"] and not _overlap(t.keys, own.keys) and t.named_in(text)
    )
    if not others:
        return ""
    return f"gene {row['gene']} row, but its phenotype text names {', '.join(others)}"


def action_words(action: str | None) -> str:
    return re.sub(r"(?<!^)([A-Z])", r" \1", action or "ligand").lower()


def prose_claim(row, table, summary, description, lexicon, names, target="c") -> Claim:
    exclude = name_keys(names.get(row["substance_id"]))
    terms = lexicon.find(summary, exclude)
    if not terms and description:
        terms = lexicon.find(description, exclude)
    if not terms:
        terms = distinctive_terms(summary, exclude)
    text = summary if not description else f"{summary}\n\nDetail: {description}"
    return Claim(
        target=target,
        table=table,
        sid=row["substance_id"],
        substance=row["_substance"],
        text=text,
        terms=terms,
        need=max(1, math.ceil(len(terms) / 2)),
        entry=entry_for(row, table),
        origin=table,
    )


def class_paragraphs() -> dict[str, dict[str, str]]:
    """language → class-paragraph summary → class name."""
    data = json.loads((CURATED / "class-mechanisms.json").read_text())
    out: dict[str, dict[str, str]] = defaultdict(dict)
    for entry in data.get("classes", []):
        for language, prose in (entry.get("prose") or {}).items():
            if prose.get("summary"):
                out[language][" ".join(prose["summary"].split())] = entry["class"]
    return out


def collect_b(conn, lexicon, names) -> list[Claim]:
    paragraphs = class_paragraphs()
    out: list[Claim] = []
    rows = uncited(conn, "mechanisms_summary", "AND src.slug = 'piru-curated'")
    copies: dict[tuple[int, str], list[dict]] = defaultdict(list)
    for row in rows:
        if row["language"] == "en":
            continue
        cls = paragraphs.get(row["language"], {}).get(" ".join((row["summary"] or "").split()))
        if cls:
            copies[(row["substance_id"], cls)].append(entry_for(row, "mechanisms_summary"))
    for row in rows:
        if row["language"] != "en":
            continue
        claim = prose_claim(
            row, "mechanisms_summary", row["summary"] or "", row["description"] or "",
            lexicon, names, target="b",
        )  # fmt: skip
        cls = paragraphs.get("en", {}).get(" ".join((row["summary"] or "").split()))
        if cls:
            claim.origin = f"class paragraph '{cls}'"
            claim.copies = copies.get((row["substance_id"], cls), [])
        out.append(claim)
    return out


#: The class article each interaction class is about. Fetched by title; the
#: identity gate is that the article resolves to exactly this title.
CLASS_ARTICLES = {
    "opioid": "Opioid", "benzodiazepine": "Benzodiazepine", "alcohol": "Alcohol (drug)",
    "ghb": "γ-Hydroxybutyric acid", "maoi": "Monoamine oxidase inhibitor",
    "ssri": "Selective serotonin reuptake inhibitor",
    "snri": "Serotonin–norepinephrine reuptake inhibitor", "tca": "Tricyclic antidepressant",
    "stimulant": "Stimulant", "empathogen": "Entactogen", "psychedelic": "Psychedelic drug",
    "dissociative": "Dissociative", "cannabinoid": "Cannabinoid", "lithium": "Lithium (medication)",
    "antipsychotic": "Antipsychotic", "antihistamine": "Antihistamine",
    "barbiturate": "Barbiturate", "gabapentinoid": "Gabapentinoid", "betaBlocker": "Beta blocker",
    "alpha2Agonist": "Alpha-2 adrenergic receptor agonist", "orexinAntagonist": "Orexin antagonist",
}  # fmt: skip
#: Words that name each class in prose, beside its members' names.
CLASS_WORDS = {
    "opioid": ["opioid", "opioids", "opiate", "opiates", "narcotic"],
    "benzodiazepine": ["benzodiazepine", "benzodiazepines"],
    "alcohol": ["alcohol", "ethanol"],
    "ghb": ["GHB", "gamma-hydroxybutyrate", "γ-hydroxybutyrate", "oxybate", "GBL"],
    "maoi": ["MAOI", "MAOIs", "monoamine oxidase inhibitor", "monoamine oxidase inhibitors"],
    "ssri": ["SSRI", "SSRIs", "selective serotonin reuptake inhibitor"],
    "snri": ["SNRI", "SNRIs", "serotonin-norepinephrine reuptake inhibitor"],
    "tca": ["TCA", "TCAs", "tricyclic antidepressant", "tricyclic antidepressants", "tricyclics"],
    "stimulant": ["stimulant", "stimulants", "amphetamines", "sympathomimetic"],
    "empathogen": ["MDMA", "empathogen", "entactogen", "ecstasy"],
    "psychedelic": ["psychedelic", "psychedelics", "hallucinogen", "hallucinogens", "LSD", "psilocybin"],
    "dissociative": ["dissociative", "dissociatives", "ketamine", "PCP", "dextromethorphan", "DXM"],
    "cannabinoid": ["cannabis", "cannabinoid", "cannabinoids", "THC", "marijuana"],
    "lithium": ["lithium"],
    "antipsychotic": ["antipsychotic", "antipsychotics", "neuroleptic", "neuroleptics"],
    "antihistamine": ["antihistamine", "antihistamines", "anticholinergic", "anticholinergics"],
    "barbiturate": ["barbiturate", "barbiturates"],
    "gabapentinoid": ["gabapentinoid", "gabapentinoids", "gabapentin", "pregabalin"],
    "betaBlocker": ["beta blocker", "beta blockers", "beta-blocker", "beta-blockers", "β-blocker"],
    "alpha2Agonist": ["alpha-2 agonist", "α2 agonist", "clonidine", "guanfacine", "dexmedetomidine"],
    "orexinAntagonist": ["orexin antagonist", "orexin receptor antagonist", "suvorexant", "lemborexant", "daridorexant"],
    "serotonergic": ["serotonergic", "serotonin"],
}  # fmt: skip
#: Members whose pages carry the class's interaction warnings, most-used first.
CLASS_MEMBERS = {
    "opioid": ["Morphine", "Oxycodone", "Fentanyl", "Heroin", "Methadone"],
    "benzodiazepine": ["Diazepam", "Alprazolam", "Clonazepam"],
    "alcohol": ["Alcohol"],
    "ghb": ["GHB", "Sodium oxybate"],
    "maoi": ["Phenelzine", "Tranylcypromine", "Moclobemide"],
    "ssri": ["Fluoxetine", "Sertraline", "Escitalopram"],
    "snri": ["Venlafaxine", "Duloxetine"],
    "tca": ["Amitriptyline", "Clomipramine"],
    "stimulant": ["Amphetamine", "Methamphetamine", "Cocaine", "Methylphenidate"],
    "empathogen": ["MDMA"],
    "psychedelic": ["LSD", "Psilocybin"],
    "dissociative": ["Ketamine", "Dextromethorphan", "PCP"],
    "cannabinoid": ["Cannabis", "THC"],
    "lithium": ["Lithium"],
    "antipsychotic": ["Quetiapine", "Olanzapine", "Haloperidol"],
    "antihistamine": ["Diphenhydramine", "Promethazine"],
    "barbiturate": ["Phenobarbital", "Butalbital"],
    "gabapentinoid": ["Gabapentin", "Pregabalin"],
    "betaBlocker": ["Propranolol", "Metoprolol"],
    "alpha2Agonist": ["Clonidine", "Guanfacine"],
    "orexinAntagonist": ["Suvorexant", "Lemborexant"],
    "serotonergic": ["Tramadol", "Dextromethorphan"],
}  # fmt: skip


def class_member_ids(conn) -> dict[str, list[int]]:
    """class → substance ids: the hand list first, then the curated class table."""
    by_name = {
        n.lower(): sid for sid, n in conn.execute("SELECT id, canonical_name FROM substances")
    }
    out: dict[str, list[int]] = defaultdict(list)
    for cls, members in CLASS_MEMBERS.items():
        for name in members:
            if name.lower() in by_name and by_name[name.lower()] not in out[cls]:
                out[cls].append(by_name[name.lower()])
    for sid, cls in conn.execute(
        "SELECT substance_id, drug_class FROM substance_interaction_classes "
        "WHERE substance_id IS NOT NULL ORDER BY rank, name"
    ):
        if sid not in out[cls]:
            out[cls].append(sid)
    return out


def class_term(conn, cls: str, members: list[int]) -> Term:
    keys: set[str] = set()
    for word in CLASS_WORDS.get(cls, [cls]):
        keys.add(compact(word))
    # Members count by their canonical, display, generic and brand names only:
    # an unclassified alias can be a common word ("Gamma" for GHB) that would
    # make every GABA sentence name the class.
    for sid in members:
        rows = conn.execute(
            "SELECT canonical_name FROM substances WHERE id = ? UNION "
            "SELECT display_name FROM substances WHERE id = ? UNION "
            "SELECT alias FROM aliases WHERE substance_id = ? "
            "AND kind IN ('generic', 'brand', 'abbreviation')",
            (sid, sid, sid),
        ).fetchall()
        for (name,) in rows:
            if name and len(compact(name)) >= 4:
                keys.add(compact(name))
    return Term(cls, frozenset(k for k in keys if k))


def collect_a(conn) -> list[Claim]:
    payload = json.loads(RULES.read_text())
    members = class_member_ids(conn)
    out: list[Claim] = []
    for rule in payload["rules"]:
        if rule.get("citation"):
            continue
        a, b = rule["classA"], rule["classB"]
        claim = Claim(
            target="a",
            table="interaction_rules",
            sid=None,
            substance=f"{a} + {b}",
            text=f"Combining {a} with {b} is {rule['severity']}: {rule['note']}",
            terms=[],
            need=2,
            entry={"rule": [a, b]},
            classes=(a, b),
            class_terms={c: class_term(conn, c, members.get(c, [])) for c in (a, b)},
            origin=f"{rule['severity']} rule",
        )
        out.append(claim)
    return out


def curated_half_life_files() -> dict[str, tuple[Path, float, bool]]:
    """name/displayName (lowercase) → (file, halfLifeMinutes, has halfLifeSource)."""
    out: dict[str, tuple[Path, float, bool]] = {}
    for path in sorted(SUBSTANCE_FILES.glob("*.json")):
        data = json.loads(path.read_text())
        if data.get("halfLifeMinutes") is None:
            continue
        for name in (data.get("name"), data.get("displayName")):
            if name:
                out.setdefault(
                    name.lower(),
                    (path, float(data["halfLifeMinutes"]), bool(data.get("halfLifeSource"))),
                )
    return out


def collect_d(conn) -> tuple[list[Claim], list[str]]:
    files = curated_half_life_files()
    out: list[Claim] = []
    unmapped: list[str] = []
    for row in uncited(conn, "half_lives", "AND src.slug = 'piru-curated'"):
        minutes = row["half_life_minutes"]
        found = None
        for name in [row["_substance"], *sorted(all_names(conn, row["substance_id"]))]:
            hit = files.get(name.lower())
            if hit and abs(hit[1] - minutes) < 1e-6 and not hit[2]:
                found = hit
                break
        if found is None:
            unmapped.append(f"{row['_substance']} ({minutes:g} min)")
            continue
        hours = minutes / 60
        claim = Claim(
            target="d",
            table="half_lives",
            sid=row["substance_id"],
            substance=row["_substance"],
            text=(
                f"The elimination half-life of {row['_substance']} is {minutes:g} minutes "
                f"(= {hours:.3g} hours"
                + (f" = {minutes / 1440:.3g} days" if minutes >= 2880 else "")
                + ")."
            ),
            terms=[Term("half-life", frozenset(compact(h) for h in HALF_LIFE))],
            need=1,
            number_minutes=minutes,
            entry={"file": str(found[0].relative_to(REPO)), "minutes": minutes},
            origin="curated half-life",
        )
        out.append(claim)
    return out, unmapped


# -------------------------------------------------------------- retrieval


def gather(claims: list[Claim], conn, names, http: Http, use_epmc: bool) -> None:
    wiki = Wikipedia(http, conn, names)
    dm = DailyMed(http, conn)
    setids = known_setids(conn)
    sids = {c.sid for c in claims if c.sid}
    members = class_member_ids(conn)
    for claim in claims:
        if claim.classes:
            for cls in claim.classes:
                sids.update(members.get(cls, [])[:4])
    print(f"  resolving Wikipedia articles for {len(sids)} substances …", flush=True)
    titles = wiki.resolve(sids)
    print(f"  {len(titles)} resolved; fetching articles and labels …", flush=True)

    def substance_docs(sid: int, classes: frozenset[str] = frozenset()) -> list[Doc]:
        docs: list[Doc] = []
        if sid in titles:
            title, how = titles[sid]
            doc = wiki.article(title, how, classes)
            if doc:
                docs.append(doc)
        for setid in sorted(setids.get(sid, ()))[:2]:
            doc = dm.doc(setid, sid, classes)
            if doc:
                docs.append(doc)
        return docs

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda s: substance_docs(s), sorted(sids)))

    class_docs: dict[str, list[Doc]] = {}

    def docs_for_class(cls: str) -> list[Doc]:
        if cls in class_docs:
            return class_docs[cls]
        docs: list[Doc] = []
        article = CLASS_ARTICLES.get(cls)
        if article:
            data = http.json(wp_url(action="query", titles=article, redirects="1"))
            pages = ((data or {}).get("query") or {}).get("pages") or []
            if pages and not pages[0].get("missing") and pages[0]["title"] == article:
                doc = wiki.article(
                    article, f"class article '{article}' for {cls}", frozenset({cls})
                )
                if doc:
                    docs.append(doc)
        for sid in [s for s in members.get(cls, []) if s in titles][:3]:
            docs.extend(substance_docs(sid, frozenset({cls})))
        class_docs[cls] = docs
        return docs

    for claim in claims:
        if claim.classes:
            for cls in claim.classes:
                claim.docs.extend(docs_for_class(cls))
        elif claim.sid:
            claim.docs.extend(substance_docs(claim.sid))
    if use_epmc:
        queries: dict[tuple[int, str], Claim] = {}
        for claim in claims:
            if claim.target in ("b", "c", "d") and claim.sid and claim.terms:
                term = "half-life" if claim.target == "d" else claim.terms[0].label
                queries.setdefault((claim.sid, term), claim)
        print(f"  {len(queries)} Europe PMC review queries …", flush=True)

        def run(item):
            (sid, term), claim = item
            if sid not in names:
                return item[0], []
            return item[0], epmc_reviews(http, names[sid], claim.substance, term)

        with ThreadPoolExecutor(max_workers=3) as pool:
            results = dict(pool.map(run, queries.items()))
        for claim in claims:
            if claim.target in ("b", "c", "d") and claim.sid and claim.terms:
                term = "half-life" if claim.target == "d" else claim.terms[0].label
                claim.docs.extend(results.get((claim.sid, term), []))


# --------------------------------------------------------- passage selection

_RANGE = re.compile(
    r"(?P<low>\d+(?:\.\d+)?)\s*(?:–|—|-|to)\s*(?P<high>\d+(?:\.\d+)?)\s*"
    r"(?P<unit>[a-zA-Z]{1,8})\b"
)


def time_ranges(text: str) -> list[tuple[float, float, str]]:
    """Every duration range in `text` ("20–33 hours", "2 to 4 h") as
    (low, high) in minutes, with the text that stated it."""
    found = []
    for match in _RANGE.finditer(text):
        low = extract_quantities(f"{match.group('low')} {match.group('unit')}")
        high = extract_quantities(f"{match.group('high')} {match.group('unit')}")
        if low and high and low[0].unit_class == high[0].unit_class == "time":
            found.append((low[0].value, high[0].value, match.group(0)))
    return found


def number_in(minutes: float, text: str) -> str | None:
    """How `text` states a half-life of `minutes`, or None.

    The value itself, to within 1% (the rounding a unit conversion leaves:
    100 min is 1.67 h): "3.6 hours" is 216 minutes and "4 hours" is not.
    (`value_matches` derives its tolerance from the row's digits, and a row in
    minutes like 300 has one significant figure, so it would let "4 h" stand
    for 5 h.) Or a range the value lies inside, recorded as "within range X–Y"
    so a reader sees that the source gives a range."""
    for quantity in extract_quantities(text):
        if quantity.unit_class == "time" and abs(quantity.value - minutes) <= 0.01 * minutes:
            return quantity.raw
    for low, high, raw in time_ranges(text):
        if low * 0.995 <= minutes <= high * 1.005 and low < high:
            return f"within range {raw}"
    return None


def content_words(text: str) -> set[str]:
    return {w for w in fold(text).split() if len(w) >= 5 and w not in GENERIC}


def select_passages(claim: Claim) -> list[Passage]:
    """The passages worth showing: each must name a key term (or, for a rule,
    a class), and for a half-life its matching number."""
    scored: list[tuple[float, int, Passage]] = []
    words = content_words(claim.text)
    order = 0
    seen: set[tuple[str, str]] = set()
    for doc in claim.docs:
        for passage in doc.passages:
            marker = (doc.key, passage.text[:80])
            if marker in seen:
                continue
            seen.add(marker)
            order += 1
            index = Text.of(passage.text)
            if claim.classes:
                named = classes_named(claim, doc, index)
                if len(named) < 2:
                    continue
                score = 10.0 + sum(1 for t in claim.class_terms.values() if t.named_in(index))
            else:
                hits = sum(1 for t in claim.terms if t.named_in(index))
                if hits == 0:
                    continue
                if (
                    claim.number_minutes is not None
                    and number_in(claim.number_minutes, passage.text) is None
                ):
                    continue
                score = 10.0 * hits
            score += len(words & content_words(passage.text)) * 0.5
            scored.append((score, order, passage))
    scored.sort(key=lambda s: (-s[0], s[1]))
    picked: list[Passage] = []
    per_doc: Counter = Counter()
    for _, _, passage in scored:
        if per_doc[passage.doc.key] >= MAX_PER_DOC:
            continue
        picked.append(passage)
        per_doc[passage.doc.key] += 1
        if len(picked) >= MAX_PASSAGES:
            break
    return picked


def classes_named(claim: Claim, doc: Doc, index: Text) -> set[str]:
    named = set()
    for cls, term in claim.class_terms.items():
        if cls in doc.subject_classes or term.named_in(index):
            named.add(cls)
    return named


# ------------------------------------------------------------------- the model

SYSTEM = """You check whether a source passage states a claim from a drug reference database.

You are given a claim and numbered passages taken from public documents (Wikipedia articles, FDA labels, review abstracts). Decide, using ONLY the passages, whether one document states the claim.

Rules:
- Never use outside knowledge, and never name a source, URL, DOI, PMID or number that is not in the passages.
- "supported": one document's passages state the claim's central assertions (the mechanism, target, enzyme, effect or interaction it asserts). Minor wording need not match.
- "partial": the passages state only part of the central assertions.
- "contradicted": a passage states the opposite of the claim.
- "not_found": the passages do not state the claim.
- For "supported" or "partial", give 1 to 3 quotes, all from ONE document, each copied character for character from the passage it cites (at most 300 characters each, whole words). The quotes must together show the support. Cite the passage number of each quote.
- For a numeric claim, a quote must contain the number as the passage writes it.
- For "not_found" or "contradicted", give no quotes unless a quote shows the contradiction.
- Keep "reason" to one short sentence."""

SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {
            "type": "string",
            "enum": ["supported", "partial", "not_found", "contradicted"],
        },
        "quotes": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"passage": {"type": "integer"}, "quote": {"type": "string"}},
                "required": ["passage", "quote"],
                "additionalProperties": False,
            },
        },
        "reason": {"type": "string"},
    },
    "required": ["verdict", "quotes", "reason"],
    "additionalProperties": False,
}


def build_prompt(claim: Claim, passages: list[Passage]) -> str:
    lines = [f"Substance: {claim.substance}", f"Claim: {claim.text}", ""]
    if claim.number_minutes is not None:
        lines += [
            "This claim is numeric: a supporting quote must contain the half-life value.",
            "",
        ]
    current = None
    for number, passage in enumerate(passages, 1):
        if passage.doc.key != current:
            current = passage.doc.key
            lines.append(f"=== Document: {passage.doc.label} ===")
        lines.append(f"[P{number}] (section: {passage.section}) {passage.text}")
    return "\n".join(lines)


def prompt_key(prompt: str) -> str:
    return hashlib.sha1(f"{MODEL}\n{SYSTEM}\n{prompt}".encode()).hexdigest()


#: Headless Claude Code with no tools: no built-in tool, no MCP server, no
#: session written to disk. The model can read the prompt and answer; it can
#: fetch, run and edit nothing.
CLI = [
    "claude", "-p", "--model", MODEL, "--output-format", "json", "--tools", "",
    "--strict-mcp-config", "--no-session-persistence", "--system-prompt", SYSTEM,
    "--json-schema", json.dumps(SCHEMA),
]  # fmt: skip
WORKERS = 4
NO_ANSWER = {"verdict": "none", "quotes": [], "reason": "no parseable answer after one retry"}


class Judge:
    """Model answers through headless Claude Code, cached by prompt hash, one
    file per answer. Spend is the sum of each call's `total_cost_usd`."""

    def __init__(self, root: Path) -> None:
        self.root = root / "haiku"
        self.root.mkdir(parents=True, exist_ok=True)
        # An empty directory, so the session picks up no project CLAUDE.md.
        self.cwd = root / "cli-cwd"
        self.cwd.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()
        self._spend: float | None = None

    def cached(self, key: str) -> dict | None:
        path = self.root / f"{key}.json"
        return json.loads(path.read_text()) if path.exists() else None

    def spend(self) -> float:
        with self.lock:
            if self._spend is None:
                self._spend = sum(
                    float(json.loads(p.read_text()).get("cost") or 0)
                    for p in self.root.glob("*.json")
                )
            return self._spend

    def _store(self, key: str, answer: dict, cost: float) -> None:
        (self.root / f"{key}.json").write_text(json.dumps({"answer": answer, "cost": cost}))
        with self.lock:
            self._spend = (self._spend or 0.0) + cost

    def _call(self, prompt: str) -> tuple[dict | None, float]:
        try:
            done = subprocess.run(
                CLI, input=prompt, capture_output=True, text=True, timeout=300, cwd=self.cwd
            )
        except subprocess.TimeoutExpired:
            return None, 0.0
        try:
            payload = json.loads(done.stdout)
        except ValueError:
            return None, 0.0
        cost = float(payload.get("total_cost_usd") or 0)
        answer = payload.get("structured_output")
        if not isinstance(answer, dict):
            try:
                answer = json.loads(payload.get("result") or "")
            except ValueError:
                answer = None
        if payload.get("is_error") or not isinstance(answer, dict) or "verdict" not in answer:
            return None, cost
        return answer, cost

    def run(self, prompts: dict[str, str]) -> None:
        total = len(prompts)
        done = [0]

        def one(item: tuple[str, str]) -> None:
            key, prompt = item
            if self.spend() > SPEND_CAP:
                return
            answer, cost = self._call(prompt)
            if answer is None:
                answer, retry_cost = self._call(prompt)
                cost += retry_cost
            self._store(key, answer or NO_ANSWER, cost)
            with self.lock:
                done[0] += 1
                if done[0] % 50 == 0 or done[0] == total:
                    print(f"  {done[0]}/{total} answered; spend ${self._spend:.2f}", flush=True)

        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            list(pool.map(one, sorted(prompts.items())))


# ------------------------------------------------------------------ the gates


@dataclass
class Outcome:
    claim: Claim
    status: str  # accepted | rejected | not_found | contradicted | partial | no_candidate | error
    reason: str = ""
    doc: Doc | None = None
    quotes: list[tuple[Passage, str]] = field(default_factory=list)
    haiku_reason: str = ""
    number: str = ""  # the quantity in the quote that matched a numeric row


def verify(claim: Claim, passages: list[Passage], answer: dict) -> Outcome:
    verdict = answer.get("verdict")
    if verdict in ("not_found", "contradicted", "partial"):
        return Outcome(claim, verdict, haiku_reason=answer.get("reason", ""))
    if verdict not in ("supported",):
        return Outcome(claim, "error", "no answer", haiku_reason=answer.get("reason", ""))
    quotes = answer.get("quotes") or []
    if verdict != "supported" or not quotes:
        return Outcome(claim, "rejected", "gate 1 (quote): supported with no quote")
    checked: list[tuple[Passage, str]] = []
    for item in quotes[:3]:
        number, quote = item.get("passage"), (item.get("quote") or "").strip()
        if not isinstance(number, int) or not 1 <= number <= len(passages):
            return Outcome(claim, "rejected", "gate 1 (quote): cites no shown passage")
        passage = passages[number - 1]
        if len(quote) > MAX_QUOTE:
            return Outcome(claim, "rejected", "gate 1 (quote): longer than 300 characters")
        if len(fold(quote).split()) < MIN_QUOTE_WORDS:
            return Outcome(claim, "rejected", "gate 1 (quote): fewer than five words")
        if not quote_in(quote, passage.text):
            return Outcome(claim, "rejected", "gate 1 (quote): not verbatim in the passage")
        checked.append((passage, quote))
    docs = {p.doc.key for p, _ in checked}
    if len(docs) != 1:
        return Outcome(claim, "rejected", "gate 1 (quote): quotes from more than one document")
    doc = checked[0][0].doc
    joined = Text.of(" ".join(q for _, q in checked))
    if not doc.identity:
        return Outcome(claim, "rejected", "gate 2 (identity): document not about the substance")
    if doc.multi_ingredient and claim.sid:
        names = [Term(n, frozenset({compact(n)})) for n in all_names_static(claim.sid)]
        if not any(t.named_in(joined) for t in names):
            return Outcome(
                claim,
                "rejected",
                "gate 2 (identity): multi-ingredient label, quote omits the substance",
            )
    if claim.classes:
        named = classes_named(claim, doc, joined)
        if len(named) < 2:
            return Outcome(claim, "rejected", "gate 3 (key term): quote does not name both classes")
        if not doc.subject_classes & set(claim.classes):
            return Outcome(claim, "rejected", "gate 2 (identity): page is about neither class")
    else:
        if not claim.terms:
            return Outcome(claim, "rejected", "gate 3 (key term): row has no key term")
        hits = [t.label for t in claim.terms if t.named_in(joined)]
        if len(hits) < claim.need:
            return Outcome(
                claim,
                "rejected",
                f"gate 3 (key term): quote names {len(hits)} of the {claim.need} needed",
            )
    if claim.number_minutes is not None:
        found = None
        for _, quote in checked:
            found = found or number_in(claim.number_minutes, quote)
        if found is None:
            return Outcome(claim, "rejected", "gate 4 (number): quote lacks the row's value")
        return Outcome(claim, "accepted", doc=doc, quotes=checked, number=found)
    return Outcome(claim, "accepted", doc=doc, quotes=checked)


_STATIC_CONN: sqlite3.Connection | None = None


def all_names_static(sid: int) -> set[str]:
    assert _STATIC_CONN is not None
    return all_names(_STATIC_CONN, sid)


# -------------------------------------------------------------------- writers


def cite_parts(outcome: Outcome) -> tuple[str, str | None]:
    doc = outcome.doc
    assert doc is not None
    if doc.kind != "wikipedia":
        return doc.ref, doc.title
    section = outcome.quotes[0][0].section
    anchor = doc.anchors.get(section, "")
    ref = doc.ref + (f"#{anchor}" if anchor and section not in ("Lead", "Infobox") else "")
    title = doc.title or ""
    if section not in ("Lead", "Infobox"):
        title = title.replace(" (revision", f", §{section} (revision")
    return ref, title or None


def evidence(outcome: Outcome) -> str:
    quotes = " … ".join(f'"{q}"' for _, q in outcome.quotes)
    section = outcome.quotes[0][0].section
    claim = outcome.claim
    if claim.classes:
        terms = "both classes named"
    else:
        terms = "key terms: " + ", ".join(
            t.label for t in claim.terms if t.named_in(Text.of(quotes))
        )
    value = f"; value {outcome.number}" if outcome.number else ""
    return f"{quotes} ({section}; {outcome.doc.identity}; {terms}{value})"


#: Rows whose accepted source `citation_topicality.py --gate` refuses, so they
#: are never written: DOEF's article title spells "(2-fluoroethyl)amphetamine",
#: which the topicality matcher reads as 2-FEA.
TOPICALITY_DROPPED = {("downstream_signalling", "DOEF")}


def write_sidecar(outcomes: list[Outcome], conn: sqlite3.Connection) -> int:
    entries = row_citations.load()
    have = {row_citations.entry_key(e) for e in entries}
    added = 0
    for outcome in outcomes:
        claim = outcome.claim
        ref, title = cite_parts(outcome)
        for base in [claim.entry, *claim.copies]:
            entry = dict(base)
            if row_citations.entry_key(entry) in have:
                continue
            if (entry["table"], entry["substance"]) in TOPICALITY_DROPPED:
                continue
            if len(row_citations.find_rows(conn, entry)) != 1:
                continue
            entry.update(
                {
                    "ref": ref,
                    "accessed": outcome.doc.accessed or TODAY,
                    "via": VIA,
                    "evidence": evidence(outcome)
                    if base is claim.entry
                    else f"{base['match'].get('language')} copy of the class paragraph whose "
                    f"English row was checked: {evidence(outcome)}",
                }
            )
            if title:
                entry["title"] = title
            entries.append(entry)
            have.add(row_citations.entry_key(entry))
            added += 1
    row_citations.save(entries)
    return added


def citation_string(outcome: Outcome) -> str:
    ref, title = cite_parts(outcome)
    return f"{title}; {ref}" if title and ref.startswith("http") else ref


def write_rules(outcomes: list[Outcome]) -> int:
    payload = json.loads(RULES.read_text())
    by_pair = {tuple(o.claim.entry["rule"]): o for o in outcomes}
    added = 0
    rules = []
    for rule in payload["rules"]:
        outcome = by_pair.get((rule["classA"], rule["classB"]))
        if outcome and not rule.get("citation"):
            new = {}
            for key, value in rule.items():
                new[key] = value
                if key == "note":
                    new["citation"] = citation_string(outcome)
                    new["citationEvidence"] = {
                        "quote": " … ".join(q for _, q in outcome.quotes),
                        "section": outcome.quotes[0][0].section,
                        "identity": outcome.doc.identity,
                        "accessed": outcome.doc.accessed or TODAY,
                        "via": VIA,
                    }
            rule = new
            added += 1
        rules.append(rule)
    payload["rules"] = rules
    RULES.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    return added


def write_half_lives(outcomes: list[Outcome]) -> int:
    """`halfLifeSource` + `halfLifeEvidence` inserted after `halfLifeMinutes`, as
    text, so the rest of each hand-formatted file is untouched."""
    added = 0
    for outcome in outcomes:
        path = REPO / outcome.claim.entry["file"]
        text = path.read_text()
        if '"halfLifeSource"' in text:
            continue
        match = re.search(r'^(?P<indent>[ \t]*)"halfLifeMinutes":[^\n]*$', text, re.M)
        if not match:
            continue
        indent = match.group("indent")
        line = match.group(0)
        trailing = line.rstrip().endswith(",")
        evidence_obj = {
            "quote": " … ".join(q for _, q in outcome.quotes),
            "section": outcome.quotes[0][0].section,
            "identity": outcome.doc.identity,
            "value": outcome.number,
            "accessed": outcome.doc.accessed or TODAY,
            "via": VIA,
        }
        block = json.dumps(evidence_obj, indent=len(indent) or 2, ensure_ascii=False)
        block = block.replace("\n", "\n" + indent)
        insert = (
            f"{line.rstrip().rstrip(',')},\n"
            f'{indent}"halfLifeSource": {json.dumps(citation_string(outcome), ensure_ascii=False)},\n'
            f'{indent}"halfLifeEvidence": {block}' + ("," if trailing else "")
        )
        text = text[: match.start()] + insert + text[match.end() :]
        json.loads(text)  # the edit must leave valid JSON
        path.write_text(text)
        added += 1
    return added


# --------------------------------------------------------------------- report


def write_report(outcomes: list[Outcome], spend: float, unmapped: list[str], path: Path) -> None:
    lines = [
        f"# Haiku-assisted sourcing pass — {TODAY}",
        "",
        f"Model `{MODEL}`. Total model spend: **${spend:.2f}** (the sum of each headless Claude Code "
        "call's `total_cost_usd`).",
        "",
        "## Outcomes per target",
        "",
        "| target | rows | accepted | rejected by a gate | partial | not_found | contradicted | no candidate passage | no source document | data defect | no answer |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    by_target: dict[str, Counter] = defaultdict(Counter)
    for o in outcomes:
        by_target[o.claim.target][o.status] += 1
    for target in sorted(by_target):
        c = by_target[target]
        lines.append(
            f"| ({target}) {TARGET_NAMES[target]} | {sum(c.values())} | {c['accepted']} | "
            f"{c['rejected']} | {c['partial']} | {c['not_found']} | {c['contradicted']} | "
            f"{c['no_candidate']} | {c['no_source']} | {c['defect']} | {c['error']} |"
        )
    lines += ["", "## Rejections by gate", "", "| target | reason | rows |", "|---|---|---|"]
    reasons = Counter((o.claim.target, o.reason) for o in outcomes if o.status == "rejected")
    for (target, reason), n in sorted(reasons.items()):
        lines.append(f"| {target} | {reason} | {n} |")
    accepted = [o for o in outcomes if o.status == "accepted"]
    by_table = Counter(o.claim.table for o in accepted)
    lines += ["", "Accepted per table: " + ", ".join(f"{t} {n}" for t, n in by_table.most_common())]
    lines += ["", "## 20 random accepted samples (seed 30)", ""]
    for o in random.Random(30).sample(accepted, min(20, len(accepted))):
        ref, _ = cite_parts(o)
        lines += [
            f"- **{o.claim.substance}** · `{o.claim.table}`",
            f"  - claim: {o.claim.text[:400]}",
            f"  - quote: {' … '.join(q for _, q in o.quotes)}",
            f"  - source: {ref}",
        ]
    for status, heading in (
        ("contradicted", "Claims a passage contradicts (review first)"),
        ("not_found", "Claims Haiku found no support for in the candidate passages"),
    ):
        rows = [o for o in outcomes if o.status == status]
        lines += ["", f"## {heading} ({len(rows)})", ""]
        lines.append(
            "Candidates for review or removal. A `not_found` means none of the passages shown "
            "(Wikipedia, DailyMed, review abstracts that name a key term) states it — it is not "
            "proof the claim is wrong."
            if status == "not_found"
            else "Haiku said a passage states the opposite. Not gate-checked; read the source."
        )
        lines.append("")
        for o in sorted(rows, key=lambda o: (o.claim.target, o.claim.table, o.claim.substance)):
            lines.append(
                f"- ({o.claim.target}) `{o.claim.table}` **{o.claim.substance}**: "
                f"{' '.join(o.claim.text.split())[:300]} — _{o.haiku_reason}_"
            )
    defects = [o for o in outcomes if o.status == "defect"]
    lines += [
        "",
        f"## Likely data defects, not sourced: pgx rows whose text names another gene and not their own ({len(defects)})",
        "",
    ]
    for o in defects:
        lines.append(
            f"- `{o.claim.table}` **{o.claim.substance}**: {o.reason}. Text: {o.claim.text}"
        )
    if unmapped:
        lines += ["", f"## Half-life rows with no curated input found ({len(unmapped)})", ""]
        lines += [f"- {u}" for u in unmapped]
    path.write_text("\n".join(lines) + "\n")


# ----------------------------------------------------------------------- main


def main() -> int:
    global _STATIC_CONN, VIA
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--targets", default="a,b,c,d")
    parser.add_argument("--db", type=Path, default=DB)
    parser.add_argument("--dry-run", action="store_true", help="retrieve and select, no model")
    parser.add_argument("--write", action="store_true", help="write accepted citations")
    parser.add_argument(
        "--backend",
        choices=["claude-cli"],
        default="claude-cli",
        help="how the model is called: headless Claude Code (`claude -p`), tools off",
    )
    parser.add_argument("--limit", type=int, default=0, help="first N claims per target")
    parser.add_argument("--via-date", default=TODAY, help="date stamped into `via`")
    parser.add_argument("--max-calls", type=int, default=0, help="answer at most N new prompts")
    parser.add_argument("--no-epmc", action="store_true")
    parser.add_argument("--offline", action="store_true", help="cache only, no network")
    parser.add_argument("--report", type=Path, default=CACHE / "REPORT.md")
    args = parser.parse_args()
    VIA = f"haiku-assisted {args.via_date}"

    # Read-only and shared by the fetch threads; `all_names` serializes its queries.
    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True, check_same_thread=False)
    _STATIC_CONN = conn
    names = load_substances(conn)
    lexicon = Lexicon(conn)
    targets = set(args.targets.split(","))
    claims: list[Claim] = []
    unmapped: list[str] = []
    if "a" in targets:
        claims += collect_a(conn)[: args.limit or None]
    if "b" in targets:
        claims += collect_b(conn, lexicon, names)[: args.limit or None]
    if "c" in targets:
        claims += collect_c(conn, lexicon, names)[: args.limit or None]
    if "d" in targets:
        half, unmapped = collect_d(conn)
        claims += half[: args.limit or None]
    print(f"{len(claims)} claims: {dict(Counter(c.target for c in claims))}", flush=True)

    http = Http(CACHE, offline=args.offline)
    gather(claims, conn, names, http, use_epmc=not args.no_epmc)
    print(f"  {http.fetched} new HTTP fetches", flush=True)

    judge = Judge(CACHE)
    prepared: list[tuple[Claim, list[Passage], str | None]] = []
    for claim in claims:
        passages = [] if claim.defect else select_passages(claim)
        prompt = build_prompt(claim, passages) if passages else None
        prepared.append((claim, passages, prompt))
    prompts = {prompt_key(p): p for _, _, p in prepared if p}
    missing = {k: p for k, p in prompts.items() if judge.cached(k) is None}
    chars = sum(len(p) for p in missing.values())
    print(
        f"{len(prompts)} prompts, {len(missing)} unanswered (~{chars / 3.5 / 1e6:.2f} M input "
        f"tokens); spend so far ${judge.spend():.2f}",
        flush=True,
    )
    if args.max_calls:
        missing = dict(sorted(missing.items())[: args.max_calls])
    if missing and not args.dry_run:
        if judge.spend() > SPEND_CAP:
            print("spend cap reached; not calling the model", file=sys.stderr)
        else:
            judge.run(missing)

    outcomes: list[Outcome] = []
    for claim, passages, prompt in prepared:
        if prompt is None:
            if claim.defect:
                outcomes.append(Outcome(claim, "defect", claim.defect))
            elif not claim.docs:
                outcomes.append(Outcome(claim, "no_source", "no fetchable candidate document"))
            else:
                outcomes.append(Outcome(claim, "no_candidate", "no passage names a key term"))
            continue
        cached = judge.cached(prompt_key(prompt))
        if cached is None:
            continue
        outcomes.append(verify(claim, passages, cached["answer"]))
    summary: dict[str, Counter] = defaultdict(Counter)
    for claim, _, prompt in prepared:
        summary[claim.target]["rows"] += 1
        summary[claim.target]["with a candidate document"] += bool(claim.docs)
        summary[claim.target]["with candidate passages (model call)"] += prompt is not None
        summary[claim.target]["no key term"] += not claim.classes and not claim.terms
    for target in sorted(summary):
        print(f"  ({target}) {TARGET_NAMES[target]}: {dict(summary[target])}")
    status = Counter((o.claim.target, o.status) for o in outcomes)
    print(dict(sorted(status.items())))
    if args.dry_run:
        return 0
    spend = judge.spend()
    write_report(outcomes, spend, unmapped, args.report)
    print(f"report: {args.report}; spend ${spend:.2f}")
    if args.write:
        accepted = [o for o in outcomes if o.status == "accepted"]
        sidecar = [o for o in accepted if o.claim.target in ("b", "c")]
        print(f"sidecar entries added: {write_sidecar(sidecar, conn)}")
        print(
            f"rule citations added: {write_rules([o for o in accepted if o.claim.target == 'a'])}"
        )
        print(
            f"half-life sources added: {write_half_lives([o for o in accepted if o.claim.target == 'd'])}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
