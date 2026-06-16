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

# Chem-info card labels.
CHEM_FORMULA = "分子式"
CHEM_CAS = "CAS"  # matched as a substring ("CAS 号", "CAS号")
CHEM_IUPAC = "系统名称"
CHEM_COMMON_NAMES = "常用名称"
CHEM_SUBST_NAME = "取代名称"
CAT_PSYCHOACTIVE = "精神活性分类"
CAT_CHEMICAL = "化学分类"

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

DOSE_UNITS = ["µg", "ug", "mcg", "mg", "ng", "ml", "g", "l"]  # longest-ish first

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
    return strip_md(s).strip(" |：:⇣").strip()


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


def parse_dose_value(raw: str) -> tuple[str, object, str] | None:
    """Parse a dose cell. Returns (kind, value, unit) where kind is 'scalar' or
    'range'; value is float or {'min','max'}. Unit defaults to mg."""
    s = strip_md(raw)
    s = s.replace("~", "-").replace("–", "-").replace("—", "-")
    s = re.sub(r"(?<=\d),(?=\d)", "", s)  # 1,000 -> 1000
    unit = "mg"
    for u in DOSE_UNITS:
        if u in s.lower():
            unit = "µg" if u in ("ug", "mcg") else u
            break
    nums = [float(n) for n in _NUM_RE.findall(s)]
    if not nums:
        return None
    if len(nums) >= 2:
        return ("range", {"min": nums[0], "max": nums[1]}, unit)
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


def split_names(value: str) -> list[str]:
    parts = re.split(r"[、,，/;；]", strip_md(value))
    # Strip stray italic underscores left when "_a / b_" splits mid-emphasis.
    return [p.strip().strip("_").strip() for p in parts if p.strip().strip("_").strip()]


def is_table_row(line: str) -> bool:
    return line.lstrip().startswith("|") and line.count("|") >= 2


def row_cells(line: str) -> list[str]:
    cells = line.strip().strip("|").split("|")
    return [c.strip() for c in cells]


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
    saw_route = False
    interaction_table = False

    for raw_line in lines:
        line = raw_line.rstrip()

        # Route markers: "⇣ [route]" headers and "**[route]** (Bioavailability)".
        if "⇣" in line:
            r = match_route(line.split("⇣", 1)[1])
            if r:
                current_route = r
                saw_route = True
                continue
        stripped = line.strip()
        if stripped.startswith("**") and (
            "生物利用度" in stripped
            or "Bioavailability" in stripped
            or len(clean_cell(stripped)) < 24
        ):
            r = match_route(stripped)
            if r:
                current_route = r
                saw_route = True
                continue

        if not is_table_row(line):
            continue

        cells = row_cells(line)
        if len(cells) < 2:
            continue
        label = clean_cell(cells[0])
        value = cells[1]

        # Interaction table header toggles capture of the emoji-severity rows.
        if "相互作用" in label:
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
            rec["cas"] = strip_md(value) or None
            continue
        if label == CHEM_IUPAC and not rec["iupac"]:
            rec["iupac"] = strip_md(value) or None
            continue
        if label in (CHEM_COMMON_NAMES, CHEM_SUBST_NAME):
            rec["names"].extend(split_names(value))
            continue
        if label == CAT_PSYCHOACTIVE:
            rec["categories"].extend(split_names(value))
            continue
        if label == CAT_CHEMICAL:
            rec["tags"].extend(split_names(value))
            continue

        # Dose tier rows.
        if label in DOSE_TIERS:
            parsed = parse_dose_value(value)
            if parsed:
                kind, val, unit = parsed
                d = rec["doses"].setdefault(current_route, {"unit": unit})
                d[DOSE_TIERS[label]] = val
                d["unit"] = unit
                if saw_route:
                    pass
            continue

        # Duration phase rows.
        if label in DURATION_PHASES:
            prof = parse_duration_value(value)
            if prof:
                rec["durations"].setdefault(current_route, {})[DURATION_PHASES[label]] = prof
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
# English inside a "中文（English）" name cell or lead.
_PAREN_EN_RE = re.compile(rf"[（(]\s*\*{{0,3}}({_EN_TOKEN})\*{{0,3}}\s*[，,、)）]")
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo", type=Path, help="Path to a FreeODwiki clone")
    ap.add_argument("--out", type=Path, default=Path("data/sources/freeodwiki.json"))
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
        stats["parsed"] += 1
        stats["with_dose"] += bool(rec["doses"])
        stats["with_duration"] += bool(rec["durations"])
        stats["with_desc"] += bool(rec["description"])
        stats["with_mechanism"] += bool(rec.get("mechanism"))
        stats["with_effects"] += bool(rec["subjective_effects"])
        stats["with_cas"] += bool(rec["cas"])
        stats["with_formula"] += bool(rec["formula"])
        records.append(rec)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(records)} records to {args.out}")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
