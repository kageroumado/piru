"""Build-time gates over the dose and duration rows every source contributed.

The source order decides which claim shows when sources disagree. It cannot
catch a claim that is wrong on its own terms — a fentanyl-analog ladder written
in milligrams, a come-up of five seconds on a swallowed pill — because nothing
outranks a row nobody else has. These gates are the deterministic checks that
run over the finished ingest and delete what fails them. Each deletion is
written to ``data/snapshots/dose-gate-report.md`` with the rule and the
values, so the source can be told and the rule can be argued with.

The rules:

* **Class ceilings** (``data/curated/dose-class-gates.json``) — for a class
  context whose members are dosed in micrograms, any ladder tier above a stated
  mass is not a dose but a unit slip or a copied error, and it goes unless the
  row carries a citation or comes from an exempt source. A member the premise
  does not hold for is named in that gate's ``exempt_substances`` with its own
  source: clonitazene is a circulating nitazene, but the one humans were given
  by mouth in tens of milligrams, so the ≤2 mg ceiling must not judge it.
* **Absorption floors** — a phase of under one minute on a route that has to
  absorb through a membrane (oral, sublingual, rectal, transdermal, buccal,
  insufflation) is a units error, whatever the source. Inhaled and injected
  routes are exempt: a smoked or IV come-up of seconds is real.
* **Toxic floors** (``data/curated/toxic-dose-floors.json``) — a cited human
  dose at which fatal or severe toxicity is documented. An uncited ladder whose
  threshold, light, common or strong tier reaches it presents that amount as an
  ordinary dose, and goes. The heavy tier is exempt: it is where a ladder says
  "dangerous", so reaching a floor there is the ladder being right.
* **Cross-source outliers** — the one rule that reads other sources. An uncited
  row whose common midpoint is ten times (or a tenth of) the median of at least
  three other sources' rows for the same substance, route, dosing context and
  isomer is a unit slip or a ladder filed under the wrong substance.
* **Foreign scripts** — a shipped text cell carrying letters from a script no
  source writes in (Ethiopic syllables where a dash belongs, "10ጰ min") is an
  export fault, and the cell is dropped.
* **Shulgin no-activity bounds** (``shulgin_dosage_verdict``, applied at the
  PIHKAL/TIHKAL ingest) — "greater than 60 mg" is the amount that did nothing.

The other rules read nothing but the row: a gate is a fact about the row itself.
"""

from __future__ import annotations

import json
import re
import sqlite3
import statistics
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GATES_PATH = REPO / "data/curated/dose-class-gates.json"
TOXIC_FLOORS_PATH = REPO / "data/curated/toxic-dose-floors.json"
REPORT_PATH = REPO / "data/snapshots/dose-gate-report.md"

#: A common midpoint this many times the other sources' median (or its
#: reciprocal) is no longer a disagreement about a dose; 10× is a unit or
#: identity slip. Fewer than three other sources is too few to call a median.
OUTLIER_FACTOR = 10.0
OUTLIER_MIN_OTHER_SOURCES = 3

#: Tiers a toxic floor is compared against. `heavy` is left out on purpose: it
#: is the tier that says "dangerous", so a heavy value at a floor is correct.
FLOOR_TIERS = (
    "threshold",
    "light_lower",
    "light_upper",
    "common_lower",
    "common_upper",
    "strong_lower",
    "strong_upper",
)

# Shulgin's DOSAGE field states a no-activity bound as often as a dose:
# "greater than 60 mg", "> 25 mgs", "300 mg or greater", "40 mg and above",
# "unknown". Each carries a number the collector's parser reads, and a bound is
# the amount that did nothing, never a dose to show.
_NO_ACTIVITY_BOUND_RE = re.compile(
    r"greater than|more than|>\s*\d|\babove\b|\bor (?:greater|more|higher)\b"
    r"|\band (?:above|up|over)\b|\bunknown\b|\buncertain\b"
    r"|\bnot (?:known|determined|established)\b|\bat least\b",
    re.IGNORECASE,
)
_DOSAGE_RANGE_RE = re.compile(r"\d+(?:\.\d+)?\s*(?:-|–|—|to)\s*\d+(?:\.\d+)?")
_DOSAGE_NUMBER_RE = re.compile(r"\d+(?:\.\d+)?")


def shulgin_dosage_verdict(text: str | None) -> str:
    """Classify one PIHKAL/TIHKAL DOSAGE clause.

    ``bound`` (a no-activity bound or "unknown": no ladder), ``range`` (a stated
    range), ``single`` (one figure, stored as itself) or ``none`` (no number)."""
    if not text:
        return "none"
    if _NO_ACTIVITY_BOUND_RE.search(text):
        return "bound"
    if _DOSAGE_RANGE_RE.search(text):
        return "range"
    if _DOSAGE_NUMBER_RE.search(text):
        return "single"
    return "none"


#: Routes whose onset physically cannot complete inside a minute.
ABSORBED_ROUTES = ("oral", "sublingual", "buccal", "rectal", "transdermal", "insufflation")
ABSORPTION_FLOOR_MINUTES = 1.0

#: Mass units the ceilings are compared in, as multiples of one milligram.
_MG_PER_UNIT = {"mg": 1.0, "µg": 0.001, "ug": 0.001, "mcg": 0.001, "g": 1000.0}

TIERS = (
    "threshold",
    "light_lower",
    "light_upper",
    "common_lower",
    "common_upper",
    "strong_lower",
    "strong_upper",
    "heavy",
)


@dataclass
class GateHit:
    rule: str
    substance: str
    source: str
    route: str
    detail: str


@dataclass
class GateResult:
    hits: list[GateHit] = field(default_factory=list)

    def by_rule(self) -> dict[str, list[GateHit]]:
        out: dict[str, list[GateHit]] = {}
        for hit in self.hits:
            out.setdefault(hit.rule, []).append(hit)
        return out


def load_gates(path: Path = GATES_PATH) -> list[dict]:
    if not path.exists():
        return []
    return [g for g in json.loads(path.read_text()).get("gates") or [] if g.get("class_context")]


def mg_factor(unit: str | None) -> float | None:
    """Milligrams per one of `unit`, or None for a unit that is not a plain mass
    (µg/kg, mL, units) — those are outside what a ceiling can judge."""
    head = (unit or "").strip().split()[0].lower() if unit else ""
    return _MG_PER_UNIT.get(head)


def apply_class_ceilings(cur: sqlite3.Cursor, gates: list[dict], result: GateResult) -> int:
    deleted = 0
    for gate in gates:
        ceiling = float(gate["max_tier_mg"])
        exempt = tuple(gate.get("exempt_sources") or ())
        # A ceiling states that a whole class is dosed below it. Where that is
        # true of the class but not of one member, the member is exempted with
        # its own citation rather than the ceiling being raised for everyone.
        exempt_names = {
            str(e["substance"]).strip().lower() for e in gate.get("exempt_substances") or []
        }
        rows = cur.execute(
            f"""
            SELECT d.id, su.canonical_name, src.slug, d.route, d.unit, d.citation_id,
                   {", ".join("d." + t for t in TIERS)}
              FROM dose_ranges d
              JOIN substances su ON su.id = d.substance_id
              JOIN sources src ON src.id = d.source_id
              JOIN substance_classes sc ON sc.substance_id = su.id
              JOIN class_contexts cc ON cc.id = sc.class_context_id
             WHERE cc.slug = ?
            """,
            (gate["class_context"],),
        ).fetchall()
        for row in rows:
            row_id, name, slug, route, unit, citation_id, *tiers = row
            if slug in exempt or citation_id is not None:
                continue
            if (name or "").strip().lower() in exempt_names:
                continue
            factor = mg_factor(unit)
            if factor is None:
                continue
            offending = [
                (tier, value)
                for tier, value in zip(TIERS, tiers, strict=True)
                if value is not None and value * factor > ceiling
            ]
            if not offending:
                continue
            cur.execute("DELETE FROM dose_ranges WHERE id = ?", (row_id,))
            deleted += 1
            worst = max(offending, key=lambda pair: pair[1])
            result.hits.append(
                GateHit(
                    rule=f"class ceiling · {gate['class_context']} ≤ {ceiling:g} mg",
                    substance=name,
                    source=slug,
                    route=route,
                    detail=(
                        f"{worst[0]} {worst[1]:g} {unit} — {len(offending)} tier(s) above the "
                        f"ceiling; {gate.get('reason', '')}".rstrip("; ")
                    ),
                )
            )
    return deleted


def apply_absorption_floor(cur: sqlite3.Cursor, result: GateResult) -> int:
    placeholders = ", ".join("?" * len(ABSORBED_ROUTES))
    rows = cur.execute(
        f"""
        SELECT d.id, su.canonical_name, src.slug, d.route, d.phase, d.min_minutes, d.max_minutes
          FROM durations d
          JOIN substances su ON su.id = d.substance_id
          JOIN sources src ON src.id = d.source_id
         WHERE d.route IN ({placeholders})
           AND d.phase IN ('onset', 'comeup', 'peak', 'offset', 'afterglow', 'total')
           AND d.max_minutes < ?
        """,
        (*ABSORBED_ROUTES, ABSORPTION_FLOOR_MINUTES),
    ).fetchall()
    for row_id, name, slug, route, phase, low, high in rows:
        cur.execute("DELETE FROM durations WHERE id = ?", (row_id,))
        result.hits.append(
            GateHit(
                rule="absorption floor · phase under 1 min on an absorbed route",
                substance=name,
                source=slug,
                route=route,
                detail=f"{phase} {low:g}–{high:g} min",
            )
        )
    return len(rows)


def load_toxic_floors(path: Path = TOXIC_FLOORS_PATH) -> list[dict]:
    if not path.exists():
        return []
    return list(json.loads(path.read_text()).get("floors") or [])


def apply_toxic_floors(cur: sqlite3.Cursor, floors: list[dict], result: GateResult) -> int:
    deleted = 0
    for floor in floors:
        floor_mg = float(floor["floor_mg"])
        rows = cur.execute(
            f"""
            SELECT d.id, su.canonical_name, src.slug, d.route, d.unit,
                   {", ".join("d." + t for t in FLOOR_TIERS)}
              FROM dose_ranges d
              JOIN substances su ON su.id = d.substance_id
              JOIN sources src ON src.id = d.source_id
             WHERE lower(su.canonical_name) = lower(?) AND d.route = ? AND d.citation_id IS NULL
            """,
            (floor["substance"], floor["route"]),
        ).fetchall()
        for row_id, name, slug, route, unit, *tiers in rows:
            factor = mg_factor(unit)
            if factor is None:
                continue
            reached = [
                (tier, value)
                for tier, value in zip(FLOOR_TIERS, tiers, strict=True)
                if value is not None and value * factor >= floor_mg
            ]
            if not reached:
                continue
            cur.execute("DELETE FROM dose_ranges WHERE id = ?", (row_id,))
            deleted += 1
            tier, value = max(reached, key=lambda pair: pair[1])
            result.hits.append(
                GateHit(
                    rule=f"toxic floor · {floor['kind']} at {floor_mg:g} mg",
                    substance=name,
                    source=slug,
                    route=route,
                    detail=(
                        f"{tier} {value:g} {unit} reaches the {floor['kind']} floor "
                        f"({floor['citation']})"
                    ),
                )
            )
    return deleted


def _common_midpoint_mg(lower, upper, unit) -> float | None:
    factor = mg_factor(unit)
    values = [v for v in (lower, upper) if v is not None and v > 0]
    if factor is None or not values:
        return None
    return sum(values) / len(values) * factor


def apply_cross_source_outliers(cur: sqlite3.Cursor, result: GateResult) -> int:
    rows = cur.execute(
        """
        SELECT d.id, su.canonical_name, src.slug, d.route, d.unit, d.common_lower,
               d.common_upper, d.citation_id, d.substance_id, d.dose_context,
               COALESCE(d.isomer, '')
          FROM dose_ranges d
          JOIN substances su ON su.id = d.substance_id
          JOIN sources src ON src.id = d.source_id
        """
    ).fetchall()
    groups: dict[tuple, list[tuple]] = {}
    for row in rows:
        mid = _common_midpoint_mg(row[5], row[6], row[4])
        if mid is None:
            continue
        groups.setdefault((row[8], row[3], row[9], row[10]), []).append((*row, mid))
    doomed: list[tuple[tuple, float, int]] = []
    for members in groups.values():
        for row in members:
            if row[7] is not None or row[2] == "piru-curated":
                continue
            # One vote per other source: a source's several rows (salts) are
            # its median, so a source cannot outvote the rest by repetition.
            by_source: dict[str, list[float]] = {}
            for other in members:
                if other[2] != row[2]:
                    by_source.setdefault(other[2], []).append(other[-1])
            if len(by_source) < OUTLIER_MIN_OTHER_SOURCES:
                continue
            median = statistics.median(statistics.median(v) for v in by_source.values())
            ratio = row[-1] / median
            if ratio >= OUTLIER_FACTOR or ratio <= 1 / OUTLIER_FACTOR:
                doomed.append((row, median, len(by_source)))
    # Judged against the full set first, deleted after, so one deletion cannot
    # move the median another row is judged against.
    for row, median, n_sources in doomed:
        row_id, name, slug, route, unit, low, high = row[:7]
        cur.execute("DELETE FROM dose_ranges WHERE id = ?", (row_id,))
        result.hits.append(
            GateHit(
                rule=f"cross-source outlier · common ≥ {OUTLIER_FACTOR:g}× from the other sources",
                substance=name,
                source=slug,
                route=route,
                detail=(
                    f"common {low:g}–{high:g} {unit} vs a median of {median:g} mg across "
                    f"{n_sources} other sources ({row[-1] / median:.3g}×; context {row[9]})"
                ),
            )
        )
    return len(doomed)


# ------------------------------------------------------------- foreign scripts

#: Columns that hold a name. Names are legitimately in any script (the Thai
#: street name for kratom, a Russian brand, a Chinese title), so only
#: characters that are not text at all are refused there.
NAME_COLUMNS = frozenset(
    {
        ("aliases", "alias"),
        ("aliases", "alias_normalized"),
        ("localized_names", "name"),
        ("localized_names", "name_normalized"),
        ("substances", "canonical_name"),
        ("substances", "normalized_name"),
        ("substances", "freeodwiki_slug"),
        ("substance_forms", "display_name"),
        ("citations", "title"),
    }
)
#: Scripts every text cell may use. CJK is here because English notes quote
#: Japanese and Chinese sources verbatim (a PMDA review sentence).
_BASE_SCRIPTS = frozenset({"LATIN", "GREEK", "MICRO", "MODIFIER"})
_CJK_SCRIPTS = frozenset(
    {"CJK", "HIRAGANA", "KATAKANA", "KATAKANA-HIRAGANA", "HALFWIDTH", "FULLWIDTH", "IDEOGRAPHIC"}
)
#: A row tagged with a non-English language (`language`/`locale`) may also
#: quote Cyrillic: the Chinese prose on Russian-origin compounds gives their
#: Russian names (Семакс).
_FOREIGN_ROW_EXTRA = frozenset({"CYRILLIC"})
_LANGUAGE_COLUMNS = ("language", "locale")


def _char_class(ch: str) -> str | None:
    """The script a character belongs to for this gate, '' for one that is
    never text (unassigned, private use, a surrogate, a stray control, U+FFFD),
    or None for script-neutral characters (digits, punctuation, symbols,
    spaces, combining marks)."""
    cat = unicodedata.category(ch)
    if cat in ("Cn", "Co", "Cs") or ch == "�" or (cat == "Cc" and ch not in "\n\r\t"):
        return ""
    if cat[0] in "PSZM" or cat == "Cf" or cat == "Cc" or (cat == "Nd" and ch.isascii()):
        return None
    if cat[0] not in "LN":
        return None
    name = unicodedata.name(ch, "")
    head = name.split(" ")[0] if name else ""
    if head in _BASE_SCRIPTS or head in _CJK_SCRIPTS:
        return head
    # Compatibility letters that decompose to Latin/Greek (ℓ, Å, ª, ﬁ, ²)
    # are spellings of the base script, not another one.
    folded = unicodedata.normalize("NFKD", ch)
    if folded != ch and all(_char_class(c) in (None, *_BASE_SCRIPTS) for c in folded):
        return None
    return head or ""


def _words(text: str):
    """Maximal runs of letters, marks and digits."""
    start = None
    for i, ch in enumerate(text):
        inside = unicodedata.category(ch)[0] in "LMN"
        if inside and start is None:
            start = i
        elif not inside and start is not None:
            yield text[start:i]
            start = None
    if start is not None:
        yield text[start:]


def foreign_characters(text: str, *, name_column: bool, foreign_row: bool) -> list[str]:
    """Characters in `text` that do not belong in the cell, in order.

    A whole word in another script is a quotation and belongs: English prose
    gives Bromantane's Russian trade name (Ладастен). A letter of another script
    inside a number or a Latin word is not a word at all — "10ጰ min", "~10В h"
    are a dash or a digit some export mangled — and neither is a lone letter."""
    allowed = set(_BASE_SCRIPTS | _CJK_SCRIPTS)
    if foreign_row:
        allowed |= _FOREIGN_ROW_EXTRA
    out = []
    for ch in text:
        if not ch.isascii() and _char_class(ch) == "":
            out.append(ch)
    for word in _words(text):
        if word.isascii():
            continue
        classes = [_char_class(ch) for ch in word]
        alien = {c for c in classes if c and c not in allowed}
        if not alien or name_column:
            continue
        letters = [ch for ch in word if unicodedata.category(ch)[0] == "L"]
        quoted = (
            len(alien) == 1
            and len(letters) >= 2
            and all(unicodedata.category(ch)[0] in "LM" for ch in word)
            and all(c in alien or c is None for c in classes)
        )
        if not quoted:
            out.extend(ch for ch, c in zip(word, classes, strict=True) if c in alien)
    return out


def _null_json_leaves(value, bad) -> tuple[object, int]:
    """`value` with every string leaf holding a foreign character set to null."""
    if isinstance(value, dict):
        nulled = 0
        out = {}
        for key, inner in value.items():
            out[key], n = _null_json_leaves(inner, bad)
            nulled += n
        return out, nulled
    if isinstance(value, list):
        pairs = [_null_json_leaves(inner, bad) for inner in value]
        return [p[0] for p in pairs], sum(p[1] for p in pairs)
    if isinstance(value, str) and bad(value):
        return None, 1
    return value, 0


def foreign_cells(cur: sqlite3.Cursor):
    """Every shipped text cell holding characters `foreign_characters` refuses,
    as dicts: table, column, rowid, value, chars, nullable, substance_id,
    source_id, route. Read-only; `apply_script_gate` acts on them."""
    tables = [
        r[0]
        for r in cur.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
    ]
    for table in tables:
        info = cur.execute(f'PRAGMA table_info("{table}")').fetchall()
        columns = {row[1]: row for row in info}
        language = next((c for c in _LANGUAGE_COLUMNS if c in columns), None)
        for column, (_, _, _, notnull, _, pk) in columns.items():
            name_column = (table, column) in NAME_COLUMNS
            select = [
                "t.rowid",
                f't."{column}"',
                f't."{language}"' if language else "NULL",
                "t.substance_id" if "substance_id" in columns else "NULL",
                "t.source_id" if "source_id" in columns else "NULL",
                "t.route" if "route" in columns else "NULL",
            ]
            try:
                rows = cur.execute(
                    f'SELECT {", ".join(select)} FROM "{table}" t '
                    f"WHERE typeof(t.\"{column}\") = 'text' AND t.\"{column}\" GLOB '*[^ -~]*'"
                ).fetchall()
            except sqlite3.OperationalError:
                continue  # a WITHOUT ROWID table: none hold prose
            for rowid, value, lang, sid, src, route in rows:
                foreign_row = bool(lang) and not str(lang).lower().startswith("en")
                chars = foreign_characters(value, name_column=name_column, foreign_row=foreign_row)
                if chars:
                    yield {
                        "table": table,
                        "column": column,
                        "rowid": rowid,
                        "value": value,
                        "chars": chars,
                        "nullable": not (notnull or pk),
                        "name_column": name_column,
                        "foreign_row": foreign_row,
                        "substance_id": sid,
                        "source_id": src,
                        "route": route,
                    }


def apply_script_gate(cur: sqlite3.Cursor, result: GateResult) -> int:
    """Drop every shipped text cell carrying characters from a script that does
    not belong there (Ethiopic syllables standing in for an en dash in a dose
    string, a Cyrillic letter inside an English number), and report it.

    The cell goes, never the characters: "~75ጒ5 mg" was some range, and
    deleting the glyph would invent "~755 mg". A JSON cell loses only the
    string values that carry one. A NOT NULL cell that is not JSON takes its
    row with it."""
    cells = list(foreign_cells(cur))
    for cell in cells:
        table, column, rowid, value = cell["table"], cell["column"], cell["rowid"], cell["value"]

        def bad(text, cell=cell):
            return foreign_characters(
                text, name_column=cell["name_column"], foreign_row=cell["foreign_row"]
            )

        parsed = None
        if value[:1] in "[{":
            try:
                parsed = json.loads(value)
            except ValueError:
                parsed = None
        if parsed is not None:
            cleaned, n = _null_json_leaves(parsed, bad)
            cur.execute(
                f'UPDATE "{table}" SET "{column}" = ? WHERE rowid = ?',
                (json.dumps(cleaned, ensure_ascii=False, separators=(",", ":")), rowid),
            )
            action = f"{n} JSON value(s) nulled"
        elif cell["nullable"]:
            cur.execute(f'UPDATE "{table}" SET "{column}" = NULL WHERE rowid = ?', (rowid,))
            action = "cell nulled"
        else:
            cur.execute(f'DELETE FROM "{table}" WHERE rowid = ?', (rowid,))
            action = "row deleted"
        substance = source = None
        if cell["substance_id"] is not None:
            substance = cur.execute(
                "SELECT canonical_name FROM substances WHERE id = ?", (cell["substance_id"],)
            ).fetchone()
        if cell["source_id"] is not None:
            source = cur.execute(
                "SELECT slug FROM sources WHERE id = ?", (cell["source_id"],)
            ).fetchone()
        chars = cell["chars"]
        where = value.find(chars[0])
        excerpt = value[max(0, where - 20) : where + 20].replace("|", "/").replace("\n", " ")
        names = ", ".join(sorted({f"U+{ord(c):04X} {unicodedata.name(c, '?')}" for c in chars}))
        result.hits.append(
            GateHit(
                rule="foreign script · characters no source text uses",
                substance=substance[0] if substance else "—",
                source=source[0] if source else "—",
                route=cell["route"] or "—",
                detail=f"{table}.{column}: {action}; “…{excerpt}…” ({names})",
            )
        )
    return len(cells)


def run(cur: sqlite3.Cursor, *, gates_path: Path = GATES_PATH) -> GateResult:
    """The gates that judge a row on its own terms, run once every source has
    spoken. `run_late` and `apply_script_gate` run later in the build and add
    to the same result."""
    result = GateResult()
    apply_class_ceilings(cur, load_gates(gates_path), result)
    apply_absorption_floor(cur, result)
    return result


def run_late(
    cur: sqlite3.Cursor, result: GateResult, *, floors_path: Path = TOXIC_FLOORS_PATH
) -> int:
    """The gates that need the finished catalog: a toxic floor names a substance
    by the canonical name it ends the build with (structural merges fold a
    source's "PMA" into "Para-Methoxyamphetamine" after `run`), and the outlier
    rule groups by the dosing context assigned near the end."""
    deleted = apply_toxic_floors(cur, load_toxic_floors(floors_path), result)
    return deleted + apply_cross_source_outliers(cur, result)


def write_report(result: GateResult, path: Path = REPORT_PATH) -> None:
    lines = [
        "# Dose gate report",
        "",
        "Rows and cells the build refused: a class or tag ceiling, a cited toxic floor "
        "(`data/curated/toxic-dose-floors.json`), a phase too short for its route, a "
        "Shulgin no-activity bound, a ladder ten times from every other source, or "
        "characters from a script no source text uses. Each is a value to report "
        "upstream; each rule is in `pipeline/build/dose_gates.py`.",
        "",
        f"{len(result.hits)} row(s) deleted.",
        "",
    ]
    for rule, hits in sorted(result.by_rule().items()):
        lines += [f"## {rule}", "", "| substance | source | route | detail |", "|---|---|---|---|"]
        for hit in sorted(hits, key=lambda h: (h.substance, h.source, h.route)):
            lines.append(f"| {hit.substance} | {hit.source} | {hit.route} | {hit.detail} |")
        lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines))
    # The same rows as data, for `audit/upstream_report.py` to list per source.
    path.with_suffix(".json").write_text(
        json.dumps([hit.__dict__ for hit in result.hits], indent=2, ensure_ascii=False) + "\n"
    )
