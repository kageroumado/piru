"""Transforms for the drug.community *experiential* datasets (intensity spectra +
reported effects) into the flat rows Piru's bundled SQLite stores.

These enhance only the inherently-experiential Effects surface — never the vetted
science cards. We take dc's structured signals (effect **frequency**, per-effect
**dose-intensity / emergence band**, **domain** grouping, real report **quotes**)
and deliberately drop dc's unreliable prose (harm-reduction/warning claims,
tolerance) — see the ``drug-community-data-trust`` project note.

Two producers, both keyed on the drug.community canonical slug:

- :func:`spectrum_levels` — one row per dose band (dc's 6 fixed levels mapped onto
  Piru's dose-band vocabulary), carrying the band description, the top reported
  effects *with their frequencies*, and generic safety warnings for the high bands.
- :func:`reported_effects` — one row per effect, merging the spectrum's frequency +
  emergence band with dc's per-effect domain and a representative quote.

Kept dependency-free and pure so it is unit-testable in isolation.
"""

from __future__ import annotations

import re

# dc always emits these six intensity levels (verified: 162/162 spectra identical),
# mapped onto Piru's dose-band vocabulary. "Extreme" becomes the Overdose band.
BAND_NAMES = ["Threshold", "Light", "Common", "Strong", "Heavy", "Overdose"]
_DC_LEVEL_TO_BAND = {
    "threshold": 0,
    "light": 1,
    "moderate": 2,
    "common": 2,
    "strong": 3,
    "intense": 4,
    "heavy": 4,
    "extreme": 5,
    "overdose": 5,
}

# dc tags effects with 21 fine-grained domains; fold them into the 5 UI groups
# (ordered by how prominently they read on a substance card).
DOMAIN_ORDER = ["Emotional", "Cognitive", "Sensory", "Physical", "Social"]
_DOMAIN_BUCKET = {
    "emotional": "Emotional",
    "cognitive": "Cognitive",
    "selfhood": "Cognitive",
    "spiritual": "Cognitive",
    "temporal": "Cognitive",
    "world-experience": "Cognitive",
    "interoceptive": "Cognitive",
    "visual": "Sensory",
    "auditory": "Sensory",
    "synesthetic": "Sensory",
    "gustatory": "Sensory",
    "olfactory": "Sensory",
    "somatic": "Physical",
    "gastrointestinal": "Physical",
    "motor": "Physical",
    "sexual": "Physical",
    "tactile": "Physical",
    "sleep": "Physical",
    "vestibular": "Physical",
    "spatial": "Physical",
    "social": "Social",
}

_WS = re.compile(r"[^a-z0-9]+")

# Last-resort domain guess for spectrum-only effects that carry no erowid domain
# and don't appear in a level's physical/psychological list. Ordered; first hit wins.
_KEYWORD_DOMAIN = [
    ("Social", ("social", "sociab", "talkativ", "communicat", "connection", "empath", "bonding")),
    (
        "Emotional",
        (
            "euphor",
            "mood",
            "happy",
            "bliss",
            "well-being",
            "anxiet",
            "paranoi",
            "fear",
            "panic",
            "crav",
            "dysphor",
            "depress",
            "invincib",
            "content",
            "warmth",
            "love",
        ),
    ),
    (
        "Cognitive",
        (
            "focus",
            "thought",
            "confidence",
            "motivat",
            "redos",
            "attention",
            "clarity",
            "concentrat",
            "time",
            "perception",
            "insight",
            "ego",
            "risk-tak",
            "vigilan",
            "judgment",
            "psychos",
            "confus",
            "delusion",
            "consciousness",
        ),
    ),
    ("Sensory", ("visual", "auditory", "hallucin", "sight", "sound", "color", "colour")),
]


def _keyword_domain(name: str) -> str:
    low = (name or "").lower()
    for domain, keys in _KEYWORD_DOMAIN:
        if any(k in low for k in keys):
            return domain
    return "Physical"


def _norm(name: str) -> str:
    """Loose normalization for cross-dataset name matching."""
    n = _WS.sub(" ", (name or "").lower()).strip()
    # collapse a few common variants so spectrum ↔ effect names line up
    n = n.replace("increased ", "").replace("enhanced ", "").replace("↑ ", "")
    return n


def domain_bucket(dc_domain: str | None) -> str:
    return _DOMAIN_BUCKET.get((dc_domain or "").lower(), "Physical")


def band_index(level_name: str, number: int | None = None) -> int:
    b = _DC_LEVEL_TO_BAND.get((level_name or "").lower())
    if b is not None:
        return b
    # fall back to the level number (1-based) clamped to 0..5
    if number:
        return max(0, min(5, int(number) - 1))
    return 2


def spectrum_levels(spectrum_data: dict) -> list[dict]:
    """Flatten a dc ``spectrum_data`` into one dict per dose band.

    Only structured, defensible content is kept: the band description, the top
    reported effects with frequencies (drives the dial's bars), and *generic*
    safety warnings for the two highest bands. dc's per-level durations are
    dropped — Piru's Dose & Duration card is the authority there.
    """
    out: list[dict] = []
    for lvl in spectrum_data.get("levels") or []:
        bi = band_index(lvl.get("name", ""), lvl.get("number"))
        common = [
            {"name": e.get("name", "").strip(), "freq": int(e.get("frequency") or 0)}
            for e in (lvl.get("commonEffects") or [])
            if e.get("name")
        ]
        common.sort(key=lambda e: -e["freq"])
        warnings = [w for w in (lvl.get("warnings") or []) if isinstance(w, str)]
        out.append(
            {
                "band_index": bi,
                "band_name": BAND_NAMES[bi],
                "description": (lvl.get("description") or "").strip(),
                "top_effects": common,
                "physical": [s for s in (lvl.get("physicalEffects") or []) if isinstance(s, str)],
                "psychological": [
                    s for s in (lvl.get("psychologicalEffects") or []) if isinstance(s, str)
                ],
                "warnings": warnings,
            }
        )
    out.sort(key=lambda r: r["band_index"])
    return out


def reported_effects(drug_effects_rec: dict | None, spectrum_data: dict | None) -> list[dict]:
    """Merge dc's reported effects into one enriched row per effect.

    Frequency and emergence band come from the intensity **spectrum** (large,
    consistent report counts; precise dose-dependence). The **domain** comes from
    the erowid-tagged ``drugEffects`` record where available, else a keyword guess.
    Effects present in only one source are still emitted. We deliberately do NOT
    carry dc's per-effect erowid quotes — first-hand reports come from FreeODWiki
    at the section level instead (native source; never machine-translated).
    """
    # 1. spectrum → {norm name: (max freq, lowest band index, raw name, phys?/psych?)}
    spec: dict[str, dict] = {}
    phys_norms: set[str] = set()
    psych_norms: set[str] = set()
    for lvl in spectrum_levels(spectrum_data or {}):
        for s in lvl["physical"]:
            phys_norms.add(_norm(s))
        for s in lvl["psychological"]:
            psych_norms.add(_norm(s))
        for e in lvl["top_effects"]:
            key = _norm(e["name"])
            if not key:
                continue
            cur = spec.get(key)
            if cur is None:
                spec[key] = {"name": e["name"], "freq": e["freq"], "band": lvl["band_index"]}
            else:
                cur["freq"] = max(cur["freq"], e["freq"])
                cur["band"] = min(cur["band"], lvl["band_index"])

    # 2. dc effects → {norm name: {domain, count, raw name}} (used only for the domain)
    de: dict[str, dict] = {}
    for e in (drug_effects_rec or {}).get("effects") or []:
        key = _norm(e.get("effect", ""))
        if not key:
            continue
        de.setdefault(
            key,
            {
                "name": e.get("effect", "").strip(),
                "domain": domain_bucket(e.get("domain")),
                "count": int(e.get("count") or 0),
            },
        )

    # 3. union
    rows: list[dict] = []
    for key in set(spec) | set(de):
        s = spec.get(key)
        d = de.get(key)
        name = (d or s)["name"]
        freq = s["freq"] if s else d["count"]
        band = s["band"] if s else None
        if d:
            domain = d["domain"]
        elif key in psych_norms:
            domain = "Cognitive"
        elif key in phys_norms:
            domain = "Physical"
        else:
            domain = _keyword_domain(name)
        rows.append(
            {
                "name": name,
                "domain": domain,
                "report_count": freq,
                "emerges_band": band,
            }
        )

    rows.sort(key=lambda r: (-r["report_count"], r["name"].lower()))
    return rows
