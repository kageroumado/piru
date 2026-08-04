#!/usr/bin/env python3
"""Europe PMC client: one place that turns an identifier or a query into text.

The citation checks are bounded by how much paper text we hold. `verify_citations`
resolves DOIs through Crossref and PMIDs through NCBI, and `citation_topicality`
pulls abstracts from the same two — which leaves 232 attached citations with no
abstract at all, and *every* absence check silently declines to fire on those.

Europe PMC closes most of that gap for three reasons the other two cannot:

  * it indexes PubMed, Agricola, patents and preprints behind **one** query
    grammar, so a DOI and a PMID take the same code path;
  * it carries an abstract for papers Crossref stores none for (measured: 24 of a
    40-paper sample of our gap);
  * for open-access records it serves the **full text**, which is the only way to
    answer "does the number this row claims actually appear in the paper?" — a
    Kᵢ almost never appears in an abstract, it appears in Table 2.

Everything is cached on disk, keyed by request, so a re-run is offline and the
gates stay reproducible.

    from audit.europepmc import client
    rec = client().by_id(pmid=27520396)      # → Record | None
    hits = client().search('TITLE:"ephenidine"')
    text = client().text_for(rec)            # abstract, or full text when OA
"""

from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CACHE = REPO / "data/sources/europepmc-cache.json"
BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest"
USER_AGENT = "piru-citation-sourcing/1.0 (https://github.com/kageroumado/piru)"
#: Europe PMC asks for courtesy rate limiting; it does not publish a hard cap.
DELAY_SECONDS = 0.15


@dataclass
class Record:
    """One paper, flattened to the fields the citation checks actually read."""

    pmid: str | None = None
    pmcid: str | None = None
    doi: str | None = None
    title: str = ""
    journal: str = ""
    year: str = ""
    volume: str = ""
    pages: str = ""
    first_author: str = ""
    #: Every author, as Europe PMC returns them. Kept whole because an
    #: author-and-year query is only as good as the check that the paper it
    #: returned is actually by that author.
    authors: str = ""
    abstract: str = ""
    is_open_access: bool = False
    #: MEDLINE's own indexing of what the paper is about — descriptor names and
    #: the qualifiers attached to them ("Ketamine" / "pharmacokinetics"). A
    #: controlled vocabulary applied by a human indexer, which makes it the one
    #: subject signal here that owes nothing to our own text matching.
    mesh: tuple[tuple[str, tuple[str, ...]], ...] = ()
    #: Filled lazily by `text_for`; never populated by a search.
    full_text: str = ""

    @property
    def mesh_qualifiers(self) -> set[str]:
        return {qualifier for _, qualifiers in self.mesh for qualifier in qualifiers}

    @property
    def mesh_descriptors(self) -> set[str]:
        return {descriptor.lower() for descriptor, _ in self.mesh}

    @property
    def identifier(self) -> str | None:
        if self.doi:
            return f"doi:{self.doi}"
        if self.pmid:
            return f"pmid:{self.pmid}"
        return None

    def cite(self) -> str:
        bits = [b for b in (self.first_author, self.year, self.journal) if b]
        return f"{' '.join(bits)} — {self.title}"[:160]


def _strip_markup(text: str | None) -> str:
    """Europe PMC embeds JATS section headers (`<h4>Methods</h4>`) inside the
    abstract field. Drop the tags, keep the words as sentence boundaries."""
    if not text:
        return ""
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", text)).strip()


def _mesh_from(raw: dict) -> tuple[tuple[str, tuple[str, ...]], ...]:
    headings = (raw.get("meshHeadingList") or {}).get("meshHeading") or []
    out: list[tuple[str, tuple[str, ...]]] = []
    for heading in headings:
        if not isinstance(heading, dict):
            continue
        descriptor = heading.get("descriptorName")
        if not descriptor:
            continue
        qualifiers = (heading.get("meshQualifierList") or {}).get("meshQualifier") or []
        out.append(
            (
                descriptor,
                tuple(
                    q.get("qualifierName", "").lower()
                    for q in qualifiers
                    if isinstance(q, dict) and q.get("qualifierName")
                ),
            )
        )
    return tuple(out)


def _record_from(raw: dict) -> Record:
    authors = raw.get("authorString") or ""
    return Record(
        mesh=_mesh_from(raw),
        pmid=(raw.get("pmid") or None),
        pmcid=(raw.get("pmcid") or None),
        doi=(raw.get("doi") or None),
        title=_strip_markup(raw.get("title")),
        journal=(
            raw.get("journalTitle")
            or (raw.get("journalInfo") or {}).get("journal", {}).get("title")
            or ""
        ),
        year=str(raw.get("pubYear") or ""),
        volume=str((raw.get("journalInfo") or {}).get("volume") or ""),
        pages=raw.get("pageInfo") or "",
        first_author=authors.split(",")[0].strip(),
        authors=authors,
        abstract=_strip_markup(raw.get("abstractText")),
        is_open_access=(raw.get("isOpenAccess") == "Y"),
    )


class EuropePMC:
    def __init__(self, cache_path: Path = CACHE, offline: bool = False) -> None:
        self.cache_path = cache_path
        self.offline = offline
        self._cache: dict[str, object] = {}
        self._dirty = False
        if cache_path.exists():
            try:
                self._cache = json.loads(cache_path.read_text())
            except ValueError:
                self._cache = {}

    # ------------------------------------------------------------------ cache

    def save(self) -> None:
        if not self._dirty:
            return
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        self.cache_path.write_text(json.dumps(self._cache, indent=1, sort_keys=True) + "\n")
        self._dirty = False

    def _get(self, key: str, url: str, *, raw_text: bool = False) -> object | None:
        """Cache-first fetch. A cached `None` is a remembered miss and is honored,
        so a re-run never re-asks for something the API does not have."""
        if key in self._cache:
            return self._cache[key]
        if self.offline:
            return None
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        payload: object | None = None
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
            payload = body.decode("utf-8", "replace") if raw_text else json.loads(body)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError):
            payload = None
        self._cache[key] = payload
        self._dirty = True
        time.sleep(DELAY_SECONDS)
        return payload

    # ----------------------------------------------------------------- lookup

    def search(self, query: str, page_size: int = 10) -> list[Record]:
        url = f"{BASE}/search?" + urllib.parse.urlencode(
            {"query": query, "resultType": "core", "format": "json", "pageSize": page_size}
        )
        payload = self._get(f"search:{page_size}:{query}", url)
        if not isinstance(payload, dict):
            return []
        results = (payload.get("resultList") or {}).get("result") or []
        return [_record_from(row) for row in results if isinstance(row, dict)]

    def by_id(self, *, pmid: str | int | None = None, doi: str | None = None) -> Record | None:
        """Exact lookup. DOI is quoted because Europe PMC's grammar treats the
        slash and colon in a DOI as syntax otherwise."""
        if pmid:
            query = f"EXT_ID:{pmid} AND SRC:MED"
        elif doi:
            query = f'DOI:"{doi}"'
        else:
            return None
        hits = self.search(query, page_size=1)
        return hits[0] if hits else None

    def full_text(self, pmcid: str) -> str:
        """Open-access full text as plain words. Returns "" when the record is
        not in the OA subset — which is most of them, and is not an error."""
        payload = self._get(f"fulltext:{pmcid}", f"{BASE}/{pmcid}/fullTextXML", raw_text=True)
        if not isinstance(payload, str) or not payload.strip().startswith("<"):
            return ""
        # Tables are where the numbers live, so markup is flattened rather than
        # sectioned — a `<td>66.4</td>` must survive as the token "66.4".
        text = re.sub(r"<[^>]+>", " ", payload)
        return re.sub(r"\s+", " ", text).strip()

    def text_for(self, record: Record | None) -> str:
        """Every word we can get for a paper: title, abstract, and full text when
        it is open access. This is the corpus a value check searches."""
        if record is None:
            return ""
        parts = [record.title, record.abstract]
        if record.pmcid:
            record.full_text = record.full_text or self.full_text(record.pmcid)
            parts.append(record.full_text)
        return " ".join(part for part in parts if part)


_CLIENT: EuropePMC | None = None


def client(offline: bool = False) -> EuropePMC:
    global _CLIENT
    if _CLIENT is None:
        _CLIENT = EuropePMC(offline=offline)
    else:
        _CLIENT.offline = offline
    return _CLIENT
