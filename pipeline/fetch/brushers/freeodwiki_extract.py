#!/usr/bin/env python3
"""Extract structured substance data from a FreeOD Wiki (SalviaSWC/FreeODwiki) clone.

FreeOD Wiki is a CC BY-SA 4.0 Chinese harm-reduction wiki. Substance pages are
MkDocs Markdown: a chem-info card, dose/duration tables, an interactions table,
and long-form zh prose. This brusher parses the *regular* tables (dose tiers and
duration phases are label-driven, so the same scanner handles both the older
single-grid-card layout and the newer per-route `**[route]** (Bioavailability)`
layout) plus identifiers, categories, the lead description, and the linked
subjective-effects, emitting `data/sources/freeodwiki.json` for `ingest_freeodwiki`.

Raw clone stays out-of-repo (e.g. ~/Developer/piru-data/freeodwiki); only the
derived JSON is committed, mirroring drug-community.json.

Usage:
    python3 freeodwiki_extract.py <freeod-repo> [--out data/sources/freeodwiki.json]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

# --- Chinese label maps -----------------------------------------------------

# Dose intensity tiers: zh label -> add_dose keyword.
DOSE_TIERS = {
    "阈值": "threshold",
    "轻微": "light",
    "中等": "common",
    "强烈": "strong",
    "严重": "heavy",
}

# Duration phases: zh label -> DurationProfile key (minutes).
DURATION_PHASES = {
    "总时长": "total",
    "药效发作": "onset",
    "药效上升": "comeup",
    "药效达峰": "peak",
    "药效褪去": "offset",
    "药效残余": "afterglow",
}

# Route keywords, longest-first so "舌下含服" wins over "舌下" and "静脉注射"
# over "静脉". Mapped onto Piru's RouteOfAdministration raw values.
ROUTE_KEYWORDS = [
    ("颊部给药", "buccal"),
    ("颊", "buccal"),
    ("舌下含服", "sublingual"),
    ("舌下", "sublingual"),
    ("含服", "sublingual"),
    ("静脉注射", "intravenous"),
    ("静脉", "intravenous"),
    ("肌肉注射", "intramuscular"),
    ("肌肉", "intramuscular"),
    ("皮下", "subcutaneous"),
    ("透皮", "transdermal"),
    ("直肠给药", "rectal"),
    ("直肠", "rectal"),
    ("鼻吸", "insufflation"),
    ("鼻腔", "insufflation"),
    ("鼻", "insufflation"),
    ("口服", "oral"),
    ("抽吸", "inhalation"),
    ("吸入", "inhalation"),
    ("汽化", "inhalation"),
    ("蒸发", "inhalation"),
]

_CAS_RE = re.compile(r"\d{2,7}-\d{2}-\d")

# Chem-info card labels.
CHEM_FORMULA = "分子式"
CHEM_CAS = "CAS"  # matched as a substring ("CAS 号", "CAS号")
# Each label set lists every spelling the wiki's pages use for that row.
CHEM_IUPAC = ("系统名称", "系统命名")
CHEM_NAMES = ("常用名称", "常见名称", "常用名", "取代名称")
# The card's header cell, "可卡因（Cocaine）": the English name in the paren.
CHEM_HEADER = "化学信息"
CAT_PSYCHOACTIVE = ("精神活性分类", "精神活性类别", "精神药效分类")
CAT_CHEMICAL = ("化学分类", "化学类别")
ROUTE_HEADER = "给药途径"

# Duration unit -> minutes multiplier.
DURATION_UNITS = [
    ("小时", 60.0),
    ("时", 60.0),
    ("分钟", 1.0),
    ("分", 1.0),
    ("天", 1440.0),
    ("日", 1440.0),
    ("秒", 1.0 / 60.0),
    ("h", 60.0),
    ("min", 1.0),
]

# Micrograms are written with both the Greek small mu (μ, U+03BC) and the micro
# sign (µ, U+00B5) across FreeOD Wiki pages — sometimes within a single page
# (e.g. 25N-NBOMe mixes both). Fold every mu variant to the micro sign before
# unit detection so "μg" reads as micrograms instead of falling through to a
# bare "g" substring match, which would relabel microgram doses (clonidine,
# fentanyl, sufentanil, NBOMes) as grams. See parse_dose_value.
# Greek small mu (U+03BC), micro sign (U+00B5), math italic small mu (U+1D707).
_MU_VARIANTS = "μµ\U0001d707"
_MU_TABLE = {ord(c): "µ" for c in _MU_VARIANTS}

# Canonical unit per recognized token. The source uses latin (µg/mg/g/ml…) AND
# native Chinese units (微克/毫克/克/毫升…); a cell whose unit goes unrecognized
# defaults to "mg", turning a 50 微克 dose into 50 mg (1000×). Two-character
# Chinese units (微克/毫克) must precede the one-character ones (克) in the
# alternation below so the longer, more specific token wins.
_UNIT_CANON = {
    "µg": "µg",
    "ug": "µg",
    "mcg": "µg",
    "微克": "µg",
    "mg": "mg",
    "毫克": "mg",
    "ng": "ng",
    "纳克": "ng",
    "kg": "kg",
    "千克": "kg",
    "µl": "µl",
    "微升": "µl",
    "ml": "ml",
    "毫升": "ml",
    "g": "g",
    "克": "g",
    "l": "l",
    "升": "l",
}

# A unit only counts when it is attached to a number, longest/most-specific
# match first, with a trailing word boundary. Anchoring to a digit and bounding
# the tail stops a bare "g"/"l" from matching inside "µg"/"mg"/"ml" or a stray
# latin letter in a prose cell (the "l" in a "…fatal…" warning row).
_UNIT_RE = re.compile(r"\d\s*(µg|mcg|ug|mg|ng|kg|ml|µl|微克|毫克|纳克|千克|毫升|微升|g|l|克|升)\b")

_NUM_RE = re.compile(r"\d+(?:\.\d+)?")
_LINK_RE = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")  # [txt](url) and ![alt](url)
_FOOTNOTE_RE = re.compile(r"\[\^?\d+\]")  # [^1] and [12]
_HTML_RE = re.compile(r"<[^>]+>")


def strip_md(s: str) -> str:
    """Reduce inline Markdown/HTML to plain text for label/value matching."""
    s = _LINK_RE.sub(lambda m: m.group(1), s)
    s = _FOOTNOTE_RE.sub("", s)
    s = _HTML_RE.sub("", s)
    s = s.replace("**", "").replace("*", "").replace("`", "")
    s = s.replace("\\~", "~").replace("\\", "")
    s = s.replace(" ", " ").replace(" ", " ").replace("​", "")
    return s.strip()


def clean_cell(s: str) -> str:
    # ⇣ (U+21E3) and ⬇ (U+2B07) are both decorative "route below" arrows the wiki
    # prefixes onto per-route section headers; strip them so the route name matches.
    return strip_md(s).strip(" |：:⇣⬇🔽").strip()


def match_route(text: str) -> str | None:
    """Return a route raw value if `text` begins with / contains a route keyword."""
    t = clean_cell(text)
    for kw, route in ROUTE_KEYWORDS:
        if t.startswith(kw):
            return route
    for kw, route in ROUTE_KEYWORDS:
        if kw in t:
            return route
    return None


def parse_dose_value(raw: str) -> tuple[str, object, str | None] | None:
    """Parse a dose cell. Returns (kind, value, unit) where kind is 'scalar' or
    'range', value is float or {'min','max'}, and unit is the detected unit or
    None when the cell carries no recognizable number-attached unit (the caller
    then keeps the route's existing unit rather than guessing 'mg')."""
    s = strip_md(raw).translate(_MU_TABLE)
    s = s.replace("~", "-").replace("–", "-").replace("—", "-")
    s = re.sub(r"(?<=\d),(?=\d)", "", s)  # 1,000 -> 1000
    m = _UNIT_RE.search(s.lower())
    unit = _UNIT_CANON.get(m.group(1)) if m else None
    nums = [float(n) for n in _NUM_RE.findall(s)]
    if not nums:
        return None
    if len(nums) >= 2:
        lo, hi = nums[0], nums[1]
        if lo > hi:
            return None  # garbled cell (e.g. prose row with stray numbers)
        return ("range", {"min": lo, "max": hi}, unit)
    return ("scalar", nums[0], unit)


def parse_duration_value(raw: str) -> dict | None:
    """Parse a duration cell into {'min','max'} minutes."""
    s = strip_md(raw)
    s = s.replace("~", "-").replace("–", "-").replace("—", "-")
    mult = 1.0
    for token, m in DURATION_UNITS:
        if token in s:
            mult = m
            break
    nums = [float(n) for n in _NUM_RE.findall(s)]
    if not nums:
        return None
    lo = nums[0] * mult
    hi = (nums[1] if len(nums) >= 2 else nums[0]) * mult
    return {"min": lo, "max": hi}


# A locant comma inside a systematic name — "2,5-dimethoxy…", "3,4-methylenedioxy…".
# The separator split has no way to know a comma is part of a chemical name, so it
# cuts "4-Bromo-2,5-dimethoxyphenethylamine" into "4-Bromo-2" + "5-dimethoxy…".
# The tell is unambiguous: the left piece ENDS in a digit and the right piece
# BEGINS with a digit followed by a hyphen. No real pair of separate names looks
# like that, and both halves are useless alone: a fragment like "5-二甲氧基苯乙胺"
# would alias every 2C-x compound, and the full name would be unsearchable.
# The right piece may itself be a bare locant — "8-bromo-2,3,6,7-benzo…" splits
# into four pieces, of which the middle two are just "3" and "6". A bare number is
# never a name on its own (``_add_alias`` drops those as noise anyway), so folding
# it leftwards is always the better reading.
_LOCANT_LEFT_RE = re.compile(r"\d$")
_LOCANT_RIGHT_RE = re.compile(r"^\d+(?:[-,]|$)")


def rejoin_locant_splits(parts: list[str]) -> list[str]:
    """Glue back name fragments a locant comma was split on."""
    out: list[str] = []
    for part in parts:
        if out and _LOCANT_LEFT_RE.search(out[-1]) and _LOCANT_RIGHT_RE.match(part):
            out[-1] = f"{out[-1]},{part}"
        else:
            out.append(part)
    return out


_NAME_SEPARATORS = frozenset("、,，/;；")
_OPENERS, _CLOSERS = "([（【", ")]）】"


def split_outside_brackets(value: str) -> list[str]:
    """Split on the name separators, except inside brackets: the comma in
    "(1S,2S)-2-(methylamino)-1-phenylpropan-1-ol" is a stereo descriptor's, and
    cutting there turned one systematic name into "(1S" and "2S)-2-(methylamino)…"."""
    parts, buf, depth = [], [], 0
    for ch in value:
        if ch in _OPENERS:
            depth += 1
        elif ch in _CLOSERS:
            depth = max(depth - 1, 0)
        if ch in _NAME_SEPARATORS and depth == 0:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    parts.append("".join(buf))
    return parts


def split_names(value: str) -> list[str]:
    parts = split_outside_brackets(strip_md(value))
    # Strip stray italic underscores left when "_a / b_" splits mid-emphasis.
    cleaned = [p.strip().strip("_").strip() for p in parts if p.strip().strip("_").strip()]
    return rejoin_locant_splits(cleaned)


def table_text(line: str) -> str:
    """The row with the list marker removed: cards open each table with "- | …"."""
    s = line.strip()
    return s[2:].strip() if s.startswith("- |") else s


def pick_cas(value: str) -> str | None:
    """The substance's own CAS number from a cell that may list several, each
    with a note: "113-45-1<br>298-59-9（盐酸盐）". The first number is the
    substance, unless another is marked racemic (消旋) without being a salt (盐),
    as on pages whose first number is one enantiomer."""
    entries = [
        (m.group(0), value[m.end() : m.end() + 12].split("<br")[0]) for m in _CAS_RE.finditer(value)
    ]
    for number, note in entries:
        if "消旋" in note and "盐" not in note:
            return number
    return entries[0][0] if entries else None


def is_table_row(line: str) -> bool:
    s = table_text(line)
    return s.startswith("|") and s.count("|") >= 2


def row_cells(line: str) -> list[str]:
    cells = table_text(line).strip("|").split("|")
    return [c.strip() for c in cells]


def route_columns(cells: list[str]) -> list[str | None] | None:
    """Routes named by a 给药途径 header row, one per value column, or None when
    the row names none. A column repeating an earlier route (two oral products
    side by side) maps to None so it can't overwrite the first."""
    named = [c for c in cells[1:] if clean_cell(c)]
    if not named:
        return None
    routes = [match_route(c) for c in named]
    if not any(routes):
        return None
    out: list[str | None] = []
    for r in routes:
        out.append(None if r is None or r in out else r)
    return out


def parse_page(path: Path) -> dict | None:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    # Front-matter title.
    title = path.stem
    if lines and lines[0].strip() == "---":
        for ln in lines[1:]:
            if ln.strip() == "---":
                break
            if ln.startswith("title:"):
                title = ln.split(":", 1)[1].strip() or title

    rec: dict = {
        "title": title,
        "page_slug": path.stem,
        "names": [],
        "formula": None,
        "cas": None,
        "iupac": None,
        "categories": [],
        "tags": [],
        "doses": {},  # route -> {tier: scalar|range, unit}
        "durations": {},  # route -> {phase: {min,max}}
        "subjective_effects": [],
        "interactions": [],  # captured for future use; ingester ignores for now
        "description": None,
    }

    current_route = "oral"
    # Set by a multi-column 给药途径 header: the route each value column belongs to.
    columns: list[str | None] | None = None
    interaction_table = False

    for raw_line in lines:
        line = raw_line.rstrip()

        # Route markers: "⇣ [route]" headers and "**[route]** (Bioavailability)".
        if "⇣" in line:
            r = match_route(line.split("⇣", 1)[1])
            if r:
                current_route = r
                columns = None
                continue
        stripped = line.strip()
        # A heading that is only a route name ("#### **口服**", "#### [抽吸](…)")
        # starts that route's section.
        if stripped.startswith("#"):
            heading = clean_cell(stripped.lstrip("#"))
            r = match_route(heading) if 0 < len(heading) <= 8 else None
            if r:
                current_route = r
                columns = None
                continue
        if stripped.startswith("**") and (
            "生物利用度" in stripped
            or "Bioavailability" in stripped
            or len(clean_cell(stripped)) < 24
        ):
            r = match_route(stripped)
            if r:
                current_route = r
                columns = None
                continue

        if not is_table_row(line):
            continue

        cells = row_cells(line)
        if len(cells) < 2:
            continue
        label = clean_cell(cells[0])
        value = cells[1]

        if label == ROUTE_HEADER:
            routes = route_columns(cells)
            if routes:
                current_route = routes[0] or current_route
                columns = routes if len(routes) > 1 else None
                interaction_table = False
            continue

        # Per-route section header — a table row whose first cell is just a route
        # name and whose value cell is empty ("| [口服] | |" then a "---" separator
        # and a per-route dose/duration grid). This is distinct from the inline
        # "⇣ [route]" and "**[route]** (Bioavailability)" headers above. Without it
        # each route's grid collapses onto the default "oral" and the last table
        # wins — e.g. morphine's intravenous ladder overwriting its oral ladder.
        # The empty-value + short-label guard keeps prose/bold section headers
        # (剂量 / 持续时间 / 给药途径) from matching a single-char route keyword.
        if not clean_cell(value) and 0 < len(label) <= 6:
            r = match_route(label)
            if r:
                current_route = r
                columns = None
                interaction_table = False
                continue

        # Interaction table header toggles capture of the emoji-severity rows.
        if "相互作用" in label or "药物联用" in label:
            interaction_table = True
            continue
        if interaction_table:
            sev = None
            if "严禁联用" in value:
                sev = "prohibited"
            elif "联用危险" in value or "💔" in value:
                sev = "dangerous"
            elif "谨慎联用" in value or "⚠" in value:
                sev = "caution"
            if sev and label and label not in ("---", ""):
                rec["interactions"].append({"with": label, "severity": sev})
            # An all-dashes separator or a non-emoji row ends the table.
            if set(label) <= {"-"} and label:
                pass
            continue

        # Chem-info / category rows.
        if label == CHEM_FORMULA and not rec["formula"]:
            rec["formula"] = strip_md(value) or None
            continue
        if label.startswith(CHEM_CAS) and not rec["cas"]:
            rec["cas"] = pick_cas(value)
            continue
        if label in CHEM_IUPAC and not rec["iupac"]:
            rec["iupac"] = strip_md(value) or None
            continue
        if label in CHEM_NAMES or label == CHEM_HEADER:
            rec["names"].extend(split_names(value))
            continue
        if label in CAT_PSYCHOACTIVE:
            rec["categories"].extend(split_names(value))
            continue
        if label in CAT_CHEMICAL:
            rec["tags"].extend(split_names(value))
            continue

        # Dose tier rows.
        if columns and len(cells) - 1 >= len(columns):
            per_route = [(r, v) for r, v in zip(columns, cells[1:], strict=False) if r]
        else:
            per_route = [(current_route, value)]

        if label in DOSE_TIERS:
            for route, cell in per_route:
                parsed = parse_dose_value(cell)
                if parsed:
                    _, val, unit = parsed
                    d = rec["doses"].setdefault(route, {"unit": "mg"})
                    d[DOSE_TIERS[label]] = val
                    # Only a recognized, number-attached unit overrides the route's
                    # default — a prose/garbled tier row must not clobber the real
                    # unit set by a sibling row (the per-route unit is shared).
                    if unit:
                        d["unit"] = unit
            continue

        # Duration phase rows.
        if label in DURATION_PHASES:
            for route, cell in per_route:
                prof = parse_duration_value(cell)
                if prof:
                    rec["durations"].setdefault(route, {})[DURATION_PHASES[label]] = prof
            continue

    # Subjective effects: links into the 药效/ index.
    seen = set()
    for lm in re.finditer(r"\[([^\]]+)\]\(([^)]*药效/[^)]*)\)", text):
        name = strip_md(lm.group(1)).strip()
        if name and name not in seen and name != "index" and "主观效应" not in name:
            seen.add(name)
            rec["subjective_effects"].append(name)

    # Lead description: first prose paragraph block after the card/tables,
    # before the first "## " section heading.
    rec["description"] = extract_description(lines)
    # Pharmacology section -> locale-aware Mechanism of Action text.
    rec["mechanism"] = extract_section(lines, ("药理学", "药理作用"))

    # Mine the English name from the bold lead paragraph. FreeOD pages title
    # in Chinese but introduce the compound as either "**中文**（English，…)"
    # (English right after the paren) or "***Latin name***（…中文…)" (a Latin
    # bold lead). These English names are prepended so the ingester can match
    # the page onto an existing English substance instead of duplicating it.
    rec["names"] = extract_english_names(title, lines) + rec["names"]
    # Pull English out of "中文（English）" name cells (e.g. "哌甲酯（Methylphenidate）").
    mined: list[str] = []
    for n in rec["names"]:
        if "（" in n or "(" in n:
            pm = _PAREN_EN_RE.search(n)
            if pm:
                mined.append(pm.group(1).strip())
    rec["names"] = mined + rec["names"]

    # Dedup name list against the title.
    rec["names"] = list(dict.fromkeys(n for n in rec["names"] if n and n != title))
    rec["categories"] = list(dict.fromkeys(rec["categories"]))
    rec["tags"] = list(dict.fromkeys(rec["tags"]))

    # Keep only records that carry usable substance data.
    if not (rec["doses"] or rec["durations"] or rec["description"]):
        return None
    return rec


def extract_description(lines: list[str]) -> str | None:
    paras: list[str] = []
    buf: list[str] = []
    started = False
    for raw in lines:
        line = raw.strip()
        if line.startswith("## "):
            break  # first major section ends the overview
        if is_table_row(raw) or line.startswith("|"):
            continue
        if (
            line.startswith("#")
            or line.startswith("!!!")
            or line.startswith("<")
            or line.startswith("[◀")
            or line.startswith("---")
        ):
            continue
        if line.startswith("- ") or line.startswith("* ") or line.startswith(">"):
            continue
        if not line:
            if buf:
                paras.append(" ".join(buf))
                buf = []
            continue
        plain = strip_md(line)
        # The overview starts at the bold compound-name lead paragraph.
        if not started:
            if (
                "**" in raw
                and "（" in raw
                or (plain and len(plain) > 40 and "**" in raw)
                or plain
                and len(plain) > 60
            ):
                started = True
            else:
                continue
        if plain:
            buf.append(plain)
        if len(paras) >= 4:
            break
    if buf:
        paras.append(" ".join(buf))
    text = "\n\n".join(p for p in paras if p).strip()
    return text or None


_EN_TOKEN = r"[A-Za-z][A-Za-z0-9 .'\-]{1,46}?"
# A Latin bold lead: "***Mitragyna speciosa***（…)" / "**Modafinil**（…)".
_LEAD_LATIN_RE = re.compile(rf"^\*{{2,3}}({_EN_TOKEN})\*{{2,3}}\s*[（(]")
# English inside a "中文（English）" name cell or lead. A bracket right after a
# letter, digit or hyphen opens a substituent of a systematic name — the
# "(methylamino)" of "2-(methylamino)-1-phenylpropan-1-ol" — never a gloss.
_PAREN_EN_RE = re.compile(rf"(?<![-0-9A-Za-z])[（(]\s*\*{{0,3}}({_EN_TOKEN})\*{{0,3}}\s*[，,、)）]")
_GENERIC = {"the", "a", "an", "or", "and"}


def extract_english_names(title: str, lines: list[str]) -> list[str]:
    """Pull English/Latin names out of the bold lead paragraph.

    Anchored on the page title (``**可卡因**（Cocaine，…)``) so a stray callout
    or systematic-name line can't hijack the match; falls back to a Latin bold
    lead (``***Mitragyna speciosa***（…)``) for pages titled in Latin."""
    out: list[str] = []
    text = "\n".join(lines)
    # Title-anchored: the English directly follows the bolded title in a paren.
    if title:
        m = re.search(
            rf"\*\*{re.escape(title)}\*\*\s*[（(]\s*\*{{0,3}}({_EN_TOKEN})\*{{0,3}}\s*[，,、)）]",
            text,
        )
        if m:
            out.append(m.group(1).strip())
    # Latin bold lead (title isn't the lead, e.g. botanicals).
    for raw in lines:
        s = raw.strip()
        if s.startswith("**") and ("（" in s or "(" in s):
            m = _LEAD_LATIN_RE.match(s)
            if m:
                out.append(m.group(1).strip())
            break
    return [n for n in out if n and n.lower() not in _GENERIC]


def extract_section(lines: list[str], headers: tuple[str, ...]) -> str | None:
    """Collect prose under a `## <header>` heading until the next `## ` heading.

    Tables, images, callouts, and figure rows are skipped; the remaining prose
    is returned as paragraph-joined plain text (or None if the section is
    absent/empty)."""
    paras: list[str] = []
    buf: list[str] = []
    capturing = False
    for raw in lines:
        line = raw.strip()
        if line.startswith("## "):
            heading = strip_md(line[3:]).strip()
            if capturing:
                break  # next major section ends the capture
            capturing = any(h in heading for h in headers)
            continue
        if not capturing:
            continue
        if line.startswith("### "):
            continue  # keep subsection prose, drop the subheading itself
        if (
            is_table_row(raw)
            or line.startswith("|")
            or line.startswith("!")
            or line.startswith("<")
            or line.startswith("---")
        ):
            continue
        if not line:
            if buf:
                paras.append(" ".join(buf))
                buf = []
            continue
        plain = strip_md(line.lstrip("-*> ").strip())
        if plain:
            buf.append(plain)
        if len(paras) >= 5:
            break
    if buf:
        paras.append(" ".join(buf))
    text = "\n\n".join(p for p in paras if p).strip()
    return text or None


ENGLISH = Path("data/sources/freeodwiki-en.json")


def zh_sha(value) -> str:
    """The hash a translation in `freeodwiki-en.json` records for its Chinese."""
    blob = json.dumps(value, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:16]


def merge_english(records: list[dict], store: Path) -> list[str]:
    """Attach English text from `store` to each record, in place.

    PsychonautWiki's own lead prose applies as is. A machine translation applies
    only while the Chinese it was made from is unchanged, so an edited FreeOD
    page never ships a translation of its old text. Returns the fields that need
    a new translation, as "page_slug: field".
    """
    if not store.exists():
        return []
    entries = json.loads(store.read_text(encoding="utf-8")).get("records") or {}
    stale: list[str] = []
    for rec in records:
        entry = entries.get(rec["page_slug"]) or {}
        description = entry.get("description")
        if description:
            translated = description["source"] == "freeodwiki"
            if not translated or description.get("zh_sha") == zh_sha(rec.get("description")):
                rec["description_en"] = description["text"]
                rec["description_en_source"] = description["source"]
                rec["description_en_mt"] = translated
            else:
                stale.append(f"{rec['page_slug']}: description")
        elif rec.get("description"):
            stale.append(f"{rec['page_slug']}: description (none yet)")
        mechanism = entry.get("mechanism")
        if mechanism:
            if mechanism.get("zh_sha") == zh_sha(rec.get("mechanism")):
                rec["mechanism_en"] = mechanism["text"]
                rec["mechanism_en_mt"] = True
            else:
                stale.append(f"{rec['page_slug']}: mechanism")
        effects = entry.get("effects")
        if effects:
            if effects.get("zh_sha") == zh_sha(rec.get("subjective_effects")):
                rec["subjective_effects_en"] = effects["names"]
            else:
                stale.append(f"{rec['page_slug']}: effects")
    return stale


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo", type=Path, help="Path to a FreeODwiki clone")
    ap.add_argument("--out", type=Path, default=Path("data/sources/freeodwiki.json"))
    ap.add_argument("--english", type=Path, default=ENGLISH, help="English text store to merge")
    args = ap.parse_args()

    drug_dir = args.repo / "药物"
    if not drug_dir.is_dir():
        print(f"error: {drug_dir} not found", file=sys.stderr)
        return 1

    records = []
    stats = {
        "files": 0,
        "parsed": 0,
        "with_dose": 0,
        "with_duration": 0,
        "with_desc": 0,
        "with_mechanism": 0,
        "with_effects": 0,
        "with_cas": 0,
        "with_formula": 0,
    }
    for md in sorted(drug_dir.glob("*.md")):
        if md.stem in ("index", "README"):
            continue
        stats["files"] += 1
        rec = parse_page(md)
        if not rec:
            continue
        # A page titled as another page that exists is a copy of that article
        # (麻黄碱.md, ephedrine, once carried 甲卡西酮's text). Ingesting it would
        # file one compound's data under another, so it is skipped and named.
        if rec["title"] != md.stem and (drug_dir / f"{rec['title']}.md").exists():
            print(
                f"  skipped {md.name}: its content is the {rec['title']} article", file=sys.stderr
            )
            stats["skipped_copies"] = stats.get("skipped_copies", 0) + 1
            continue
        stats["parsed"] += 1
        stats["with_dose"] += bool(rec["doses"])
        stats["with_duration"] += bool(rec["durations"])
        stats["with_desc"] += bool(rec["description"])
        stats["with_mechanism"] += bool(rec.get("mechanism"))
        stats["with_effects"] += bool(rec["subjective_effects"])
        stats["with_cas"] += bool(rec["cas"])
        stats["with_formula"] += bool(rec["formula"])
        records.append(rec)

    stale = merge_english(records, args.english)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(records)} records to {args.out}")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    if stale:
        print(f"  needs English ({len(stale)}): add to {args.english}")
        for line in stale:
            print(f"    {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
