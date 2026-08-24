"""Cleaning wiki prose down to what a reader should see.

PsychonautWiki and FreeOD Wiki are written as encyclopedia articles, and three
kinds of thing come along with the sentences that carry the substance:

- **The wiki's own scaffolding** — reference markers, `[citation needed]`, and
  the "Main article: X" line that heads a section. They point at a page and a
  bibliography the app does not ship, so they render as noise.
- **A closing exhortation.** PW ends most research-chemical articles with a
  variant of "It is highly advised to use harm reduction practices if using this
  substance." It is advice, not reference; it says nothing about the substance;
  and the phrase is the one this project's voice rule names outright, because it
  implies the reader is guilty of something needing reducing.

Everything here is a literal pattern with a test. Nothing paraphrases, and a
sentence that carries any substance content keeps that content — the advisory
clause is trimmed off the end rather than the whole sentence being dropped.
"""

from __future__ import annotations

import re

__all__ = [
    "americanize",
    "clean_wiki_prose",
    "strip_advice",
    "enforce_voice",
    "clean_label_prose",
    "BANNED_PHRASE",
]

#: `[[5]](#cite_note-Ettrup2011-5)`, `[10](#cite_note-10)`, and the bare `](#cite…)`
#: tail left when only half of one survived an earlier pass.
_CITE_LINK = re.compile(r"\[{1,2}\d+(?:,\s*\d+)*\]{1,2}\((?:#cite|https?://[^)]*#cite)[^)]*\)")

#: A bare wiki reference marker: `[2]`, `[12]`, `[3,4]`. Deliberately does NOT
#: match a locant set inside a systematic name (`[1,2,4]triazolo`, `[4,3-a]`),
#: which is a chemical name and not a citation.
_BARE_MARKER = re.compile(r"\s*\[\d+(?:,\s*\d+)*\](?![-a-zA-Z0-9])")

_EDITORIAL_TAG = re.compile(
    r"\[\s*(?:需要引用|citation needed|edit|编辑|来源请求)\s*\]", re.IGNORECASE
)

#: A section's cross-reference header, on its own line.
_XREF_LINE = re.compile(
    "^[ \\t]*(?:更多信息|另见|参见|Main article|See also|Further information)\\s*[:\uff1a][^\\n]*$",
    re.MULTILINE,
)

#: Words that turn a mention of the practice into an instruction to follow it.
#: A sentence naming harm reduction *without* one of these is describing
#: something (a source, a route preference) rather than telling the reader what
#: to do, and is left alone.
_ADVISORY = re.compile(
    r"\b(advised|advisable|recommend(?:ed)?|encouraged|suggested|urged|warranted|"
    r"necessary|should be followed|must be)\b",
    re.IGNORECASE,
)

_HARM_REDUCTION = re.compile(r"harm[- ]reduction", re.IGNORECASE)

#: Sentence boundary that keeps its terminator and does not split on a decimal
#: point or an abbreviation followed by a lowercase word.
_SENTENCE = re.compile(r"[^.!?。！？]*[.!?。！？]+[\s]*|[^.!?。！？]+$")


def _is_advice(sentence: str) -> bool:
    return bool(_HARM_REDUCTION.search(sentence) and _ADVISORY.search(sentence))


_MULTISPACE = re.compile(r"[ \t]{2,}")
_MULTINEWLINE = re.compile(r"\n{3,}")


#: A sentence addressed to whoever is curating the data rather than to whoever
#: is reading the app. The enrichment passes that produced the deep-pharmacology
#: tables left these inline — "MISCATEGORIZED: …", "See deliriants enrichment
#: file.", "Recategorize as Psychedelic." — and they shipped to the screen.
#: `[sz]` throughout: the enrichment files are written in British English and
#: `americanize` runs later in the build, so a matcher that only knows -ize
#: never sees these strings — which is how "miscategorised" survived a pass
#: written to remove exactly it.
_CURATOR_NOTE = re.compile(
    r"\b(?:miscategori[sz]|misclassif|recategori[sz]|reassign(?:ing|ed)?\b|"
    r"enrichment file|for proper enrichment|recommend reassigning|"
    r"\bTODO\b|\bFIXME\b|this group\b|\bhere\b\s*[.,;]|needs? review)",
    re.IGNORECASE,
)


def strip_curator_notes(text: str) -> str:
    """`text` with the sentences aimed at the curator removed.

    Sentence-level, like ``strip_advice``: a note is usually one sentence among
    real pharmacology ("… STIMULANT, miscategorized here. See stimulants-DAT
    -inhibitors enrichment file. Pharmacology similar to methylphenidate …"),
    and cutting the whole string would throw away the third sentence with the
    first two. Returns "" when every sentence was a note, which the caller reads
    as "drop the row".
    """
    kept = [x for x in _SENTENCE.findall(text or "") if not _CURATOR_NOTE.search(x)]
    return "".join(kept).strip()


def strip_advice(text: str) -> str:
    """`text` with the closing harm-reduction exhortation removed.

    Sentence-level, because the clause turns up after a period, after a newline,
    and after a comma, and one regex spanning all three either misses cases or
    eats the sentence in front of them. A sentence that is only the exhortation
    goes entirely; one that opens with substance content is cut at the comma and
    keeps that content.
    """
    kept: list[str] = []
    for sentence in _SENTENCE.findall(text):
        if not _is_advice(sentence):
            kept.append(sentence)
            continue
        # Salvage a leading clause: everything before the comma that introduces
        # the advice, when there is enough of it to be a statement on its own.
        head = ""
        for match in re.finditer(r",\s*", sentence):
            before, after = sentence[: match.start()], sentence[match.end() :]
            if _is_advice(after) and len(before.strip()) >= 30 and not _is_advice(before):
                head = before.strip()
                break
        if head:
            if head[-1] not in ".!?\u3002\uff01\uff1f":
                head += "."
            kept.append(head + " ")
    cleaned = "".join(kept).rstrip()
    cleaned = re.sub(r"[,;]\s*$", ".", cleaned)
    return cleaned


def clean_wiki_prose(text: str | None) -> str:
    """Wiki prose reduced to the sentences that describe the substance."""
    if not text:
        return ""
    out = _CITE_LINK.sub("", text)
    out = _EDITORIAL_TAG.sub("", out)
    out = _XREF_LINE.sub("", out)
    out = _BARE_MARKER.sub("", out)
    out = strip_advice(out)
    out = _MULTISPACE.sub(" ", out)
    out = _MULTINEWLINE.sub("\n\n", out)
    # Punctuation left stranded by a removed marker: " ." or " ,"
    out = re.sub(r"\s+([.,;:!?。，；：！？])", r"\1", out)
    return out.strip()


# ---------------------------------------------------------------------------
# The voice rule
# ---------------------------------------------------------------------------

#: The repo's voice rule names this phrase outright: it implies the reader is
#: guilty of something needing reducing. Banned in anything a reader sees.
#: (Scholarship is exempt — in a paper it is a field name — but nothing here is
#: a paper.)
BANNED_PHRASE = re.compile(r"harm[- ]reduction", re.IGNORECASE)

#: What each surviving form becomes. Sources use the phrase three ways and each
#: needs a different repair, so this is a table rather than a deletion:
#:
#: 1. As a qualifier on a real statement ("oral preferred for harm reduction") —
#:    the qualifier goes and the statement stays, because the statement was the
#:    content.
#: 2. As a lead-in ("For harm reduction, take 1-2 small puffs") — the lead-in
#:    goes and the instruction stands on its own.
#: 3. Naming a kind of organisation — replaced with a plain description.
#:
#: An entry is a (pattern, replacement) pair applied in order. Anything the
#: table does not cover survives, and `assert_voice_rule` then fails the build —
#: silence is not an option for this one.
_VOICE_REWRITES: list[tuple[re.Pattern[str], object]] = [
    # ---- whole sentences first -------------------------------------------
    # A sentence whose content IS the exhortation. These run before the
    # qualifier repairs below, or "Immediate harm reduction steps and external
    # support may be necessary." becomes "Immediate safety steps and external
    # support may be necessary." — the phrase gone and the empty advice kept.
    (re.compile(r"[^.!?]*\bImmediate harm[- ]reduction[^.!?]*[.!?]\s*", re.I), ""),
    (
        re.compile(
            r"[^.!?]*\bharm[- ]reduction[^.!?]*\b(?:advised|recommended)\b[^.!?]*[.!?]\s*", re.I
        ),
        "",
    ),
    # ---- then the qualifiers, in what is left -----------------------------
    (re.compile(r",?\s*\b(?:generally\s+)?preferred for harm[- ]reduction", re.I), " preferred"),
    (re.compile(r"\bPrefer (\w+) for harm[- ]reduction\b", re.I), r"Prefer \1"),
    (re.compile(r"\b(not advised) for harm[- ]reduction\b", re.I), r"\1"),
    # Sentence-initial lead-in: the instruction after it becomes the sentence,
    # so it has to take the capital the lead-in was holding.
    (re.compile(r"\bFor harm[- ]reduction[,:]\s*(\w)", re.I), lambda m: m.group(1).upper()),
    (re.compile(r"\bharm[- ]reduction orgs?\b", re.I), "community organizations"),
    # Naming a KIND OF SOURCE — "user reports and harm-reduction compendia",
    # "community harm-reduction guidance". This is the commonest surviving form
    # by far, and the phrase is doing no work in it: what is meant is that the
    # source is a community one. Where a qualifier is already there, the phrase
    # just goes; where it is not, it becomes "community".
    (
        re.compile(
            r"\b(community|general|legacy|historical|multiple|independent|TripSit|Erowid)"
            r"\s+harm[- ]reduction\s+(?=\w)",
            re.I,
        ),
        r"\1 ",
    ),
    (
        re.compile(
            r"\bharm[- ]reduction[- ]?\s*(compendia|sites?|sources?|guidance|sheets?|forums?"
            r"|wikis?|summaries|write-?ups?|services|practices?|discussions?"
            r"|organi[sz]ations?|consensus|factsheets?|guides?|communities|literature"
            r"|tables?|estimates?|references?|projects?|material|advice|info(?:rmation)?"
            r"|data|reporting|context|circles|groups?)\b",
            re.I,
        ),
        r"community \1",
    ),
    (re.compile(r"\bis not a harm[- ]reduction strategy\b", re.I), "is not a safety strategy"),
    (re.compile(r"\bcommunity/harm[- ]reduction\b", re.I), "community"),
    (re.compile(r"\bforum harm[- ]reduction threads?\b", re.I), "forum threads"),
    (
        re.compile(r"\bharm[- ]reduction (steps?|concerns?|emphasis|nasal care)\b", re.I),
        r"safety \1",
    ),
    (re.compile(r"\bmodern harm[- ]reduction favou?rs\b", re.I), "modern practice favors"),
    (re.compile(r"\bharm[- ]reduction[- ]critical\b", re.I), "safety-critical"),
]


def enforce_voice(text: str | None) -> str:
    """`text` with the banned phrase repaired, keeping whatever it qualified."""
    if not text:
        return text or ""
    out = text
    for pattern, replacement in _VOICE_REWRITES:
        out = pattern.sub(replacement, out)
    out = _MULTISPACE.sub(" ", out)
    out = re.sub(r"\s+([.,;:!?])", r"\1", out)
    return out.strip()


# ---------------------------------------------------------------------------
# FDA label prose
# ---------------------------------------------------------------------------

#: A label's pointer into its own document. Piru ships one section of a label,
#: never the whole thing, so "see below" points at nothing a reader can reach.
_DANGLING_REFERENCE = re.compile(
    r",?\s*\((?:see|refer to)[^)]*\)"
    r"|,?\s*\bsee (?:below|above|section [\w.()]+|Clinical Pharmacology|Dosage[^.,;]*)",
    re.IGNORECASE,
)

#: A section label ingested as the section's content ("indications"). The
#: extractor's header/value split misses these when the label repeats its own
#: heading inside the body.
_BARE_HEADING = re.compile(
    r"^\s*(?:indications?|contraindications?|warnings?|dosage|precautions?|"
    r"adverse reactions?|description|usage|overview|and usage)"
    r"(?:\s*(?:&|and)\s*(?:usage|cautions?|administration|dosage))?\s*[:.]?\s*$",
    re.IGNORECASE,
)


#: The same section label, but glued to the front of the section's own body —
#: "Indications & Usage Sumatriptan tablets are indicated for…". 323 indication
#: rows arrive this way. Stripping it is lossless: the heading names the field
#: the row is already stored in.
_LEADING_HEADING = re.compile(
    r"^\s*(?:indications?|contraindications?|warnings?|precautions?|"
    r"adverse reactions?|description|usage|overview)"
    r"(?:\s*(?:&|and)\s*(?:usage|cautions?|precautions?|administration|dosage))?"
    r"\s*[:.\u2014-]?\s+"
    # Not when the word is the subject of a sentence rather than a heading:
    # "Description **of** the induction phase", "Overview **of** dosing". A
    # heading is followed by the section's content, never by a preposition
    # binding back to it. (`[A-Z]` cannot do this job — IGNORECASE below makes
    # it match lowercase too, which is how "Description of" got stripped.)
    r"(?!(?:of|for|in|on|to|and|or|with|is|are|was|were)\b)",
    re.IGNORECASE,
)


#: An OTC label selling the product rather than stating what it treats — "Let
#: Whatta-Melon® help soothe your child's sore throat. We have specially
#: formulated these great tasting …". Second person and a sales verb together;
#: either alone appears in legitimate label prose.
_MARKETING_VOICE = re.compile(
    r"\b(?:your|you)\b[^.]{0,60}\b(?:child|family|loved one)\b"
    r"|\blet\s+\S+\s+help\b"
    r"|\b(?:great|delicious|refreshing|pleasant)[- ]tasting\b"
    r"|\bspecially formulated\b",
    re.IGNORECASE,
)


def clean_label_prose(text: str | None) -> str:
    """A prescribing-label paragraph reduced to what stands on its own.

    Returns `""` for a string that is only a section heading, so the caller can
    skip the row rather than shipping the word "indications" as an indication.
    """
    if not text:
        return ""
    if _BARE_HEADING.match(text.strip()):
        return ""
    text = _LEADING_HEADING.sub("", text.strip(), count=1)
    if _MARKETING_VOICE.search(text):
        return ""
    # A sentence that is only a pointer goes whole; an inline one is cut out of
    # the sentence carrying it. Whole first, or the inline rule eats the "See
    # below" and strands the rest of its sentence.
    out = re.sub(r"(?:^|(?<=[.!?])\s*)See (?:below|above)[^.!?]*[.!?]\s*", "", text, flags=re.I)
    out = _DANGLING_REFERENCE.sub("", out)
    out = _MULTISPACE.sub(" ", out)
    out = re.sub(r"\s+([.,;:!?])", r"\1", out)
    return out.strip()


# ---------------------------------------------------------------------------
# US English
# ---------------------------------------------------------------------------

#: British spellings that turn up in pharmacology and label prose, and the US
#: form each becomes. The repo is US English everywhere including strings, and
#: most of these arrive in PsychonautWiki prose rather than being authored here.
#:
#: A word list rather than a morphological rule, because the endings are shared
#: with words that are already correct: `hours` ends in -ours, `dialogue` and
#: `analogue` in -ogue, and `analyses` is the US plural of `analysis`. Every
#: attempt at a general rule mangled one of those.
_US_SPELLINGS: dict[str, str] = {
    "behaviour": "behavior",
    "colour": "color",
    "flavour": "flavor",
    "favour": "favor",
    "favourite": "favorite",
    "favourable": "favorable",
    "favourably": "favorably",
    "disfavour": "disfavor",
    "disfavours": "disfavors",
    "hydrolysed": "hydrolyzed",
    "hydrolyse": "hydrolyze",
    "hydrolysing": "hydrolyzing",
    "polarised": "polarized",
    "polarise": "polarize",
    "labour": "labor",
    "honour": "honor",
    "humour": "humor",
    "odour": "odor",
    "vapour": "vapor",
    "tumour": "tumor",
    "grey": "gray",
    "centre": "center",
    "litre": "liter",
    "fibre": "fiber",
    "defence": "defense",
    "aluminium": "aluminum",
    "whilst": "while",
    "amongst": "among",
    "ageing": "aging",
    "oedema": "edema",
    "anaemia": "anemia",
    "anaemic": "anemic",
    "paediatric": "pediatric",
    "paediatrics": "pediatrics",
    "foetal": "fetal",
    "foetus": "fetus",
    "aetiology": "etiology",
    "oesophagus": "esophagus",
    "oesophageal": "esophageal",
    "diarrhoea": "diarrhea",
    "diarrhoeal": "diarrheal",
    "leukaemia": "leukemia",
    "haemoglobin": "hemoglobin",
    "haemolysis": "hemolysis",
    "haemorrhage": "hemorrhage",
    "haemorrhagic": "hemorrhagic",
    "haemodynamic": "hemodynamic",
    "sulphur": "sulfur",
    "sulphate": "sulfate",
    "sulphide": "sulfide",
    "sulphonate": "sulfonate",
    "prioritise": "prioritize",
    "organise": "organize",
    "organisation": "organization",
    "recognise": "recognize",
    "characterise": "characterize",
    "characterisation": "characterization",
    "minimise": "minimize",
    "maximise": "maximize",
    "utilise": "utilize",
    "normalise": "normalize",
    "standardise": "standardize",
    "categorise": "categorize",
    "miscategorise": "miscategorize",
    "metabolise": "metabolize",
    "summarise": "summarize",
    "emphasise": "emphasize",
    "specialise": "specialize",
    "stabilise": "stabilize",
    # `analyses` is the US plural of `analysis` and dominates this corpus
    # ("Pooled analyses of 199 trials"), so only the verb forms are listed.
    "analyse": "analyze",
    "analysed": "analyzed",
    "analysing": "analyzing",
    "practise": "practice",
    "practised": "practiced",
}


#: `-ise` verbs inflect, and listing every form quadruples the table. The stems
#: above ending in `ise`/`isation` are expanded here instead.
def _expand(table: dict[str, str]) -> dict[str, str]:
    out = dict(table)
    for british, american in table.items():
        if british.endswith("ise"):
            for suffix in ("d", "s", "rs"):
                out[british + suffix] = american.replace("ize", "iz") + "e" + suffix
            out[british[:-1] + "ing"] = american[:-1] + "ing"
            out[british[:-3] + "isation"] = american[:-3] + "ization"
            out[british[:-3] + "isations"] = american[:-3] + "izations"
        elif british.endswith(("our", "re", "ry")):
            for suffix in ("s", "ed", "ing", "al", "ally", "less"):
                out[british + suffix] = american + suffix
    return out


_US_SPELLINGS = _expand(_US_SPELLINGS)

_BRITISH_WORD = re.compile(
    r"\b(" + "|".join(sorted(_US_SPELLINGS, key=len, reverse=True)) + r")\b",
    re.IGNORECASE,
)


def _match_case(replacement: str, original: str) -> str:
    if original.isupper():
        return replacement.upper()
    if original[:1].isupper():
        return replacement[:1].upper() + replacement[1:]
    return replacement


def americanize(text: str | None) -> str:
    """`text` with British spellings replaced, preserving capitalisation.

    Applied as a sweep over the built database rather than at each ingest site,
    for the same reason the voice rule is: the prose arrives from four sources
    through paths that keep being added, and a filter has to be remembered on
    every new one.
    """
    if not text:
        return text or ""
    return _BRITISH_WORD.sub(
        lambda m: _match_case(_US_SPELLINGS[m.group(1).lower()], m.group(1)), text
    )
