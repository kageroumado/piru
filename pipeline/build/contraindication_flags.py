"""A closed vocabulary of contraindication flags, and the matcher that fills it.

Label prose arrives as clinical sentences written for prescribers — "Those who
have experienced asthma, urticaria, or allergic reactions after takings NSAIDs".
Piru is a reference for the person taking the thing, so it needs the *fact* in a
few words and its own wording for it: a flag the app supplies a string for.

Three outcomes, and nothing else:

- **A flag matched.** The row ships as `flag` and Piru's own short label. The
  source sentence is not stored.
- **The row is already a bare condition name** — "Anuria", "Systemic fungal
  infections", "Nursing mothers". A disease name is the fact; there is nothing
  to normalize and nothing to reword, so it ships as written.
- **Neither.** The row is dropped and counted. A verbose sentence that no flag
  covers is prose we have no right to and no use for.

Order matters in ``FLAG_PATTERNS``: the first match wins, so the specific
patterns are listed before the general ones (an MAOI sentence is an MAOI
contraindication even though it also contains the word "concomitant").
"""

from __future__ import annotations

import re

#: flag id -> the short label Piru shows. These are Piru's words, not the
#: label's. House voice: a noun phrase stating the fact, never an instruction —
#: the reader is told what the contraindication IS, not what to do about it.
FLAG_LABELS: dict[str, str] = {
    "hypersensitivity": "Known allergy to it",
    "maoi": "With an MAOI, or within 14 days of one",
    "cns_depressants": "With other CNS depressants",
    "cyp3a4": "With a strong CYP3A4 inhibitor",
    "qt_prolonging": "With a QT-prolonging drug",
    "live_vaccine": "With a live vaccine",
    "guanylate_cyclase": "With a nitrate or a guanylate cyclase stimulator",
    "alcohol": "With alcohol",
    "anticoagulant": "With an anticoagulant",
    "respiratory_depression": "Existing respiratory depression",
    "acute_asthma": "During an acute asthma attack",
    "gi_obstruction": "Bowel obstruction",
    "active_bleeding": "Active bleeding",
    "hepatic_impairment": "Liver disease",
    "renal_impairment": "Kidney disease",
    "anuria": "Anuria",
    "cardiac_ischemia": "Recent heart attack or heart surgery",
    "uncontrolled_hypertension": "Uncontrolled high blood pressure",
    "arrhythmia": "Heart rhythm disorder",
    "heart_failure": "Heart failure",
    "seizure_disorder": "Seizure disorder",
    "glaucoma": "Narrow-angle glaucoma",
    "urinary_retention": "Urinary retention",
    "adrenal_insufficiency": "Adrenal insufficiency",
    "fungal_infection": "Systemic fungal infection",
    "porphyria": "Porphyria",
    "phaeochromocytoma": "Pheochromocytoma",
    "thyroid": "Untreated thyroid disease",
    "pregnancy": "Pregnancy",
    "breastfeeding": "Breastfeeding",
    "children": "Children",
    "eating_disorder": "Eating disorder",
    "myasthenia_gravis": "Myasthenia gravis",
    "sleep_apnea": "Sleep apnea",
    "smoking_over_35": "Smoking over the age of 35",
    "hypoglycemia": "During low blood sugar",
    "hypokalemia": "Low potassium",
    "hyperkalemia": "High potassium",
    "thyroid_cancer_history": "Personal or family history of thyroid cancer",
    "anxiety_agitation": "Marked anxiety or agitation",
    "recent_surgery": "Around surgery",
}

#: (flag, pattern). First match wins, so specific rules precede general ones.
FLAG_PATTERNS: list[tuple[str, str]] = [
    # Drug-drug axes. These are named before any condition rule, because a
    # sentence about a drug pairing usually also names the condition it causes.
    (
        "maoi",
        r"monoamine[\s\-]?oxidase|\bmaoi\b|linezolid|methylene blue|\bselegiline\b|\bphenelzine\b|\btranylcypromine\b|\bisocarboxazid\b",
    ),
    (
        "guanylate_cyclase",
        r"guanylate cyclase|riociguat|\bnitrate|nitric oxide donor|\bnitroglycerin",
    ),
    ("live_vaccine", r"live[, ]|live,? attenuated vaccine|live vaccine"),
    ("cyp3a4", r"cyp\s*3a4|cytochrome p450 3a4|strong (?:cyp)?3a4"),
    ("qt_prolonging", r"qt[\s\-]?(?:interval )?prolong|torsades"),
    (
        "cns_depressants",
        r"benzodiazepines? or other cns|other cns depressant|central nervous system depressant",
    ),
    ("anticoagulant", r"anticoagulant|\bwarfarin\b|antiplatelet"),
    ("alcohol", r"\balcohol\b|ethanol"),
    # Allergy. Deliberately after the drug axes: "hypersensitivity to X" is the
    # single commonest sentence in the corpus and would otherwise swallow rules
    # that mention an ingredient in passing.
    (
        "hypersensitivity",
        r"hypersensitiv|anaphyla|allergic reaction|allergy to|angioedema|urticaria|milk protein",
    ),
    # Organ systems and conditions.
    (
        "acute_asthma",
        r"status asthmaticus|acute (?:episodes? of )?asthma|severe bronchial asthma|acute bronchospasm",
    ),
    (
        "respiratory_depression",
        r"respiratory depression|respiratory arrest|hypercapnia|hypercarbia",
    ),
    ("sleep_apnea", r"sleep apnea|sleep apnoea"),
    (
        "gi_obstruction",
        r"gastrointestinal obstruction|paralytic ileus|\bileus\b|bowel obstruction|toxic megacolon|ischemic bowel",
    ),
    (
        "active_bleeding",
        r"active (?:pathological )?bleed|gastrointestinal bleed|\bhemorrhage|peptic ulcer",
    ),
    (
        "hepatic_impairment",
        r"hepatic (?:impairment|failure|disease)|liver (?:disease|failure|impairment)|cirrhosis|hepatic transaminase",
    ),
    ("anuria", r"\banuria\b"),
    (
        "renal_impairment",
        r"renal (?:impairment|failure|disease)|kidney (?:disease|failure|impairment)|creatinine clearance|end[\s\-]stage renal",
    ),
    (
        "cardiac_ischemia",
        r"myocardial infarction|coronary artery bypass|\bcabg\b|ischemic heart|unstable angina|coronary artery disease",
    ),
    ("heart_failure", r"heart failure|cardiogenic shock|cardiomyopathy"),
    (
        "arrhythmia",
        r"\barrhythmia|heart block|bradycardia|sick sinus|atrial fibrillation|ventricular tachycardia",
    ),
    (
        "uncontrolled_hypertension",
        r"uncontrolled hypertension|severe hypertension|hypertensive crisis",
    ),
    ("seizure_disorder", r"seizure disorder|epilep|history of seizure|convulsive disorder"),
    ("glaucoma", r"glaucoma"),
    ("urinary_retention", r"urinary retention|bladder outlet|prostatic hypertroph"),
    ("adrenal_insufficiency", r"adrenal insufficiency|addison"),
    ("fungal_infection", r"fungal infection"),
    ("porphyria", r"porphyria"),
    ("phaeochromocytoma", r"pheochromocytoma|phaeochromocytoma"),
    ("thyroid", r"thyrotoxicosis|untreated hypothyroid|hyperthyroid"),
    ("hypokalemia", r"hypokalemia|hypokalaemia|low potassium"),
    ("hyperkalemia", r"hyperkalemia|hyperkalaemia|elevated serum potassium|high potassium"),
    (
        "thyroid_cancer_history",
        r"medullary thyroid|thyroid c-cell|multiple endocrine neoplasia|\bmen 2\b",
    ),
    ("anxiety_agitation", r"marked anxiety|anxiety, tension, and agitation"),
    ("hypoglycemia", r"hypoglycemia|hypoglycaemia|low blood sugar"),
    ("myasthenia_gravis", r"myasthenia gravis"),
    ("eating_disorder", r"anorexia nervosa|bulimia|eating disorder"),
    ("recent_surgery", r"(?:peri|post)[\s\-]?operative|prior to surgery|before surgery"),
    # Populations.
    ("smoking_over_35", r"over age 35 who smoke|smoke and are over"),
    ("pregnancy", r"\bpregnan|fetal toxicity|teratogen|may become pregnant"),
    ("breastfeeding", r"nursing mother|breast[\s\-]?feed|lactation"),
    (
        "children",
        r"younger than \d+ years|children (?:younger|under)|pediatric patients (?:younger|under)|neonates?\b",
    ),
]

_COMPILED = [(flag, re.compile(pattern, re.IGNORECASE)) for flag, pattern in FLAG_PATTERNS]

#: A bare condition name has no clause structure. These words mean the string is
#: a sentence *about* a population or a risk rather than the name of a thing.
_SENTENCE_MARKERS = re.compile(
    r"\b(?:those who|patients who|patients with|patients receiving|should|must|"
    r"may |can |is |are |be |been |including|include|such as|when |where |"
    r"in the setting|use of|use with|concomitant|concurrent|risk|risks|"
    r"treatment of|treated with|intended|caution|avoid|do not|discontinu)\b",
    re.IGNORECASE,
)

#: A condition name that runs longer than this is a sentence with the verbs
#: elided, not a name. Measured against the corpus: the longest genuine name is
#: "Concurrent administration of live vaccines" at 42.
_MAX_CONDITION_NAME = 48


def match_flag(text: str) -> str | None:
    """The flag this sentence names, or ``None`` if no flag covers it."""
    for flag, pattern in _COMPILED:
        if pattern.search(text or ""):
            return flag
    return None


def is_bare_condition_name(text: str) -> bool:
    """Whether the string is the name of a condition rather than a sentence.

    A disease name is already the fact in the fewest possible words, so there is
    nothing for a flag to normalize and no wording of ours to substitute.
    """
    stripped = (text or "").strip().rstrip(".")
    if not stripped or len(stripped) > _MAX_CONDITION_NAME:
        return False
    if _SENTENCE_MARKERS.search(stripped):
        return False
    # A comma-separated list is an enumeration, and an enumeration of three
    # conditions is not one condition's name.
    return stripped.count(",") <= 1


#: A row that talks *about* the label rather than stating a warning. Two in the
#: corpus — "No Boxed Warnings for this product; however, several exist for
#: single-agent codeine" and a bare "Warnings for this product". Neither names
#: anything the reader can act on, and the first is the scraper reporting an
#: absence as if it were a finding.
_META_COMMENTARY = re.compile(
    r"no boxed warnings?\b|\bfor this product\b|^\s*warnings?\s*$", re.IGNORECASE
)


#: A boxed warning is a section title in the FDA label, so it arrives already
#: short and already a name — "Cardiovascular Thrombotic Events". Eight of the
#: 267 in the corpus are a paragraph instead, and those are the ones to drop.
_MAX_BOXED_HEADING = 90


def is_boxed_heading(text: str) -> bool:
    """Whether a boxed warning arrived as its title rather than its body."""
    stripped = (text or "").strip().rstrip(".")
    return bool(stripped) and len(stripped) <= _MAX_BOXED_HEADING


def normalize(text: str, *, boxed: bool = False) -> tuple[str | None, str | None]:
    """``(flag, text)`` for one label row. ``(None, None)`` drops it.

    At most one of the two is set.

    Boxed warnings take no flag. A boxed warning says what the drug *does*
    ("Cardiovascular Thrombotic Events"); a contraindication says when not to
    take it ("Uncontrolled high blood pressure"). One vocabulary over both would
    label half of them wrongly, so the boxed rows keep their own title and only
    the paragraphs are dropped.
    """
    if _META_COMMENTARY.search(text or ""):
        return None, None
    if boxed:
        return (None, (text or "").strip().rstrip(".")) if is_boxed_heading(text) else (None, None)
    # Name before flag. A short name-shaped row is already the fact in the
    # fewest words, and it is often more specific than any flag: "All other CNS
    # depressants, and Cimetidine" names the cimetidine, which `cns_depressants`
    # would throw away. Flagging exists for the sentences, not for these.
    if is_bare_condition_name(text):
        return None, (text or "").strip().rstrip(".")
    flag = match_flag(text)
    return (flag, None) if flag else (None, None)
