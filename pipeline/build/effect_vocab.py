"""Controlled effect vocabulary — Track 1 of the substance-data-hardening
localization workstream (Stage 2).

The high-leverage localization win: instead of translating "Anxiety" once per
occurrence across hundreds of substances, there is ONE canonical effect
(``vocab_id``) with one translated label set, and every raw ``effects.text``
points at it via ``effects.vocab_id``. A zh user then sees translated effects on
*every* substance — even ones whose source data was English-only.

This module derives the canonical, slug-keyed vocabulary from the PsychonautWiki
SEI whitelist in ``pw_effect_categories.py`` (the single source for English
labels + categories — no drift) and loads curated zh-Hans/zh-Hant labels from
``effect_vocab_zh.json``. ``sqlite.py`` seeds the ``effect_vocab`` +
``effect_vocab_labels`` tables from ``EFFECT_VOCAB`` / ``vocab_labels()`` and
stamps each raw ``effects.text`` with ``vocab_id_for(text)``.

Matching is deterministic, NOT fuzzy: ``add_effect`` already whitelists every
effect string against the PW taxonomy (``PW_EFFECT_CATEGORY``), so the rows in
``effects`` are exact canonical PW names. ``vocab_id_for`` therefore only has to
normalize + resolve a handful of orthography variants — no risky auto-merge of
distinct effects (spec open-question 2a is avoided by construction). A string
that doesn't resolve returns ``None``; the raw ``text`` stays as the fallback.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from pw_effect_categories import CANONICAL_EFFECTS, normalize_effect

__all__ = [
    "EFFECT_VOCAB",
    "slugify",
    "vocab_id_for",
    "vocab_labels",
    "LANGUAGES",
]

LANGUAGES = ("en", "zh-Hans", "zh-Hant")

_ZH_PATH = Path(__file__).resolve().parent / "effect_vocab_zh.json"

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def slugify(name: str) -> str:
    """Stable slug for a canonical effect name (the ``vocab_id``).

    Lowercase; every run of non-alphanumeric characters becomes a single
    underscore; leading/trailing underscores stripped. e.g.
    "Empathy, love, and sociability enhancement" -> "empathy_love_and_sociability_enhancement".
    """
    return _SLUG_RE.sub("_", name.strip().lower()).strip("_")


# vocab_id -> (en_label, category). Built from the canonical PW list; first-wins
# dedup is already applied by CANONICAL_EFFECTS, so distinct slugs collide only
# if two canonical names slugify identically (asserted against below).
EFFECT_VOCAB: dict[str, tuple[str, str]] = {}
for _name, _category in CANONICAL_EFFECTS:
    _vid = slugify(_name)
    if _vid not in EFFECT_VOCAB:
        EFFECT_VOCAB[_vid] = (_name, _category)


# Orthography variants whose normalized form differs from a canonical name but
# denote the SAME effect — they must collapse to one vocab_id (American vs.
# British spelling, singular/plural the corpus uses inconsistently). Maps a
# normalized variant -> the normalized canonical name it aliases. Kept small and
# explicit (reviewable); these are spelling collapses, never semantic merges.
_ORTHOGRAPHY_ALIASES: dict[str, str] = {
    "color enhancement": "colour enhancement",
    "color shifting": "colour shifting",
    "color replacement": "colour replacement",
    "color tinting": "colour tinting",
    "synesthesia": "synaesthesia",
    "delusion": "delusions",
    "internal hallucination": "internal hallucinations",
    "external hallucination": "external hallucinations",
    "hallucination": "hallucinations",
    "transformation": "transformations",
    "headache": "headaches",
    "stomach cramp": "stomach cramps",
    "muscle cramp": "muscle cramps",
    "muscle spasm": "muscle spasms",
    "tracer": "tracers",
    "after image": "after images",
    "thought loop": "thought loops",
    "panic attack": "panic attacks",
    "emotional amplification": "emotion enhancement",
}


def _build_text_index() -> dict[str, str]:
    idx: dict[str, str] = {}
    # Canonical names map directly to their own slug.
    for name, _category in CANONICAL_EFFECTS:
        idx[normalize_effect(name)] = slugify(name)
    # Orthography variants map to the canonical's slug (resolve the target's
    # normalized form against the canonical index).
    for variant, canonical in _ORTHOGRAPHY_ALIASES.items():
        target = idx.get(normalize_effect(canonical))
        if target is not None:
            idx[normalize_effect(variant)] = target
    return idx


_TEXT_TO_VOCAB: dict[str, str] = _build_text_index()


def vocab_id_for(text: str) -> str | None:
    """Resolve a raw ``effects.text`` to a canonical ``vocab_id``, or ``None``.

    ``None`` means no canonical match — the caller keeps the raw text as the
    localized fallback (no-silent-caps).
    """
    if not text:
        return None
    return _TEXT_TO_VOCAB.get(normalize_effect(text))


def _load_zh() -> tuple[dict[str, dict[str, str]], dict[str, int]]:
    """Return ``(labels, mt_flags)`` from the curated JSON.

    ``labels``: vocab_id -> {'zh-Hans': label, 'zh-Hant': label}.
    ``mt_flags``: language -> machine_translated default (zh-Hans curated=0,
    zh-Hant OpenCC-converted=1). Missing file/entries are tolerated — those
    vocab_ids ship en-only and the app falls back to English (honest partial
    coverage, never a fabricated label).
    """
    if not _ZH_PATH.exists():
        return {}, {}
    raw = json.loads(_ZH_PATH.read_text(encoding="utf-8"))
    labels = raw.get("labels", raw)
    mt = (raw.get("_meta") or {}).get("machine_translated") or {}
    return labels, mt


_ZH_LABELS, _ZH_MT = _load_zh()


def vocab_labels() -> list[tuple[str, str, str, int]]:
    """Flatten the vocabulary into ``(vocab_id, language, label, machine_translated)``
    rows for seeding ``effect_vocab_labels``.

    English labels are always emitted (canonical, machine_translated=0). zh-Hans
    (reviewed against FreeODwiki's native 药效) and zh-Hant (OpenCC-converted) are
    emitted only where the curated JSON supplies them, each carrying the
    machine_translated default declared in the JSON's ``_meta``.
    """
    rows: list[tuple[str, str, str, int]] = []
    for vid, (en_label, _category) in EFFECT_VOCAB.items():
        rows.append((vid, "en", en_label, 0))
        zh = _ZH_LABELS.get(vid) or {}
        for lang in ("zh-Hans", "zh-Hant"):
            label = zh.get(lang)
            if label:
                rows.append((vid, lang, label, int(_ZH_MT.get(lang, 0))))
    return rows


# Integrity: no two canonical names collapse to the same slug with different
# English labels (would silently lose one effect).
assert len({slugify(n) for n, _ in CANONICAL_EFFECTS}) == len(EFFECT_VOCAB), (
    "slug collision between distinct canonical effects"
)
