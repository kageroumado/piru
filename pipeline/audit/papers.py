#!/usr/bin/env python3
"""Read-only client for the papers cache, with optional CLI for fetching.

The papers cache (``~/Developer/papers/`` by default, ``PAPERS_DIR`` to
override) holds full-text Markdown, metadata, and identifiers for every paper
that has been fetched.  This module reads that cache so the citation scripts
can check a value against the actual paper text rather than relying on the
~25% that happens to be open access in Europe PMC.

When the cache does not exist, every function returns its "miss" value and
the caller falls back to its own HTTP resolution — so nothing here is
required for the pipeline to work.  The ``papers`` CLI is a private tool
described in ``pipeline/README.md``; anyone cloning the repo can build their
own version against the spec there.

    from audit.papers import papers_cache
    pc = papers_cache()

    meta = pc.meta("27520396")           # → dict | None
    text = pc.text("10.1016/j.neuro...")  # → str (empty if not cached)
    pc.has("27520396")                    # → bool

    # Batch fetch (needs the CLI installed):
    pc.populate(["27520396", "10.1016/..."], metadata_only=True)
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
from collections.abc import Callable
from pathlib import Path


def _papers_dir() -> Path:
    return Path(os.environ.get("PAPERS_DIR", Path.home() / "Developer" / "papers"))


def _cli_available() -> bool:
    return shutil.which("papers") is not None


# ── key conversion ───────────────────────────────────────────────────────────
#
# The papers cache keys DOIs as ``10.1016_j.foo`` (slashes → underscores) and
# PMIDs as ``pmid_12345``.  Aliases (e.g. a PMID pointing at a DOI-keyed
# entry) are resolved transparently.


def _normalize_doi(raw: str) -> str:
    text = raw.strip()
    text = re.sub(r"^https?://(dx\.)?doi\.org/", "", text, flags=re.I)
    text = re.sub(r"^doi:\s*", "", text, flags=re.I)
    return text


def _to_cache_key(identifier: str) -> str:
    text = str(identifier).strip()
    if re.match(r"^pmid:?\s*\d+$", text, re.I):
        return f"pmid_{re.sub(r'^pmid:?\\s*', '', text, flags=re.I)}"
    if re.match(r"^\d{1,9}$", text):
        return f"pmid_{text}"
    if "10." in text:
        doi = _normalize_doi(text)
        if doi.startswith("10."):
            safe = re.sub(r"[^A-Za-z0-9._-]+", "_", doi.lower()).strip("_")
            return safe
    return text


# ── cache reader ─────────────────────────────────────────────────────────────


class PapersCache:
    """Lazy, read-only view of the papers cache on disk.

    Loads the index once on first access and holds it for the process
    lifetime.  The index is small (~50 KB for 1,000 papers) so this is cheap.
    """

    def __init__(self, root: Path | None = None) -> None:
        self._root = root or _papers_dir()
        self._index: dict[str, dict] | None = None

    @property
    def available(self) -> bool:
        return (self._root / "index.json").exists()

    @property
    def _idx(self) -> dict[str, dict]:
        if self._index is None:
            idx_path = self._root / "index.json"
            if idx_path.exists():
                try:
                    self._index = json.loads(idx_path.read_text())
                except (ValueError, OSError):
                    self._index = {}
            else:
                self._index = {}
        return self._index

    def _resolve(self, identifier: str) -> dict | None:
        key = _to_cache_key(identifier)
        entry = self._idx.get(key)
        if entry is not None:
            if entry.get("status") == "alias" and entry.get("alias_of"):
                entry = self._idx.get(entry["alias_of"])
            return entry
        # A paper fetched via DOI has no pmid_ alias in the index, but its
        # metadata carries the PMID.  Fall back to scanning the field.
        text = str(identifier).strip()
        if re.match(r"^(pmid:?\s*)?\d{1,9}$", text, re.I):
            pmid = re.sub(r"^pmid:?\s*", "", text, flags=re.I)
            if pmid not in self._pmid_map:
                return None
            return self._idx.get(self._pmid_map[pmid])
        return None

    @property
    def _pmid_map(self) -> dict[str, str]:
        if not hasattr(self, "_pmid_to_key"):
            self._pmid_to_key: dict[str, str] = {}
            for key, entry in self._idx.items():
                if entry.get("pmid") and entry.get("status") != "alias":
                    self._pmid_to_key[str(entry["pmid"])] = key
        return self._pmid_to_key

    def has(self, identifier: str) -> bool:
        entry = self._resolve(identifier)
        return entry is not None and entry.get("status") in ("ok", "scanned")

    def meta(self, identifier: str) -> dict | None:
        """Return metadata for a cached paper, or None if not in the cache.

        The returned dict has: title, journal, year, doi, pmid, pmcid,
        authors, status.  This is enough for verify_citations and
        citation_topicality to skip their HTTP resolution.
        """
        entry = self._resolve(identifier)
        if entry is None:
            return None
        return {
            "title": entry.get("title", ""),
            "journal": entry.get("journal", ""),
            "year": entry.get("year", ""),
            "doi": entry.get("doi", ""),
            "pmid": entry.get("pmid", ""),
            "pmcid": entry.get("pmcid", ""),
            "authors": entry.get("authors", ""),
            "status": entry.get("status", ""),
        }

    def text(self, identifier: str) -> str:
        """Return the full Markdown text of a cached paper.

        Returns "" if not cached or status is not ``ok``.  The YAML front
        matter is stripped — the caller gets the body only.
        """
        entry = self._resolve(identifier)
        if entry is None or entry.get("status") != "ok":
            return ""
        md_path = self._root / "md" / f"{entry['key']}.md"
        if not md_path.exists():
            return ""
        content = md_path.read_text(errors="replace")
        if content.startswith("---"):
            end = content.find("\n---", 3)
            if end != -1:
                content = content[end + 4 :]
        return content.strip()

    def populate(
        self,
        identifiers: list[str],
        *,
        metadata_only: bool = False,
        on_progress: Callable[[int, int, str, str], None] | None = None,
        workers: int = 1,
    ) -> int:
        """Fetch papers into the cache via the ``papers`` CLI.

        Returns the number of identifiers submitted (0 if the CLI is not
        installed).  With ``metadata_only=True``, calls ``papers meta`` in a
        loop instead of ``papers get``.

        ``on_progress(done, total, identifier, status)`` is called after each
        identifier completes.  ``workers`` controls concurrency (default 1).
        """
        if not _cli_available() or not identifiers:
            return 0

        import threading
        from concurrent.futures import ThreadPoolExecutor, as_completed

        total = len(identifiers)
        counter = threading.Lock()
        done_count = 0
        submitted = 0

        def _fetch_one(ident: str) -> tuple[str, str, bool]:
            if self._resolve(ident) is not None:
                return (ident, "cached", False)
            cmd = ["papers", "meta" if metadata_only else "get", str(ident)]
            try:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
                status = "ok" if result.returncode == 0 else "failed"
            except subprocess.TimeoutExpired:
                status = "timeout"
            except FileNotFoundError:
                status = "no-cli"
            return (ident, status, status != "cached")

        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(_fetch_one, ident): ident for ident in identifiers}
            for future in as_completed(futures):
                ident, status, was_submitted = future.result()
                with counter:
                    done_count += 1
                    if was_submitted:
                        submitted += 1
                    n = done_count
                if on_progress:
                    on_progress(n, total, ident, status)
                if status == "no-cli":
                    break

        return submitted

    def reload(self) -> None:
        """Force a re-read of the index (e.g. after ``populate``)."""
        self._index = None
        if hasattr(self, "_pmid_to_key"):
            del self._pmid_to_key


_CACHE: PapersCache | None = None


def papers_cache(root: Path | None = None) -> PapersCache:
    """Module-level singleton.  Thread-safe enough for a build script."""
    global _CACHE
    if _CACHE is None:
        _CACHE = PapersCache(root)
    return _CACHE
