#!/usr/bin/env python3
"""Verify every per-substance SOURCE LINK lands on a page about that substance.

`validate_links.py` answers "does this URL resolve?". That is not the question a
user asks — they tap "FreeOD Wiki" under 2-FDCK and expect the 2-FDCK page. Two
ways that silently fails, both returning HTTP 200:

  1. **Homepage fallback.** The app's URL builder has no per-substance case, so
     it hands back the source's site root. The row still looks like a working
     link. (`f11eb78` made both such builders return nil instead — this checker
     reads which behavior the Swift currently has rather than assuming, so it
     catches the fallback if it is ever reintroduced.)
  2. **Soft-404.** The host serves a 200 error page for a slug that doesn't
     exist. Status code alone proves nothing.

A third failure needs no fetch at all: a source contributes data for a compound
but the build captured no page slug, so the attribution row is dead text
(MISSING_SLUG).

So this checker builds the SAME URL the app builds (mirroring
`Piru/Data/SubstanceDB/AppSources.swift` +
`Piru/Views/Library/SubstanceDetail/SubstanceSourceLinks.swift`), fetches it, and
asserts it is neither the site root nor the host's error page, and that it names
the substance.

**The soft-404 baseline.** Rather than hardcoding each site's error text, we
probe every host once with a deliberately nonexistent slug and once with a
known-good control. The sentinel response becomes the host's error fingerprint;
anything closely matching it is a soft-404. The control is what makes the trick
honest: if sentinel and control are indistinguishable, the host is a
client-rendered shell and its HTML *cannot* prove anything — we say so
(UNVERIFIABLE) instead of inventing a verdict. TripSit and drug.community are
both such shells, so each gets an explicit existence oracle (their own data API)
rather than a guess from HTML.

Two rules keep that baseline from libelling real pages:

  * **Compare article bodies, never documents.** A site's chrome is identical on
    every page including its 404, so a whole-document measure describes the
    template. PsychonautWiki's error page is 189 KB of document and *314
    characters* of body; a real article is 76,205. Comparing documents scored
    0.99 against every real article on the host and called them all soft-404s.
  * **Positive evidence outranks suspicion.** If the body names the compound,
    the page is real, full stop — the size heuristic never gets to argue. Only
    a page that never says what it is about is measured against the baseline.

Verdicts, per (substance, source) pair:
  OK           — page resolves, is not the site root, is not the error page, and
                 names the substance (or an alias).
  HOMEPAGE     — the built URL is the source's site root, or redirects to it.
                 Provable offline; this is failure mode 1.
  BROKEN       — hard 404/410, or a soft-404 matching the host's error baseline.
  NO_MENTION   — loads, is a distinct page, but never names the substance.
  MISSING_SLUG — the source contributed data but no per-substance slug was
                 captured, so no link can be built. A pipeline gap, not a lying
                 link: reported, never gating.
  UNVERIFIABLE — 403/429/5xx/timeout, or a host whose HTML can't distinguish a
                 real page from a missing one and has no oracle. Never a
                 failure: an unknown is not a defect.
  NO_LINK      — the source contributes data but the app deliberately offers no
                 deep link (PiHKAL/TiHKAL chapters, the curated overlay).
                 Informational.

Search-URL sources (DailyMed, PubMed, EMCDDA, Erowid) are a separate category:
the app builds a query, not a page, so we assert only that the search resolves.
They are sampled by default — the URL shape doesn't vary per substance, so
checking all 387 PubMed links would buy nothing.

Usage:
    python3 pipeline/audit/source_link_check.py                    # full run
    python3 pipeline/audit/source_link_check.py --limit 20         # per source
    python3 pipeline/audit/source_link_check.py --source freeodwiki
    python3 pipeline/audit/source_link_check.py --json report.json
    python3 pipeline/audit/source_link_check.py --gate             # offline
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zlib
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from pathlib import Path

#: Repo root when installed at `pipeline/audit/`. `--repo` overrides it so the
#: script can be run from anywhere (a scratchpad copy, CI checkout).
REPO = Path(__file__).resolve().parents[2]
DB_RELPATH = Path("Piru/Data/piru-substances.sqlite")
# Deliberately NOT data/sources/link-cache.json — the build reads that file and
# it answers a different question (does this citation URL resolve?).
CACHE_RELPATH = Path("data/sources/source-page-cache.json")

UA = (
    "Piru-SourceLinkCheck/1.0 (+https://github.com/kageroumado/piru; "
    "per-substance source link verification)"
)
TIMEOUT = 30
STALE_DAYS = 30
#: Minimum seconds between requests to one host. Hosts are checked in parallel
#: with each other but strictly serialized within a host.
HOST_DELAY = 1.0

#: A slug no site can plausibly have. Used to fingerprint each host's 404.
SENTINEL = "ThisPageDoesNotExist7f3a91"

#: How similar to the host's error page a response may be before we call it a
#: soft-404. Tuned against freeodwiki (1.4 KB error vs 660 KB article — nowhere
#: near) and the SPA shells (identical — caught by the control probe instead).
SOFT_404_SIMILARITY = 0.90
#: Length window for the same test; a soft-404 is usually byte-comparable to the
#: baseline. Both conditions must hold, so an article that happens to be short
#: isn't condemned on size alone.
SOFT_404_LENGTH_TOLERANCE = 0.25

#: Chars of extracted text compared against the baseline. Enough to characterize
#: a page without shingling megabytes of article prose.
COMPARE_CHARS = 120_000
#: Words per shingle in the similarity metric. 5 is long enough that shared
#: boilerplate phrases don't dominate, short enough to survive small edits.
SHINGLE_WORDS = 5
#: Below this many words of server-rendered prose there is nothing to read a
#: substance name out of, so the page is unverifiable rather than wrong.
MIN_MEANINGFUL_WORDS = 40


# --------------------------------------------------------------------------- #
# URL construction — mirrors AppSources.swift. Any divergence here is a bug.
# --------------------------------------------------------------------------- #

#: Foundation's `CharacterSet.urlPathAllowed` / `.urlQueryAllowed`, spelled out
#: so the Python-built URL is byte-identical to the Swift one. Note both sets
#: leave `&`, `+`, `=` and `;` unescaped — see `encoding_hazards`.
PATH_ALLOWED = "-._~!$&'()*+,;=:@/"
QUERY_ALLOWED = "-._~!$&'()*+,;=:@/?"

#: Characters Foundation's `.urlQueryAllowed` passes through verbatim but that a
#: server reads as query syntax. A substance name containing one produces a
#: mangled search: "BPC-157 + TB-500" reaches PubMed as "BPC-157   TB-500",
#: because `+` means space in a query string.
QUERY_HAZARD_CHARS = "&+=;"


def swift_path_encode(value: str) -> str:
    """`value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`."""
    return urllib.parse.quote(value, safe=PATH_ALLOWED, encoding="utf-8")


def swift_query_encode(value: str) -> str:
    """`value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)`."""
    return urllib.parse.quote(value, safe=QUERY_ALLOWED, encoding="utf-8")


def iri_to_uri(url: str) -> str:
    """Percent-encode the non-ASCII the app's URL literals leave in place.

    `AppSources.freeodwikiURL` builds `https://freeodwiki.org/药物/<slug>.html`
    with the Chinese segment literal, relying on `URL(string:)`'s RFC 3986
    lenient parsing to encode it on the way out. urllib does no such thing, so
    do it here — and keep `%` safe so an already-encoded slug isn't doubled."""
    parts = urllib.parse.urlsplit(url)
    return urllib.parse.urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            urllib.parse.quote(parts.path, safe=PATH_ALLOWED + "%"),
            urllib.parse.quote(parts.query, safe=QUERY_ALLOWED + "%"),
            parts.fragment,
        )
    )


def psychonautwiki_url(sub: Substance) -> str:
    # Swift: substance.replacingOccurrences(of: " ", with: "_"), then URL(string:)
    # — no explicit percent-encoding, so URL()'s lenient parsing does it.
    return "https://psychonautwiki.org/wiki/" + swift_path_encode(sub.name.replace(" ", "_"))


def tripsit_url(sub: Substance) -> str:
    return "https://drugs.tripsit.me/" + swift_path_encode(sub.name.lower())


def freeodwiki_url(sub: Substance) -> str | None:
    # Chinese page titles, so the build captures `freeodwiki_slug`. Since
    # f11eb78 a missing slug yields nil, not the site root, so this is NO_LINK
    # rather than HOMEPAGE — the row shows as plain text with no affordance.
    # Still worth reporting: the source contributed data the user can't trace.
    if not sub.freeodwiki_slug:
        return None
    # MkDocs renders each page as `药物/<title>.html`, not a directory URL.
    return "https://freeodwiki.org/药物/" + swift_path_encode(sub.freeodwiki_slug) + ".html"


def drug_community_url(sub: Substance) -> str | None:
    # SubstanceSourceLinks returns nil without the captured slug (the site has no
    # alias fallback), so a missing slug is NO_LINK, not a homepage.
    if not sub.drug_community_slug:
        return None
    return "https://drug.community/drug/" + sub.drug_community_slug


def dailymed_url(sub: Substance) -> str:
    return (
        "https://dailymed.nlm.nih.gov/dailymed/search.cfm?labeltype=all&query="
        + swift_query_encode(sub.name)
    )


def pubmed_url(sub: Substance) -> str:
    return "https://pubmed.ncbi.nlm.nih.gov/?term=" + swift_query_encode(sub.name) + "+pharmacology"


def emcdda_url(sub: Substance) -> str:
    return (
        "https://www.emcdda.europa.eu/publications/drug-profiles_en?search="
        + swift_query_encode(sub.name)
    )


def erowid_url(sub: Substance) -> str:
    return "https://www.erowid.org/search.php?q=" + swift_query_encode(sub.name)


@dataclass(frozen=True)
class SourceSpec:
    """One source the app can deep-link, and how it builds that link."""

    slug: str  #: the DB `sources.slug`, or a pseudo-slug for non-DB links
    name: str  #: AppSources display name
    base: str  #: site root — a final URL equal to this means HOMEPAGE
    kind: str  #: "page" | "search"
    build: object  #: (Substance) -> str | None
    #: Sentinel/control slugs for the host probe. The control must be a page we
    #: are confident exists; if it can't be distinguished from the sentinel, the
    #: host is a client-rendered shell.
    control: str = "MDMA"
    #: Optional existence oracle for shell hosts (see `ORACLES`).
    oracle: str | None = None
    #: From the DB, or synthesized for every substance (Erowid's link is offered
    #: on the effects card regardless of whether Erowid contributed data).
    from_db: bool = True
    #: False for a builder no shipping code path can reach — checked only when
    #: named explicitly with `--source`, so a full run isn't padded with
    #: verdicts about dead code.
    enumerate_default: bool = True


#: Sources the app links per substance. Keyed by DB slug where one exists.
SOURCES: dict[str, SourceSpec] = {
    spec.slug: spec
    for spec in [
        SourceSpec(
            "psychonautwiki",
            "PsychonautWiki",
            "https://psychonautwiki.org",
            "page",
            psychonautwiki_url,
        ),
        SourceSpec(
            "tripsit", "TripSit", "https://tripsit.me", "page", tripsit_url, oracle="tripsit"
        ),
        SourceSpec(
            "freeodwiki",
            "FreeOD Wiki",
            "https://freeodwiki.org",
            "page",
            freeodwiki_url,
            control="MDMA",
        ),
        SourceSpec(
            "drug.community",
            "drug.community",
            "https://drug.community",
            "page",
            drug_community_url,
            control="mdma",
            oracle="drug.community",
        ),
        SourceSpec("dailymed", "DailyMed", "https://dailymed.nlm.nih.gov", "search", dailymed_url),
        SourceSpec(
            "peer-review-primary", "PubMed", "https://pubmed.ncbi.nlm.nih.gov", "search", pubmed_url
        ),
        # EMCDDA has a case in substanceURL(for:) but no slugToName entry, so no
        # shipping call site reaches it. Kept so `--source emcdda` can check the
        # builder if it is ever wired up.
        SourceSpec(
            "emcdda",
            "EMCDDA",
            "https://www.emcdda.europa.eu",
            "search",
            emcdda_url,
            from_db=False,
            enumerate_default=False,
        ),
        SourceSpec(
            "erowid", "Erowid", "https://www.erowid.org", "search", erowid_url, from_db=False
        ),
    ]
}

#: DB sources that contribute data but that the app deliberately does NOT
#: deep-link, with the reason. Reported as NO_LINK so the tally accounts for
#: every attribution row a user can see.
NO_LINK_SOURCES = {
    "erowid-pihkal": "BY DESIGN — book has no per-substance page; the citation carries the chapter",
    "erowid-tihkal": "BY DESIGN — book has no per-substance page; the citation carries the chapter",
    "piru-curated": "BY DESIGN — hand-curated overlay; links to the curated reference instead",
    "wikidata": "LINKABLE, NOT LINKED — every item is a Q-page, but the QID is dropped at build "
    "(pipeline/build/sqlite.py:3673, wikidata.org is in _NON_LITERATURE_HOSTS). Needs a "
    "`wikidata_qid` column, mirroring drug_community_slug",
    "pyrls": "NO PUBLIC PAGE — private MongoDB dump, not a crawl; the only id is a Mongo $oid "
    "(pipeline/fetch/brushers/extract.py:334) and no record carries a URL",
    "medtap": "NO PUBLIC PAGE — private FDA-label dump; only a Mongo $oid "
    "(pipeline/fetch/brushers/extract.py:441). Its unused x_unii WOULD sharpen the "
    "DailyMed search from a name to an identifier",
    "pubchem": "not in AppSources.slugToName — no deep link offered",
    "pdsp": "not in AppSources.slugToName — no deep link offered",
    "dea-orange-book": "not in AppSources.slugToName — no deep link offered",
    "benzos-cited": "not in AppSources.slugToName — no deep link offered",
    "nps-datahub": "not in AppSources.slugToName — no deep link offered",
}


# --------------------------------------------------------------------------- #
# Static audit of the Swift itself — catches the trap before it ships.
# --------------------------------------------------------------------------- #

#: Display names `AppSources.substanceURL(for:substance:)` handles with a real
#: per-substance case. Everything else falls through to `default:` and returns
#: the site root — the homepage-fallback trap. Kept here so a new
#: `slugToName` entry without a matching case is a reported finding, not a
#: silently-200 link a user has to notice.
SWITCH_CASES = {"PsychonautWiki", "TripSit", "DailyMed", "PubMed", "EMCDDA"}

#: Sources whose deep link is built by a dedicated function elsewhere, so
#: falling through `substanceURL`'s switch is harmless *as long as* every caller
#: routes around it (SubstanceSourceLinks.deepLink does).
DEDICATED_BUILDERS = {"FreeOD Wiki", "drug.community"}


def audit_swift_sources(repo: Path) -> list[str]:
    """Read AppSources.swift and report display names reachable through
    `substanceURL(forSlug:)` that have no per-substance case. Offline."""
    swift = repo / "Piru/Data/SubstanceDB/AppSources.swift"
    if not swift.exists():
        return [f"AppSources.swift not found at {swift} — static audit skipped"]
    text = swift.read_text(encoding="utf-8")
    block = re.search(r"slugToName: \[String: String\] = \[(.*?)\]", text, re.S)
    if not block:
        return ["could not parse AppSources.slugToName — static audit skipped"]
    mapped = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', block.group(1)))
    cases = set(re.findall(r'case "([^"]+)":', text))

    # Does the `default:` branch hand back a homepage, or nil? This is the whole
    # difference between "the link is silently wrong" and "there is no link", so
    # read it from the source rather than assuming either.
    default_branch = text.split("default:", 1)[-1]
    falls_back_to_homepage = "sourceInfo.url" in default_branch.split("}", 1)[0]

    findings = []
    for slug, name in sorted(mapped.items()):
        if name in cases:
            continue
        if not falls_back_to_homepage:
            findings.append(
                f"slugToName maps {slug!r} → {name!r} with NO case in "
                f"substanceURL(for:) — that call yields nil, so the row shows "
                f"without a link"
                + (
                    " (fine: a dedicated builder handles it earlier)."
                    if name in DEDICATED_BUILDERS
                    else ". Deliberate for a source with no per-compound page."
                )
            )
        elif name in DEDICATED_BUILDERS:
            findings.append(
                f"slugToName maps {slug!r} → {name!r}, which has NO case in "
                f"substanceURL(for:) and falls back to the site root. Safe only "
                f"while every caller special-cases it before that call."
            )
        else:
            findings.append(
                f"slugToName maps {slug!r} → {name!r} with NO case in "
                f"substanceURL(for:) and no dedicated builder — any caller gets "
                f"the site ROOT."
            )
    for name in sorted(cases - set(mapped.values())):
        if name in SOURCES or name in SWITCH_CASES:
            findings.append(
                f"substanceURL(for:) has a case for {name!r} but no slug maps to "
                f"it — unreachable from the DB path (dead code)."
            )
    return findings


def encoding_hazards(substances: dict[int, Substance]) -> list[str]:
    """Names whose characters survive `.urlQueryAllowed` but mean something to a
    server. The link still resolves, so no fetch can catch this — only reading
    the name can."""
    findings = []
    for sub in sorted(substances.values(), key=lambda s: s.name):
        hit = [char for char in QUERY_HAZARD_CHARS if char in sub.name]
        if hit:
            findings.append(
                f"{sub.name!r} contains {''.join(hit)!r}, which Foundation's "
                f".urlQueryAllowed leaves unescaped — the search URL reaches the "
                f"server mangled (e.g. '+' arrives as a space)."
            )
    return findings


# --------------------------------------------------------------------------- #
# Database
# --------------------------------------------------------------------------- #


@dataclass
class Substance:
    id: int
    name: str
    display_name: str | None
    aliases: list[str]
    freeodwiki_slug: str | None
    drug_community_slug: str | None

    def mention_terms(self) -> list[str]:
        """Names a real page for this substance should contain. Short Latin
        terms are dropped — a two-letter alias matches anything. Two *CJK*
        characters are already a whole word, so the floor is lower there."""
        terms = [self.name, *(([self.display_name]) if self.display_name else []), *self.aliases]
        seen, out = set(), []
        for term in terms:
            norm = normalize_for_match(term)
            floor = 2 if any(ord(char) > 0x7F for char in norm) else 3
            if len(norm) < floor or norm in seen:
                continue
            seen.add(norm)
            out.append(term)
        return out


#: Mirrors SubstanceStore.citedSources — the exact set of source rows the detail
#: screen attributes, so we check what a user can actually tap and nothing else.
CITED_SOURCES_SQL = """
    SELECT src.slug, uses.substance_id FROM (
        SELECT substance_id, source_id FROM categories
        UNION SELECT substance_id, source_id FROM dose_ranges
        UNION SELECT substance_id, source_id FROM durations
        UNION SELECT substance_id, source_id FROM half_lives
        UNION SELECT substance_id, source_id FROM mechanisms_summary
        UNION SELECT substance_id, source_id FROM bindings
    ) AS uses
    JOIN sources src ON src.id = uses.source_id
"""


def load_pairs(db_path: Path) -> tuple[dict[int, Substance], list[tuple[str, int]]]:
    conn = sqlite3.connect(db_path)
    try:
        substances: dict[int, Substance] = {}
        for row in conn.execute(
            "SELECT id, canonical_name, display_name, freeodwiki_slug, drug_community_slug "
            "FROM substances"
        ):
            substances[row[0]] = Substance(row[0], row[1], row[2], [], row[3], row[4])
        for sid, alias in conn.execute("SELECT substance_id, alias FROM aliases"):
            if sid in substances:
                substances[sid].aliases.append(alias)
        pairs = sorted({(slug, sid) for slug, sid in conn.execute(CITED_SOURCES_SQL)})
    finally:
        conn.close()
    return substances, pairs


# --------------------------------------------------------------------------- #
# Polite fetching
# --------------------------------------------------------------------------- #


class HostThrottle:
    """One request per `delay` seconds per host. Hosts run in parallel with each
    other; requests to a single host never overlap."""

    def __init__(self, delay: float) -> None:
        self.delay = delay
        self._last: dict[str, float] = {}
        self._extra: dict[str, float] = {}
        self._locks: dict[str, threading.Lock] = defaultdict(threading.Lock)
        self._guard = threading.Lock()

    def wait(self, host: str) -> None:
        with self._guard:
            lock = self._locks[host]
        with lock:
            last = self._last.get(host, 0.0)
            gap = self._delay_for(host) - (time.monotonic() - last)
            if gap > 0:
                time.sleep(gap)
            self._last[host] = time.monotonic()

    def back_off(self, host: str, seconds: float) -> None:
        """Sleep, then permanently slow this host down. A 429 means our pace was
        wrong, so raising the floor is the fix — retrying at the same rate just
        earns another 429."""
        time.sleep(seconds)
        with self._guard:
            self._extra[host] = min(self._extra.get(host, 0.0) + self.delay, 10.0)

    def _delay_for(self, host: str) -> float:
        with self._guard:
            return self.delay + self._extra.get(host, 0.0)


@dataclass
class Response:
    status: int | None
    final_url: str
    body: bytes
    error: str | None = None

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="ignore")


def fetch(
    url: str, throttle: HostThrottle, *, max_bytes: int = 2_000_000, retries: int = 2
) -> Response:
    """GET with redirects followed. Bodies are capped — we only need enough text
    to fingerprint the page, and some articles are megabytes.

    A 429 is the host asking us to slow down, so we honor `Retry-After` and back
    off rather than recording an UNVERIFIABLE we caused ourselves."""
    host = urllib.parse.urlsplit(url).netloc
    for attempt in range(retries + 1):
        throttle.wait(host)
        req = urllib.request.Request(
            iri_to_uri(url),
            headers={
                "User-Agent": UA,
                "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
                "Accept-Encoding": "gzip, deflate",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                raw = resp.read(max_bytes)
                return Response(resp.status, resp.geturl(), decompress(raw, resp.headers))
        except urllib.error.HTTPError as exc:
            if exc.code in (429, 503) and attempt < retries:
                throttle.back_off(host, retry_after(exc.headers, attempt))
                continue
            try:
                body = decompress(exc.read(max_bytes), exc.headers)
            except Exception:  # noqa: BLE001 — error bodies are best-effort
                body = b""
            return Response(exc.code, exc.url or url, body)
        except Exception as exc:  # noqa: BLE001 — transport/timeout → unverifiable
            if attempt < retries:
                throttle.back_off(host, 2.0 * (attempt + 1))
                continue
            return Response(None, url, b"", error=type(exc).__name__)
    return Response(None, url, b"", error="RetriesExhausted")


def retry_after(headers, attempt: int) -> float:
    """Seconds to wait, from `Retry-After` when the host states one. Capped so a
    hostile header can't stall the run for an hour."""
    raw = (headers.get("Retry-After") or "").strip()
    if raw.isdigit():
        return min(float(raw), 60.0)
    return min(5.0 * (attempt + 1), 60.0)


def decompress(raw: bytes, headers) -> bytes:
    """Undo Content-Encoding. We ask for gzip because the wiki pages are large
    and it is the polite thing to do; a truncated stream still decodes enough."""
    encoding = (headers.get("Content-Encoding") or "").lower()
    try:
        if "gzip" in encoding:
            return gzip.decompress(raw)
        if "deflate" in encoding:
            return zlib.decompress(raw, -zlib.MAX_WBITS)
    except Exception:  # noqa: BLE001 — truncated body; salvage what we can
        try:
            return zlib.decompressobj(zlib.MAX_WBITS | 32).decompress(raw)
        except Exception:  # noqa: BLE001
            return raw
    return raw


# --------------------------------------------------------------------------- #
# Content comparison
# --------------------------------------------------------------------------- #

_TAG_RE = re.compile(r"<(script|style)\b.*?</\1>|<[^>]+>", re.S | re.I)
_WS_RE = re.compile(r"\s+")
#: Chrome that repeats identically on every page of a site. Removing it is the
#: whole point: MediaWiki ships ~190 KB of nav/sidebar/footer, which dwarfs the
#: article and made a whole-document comparison score ~0.99 against the error
#: page for EVERY article, real or not.
_CHROME_RE = re.compile(
    r"<(script|style|nav|header|footer|aside|noscript|form)\b.*?</\1>", re.S | re.I
)

#: Content-region openers, most specific first. `#mw-content-text` is
#: MediaWiki's article container; `.mw-parser-output` is the wikitext body
#: inside it; `<main>` / `<article>` / `role="main"` cover everyone else.
_CONTENT_OPENERS = [
    re.compile(r'<div[^>]*\bid\s*=\s*["\']mw-content-text["\'][^>]*>', re.I),
    re.compile(r'<div[^>]*\bclass\s*=\s*["\'][^"\']*\bmw-parser-output\b[^"\']*["\'][^>]*>', re.I),
    re.compile(r"<main\b[^>]*>", re.I),
    re.compile(r"<article\b[^>]*>", re.I),
    re.compile(r'<[a-z]+[^>]*\brole\s*=\s*["\']main["\'][^>]*>', re.I),
]

#: MediaWiki's explicit "this page does not exist" class. The baseline
#: comparison catches it anyway, but naming it makes the verdict legible and
#: costs one substring search.
_NOARTICLE_RE = re.compile(r'class\s*=\s*["\'][^"\']*\bnoarticletext\b', re.I)


def content_region(html: str) -> str:
    """The article body, chrome removed — what the page is actually *about*.

    Everything downstream (the soft-404 baseline and the substance-name search)
    runs on this rather than the whole document, so a host with heavy chrome
    can't flatten the signal."""
    for opener in _CONTENT_OPENERS:
        match = opener.search(html)
        if match:
            # No HTML parser in the stdlib worth using here, and the closing tag
            # can't be found by counting without one — take everything from the
            # container to the end and let chrome removal handle the tail. The
            # footer is a fraction of what the header was.
            return html[match.end() :]
    return html


def visible_text(html: str, *, body_only: bool = False) -> str:
    """Readable text. `body_only` narrows to the content region first."""
    source = content_region(html) if body_only else html
    return _WS_RE.sub(" ", _TAG_RE.sub(" ", _CHROME_RE.sub(" ", source))).strip().lower()


def normalize_for_match(value: str) -> str:
    """Collapse to bare alphanumerics so hyphen/space/case variation stops
    mattering: "2-FDCK", "2 FDCK" and "2fdck" all become "2fdck".

    `str.isalnum()`, not `[^a-z0-9]` — Unicode alphanumerics keep CJK. Some
    canonical names in the DB *are* Chinese (麦斯卡林, 环唑酮), and an
    ASCII-only rule normalized those to the empty string, so a FreeOD Wiki page
    that names the substance perfectly well could never be seen to."""
    return "".join(char for char in value.lower() if char.isalnum())


def shingles(text: str) -> frozenset[tuple[str, ...]]:
    words = text[:COMPARE_CHARS].split()
    return frozenset(
        tuple(words[i : i + SHINGLE_WORDS]) for i in range(max(0, len(words) - SHINGLE_WORDS + 1))
    )


def similarity(left: str, right: str) -> float:
    """Jaccard overlap of word shingles across each page's whole visible text.

    Not `difflib`: `quick_ratio()` compares character multisets, so any two large
    HTML documents score ~1.0 (a 190 KB MediaWiki error page scored 0.99 against
    a 460 KB article), and `ratio()` over a truncated prefix just compares the
    two pages' identical head boilerplate. Shingling the *whole* text is the only
    version of this that measures shared content rather than shared chrome."""
    left_set, right_set = shingles(left), shingles(right)
    if not left_set or not right_set:
        return 0.0
    return len(left_set & right_set) / len(left_set | right_set)


# --------------------------------------------------------------------------- #
# Host probes — the soft-404 baseline, plus an honesty check on it
# --------------------------------------------------------------------------- #


@dataclass
class HostProbe:
    """What one probe of a source taught us about how its host answers."""

    mode: str  #: "content" (HTML is diagnostic) | "opaque" (shell) | "unreachable"
    sentinel_status: int | None = None
    #: The error page's ARTICLE BODY, chrome stripped — the fingerprint every
    #: candidate is compared against. Deliberately not the whole document: a
    #: site's chrome is identical on every page including its 404, so comparing
    #: documents measures the template and nothing else.
    sentinel_body: str = ""
    sentinel_len: int = 0
    control_status: int | None = None
    control_len: int = 0
    control_body_len: int = 0
    control_similarity: float = 0.0
    base_final: str = ""
    note: str = ""
    #: True when the host answers a missing page with a hard 4xx — recorded for
    #: the report. It is no longer used to skip the soft-404 test: now that the
    #: comparison is body-relative it does not need the escape hatch, and a host
    #: that 404s for some misses may still soft-404 for others.
    honest_status: bool = False


def probe_source(spec: SourceSpec, throttle: HostThrottle) -> HostProbe:
    """Fetch the site root, a guaranteed-missing page, and a known-good page.

    The sentinel is the error fingerprint. The control is the control: if the
    two look the same, the host renders client-side and its HTML cannot tell us
    whether a page exists — say so rather than condemning every link."""
    fake = Substance(-1, SENTINEL, None, [], SENTINEL, SENTINEL)
    real = Substance(-2, spec.control, None, [], spec.control, spec.control)
    sentinel_url = spec.build(fake)
    control_url = spec.build(real)
    if not sentinel_url or not control_url:
        return HostProbe("unreachable", note="source builds no URL for the probe")

    root = fetch(spec.base, throttle)
    sentinel = fetch(sentinel_url, throttle)
    control = fetch(control_url, throttle)

    if control.error or (control.status is not None and control.status >= 400):
        return HostProbe(
            "unreachable",
            base_final=root.final_url,
            note=f"control page {control_url} did not load "
            f"(status={control.status} error={control.error}) — cannot calibrate",
        )

    # Calibrate on article bodies, so "how different is a real page from a
    # missing one?" is answered by content rather than by shared template.
    sentinel_body = visible_text(sentinel.text, body_only=True)
    control_body = visible_text(control.text, body_only=True)
    ratio = similarity(sentinel_body, control_body)
    size_close = close_in_size(len(sentinel_body), len(control_body))

    def opaque(reason: str) -> HostProbe:
        return HostProbe(
            "opaque",
            sentinel.status,
            sentinel_body,
            len(sentinel.body),
            control.status,
            len(control.body),
            len(control_body),
            ratio,
            root.final_url,
            note=f"{reason} — client-rendered; HTML proves nothing",
        )

    # A page that server-renders no prose can't be read for a substance name no
    # matter what it returns. Check this BEFORE the similarity test: two empty
    # bodies have an empty shingle set, which scores 0.0 and would otherwise look
    # like two *different* pages.
    if len(control_body.split()) < MIN_MEANINGFUL_WORDS:
        return opaque(f"the known-good control renders only {len(control_body.split())} body words")

    if (
        sentinel.status is not None
        and 200 <= sentinel.status < 400
        and ratio >= SOFT_404_SIMILARITY
        and size_close
    ):
        # Real and missing pages are indistinguishable → client-rendered shell.
        return opaque(f"missing and existing pages return identical HTML (similarity {ratio:.2f})")

    honest = sentinel.status is not None and 400 <= sentinel.status < 500
    return HostProbe(
        "content",
        sentinel.status,
        sentinel_body,
        len(sentinel.body),
        control.status,
        len(control.body),
        len(control_body),
        ratio,
        root.final_url,
        note=f"sentinel status={sentinel.status} {len(sentinel.body)}B doc / "
        f"{len(sentinel_body)} body chars vs control status={control.status} "
        f"{len(control.body)}B doc / {len(control_body)} body chars "
        f"(body similarity {ratio:.2f})" + ("; honest 4xx" if honest else ""),
        honest_status=honest,
    )


def close_in_size(left: int, right: int) -> bool:
    ceiling = max(left, right, 1)
    return abs(left - right) / ceiling <= SOFT_404_LENGTH_TOLERANCE


# --------------------------------------------------------------------------- #
# Existence oracles — for hosts whose HTML can't answer
# --------------------------------------------------------------------------- #


class Oracles:
    """Per-source "does this page exist?" answers that don't rely on HTML.

    Used only for `opaque` hosts. Each oracle is the site's own data API, so it
    is the same fact the page itself would render — not a guess."""

    def __init__(self, throttle: HostThrottle) -> None:
        self.throttle = throttle
        self._dc_slugs: set[str] | None = None
        self._tripsit_names: set[str] | None = None
        self._lock = threading.Lock()

    def check(self, oracle: str, sub: Substance) -> tuple[bool | None, str]:
        if oracle == "tripsit":
            return self._tripsit(sub)
        if oracle == "drug.community":
            return self._drug_community(sub)
        return None, f"no oracle named {oracle!r}"

    def _tripsit(self, sub: Substance) -> tuple[bool | None, str]:
        """Bulk list first, per-drug API only for what the list misses.

        Asking 530 times what one request answers earns a 429 within a minute
        (measured: the host's limiter pushed us to ~10s/request). The bulk list
        is a POSITIVE oracle only — it holds canonical names, so a URL built
        from an alias is absent from it without being wrong, and only those fall
        through to the per-drug endpoint, which does resolve aliases."""
        if self._tripsit_names is None:
            with self._lock:
                if self._tripsit_names is None:
                    self._tripsit_names = self._tripsit_bulk()
        if normalize_for_match(sub.name) in self._tripsit_names:
            return True, f"tripsit lists {sub.name} among {len(self._tripsit_names)} drugs"
        # The canonical name misses. Before spending a request, see whether one
        # of OUR aliases is what TripSit files the drug under — that turns
        # "broken link" into "link it by this name instead".
        working = [
            alias for alias in sub.aliases if normalize_for_match(alias) in self._tripsit_names
        ]

        # The factsheet page is a shell over this API; `data[0].err` is the
        # site's own not-found signal.
        url = "https://tripbot.tripsit.me/api/tripsit/getDrug/" + urllib.parse.quote(
            sub.name.lower()
        )
        resp = fetch(url, self.throttle, max_bytes=400_000)
        if resp.error or resp.status is None or resp.status >= 400:
            return None, f"tripsit API status={resp.status} error={resp.error}"
        try:
            payload = json.loads(resp.text)
        except ValueError:
            return None, "tripsit API returned non-JSON"
        data = payload.get("data") or []
        if not data:
            return None, "tripsit API returned no data field"
        entry = data[0]
        if isinstance(entry, dict) and entry.get("err"):
            hint = f"; TripSit files it under {working[0]!r}" if working else ""
            return False, entry.get("msg", "not found") + hint
        name = (
            (entry.get("pretty_name") or entry.get("name") or "") if isinstance(entry, dict) else ""
        )
        return True, f"tripsit API has {name or sub.name}"

    def _tripsit_bulk(self) -> set[str]:
        """Every drug name TripSit knows, in one request. Empty on failure —
        callers then fall back to the per-drug endpoint."""
        resp = fetch(
            "https://tripbot.tripsit.me/api/tripsit/getAllDrugNames",
            self.throttle,
            max_bytes=2_000_000,
        )
        if resp.error or resp.status != 200:
            return set()
        try:
            payload = json.loads(resp.text)
        except ValueError:
            return set()
        names = payload.get("data") if isinstance(payload, dict) else payload
        if isinstance(names, list) and len(names) == 1 and isinstance(names[0], list):
            names = names[0]  # the API wraps its payload in a one-element list
        if not isinstance(names, list):
            return set()
        return {normalize_for_match(str(name)) for name in names if name}

    def _drug_community(self, sub: Substance) -> tuple[bool | None, str]:
        # One bootstrap fetch covers every substance, so this costs 1 request
        # for the whole run instead of 403.
        with self._lock:
            if self._dc_slugs is None:
                resp = fetch(
                    "https://drug.community/api/data/bootstrap", self.throttle, max_bytes=8_000_000
                )
                try:
                    payload = json.loads(resp.text)
                    self._dc_slugs = {
                        slugify(entry.get("drug_name", ""))
                        for entry in payload.get("drugs", [])
                        if entry.get("drug_name")
                    }
                except ValueError:
                    self._dc_slugs = set()
        if not self._dc_slugs:
            return None, "drug.community bootstrap unavailable"
        slug = (sub.drug_community_slug or "").lower()
        return slug in self._dc_slugs, f"bootstrap lists {len(self._dc_slugs)} slugs"


def slugify(value: str) -> str:
    """drug.community's page slug: lowercase, non-alphanumerics → hyphens."""
    return re.sub(r"-{2,}", "-", re.sub(r"[^a-z0-9]+", "-", value.lower())).strip("-")


# --------------------------------------------------------------------------- #
# Verdicts
# --------------------------------------------------------------------------- #


@dataclass
class Finding:
    slug: str
    substance: str
    url: str | None
    verdict: str
    detail: str
    status: int | None = None
    final_url: str | None = None
    category: str = "page"


def same_page(left: str, right: str) -> bool:
    """URL equality for the homepage test: host + path + query, trailing slash
    and a `www.` prefix ignored. A redirect to `/` is still the homepage.

    The query MUST be part of the key — every search source lives at the site
    root with only `?term=…` to distinguish it, and ignoring the query called
    each of those a homepage fallback."""

    def key(url: str) -> tuple[str, str, str, str]:
        parts = urllib.parse.urlsplit(url)
        return (
            parts.scheme.lower(),
            parts.netloc.lower().removeprefix("www."),
            parts.path.rstrip("/"),
            parts.query,
        )

    return key(left) == key(right)


#: How many aliases to try when a page 404s. A handful is enough to catch the
#: common causes (wrong capitalization, chemical name vs street abbreviation)
#: without turning one bad link into a dozen requests.
ALIAS_PROBE_LIMIT = 6


def mediawiki_title(spec: SourceSpec, sub: Substance, throttle: HostThrottle) -> str | None:
    """Ask MediaWiki what it actually calls this compound.

    Wiki titles are case-sensitive past the first character, so `1Cp-LSD` 404s
    while `1cP-LSD` is a live article — a casing no alias list and no plausible
    guess would produce. The search API answers authoritatively in one request,
    which beats probing variants and hoping."""
    host = urllib.parse.urlsplit(spec.base).netloc
    query = urllib.parse.urlencode(
        {
            "action": "query",
            "list": "search",
            "srsearch": sub.name,
            "srlimit": "1",
            "format": "json",
        }
    )
    resp = fetch(f"https://{host}/w/api.php?{query}", throttle, max_bytes=200_000)
    if resp.error or resp.status != 200:
        return None
    try:
        hits = json.loads(resp.text).get("query", {}).get("search", [])
    except ValueError:
        return None
    if not hits:
        return None
    title = hits[0].get("title", "")
    # Only offer it when it is the SAME name differently spelled. A nearest
    # search hit for a compound the wiki genuinely lacks is a different
    # substance, and suggesting it would be worse than saying nothing.
    if not title or normalize_for_match(title) != normalize_for_match(sub.name):
        return None
    return f"{title!r} (https://{host}/wiki/{swift_path_encode(title.replace(' ', '_'))})"


def working_alias(spec: SourceSpec, sub: Substance, throttle: HostThrottle) -> str | None:
    """A name whose URL resolves where the canonical name's does not.

    Run only after a confirmed 404, so it costs nothing on the happy path. It is
    what makes a finding actionable: `Bromo-dragonfly` 404s and
    `Bromo-DragonFLY` is a live page, which names the fix instead of just the
    symptom."""
    if "psychonautwiki" in spec.base:
        exact = mediawiki_title(spec, sub, throttle)
        if exact:
            return exact
    for alias in sub.aliases[:ALIAS_PROBE_LIMIT]:
        if normalize_for_match(alias) == normalize_for_match(sub.name):
            continue
        candidate = spec.build(
            Substance(sub.id, alias, None, [], sub.freeodwiki_slug, sub.drug_community_slug)
        )
        if not candidate:
            continue
        probe_resp = fetch(candidate, throttle, max_bytes=4096)
        if probe_resp.status is not None and 200 <= probe_resp.status < 400:
            return f"{alias!r} ({candidate})"
    return None


def check_page(
    spec: SourceSpec, sub: Substance, probe: HostProbe, throttle: HostThrottle, oracles: Oracles
) -> Finding:
    url = spec.build(sub)
    if url is None:
        # The source contributed data for this compound but the build captured
        # no page slug, so the attribution row is dead text. Not a wrong link —
        # a pipeline gap — hence its own verdict rather than BROKEN or NO_LINK.
        return Finding(
            spec.slug,
            sub.name,
            None,
            "MISSING_SLUG",
            f"{spec.slug} contributed data but no per-substance slug was captured, "
            f"so the app can build no link",
        )

    # Failure mode 1 is provable without the network: the builder handed back the
    # site root, so the row links to a homepage no matter what the server says.
    if same_page(url, spec.base):
        return Finding(
            spec.slug, sub.name, url, "HOMEPAGE", "URL builder fell back to the site root"
        )

    if probe.mode == "unreachable":
        return Finding(spec.slug, sub.name, url, "UNVERIFIABLE", f"host probe failed: {probe.note}")

    if probe.mode == "opaque":
        if not spec.oracle:
            return Finding(
                spec.slug,
                sub.name,
                url,
                "UNVERIFIABLE",
                f"client-rendered host with no oracle: {probe.note}",
            )
        exists, note = oracles.check(spec.oracle, sub)
        if exists is None:
            return Finding(spec.slug, sub.name, url, "UNVERIFIABLE", note)
        if not exists:
            return Finding(
                spec.slug,
                sub.name,
                url,
                "BROKEN",
                f"page does not exist per the site's own data ({note})",
            )
        return Finding(spec.slug, sub.name, url, "OK", f"verified via oracle ({note})")

    resp = fetch(url, throttle)
    if resp.error:
        return Finding(spec.slug, sub.name, url, "UNVERIFIABLE", f"transport error {resp.error}")
    status = resp.status
    if status in (403, 429) or (status is not None and status >= 500):
        return Finding(
            spec.slug,
            sub.name,
            url,
            "UNVERIFIABLE",
            f"blocked or server-side (HTTP {status})",
            status,
            resp.final_url,
        )
    if status is not None and status >= 400:
        hint = working_alias(spec, sub, throttle)
        return Finding(
            spec.slug,
            sub.name,
            url,
            "BROKEN",
            f"HTTP {status}" + (f"; {hint} resolves instead" if hint else ""),
            status,
            resp.final_url,
        )

    # A 200 that redirected home is failure mode 1 wearing a disguise.
    if same_page(resp.final_url, spec.base) or (
        probe.base_final and same_page(resp.final_url, probe.base_final)
    ):
        return Finding(
            spec.slug,
            sub.name,
            url,
            "HOMEPAGE",
            f"redirected to the site root ({resp.final_url})",
            status,
            resp.final_url,
        )

    # Everything below reads the ARTICLE BODY, not the document. On a MediaWiki
    # host the chrome is ~190 KB against a ~50 KB article, so whole-page measures
    # describe the skin, not the substance.
    body = visible_text(resp.text, body_only=True)

    # --- Positive evidence first. -----------------------------------------
    # If the body names the compound, the page is real — say so and stop. A
    # size- or similarity-based suspicion cannot outrank the page having told us
    # what it is about, and running the heuristic first is exactly how real
    # PsychonautWiki articles got called soft-404s.
    haystack = normalize_for_match(body)
    for term in sub.mention_terms():
        if normalize_for_match(term) in haystack:
            return Finding(
                spec.slug, sub.name, url, "OK", f"page names {term!r}", status, resp.final_url
            )

    # --- No name found. Now decide between "missing page" and "odd page". ---
    if _NOARTICLE_RE.search(resp.text):
        hint = working_alias(spec, sub, throttle)
        return Finding(
            spec.slug,
            sub.name,
            url,
            "BROKEN",
            "MediaWiki noarticletext — the page does not exist"
            + (f"; {hint} resolves instead" if hint else ""),
            status,
            resp.final_url,
        )

    ratio = similarity(body, probe.sentinel_body)
    if ratio >= SOFT_404_SIMILARITY and close_in_size(len(body), len(probe.sentinel_body)):
        hint = working_alias(spec, sub, throttle)
        return Finding(
            spec.slug,
            sub.name,
            url,
            "BROKEN",
            f"soft-404: article body ({len(body)} chars) matches the host's error "
            f"baseline ({len(probe.sentinel_body)} chars, similarity {ratio:.2f})"
            + (f"; {hint} resolves instead" if hint else ""),
            status,
            resp.final_url,
        )

    # A body with nothing in it can't be read either way — that is an unknown,
    # not an accusation.
    if len(body.split()) < MIN_MEANINGFUL_WORDS:
        return Finding(
            spec.slug,
            sub.name,
            url,
            "UNVERIFIABLE",
            f"article body rendered only {len(body.split())} words",
            status,
            resp.final_url,
        )

    return Finding(
        spec.slug,
        sub.name,
        url,
        "NO_MENTION",
        f"{len(body)}-char article body never names the substance or any of "
        f"{len(sub.mention_terms())} aliases",
        status,
        resp.final_url,
    )


def check_search(spec: SourceSpec, sub: Substance, throttle: HostThrottle) -> Finding:
    """Search URLs are a weaker contract: assert the query resolves and looks
    like a results page. We deliberately do NOT require it to name the
    substance — a zero-hit search is a legitimate answer, not a broken link."""
    url = spec.build(sub)
    if url is None:
        return Finding(spec.slug, sub.name, None, "NO_LINK", "no search URL", category="search")
    resp = fetch(url, throttle)
    if resp.error:
        return Finding(
            spec.slug,
            sub.name,
            url,
            "UNVERIFIABLE",
            f"transport error {resp.error}",
            category="search",
        )
    status = resp.status
    if status in (403, 429) or (status is not None and status >= 500):
        # Erowid answers automated requests with 403 — not a broken link, just
        # one we can't check. A person tapping it in Safari gets the results.
        return Finding(
            spec.slug,
            sub.name,
            url,
            "UNVERIFIABLE",
            f"blocked or server-side (HTTP {status})",
            status,
            resp.final_url,
            "search",
        )
    if status is not None and status >= 400:
        return Finding(
            spec.slug, sub.name, url, "BROKEN", f"HTTP {status}", status, resp.final_url, "search"
        )
    if same_page(resp.final_url, spec.base):
        return Finding(
            spec.slug,
            sub.name,
            url,
            "HOMEPAGE",
            f"search redirected to the site root ({resp.final_url})",
            status,
            resp.final_url,
            "search",
        )
    if len(resp.body) < 512:
        return Finding(
            spec.slug,
            sub.name,
            url,
            "BROKEN",
            f"search returned a {len(resp.body)}B body — not a results page",
            status,
            resp.final_url,
            "search",
        )
    return Finding(
        spec.slug,
        sub.name,
        url,
        "OK",
        f"search resolves ({len(resp.body)}B)",
        status,
        resp.final_url,
        "search",
    )


# --------------------------------------------------------------------------- #
# Cache
# --------------------------------------------------------------------------- #


def load_cache(path: Path) -> dict[str, dict]:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except ValueError:
            return {}
    return {}


def save_cache(path: Path, cache: dict[str, dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    ordered = {key: cache[key] for key in sorted(cache)}
    path.write_text(json.dumps(ordered, indent=2, ensure_ascii=False) + "\n")


def cache_key(slug: str, substance: str) -> str:
    return f"{slug}|{substance}"


def needs_recheck(entry: dict | None, today: date, stale_days: int) -> bool:
    if entry is None:
        return True
    if entry.get("verdict") != "OK":
        return True  # retry failures — slugs get fixed, blocks lift
    checked = entry.get("checked")
    if not checked:
        return True
    try:
        return (today - date.fromisoformat(checked)).days >= stale_days
    except ValueError:
        return True


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

VERDICT_ORDER = [
    "OK",
    "HOMEPAGE",
    "BROKEN",
    "NO_MENTION",
    "MISSING_SLUG",
    "UNVERIFIABLE",
    "NO_LINK",
]
#: Verdicts that fail `--gate`. UNVERIFIABLE never fails: we refuse to call a
#: link broken because a host blocked us.
GATE_FAILING = {"HOMEPAGE", "BROKEN", "NO_MENTION"}


@dataclass
class Plan:
    spec: SourceSpec
    substances: list[Substance] = field(default_factory=list)


def build_plan(
    substances: dict[int, Substance],
    pairs: list[tuple[str, int]],
    args: argparse.Namespace,
) -> tuple[list[Plan], Counter]:
    """Group the work by source so each host gets one serialized worker."""
    by_slug: dict[str, list[Substance]] = defaultdict(list)
    skipped: Counter = Counter()
    for slug, sid in pairs:
        if slug in NO_LINK_SOURCES:
            skipped[slug] += 1
            continue
        if slug not in SOURCES:
            skipped[f"{slug} (unknown source)"] += 1
            continue
        sub = substances.get(sid)
        if sub:
            by_slug[slug].append(sub)

    # Sources whose link the app offers for every substance regardless of who
    # contributed data (Erowid's experience-vault search on the effects card).
    for slug, spec in SOURCES.items():
        if spec.from_db:
            continue
        if args.source == slug or (not args.source and spec.enumerate_default):
            by_slug[slug] = sorted(substances.values(), key=lambda s: s.name)

    wanted = {name.lower() for name in args.substance}
    plans = []
    for slug, subs in sorted(by_slug.items()):
        if args.source and slug != args.source:
            continue
        spec = SOURCES[slug]
        subs = sorted(subs, key=lambda s: s.name)
        if wanted:
            # Match aliases too — a report arrives as "2-FDCK", not
            # "2-Fluorodeschloroketamine".
            plans.append(
                Plan(
                    spec,
                    [
                        sub
                        for sub in subs
                        if wanted & ({sub.name.lower()} | {a.lower() for a in sub.aliases})
                    ],
                )
            )
            continue
        if spec.kind == "search" and args.search_sample:
            subs = even_sample(subs, args.search_sample)
        plans.append(Plan(spec, subs))

    if args.limit and not wanted:
        plans = apply_global_limit(plans, args.limit)
    return plans, skipped


def even_sample(subs: list[Substance], cap: int) -> list[Substance]:
    """`cap` substances spread across the alphabet. Taking the first N would only
    ever exercise the numeric-prefixed research chemicals."""
    if cap <= 0 or len(subs) <= cap:
        return subs
    step = max(1, len(subs) // cap)
    return subs[::step][:cap]


def apply_global_limit(plans: list[Plan], limit: int) -> list[Plan]:
    """Cap TOTAL pages fetched, spread round-robin across sources.

    `--limit` is a smoke test: "check `limit` links and tell me if anything is
    obviously wrong". Applying it per source made `--limit 40` mean 240 fetches
    and skewed toward whichever source happened to be listed — and it never
    reached a source at all if the earlier ones filled the budget. Round-robin
    guarantees every source is represented before any source gets a second
    round."""
    sampled = [(plan.spec, even_sample(plan.substances, limit)) for plan in plans]
    taken: dict[str, list[Substance]] = {spec.slug: [] for spec, _ in sampled}
    budget = limit
    for index in range(max((len(subs) for _, subs in sampled), default=0)):
        for spec, subs in sampled:
            if budget <= 0:
                break
            if index < len(subs):
                taken[spec.slug].append(subs[index])
                budget -= 1
        if budget <= 0:
            break
    return [Plan(spec, taken[spec.slug]) for spec, _ in sampled if taken[spec.slug]]


def run_plan(
    plan: Plan,
    throttle: HostThrottle,
    oracles: Oracles,
    cache: dict,
    today: date,
    args: argparse.Namespace,
    checkpoint: object,
) -> tuple[list[Finding], HostProbe | None]:
    findings: list[Finding] = []
    todo = []
    for sub in plan.substances:
        entry = cache.get(cache_key(plan.spec.slug, sub.name))
        if not args.all and not needs_recheck(entry, today, args.stale_days):
            findings.append(
                Finding(
                    plan.spec.slug,
                    sub.name,
                    entry.get("url"),
                    entry["verdict"],
                    entry.get("detail", "") + " (cached)",
                    entry.get("status"),
                    entry.get("final_url"),
                    plan.spec.kind,
                )
            )
            continue
        todo.append(sub)

    if not todo:
        return findings, None

    probe = None
    if plan.spec.kind == "page":
        probe = probe_source(plan.spec, throttle)
        print(f"  [{plan.spec.slug}] probe → {probe.mode}: {probe.note}", flush=True)

    for index, sub in enumerate(todo, 1):
        if plan.spec.kind == "page":
            finding = check_page(plan.spec, sub, probe, throttle, oracles)
        else:
            finding = check_search(plan.spec, sub, throttle)
        findings.append(finding)
        cache[cache_key(plan.spec.slug, sub.name)] = {
            "verdict": finding.verdict,
            "url": finding.url,
            "status": finding.status,
            "final_url": finding.final_url,
            "detail": finding.detail,
            "category": finding.category,
            "checked": today.isoformat(),
        }
        if index % 25 == 0:
            print(f"  [{plan.spec.slug}] {index}/{len(todo)}", flush=True)
            # Flush mid-run. A full sweep is tens of minutes of someone else's
            # bandwidth; losing it to a Ctrl-C would mean spending it twice.
            checkpoint()
    return findings, probe


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--repo", type=Path, default=REPO, help="repo root (defaults to this script's ../..)"
    )
    parser.add_argument("--db", type=Path, help="path to the built SQLite")
    parser.add_argument(
        "--cache", type=Path, help="verdict cache (NOT data/sources/link-cache.json)"
    )
    parser.add_argument("--json", type=Path, help="write the full report as JSON")
    parser.add_argument(
        "--gate",
        action="store_true",
        help="offline build gate: no network; exit 1 on a statically-provable "
        "homepage fallback or a cached BROKEN/NO_MENTION",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="GLOBAL cap on links checked this run, spread round-robin across "
        "every source (a quick smoke test); 0 = all",
    )
    parser.add_argument(
        "--search-sample",
        type=int,
        default=25,
        help="max substances per SEARCH source; 0 = all. Search URLs don't vary "
        "in shape, so a sample is enough",
    )
    parser.add_argument("--source", help="check only this source slug")
    parser.add_argument(
        "--substance",
        action="append",
        default=[],
        help="check only these substances (repeatable, case-insensitive)",
    )
    parser.add_argument("--all", action="store_true", help="ignore cached OK verdicts")
    parser.add_argument("--stale-days", type=int, default=STALE_DAYS)
    parser.add_argument(
        "--delay",
        type=float,
        default=HOST_DELAY,
        help="minimum seconds between requests to one host",
    )
    args = parser.parse_args()
    args.db = args.db or args.repo / DB_RELPATH
    args.cache = args.cache or args.repo / CACHE_RELPATH

    if args.source and args.source not in SOURCES:
        print(
            f"unknown --source {args.source!r}; known: {', '.join(sorted(SOURCES))}",
            file=sys.stderr,
        )
        return 2
    if not args.db.exists():
        print(f"source-link-check: no database at {args.db}", file=sys.stderr)
        return 2

    substances, pairs = load_pairs(args.db)
    static_findings = audit_swift_sources(args.repo) + encoding_hazards(substances)
    plans, skipped = build_plan(substances, pairs, args)
    today = datetime.now(UTC).date()
    cache = load_cache(args.cache)

    print(f"source-link-check: {args.db}")
    if static_findings:
        print(f"\nSTATIC AUDIT of AppSources.swift ({len(static_findings)}):")
        for line in static_findings:
            print(f"  ! {line}")

    # --- Offline gate ------------------------------------------------------ #
    if args.gate:
        # Both of these are decidable from the DB + the URL builders alone, so
        # the gate proves them with no network at all — the network run only
        # adds what a fetch can tell us.
        offline: list[Finding] = []
        for plan in plans:
            if plan.spec.kind != "page":
                continue
            for sub in plan.substances:
                url = plan.spec.build(sub)
                if url is None:
                    offline.append(
                        Finding(
                            plan.spec.slug,
                            sub.name,
                            None,
                            "MISSING_SLUG",
                            f"{plan.spec.slug} contributed data but no per-substance slug "
                            f"was captured, so the app can build no link",
                        )
                    )
                elif same_page(url, plan.spec.base):
                    offline.append(
                        Finding(
                            plan.spec.slug,
                            sub.name,
                            url,
                            "HOMEPAGE",
                            "URL builder fell back to the site root",
                        )
                    )
        cached_bad = [
            Finding(
                key.split("|", 1)[0],
                key.split("|", 1)[1],
                entry.get("url"),
                entry["verdict"],
                entry.get("detail", ""),
                entry.get("status"),
                entry.get("final_url"),
                entry.get("category", "page"),
            )
            for key, entry in sorted(cache.items())
            if entry.get("verdict") in GATE_FAILING
        ]
        seen = {(f.slug, f.substance) for f in offline}
        combined = offline + [f for f in cached_bad if (f.slug, f.substance) not in seen]
        report_findings(combined)
        # MISSING_SLUG is a data-completeness gap, not a link that lies, so it is
        # reported above but never turns the build red.
        failures = [f for f in combined if f.verdict in GATE_FAILING]
        if failures:
            print(
                f"\nGATE FAILED: {len(failures)} source link(s) do not land on a substance page.",
                file=sys.stderr,
            )
            return 1
        print(f"\ngate OK — no homepage fallbacks; {len(cache)} cached verdicts clean.")
        return 0

    # --- Live run ---------------------------------------------------------- #
    total = sum(len(p.substances) for p in plans)
    print(
        f"\n{total} (substance, source) link(s) across {len(plans)} source(s); "
        f"{args.delay:g}s/request per host"
    )
    # A rebuild can drop a source's contribution for a compound, orphaning its
    # cache entry. Prune passing ones so the cache tracks what ships; keep the
    # failures as the audit trail that we found and fixed them (the same bargain
    # validate_links.py strikes with its dead links).
    if not args.source and not args.substance and not args.limit:
        shipped = {cache_key(p.spec.slug, sub.name) for p in plans for sub in p.substances}
        for orphan in [
            key
            for key, entry in cache.items()
            if key not in shipped and entry.get("verdict") == "OK"
        ]:
            del cache[orphan]

    throttle = HostThrottle(args.delay)
    oracles = Oracles(throttle)
    checkpoint_lock = threading.Lock()

    def checkpoint() -> None:
        with checkpoint_lock:
            save_cache(args.cache, dict(cache))

    findings: list[Finding] = []
    probes: dict[str, HostProbe] = {}
    # One worker per source keeps each host serialized while letting different
    # hosts overlap — the whole reason a full run finishes in minutes.
    with ThreadPoolExecutor(max_workers=max(1, len(plans))) as pool:
        for plan, (result, probe) in zip(
            plans,
            pool.map(
                lambda p: run_plan(p, throttle, oracles, cache, today, args, checkpoint), plans
            ),
            strict=True,
        ):
            findings.extend(result)
            if probe:
                probes[plan.spec.slug] = probe

    save_cache(args.cache, cache)
    report_findings(findings)

    tally = Counter(f.verdict for f in findings)
    print(f"\ncache → {args.cache}")
    if skipped:
        print("\nsources with no deep link (informational):")
        for slug, count in sorted(skipped.items(), key=lambda kv: -kv[1]):
            reason = NO_LINK_SOURCES.get(slug, "unknown source")
            print(f"  {slug:<22} {count:>5} substance(s) — {reason}")

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(
                {
                    "checked": today.isoformat(),
                    "db": str(args.db),
                    "static_audit": static_findings,
                    "probes": {
                        slug: probe.__dict__ | {"sentinel_text": ""}
                        for slug, probe in probes.items()
                    },
                    "tally": dict(tally),
                    "findings": [f.__dict__ for f in findings],
                    "no_link_sources": dict(skipped),
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n"
        )
        print(f"json  → {args.json}")

    return 1 if any(tally.get(v) for v in GATE_FAILING) else 0


def report_findings(findings: list[Finding]) -> None:
    tally = Counter(f.verdict for f in findings)
    print(
        "\nverdicts: "
        + "  ".join(f"{verdict}={tally.get(verdict, 0)}" for verdict in VERDICT_ORDER)
    )

    by_source: dict[str, Counter] = defaultdict(Counter)
    for finding in findings:
        by_source[finding.slug][finding.verdict] += 1
    if by_source:
        print("\nper source:")
        for slug in sorted(by_source):
            counts = by_source[slug]
            line = "  ".join(f"{v}={counts[v]}" for v in VERDICT_ORDER if counts[v])
            print(f"  {slug:<22} {line}")

    for verdict in ("HOMEPAGE", "BROKEN", "NO_MENTION", "MISSING_SLUG"):
        bad = [f for f in findings if f.verdict == verdict]
        if not bad:
            continue
        print(f"\n{verdict} ({len(bad)}):")
        for finding in bad[:40]:
            print(f"  {finding.slug:<16} {finding.substance:<28} {finding.detail}")
            if finding.url:
                print(f"      {finding.url}")
        if len(bad) > 40:
            print(f"  … and {len(bad) - 40} more")


if __name__ == "__main__":
    raise SystemExit(main())
