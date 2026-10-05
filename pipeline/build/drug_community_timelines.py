"""Lossless reference timelines; never a source of inferred phase lengths.

The published legacy fields do not declare a shared clock origin. In particular,
start/end are not a license to subtract across phases, and after_effects does not
mean positive afterglow. Study statistics have their own, explicit contract.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path


def canonical_json(value: object) -> str:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    )


def digest(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode()).hexdigest()


def snapshot_binding(path: Path) -> tuple[str, str | None]:
    """A file digest is always available; assert a release only for matching metadata."""
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    meta_path = path.with_suffix(".meta.json")
    if not meta_path.exists():
        return sha, None
    meta = json.loads(meta_path.read_text())
    expected = meta.get("snapshot_sha256")
    if expected is not None and expected != sha:
        raise ValueError("drug.community snapshot does not match its release metadata")
    return sha, meta.get("release_id") if expected == sha else None


def reference_timelines(record: dict, snapshot_sha256: str):
    """Retain each source position, even when route labels or contents repeat.

    record_key is a snapshot-local locator, not an invented upstream curve UUID.
    Original units, route, formulation, nulls, ISO fields and citations stay in
    entry_json. No unit defaults, boundary repairs or numerical projections occur.
    """
    profile_sha = digest(record)
    for collection, representations in (
        ("duration_curves", ("duration_curve", "partial_duration_curve")),
        ("duration_studies", ("duration_study",)),
    ):
        for index, entry in enumerate(record.get(collection) or []):
            if not isinstance(entry, dict):
                raise ValueError(
                    f"{record.get('drug_name')}: {collection}[{index}] is not an object"
                )
            kinds = (
                representations
                if collection == "duration_studies"
                else tuple(key for key in representations if isinstance(entry.get(key), dict))
            )
            if not kinds:
                raise ValueError(f"{record.get('drug_name')}: unrecognized {collection}[{index}]")
            for kind in kinds:
                context = entry.get("context") or {}
                yield {
                    "record_key": digest(
                        [snapshot_sha256, record["drug_name"], collection, index, kind]
                    ),
                    "source_name": record["drug_name"],
                    "route": context.get("route")
                    if kind == "duration_study"
                    else entry.get("method"),
                    "kind": kind,
                    "entry_index": index,
                    "entry_json": canonical_json(entry),
                    "duration_text_json": canonical_json(record.get("duration") or {}),
                    "citations_json": canonical_json(record.get("citations") or []),
                    "profile_sha256": profile_sha,
                    "snapshot_sha256": snapshot_sha256,
                }
