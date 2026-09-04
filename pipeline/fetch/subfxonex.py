#!/usr/bin/env python3
"""Fetch one SubFxOnEx ontology release and save it as the bundled snapshot the
SQLite build ingests into `subjective_effect_concepts` +
`subjective_effect_concept_aliases`.

SubFxOnEx (https://github.com/Di-lemma/SubFxOnEx, LGPL-2.1) is the bottom-up
subjective-effects ontology behind drug.community's effect parser, built from
Erowid report corpora. Piru uses it as the descriptor vocabulary on session
notes: the 21 rollups are the chip groups, the 485 atomic concepts are the
chips, and the 1,178 aliases feed the chip search.

The snapshot is the release file **verbatim** (the license asks that the data
ship unmodified in shape); the build reads only the `concepts` and `aliases`
keys. Re-run with a new release URL when one lands — the release hash is part
of the URL, so this script pins exactly one version and `subfxonex.meta.json`
records which.

Usage:
    python3 pipeline/fetch/subfxonex.py            # fetch the pinned release
    python3 pipeline/fetch/subfxonex.py <url>      # fetch a different release
"""

from __future__ import annotations

import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from urllib import request as urlrequest

RELEASE_URL = (
    "https://raw.githubusercontent.com/Di-lemma/SubFxOnEx/main/ontology_releases/"
    "subjective-effects-a6c48eee78d163113b37585e6cbaf2974ccf55953dbef902817503f2d732ea72.json"
)
REPO_URL = "https://github.com/Di-lemma/SubFxOnEx"
OUTPUT = Path(__file__).resolve().parents[2] / "data" / "sources" / "subfxonex.json"
META = OUTPUT.with_suffix(".meta.json")


def fetch(url: str) -> dict:
    req = urlrequest.Request(url, headers={"User-Agent": "piru-subfxonex-snapshot/1.0"})
    with urlrequest.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read())


def main() -> int:
    url = sys.argv[1] if len(sys.argv) > 1 else RELEASE_URL
    data = fetch(url)
    concepts = data.get("concepts") or []
    aliases = data.get("aliases") or []
    if not concepts or not aliases:
        print(
            "SubFxOnEx release has no concepts/aliases — refusing to overwrite the snapshot",
            file=sys.stderr,
        )
        return 1

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(data, indent=2, ensure_ascii=False, sort_keys=True) + "\n")
    META.write_text(
        json.dumps(
            {
                "source": "SubFxOnEx (drug.community) subjective-effects ontology release",
                "repo": REPO_URL,
                "url": url,
                "license": "LGPL-2.1",
                "release_hash": data.get("release_hash"),
                "fetched_at": datetime.now(UTC).isoformat(timespec="seconds"),
                "concept_count": len(concepts),
                "rollup_count": sum(1 for c in concepts if c.get("kind") == "rollup"),
                "alias_count": len(aliases),
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Saved {len(concepts)} concepts / {len(aliases)} aliases → {OUTPUT}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
