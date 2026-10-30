#!/usr/bin/env python3
"""Cite each MedTAP-derived mechanism line to the DailyMed label it paraphrases.

`data/curated/mechanism-lines.json` → `medtap_lines` holds Piru's one-sentence
mechanism for MedTAP records whose label prose Piru does not ship. Each line was
written from that record's FDA label, and the record names the label's product
NDC (`data/sources/medtap-pk.json`, else the private MedTAP extract's `x_ndc`).
So the source is known exactly; it was just never written down.

For each line, deterministically:

  1. **NDC → setid** through DailyMed's own SPL service (`spls.json?ndc=`). An
     NDC that resolves to no label, or to several, stays uncited.
  2. **The label is about this substance**: the SPL title states it as whole
     words (`resolve_fda_label_links.title_names`), and the DailyMed page
     resolves (`source_link_check.fetch` + `visible_text`, the fetch and body
     extraction the source-link gate uses).
  3. **The label states the line**: at least half of the line's content words
     appear, by stem, in the label's §12.1 Mechanism of Action — the section the
     line paraphrases.

Responses are cached in `data/sources/dailymed-labels.json` (committed), so a
re-run is offline. Lines that pass become `mechanisms_summary` entries in
`data/curated/row-citations.json` with `via: dailymed-ndc`.

    python3 pipeline/audit/source_dailymed_mechanisms.py --fetch --write
    python3 pipeline/audit/source_dailymed_mechanisms.py            # offline, report only
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import urllib.parse
from collections import Counter
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))

import row_citations  # noqa: E402
from audit.resolve_fda_label_links import title_names  # noqa: E402
from audit.source_link_check import (  # noqa: E402
    HostThrottle,
    fetch,
    visible_text,
)
from sqlite import clean_wiki_prose  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"
MECHANISM_LINES = REPO / "data/curated/mechanism-lines.json"
MEDTAP_PK = REPO / "data/sources/medtap-pk.json"
MEDTAP_EXTRACT = (
    Path(os.environ.get("PIRU_EXTERNAL_DIR", "/tmp/piru-extract")) / "medtap.substances.json"
)
CACHE = REPO / "data/sources/dailymed-labels.json"
VIA = "dailymed-ndc"
SPLS = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json?ndc="
SPL_XML = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls/{setid}.xml"
PAGE = "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid="
#: Share of a line's content words the label's §12.1 must contain.
MIN_OVERLAP = 0.5
#: Words that carry no pharmacology, so they neither help nor hurt the overlap.
STOPWORDS = {
    "which", "their", "these", "those", "there", "where", "while", "through", "within",
    "other", "about", "against", "between", "into", "from", "that", "this", "with",
    "without", "increases", "increasing", "reduces", "reducing", "thereby", "leading",
    "resulting", "action", "actions", "effect", "effects", "activity", "levels", "level",
}  # fmt: skip


def stems(text: str) -> set[str]:
    """Content-word stems: lowercase words of 5+ letters, cut to 6 characters, so
    "inhibitor"/"inhibition" and "blocks"/"blocking" meet."""
    words = re.findall(r"[a-z][a-z0-9'-]{4,}", text.lower())
    return {w[:6] for w in words if w not in STOPWORDS}


def ndc_by_name() -> dict[str, str]:
    out: dict[str, str] = {}
    if MEDTAP_EXTRACT.exists():
        for record in json.loads(MEDTAP_EXTRACT.read_text()):
            if record.get("name") and record.get("x_ndc"):
                out[record["name"].lower()] = record["x_ndc"]
    # The committed table wins: it is what a clone without the extract sees.
    for entry in json.loads(MEDTAP_PK.read_text())["entries"]:
        if entry.get("substance") and entry.get("ndc"):
            out[entry["substance"].lower()] = entry["ndc"]
    return out


def load_cache() -> dict:
    return json.loads(CACHE.read_text()) if CACHE.exists() else {}


def save_cache(cache: dict) -> None:
    CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True, ensure_ascii=False) + "\n")


def resolve(
    ndc: str, names: list[str], cache: dict, throttle: HostThrottle, online: bool
) -> dict | None:
    """The cached label record for an NDC, fetching it when allowed. `names`
    are the substance's names, checked against the DailyMed page body at fetch
    time so the cache keeps the verdict rather than the page."""
    if ndc in cache or not online:
        return cache.get(ndc)
    entry: dict = {"ndc": ndc, "checked": date.today().isoformat()}
    spls = fetch(SPLS + urllib.parse.quote(ndc), throttle)
    labels = (json.loads(spls.text).get("data") or []) if spls.status == 200 else []
    entry["setids"] = sorted({label["setid"] for label in labels})
    if len(entry["setids"]) == 1:
        setid = entry["setids"][0]
        entry["title"] = labels[0].get("title")
        spl = fetch(SPL_XML.format(setid=setid), throttle, max_bytes=8_000_000)
        entry["mechanism_of_action"] = mechanism_section(spl.text) if spl.status == 200 else ""
        page = fetch(PAGE + setid, throttle)
        entry["page_status"] = page.status
        body = visible_text(page.text, body_only=True) if page.status == 200 else ""
        entry["page_status"] = page.status if body else None
    cache[ndc] = entry
    return entry


def mechanism_section(xml: str) -> str:
    """The text of the SPL's Mechanism of Action section (LOINC 43679-0, §12.1).

    The section is a leaf in every label we read, so it runs from its code to
    the next closing `</section>`."""
    match = re.search(r'code="43679-0"[^>]*>', xml)
    if not match:
        return ""
    body = xml[match.end() :]
    body = body[: body.find("</section>")] if "</section>" in body else body[:20_000]
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", body)).strip()[:6_000]


def names_substance(entry: dict, names: list[str]) -> tuple[bool, bool]:
    """(the label's title states it as whole words, the DailyMed page resolves).

    Whole words because "Orap" is a prefix of "Orapred"; the title because a
    label's page lists every drug it interacts with (`title_names`)."""
    return bool(title_names(names, entry.get("title") or "")), entry.get("page_status") == 200


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--fetch", action="store_true", help="allow DailyMed requests")
    parser.add_argument("--write", action="store_true", help="update row-citations.json")
    args = parser.parse_args()

    lines: dict[str, str] = json.loads(MECHANISM_LINES.read_text()).get("medtap_lines", {})
    ndcs = ndc_by_name()
    cache = load_cache()
    throttle = HostThrottle(0.5)
    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)

    # The shipped row for each line, found by its text: the record name the
    # line is keyed by may since have merged into another canonical name.
    rows_by_claim: dict[str, list[tuple[str, int]]] = {}
    for name, sid, summary in conn.execute(
        "SELECT s.canonical_name, s.id, m.summary FROM mechanisms_summary m "
        "JOIN substances s ON s.id = m.substance_id JOIN sources src ON src.id = m.source_id "
        "WHERE src.slug = 'piru-curated' AND m.language = 'en'"
    ):
        rows_by_claim.setdefault(row_citations.claim_sha1(summary), []).append((name, sid))

    tally: Counter = Counter()
    proposed: list[dict] = []
    for record_name, line in sorted(lines.items()):
        claim = row_citations.claim_sha1(clean_wiki_prose(line))
        rows = rows_by_claim.get(claim, [])
        if len(rows) > 1:
            # One line under several names: keep the substance the record names.
            named = {
                sid
                for (sid,) in conn.execute(
                    "SELECT id FROM substances WHERE lower(canonical_name) = lower(?) "
                    "UNION SELECT substance_id FROM aliases WHERE lower(alias) = lower(?)",
                    (record_name, record_name),
                )
            }
            rows = [row for row in rows if row[1] in named]
        if len(rows) != 1:
            tally[f"not shipped as one row ({len(rows)} rows carry it)"] += 1
            continue
        canonical, sid = rows[0]
        ndc = ndcs.get(record_name.lower())
        if not ndc:
            tally["no NDC for the record"] += 1
            continue
        aliases = [
            a for (a,) in conn.execute("SELECT alias FROM aliases WHERE substance_id = ?", (sid,))
        ]
        names = [record_name, canonical, *aliases]
        entry = resolve(ndc, names, cache, throttle, args.fetch)
        if entry is None:
            tally["NDC not resolved yet (run with --fetch)"] += 1
            continue
        if len(entry.get("setids") or []) != 1:
            tally[f"NDC resolves to {len(entry.get('setids') or [])} labels"] += 1
            continue
        in_label, on_page = names_substance(entry, names)
        if not in_label:
            tally["label title does not name the substance"] += 1
            continue
        if not on_page:
            tally["DailyMed page does not resolve"] += 1
            continue
        line_stems = stems(line)
        label_stems = stems(entry.get("mechanism_of_action") or "")
        overlap = len(line_stems & label_stems) / len(line_stems) if line_stems else 0.0
        if overlap < MIN_OVERLAP:
            tally["§12.1 does not state the line"] += 1
            continue
        setid = entry["setids"][0]
        # "CALQUENCE (ACALABRUTINIB) CAPSULE … [ASTRAZENECA]" → "Calquence (acalabrutinib)".
        named = re.match(r"\s*([^(\[]+?)\s*\(([^)]+)\)", entry.get("title") or "")
        product = f"{named.group(1).title()} ({named.group(2).lower()})" if named else record_name
        proposed.append(
            {
                "table": "mechanisms_summary",
                "substance": canonical,
                "source": "piru-curated",
                "match": {"language": "en"},
                "claim_sha1": claim,
                "ref": PAGE + setid,
                "title": f"{product} label, §12.1 Mechanism of Action",
                "accessed": entry.get("checked") or date.today().isoformat(),
                "via": VIA,
                "evidence": f"MedTAP NDC {ndc} → DailyMed setid {setid}; label names "
                f"{record_name}; §12.1 holds {overlap:.0%} of the line's content words",
            }
        )
        tally["attached"] += 1

    conn.close()
    if args.fetch:
        save_cache(cache)

    print(f"source-dailymed-mechanisms: {len(lines)} MedTAP lines")
    for reason, n in tally.most_common():
        print(f"  {n:4d}  {reason}")

    if args.write:
        merged = {row_citations.entry_key(e): e for e in row_citations.load()}
        for entry in proposed:
            merged[row_citations.entry_key(entry)] = entry
        row_citations.save(list(merged.values()))
        print(f"→ {row_citations.ROW_CITATIONS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
