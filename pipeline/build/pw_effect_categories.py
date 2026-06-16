"""Canonical PsychonautWiki Subjective Effect Index → category mapping.

This module is reference data for the Piru substance data pipeline. The bundled
substance DB's ``effects`` table mixes the real PsychonautWiki (PW) subjective
effect taxonomy with substance-summary prose and dose-report fragments. This map
is used as a **whitelist + categorizer**: an effect string survives only if its
normalized form is a known PW effect, and it is grouped under the mapped
category.

The category set is PW's top-level grouping. Every value in
``PW_EFFECT_CATEGORY`` is one of:

    Sensory, Visual, Auditory, Tactile, Smell and taste, Multisensory,
    Cognitive, Physical, Transpersonal, Disconnective

The keys are ``normalize_effect(canonical_name)`` for the *full* canonical PW
subjective effect index (~220 effects), not merely those present in any one
corpus, so the map stays useful as data grows.
"""

from __future__ import annotations

import re

__all__ = [
    "normalize_effect",
    "PW_EFFECT_CATEGORY",
    "CATEGORY_ORDER",
]

_WHITESPACE_RE = re.compile(r"\s+")


def normalize_effect(s: str) -> str:
    """Normalize an effect string for whitelist lookup.

    Lowercases, strips surrounding whitespace, collapses internal runs of
    whitespace to a single space, and strips a single trailing period. Commas
    and hyphens are preserved (they are semantically meaningful in canonical PW
    effect names, e.g. "Empathy, love, and sociability enhancement").
    """
    s = s.strip().lower()
    s = _WHITESPACE_RE.sub(" ", s)
    if s.endswith("."):
        s = s[:-1]
    return s


# ---------------------------------------------------------------------------
# Canonical PsychonautWiki Subjective Effect Index.
#
# Organized by category for authoring/review clarity; flattened into
# PW_EFFECT_CATEGORY below. Source effect names use PW's spellings (e.g.
# "Colour", "Synaesthesia"). Common spelling variants are added afterwards so
# the corpus's mixed orthography still matches.
# ---------------------------------------------------------------------------

_PHYSICAL = [
    # Cardiovascular
    "Increased heart rate",
    "Decreased heart rate",
    "Abnormal heartbeat",
    "Increased blood pressure",
    "Decreased blood pressure",
    "Blood pressure elevation",
    "Vasoconstriction",
    "Vasodilation",
    "Cerebral vasodilation",
    # Pupils / eyes
    "Pupil dilation",
    "Pupil constriction",
    "Watery eyes",
    "Photophobia",
    # Gastrointestinal
    "Nausea",
    "Nausea suppression",
    "Vomiting",
    "Constipation",
    "Diarrhea",
    "Stomach bloating",
    "Stomach cramps",
    "Stomach pain",
    "Increased salivation",
    "Salivation",
    "Dry mouth",
    "Increased appetite",
    "Appetite enhancement",
    "Appetite suppression",
    "Decreased appetite",
    "Dehydration",
    "Increased thirst",
    # Respiratory / nasal
    "Respiratory depression",
    "Bronchodilation",
    "Bronchoconstriction",
    "Cough suppression",
    "Runny nose",
    "Nasal congestion",
    "Excessive yawning",
    "Difficulty breathing",
    # Sedation / stimulation / energy
    "Sedation",
    "Stimulation",
    "Wakefulness",
    "Physical fatigue",
    "Physical euphoria",
    "Physical dysphoria",
    "Stamina enhancement",
    "Rejuvenation",
    "Restless leg syndrome",
    # Muscular / motor
    "Muscle relaxation",
    "Muscle contractions",
    "Muscle cramps",
    "Muscle spasms",
    "Muscle tension",
    "Muscle twitching",
    "Motor control loss",
    "Difficulty urinating",
    "Frequent urination",
    "Increased bodily temperature",
    "Decreased bodily temperature",
    "Temperature regulation suppression",
    # Skin / surface
    "Increased perspiration",
    "Decreased perspiration",
    "Skin flushing",
    "Itchiness",
    "Skin tingling",
    "Goosebumps",
    "Body odor alteration",
    # Sexual
    "Increased libido",
    "Decreased libido",
    "Temporary erectile dysfunction",
    "Orgasm enhancement",
    "Orgasm suppression",
    "Spontaneous orgasm",
    # Head / neuro physical
    "Headaches",
    "Dizziness",
    "Seizure",
    "Seizure suppression",
    "Pain relief",
    "Analgesia",
    "Increased pain perception",
    "Teeth grinding",
    "Mouth numbing",
    "Sublingual numbing",
    "Inner ear pressure",
    "Bodily pressures",
    "Bodily vibrations",
    "Bodily heaviness",
    "Bodily lightness",
    "Perception of decreased weight",
    "Perception of increased weight",
    "Difficulty swallowing",
]

_COGNITIVE = [
    # Mood / affect
    "Anxiety",
    "Anxiety suppression",
    "Cognitive euphoria",
    "Cognitive dysphoria",
    "Depression",
    "Emotion enhancement",
    "Emotion suppression",
    "Empathy, love, and sociability enhancement",
    "Empathy, love and sociability suppression",
    "Irritability",
    "Mania",
    "Paranoia",
    "Panic attacks",
    "Simultaneous emotions",
    "Laughter",
    "Existential self-realization",
    # Thought
    "Analysis enhancement",
    "Analysis suppression",
    "Conceptual thinking",
    "Thought acceleration",
    "Thought deceleration",
    "Thought connectivity",
    "Thought disorganization",
    "Thought organization",
    "Thought loops",
    "Thought suppression",
    "Multiple thought streams",
    "Cognitive fatigue",
    "Information processing acceleration",
    "Information processing suppression",
    "Language suppression",
    "Memory enhancement",
    "Memory suppression",
    "Amnesia",
    "Déjà vu",
    "Jamais vu",
    "Creativity enhancement",
    "Creativity suppression",
    "Novelty enhancement",
    "Pattern recognition enhancement",
    "Pattern recognition suppression",
    "Suggestibility enhancement",
    "Suggestibility suppression",
    "Personal bias suppression",
    "Personal meaning enhancement",
    "Conceptual thinking",
    "Subconscious communication",
    "Mindfulness",
    # Focus / motivation / drive
    "Focus enhancement",
    "Focus suppression",
    "Motivation enhancement",
    "Motivation suppression",
    "Immersion enhancement",
    "Compulsive redosing",
    "Disinhibition",
    "Increased music appreciation",
    "Increased sense of humor",
    # Self / ego
    "Ego inflation",
    "Ego replacement",
    "Personality regression",
    "Catharsis",
    "Identity alteration",
    "Perception of self-design",
    "Feelings of self-design",
    # Perceptual / dream
    "Time distortion",
    "Dream potentiation",
    "Dream suppression",
    "Sleep paralysis",
    "Delusions",
    "Delusion",
    "Psychosis",
    "Mania",
    "Confusion",
    "Perspective alterations",
    "Perspective distortions",
    "Memory replays",
    "Spatial disorientation",
]

_VISUAL = [
    # Enhancements
    "Colour enhancement",
    "Pattern recognition enhancement",
    "Visual acuity enhancement",
    "Acuity enhancement",
    "Acuity suppression",
    "Magnification",
    "Brightness alteration",
    "Frame rate enhancement",
    "Frame rate suppression",
    # Distortions
    "Colour shifting",
    "Colour replacement",
    "Colour tinting",
    "Depth perception distortions",
    "Diffraction",
    "Drifting",
    "After images",
    "Tracers",
    "Visual haze",
    "Visual sliding",
    "Vibrating vision",
    "Double vision",
    "Recursion",
    "Scenery slicing",
    "Symmetrical texture repetition",
    "Environmental cubism",
    "Environmental orbism",
    "Peripheral information misinterpretation",
    "Visual stretching",
    "Visual flipping",
    # Geometry
    "Geometry",
    # Hallucinatory states
    "Internal hallucinations",
    "External hallucinations",
    "Hallucinations",
    "Transformations",
    "Autonomous entities",
    "Settings, sceneries, and landscapes",
    "Scenarios and plots",
    "Machinescapes",
    "Shadow people",
    "Unspeakable horrors",
    "Perspective distortions",
    "Object alteration",
    "Object activation",
    "Object multiplication",
    "Texture liquidation",
    "Texture repetition",
    "Aura vision",
]

_AUDITORY = [
    "Auditory enhancement",
    "Auditory suppression",
    "Auditory distortion",
    "Auditory hallucinations",
    "Auditory misinterpretation",
]

_TACTILE = [
    "Tactile enhancement",
    "Tactile suppression",
    "Tactile hallucinations",
    "Spontaneous tactile sensations",
    "Bodily control enhancement",
    "Physical autonomy",
    "Changes in felt bodily form",
    "Changes in gravity",
    "Gravity perception alteration",
]

_SMELL_TASTE = [
    "Smell enhancement",
    "Smell suppression",
    "Smell hallucination",
    "Olfactory hallucination",
    "Taste enhancement",
    "Taste suppression",
    "Gustatory hallucination",
    "Gustatory enhancement",
    "Gustatory suppression",
]

_MULTISENSORY = [
    "Synaesthesia",
    "Synesthesia",
    "Multisensory enhancement",
]

_SENSORY = [
    "Sensory enhancement",
    "Sensory suppression",
    "Stimulation suppression",
    "Enhancement and suppression cycles",
]

_TRANSPERSONAL = [
    "Spirituality enhancement",
    "Unity and interconnectedness",
    "Existential realization",
    "Existential self-realization",
    "Feelings of eternalism",
    "Feelings of impending doom",
    "Feelings of predeterminism",
    "Feelings of interdependent opposites",
    "Feelings of self-design",
    "Perception of eternalism",
    "Perception of interdependent opposites",
    "Perception of predeterminism",
    "Perception of self-design",
    "Catharsis",
    "Mindfulness",
]

_DISCONNECTIVE = [
    "Derealization",
    "Depersonalization",
    "Consciousness disconnection",
    "Ego death",
    "Ego dissolution",
    "Visual disconnection",
    "Auditory disconnection",
    "Tactile disconnection",
    "Cognitive disconnection",
    "Sensory disconnection",
    "Spatial disconnection",
]


def _build() -> dict[str, str]:
    groups: list[tuple[list[str], str]] = [
        (_PHYSICAL, "Physical"),
        (_COGNITIVE, "Cognitive"),
        (_VISUAL, "Visual"),
        (_AUDITORY, "Auditory"),
        (_TACTILE, "Tactile"),
        (_SMELL_TASTE, "Smell and taste"),
        (_MULTISENSORY, "Multisensory"),
        (_SENSORY, "Sensory"),
        (_TRANSPERSONAL, "Transpersonal"),
        (_DISCONNECTIVE, "Disconnective"),
    ]
    out: dict[str, str] = {}
    # Earlier groups win on conflict (e.g. duplicates across lists), which is
    # why the primary-modality lists precede the cross-cutting ones.
    for names, category in groups:
        for name in names:
            key = normalize_effect(name)
            out.setdefault(key, category)
    return out


PW_EFFECT_CATEGORY: dict[str, str] = _build()


# Corpus-orthography aliases: variants whose normalized form differs from the
# canonical key but denote the same PW effect. Each maps to the same category.
_ALIASES: dict[str, str] = {
    "colour enhancement": "Visual",
    "color enhancement": "Visual",
    "color shifting": "Visual",
    "color replacement": "Visual",
    "colour replacement": "Visual",
    "colour shifting": "Visual",
    "cognitive amplification": "Cognitive",
    "emotional amplification": "Cognitive",
    "exposure to inner mechanics of consciousness": "Visual",
    "exposure to semantic concept network": "Visual",
}
for _k, _v in _ALIASES.items():
    PW_EFFECT_CATEGORY.setdefault(normalize_effect(_k), _v)


CATEGORY_ORDER: list[str] = [
    "Physical",
    "Cognitive",
    "Visual",
    "Auditory",
    "Tactile",
    "Multisensory",
    "Sensory",
    "Smell and taste",
    "Transpersonal",
    "Disconnective",
]

# Sanity: every value uses an allowed category string.
assert set(PW_EFFECT_CATEGORY.values()) <= set(CATEGORY_ORDER), (
    "category value outside CATEGORY_ORDER"
)


if __name__ == "__main__":
    import sys

    path = "/tmp/tripsit_effects.txt"
    try:
        with open(path, encoding="utf-8") as fh:
            raw_lines = [ln.rstrip("\n") for ln in fh]
    except FileNotFoundError as err:
        print(f"corpus not found: {path}", file=sys.stderr)
        raise SystemExit(1) from err

    distinct = sorted({ln for ln in raw_lines if ln.strip()})
    mapped: list[str] = []
    unmapped: list[str] = []
    for line in distinct:
        if normalize_effect(line) in PW_EFFECT_CATEGORY:
            mapped.append(line)
        else:
            unmapped.append(line)

    print(f"PW_EFFECT_CATEGORY keys: {len(PW_EFFECT_CATEGORY)}")
    print(f"distinct corpus lines:   {len(distinct)}")
    print(f"  mapped:   {len(mapped)}")
    print(f"  unmapped: {len(unmapped)}")
    print()

    def _is_short_termlike(s: str) -> bool:
        if len(s) > 45:
            return False
        # Reject lines with a sentence-style mid-string period ("X. Y").
        body = s[:-1] if s.endswith(".") else s
        return "." not in body

    short_unmapped = sorted(s for s in unmapped if _is_short_termlike(s))
    print(f"SHORT unmapped lines (≤ 45 chars, no mid-string period): {len(short_unmapped)}")
    for s in short_unmapped:
        print(f"  - {s}")
