"""Single source of truth for InChIKey collision dispositions across the pipeline.

Several same-skeleton (block-1) or same-full-key InChIKey collisions in the
catalog are not accidental: some are distinct drugs whose upstream keys were
corrupted to collide, some are the same drug split across two rows, and some are
legitimate stereoisomer families. Historically these dispositions were tracked
in three drifting places — ``_DO_NOT_MERGE`` and ``_FORCE_MERGE`` in the build,
and the ``_KNOWN_INCHIKEY_DUPS`` allowlist in the overlay-integrity test. This
module unifies them behind one curated registry
(``data/curated/inchikey-collisions.json``). The fold families stay in
``isomer-families.json`` and are referenced there by disposition only.

Each cluster is a set of exact ``canonical_name`` values with a disposition:

* ``distinct`` — different drugs that share (or shared, pre-correction) an
  InChIKey block; the dedup merge must NEVER fuse them.
* ``merge`` — the same drug split across rows; fold every member into ``into``.

Kept stdlib-only and import-light so ``pipeline/build/``, ``pipeline/audit/``,
and the test suite can all import it (via a ``sys.path`` insert of ``pipeline/``).
Consumers: the build's do-not-merge guard and forced-merge pass, the
overlay-integrity test, and (Stage 0.1) PSID FAMILY assignment.
"""

from __future__ import annotations

import json
from itertools import combinations
from pathlib import Path

_REGISTRY = Path(__file__).resolve().parent.parent / "data/curated/inchikey-collisions.json"
_ISOMER_FAMILIES = _REGISTRY.parent / "isomer-families.json"


def load() -> dict:
    """The raw registry (``distinct``/``merge`` lists), metadata keys included."""
    return json.loads(_REGISTRY.read_text())


def fold_families() -> list[dict]:
    """The curated stereoisomer fold families (from isomer-families.json). Each is
    ``{parent, variants:[{name, isomer, ...}]}`` — all members share one FAMILY."""
    return json.loads(_ISOMER_FAMILIES.read_text()).get("families", [])


def distinct_clusters() -> list[list[str]]:
    """Member-name lists for every ``distinct`` cluster (raw canonical names)."""
    return [c["members"] for c in load().get("distinct", [])]


def do_not_merge_pairs() -> list[frozenset[str]]:
    """Every pairwise name combination within a ``distinct`` cluster — the pairs
    the dedup merge must refuse to fuse. Names are RAW canonical; the caller
    normalises (this module stays free of build-layer helpers)."""
    pairs: list[frozenset[str]] = []
    for members in distinct_clusters():
        pairs.extend(frozenset(pair) for pair in combinations(members, 2))
    return pairs


def classify(names) -> str | None:
    """Disposition for a set of canonical names that share an InChIKey block 1:
    ``"fold"`` (one stereoisomer family — share a FAMILY), ``"distinct"`` (different
    drugs — separate FAMILYs), ``"merge"`` (same drug, one should fold into the
    other), or ``None`` when the collision is unclassified. The build's PSID
    FAMILY assignment fails loudly on ``None`` so a corrupt/un-triaged collision
    can never silently merge two drugs into one identity."""
    members = set(names)
    for fam in fold_families():
        family_members = {fam["parent"]} | {v["name"] for v in fam["variants"]}
        if members <= family_members:
            return "fold"
    distinct_pairs = {frozenset(pair) for pair in do_not_merge_pairs()}
    if len(members) >= 2 and all(
        frozenset(pair) in distinct_pairs for pair in combinations(members, 2)
    ):
        return "distinct"
    for cluster in load().get("merge", []):
        if members <= set(cluster["members"]):
            return "merge"
    return None


def force_merge_tuples() -> list[tuple[str, str, bool]]:
    """``(loser, winner, fold_aliases)`` for each ``merge`` cluster — winner is
    the cluster's ``into``, every other member is a loser folded (with aliases)
    into it. Feeds the build's ``_FORCE_MERGE`` list."""
    tuples: list[tuple[str, str, bool]] = []
    for cluster in load().get("merge", []):
        winner = cluster["into"]
        for member in cluster["members"]:
            if member != winner:
                tuples.append((member, winner, True))
    return tuples
