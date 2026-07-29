#!/usr/bin/env python3
"""Ask whether a substance's dose numbers can all be true at once.

No single dose row looks wrong on its own — 75-150 mg insufflated is a perfectly
ordinary sentence. It is only wrong next to the *same compound's* oral range of
25-70 mg, because insufflation skips first-pass metabolism: it cannot need three
times the drug. That contradiction is invisible while reading one card and
invisible to the pipeline, which never compares a row to its neighbours.

So this cross-checks each substance against itself, three ways:

    ROUTE     a route that should need LESS drug is asking for more.
              Ordering, most bioavailable first:
              IV < IM/SC < inhaled < insufflated < SL/buccal/rectal < oral.
    SOURCE    two sources disagree about the same substance+route by more than
              a factor. Names the outlier against the median of the rest —
              this is what isolates one bad curated row when the others agree.
    LADDER    a single row contradicts itself: every tier's lower and upper
              bound rising in step, lower ≤ upper, all positive, one unit
              dimension per route.

ROUTE compares what the app actually *shows*: for each route the row from the
highest-priority enabled source wins, exactly as `SubstanceStore` resolves it.
A finding therefore means a user can see both numbers, not that some unused row
disagrees — SOURCE covers that case separately.

Within a severity, ROUTE lists the rows the DB **already contradicts** first: if
the offending row is also far from what this route's other sources say, the
numbers are wrong rather than the pharmacology surprising. Those carry an
`outlier` mark. Pure ratio orders the rest.

Real exceptions exist (poor mucosal absorption, volume limits, a route used for
a different effect). Confirm one, then add it to `ROUTE_EXCEPTIONS` below with a
reason; it stops being reported.

    python3 pipeline/audit/dose_sanity.py                    # ranked report
    python3 pipeline/audit/dose_sanity.py --gate             # exit 1 on HIGH
    python3 pipeline/audit/dose_sanity.py --ratio 2.0        # loosen ROUTE
    python3 pipeline/audit/dose_sanity.py --json out.json    # machine-readable

Offline and deterministic — it reads only the built SQLite.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from statistics import median

REPO = Path(__file__).resolve().parents[2]
DEFAULT_DB = REPO / "Piru/Data/piru-substances.sqlite"

#: Bioavailability rank, low number = reaches the blood most completely = needs
#: the smallest dose. Routes sharing a rank are not compared against each other
#: (IM vs SC is a wash). Routes absent from this map are never compared:
#: transdermal is dosed as a rate (mcg/hr) and `other` is a grab bag.
ROUTE_RANK: dict[str, int] = {
    "intravenous": 0,
    "intramuscular": 1,
    "subcutaneous": 1,
    "inhalation": 2,
    "insufflation": 3,
    "sublingual": 4,
    "buccal": 4,
    "rectal": 4,
    "oral": 5,
}

#: DB / upstream spellings → the canonical route names above. Mirrors
#: `RouteOfAdministration.from(string:)` in Shared/RouteOfAdministration.swift,
#: including `buccal`, which is a first-class case there as of 2026-07-28.
ROUTE_ALIASES: dict[str, str] = {
    "oral_ir": "oral",
    "oral_er": "oral",
    "oral(pure)": "oral",
    "oral(benzedrex)": "oral",
    "insufflated": "insufflation",
    "insufflated(pure)": "insufflation",
    "intranasal": "insufflation",
    "nasal": "insufflation",
    "inhaled": "inhalation",
    "smoked": "inhalation",
    "vaporized": "inhalation",
    "vapourized": "inhalation",
    "iv": "intravenous",
    "im": "intramuscular",
    "sc": "subcutaneous",
    "subq": "subcutaneous",
    "plugged": "rectal",
    "topical": "transdermal",
    "sl": "sublingual",
}

#: Confirmed exceptions to the ordering above, keyed by
#: (lowercased substance name, faster route, slower route). Everything here has
#: been checked by a human against the literature — do not add a guess.
ROUTE_EXCEPTIONS: dict[tuple[str, str, str], str] = {}

#: Unit → (dimension, multiplier to the dimension's base). Deliberately exact:
#: a qualified unit ("mg THC", "mg (salt)", "mg (with MAOI)") measures a
#: different thing than plain mg, so it is skipped rather than guessed at.
UNITS: dict[str, tuple[str, float]] = {
    "g": ("mass", 1000.0),
    "gram": ("mass", 1000.0),
    "grams": ("mass", 1000.0),
    "mg": ("mass", 1.0),
    "mgs": ("mass", 1.0),
    "milligram": ("mass", 1.0),
    "milligrams": ("mass", 1.0),
    "µg": ("mass", 0.001),
    "μg": ("mass", 0.001),  # U+03BC, the other micro sign the sources mix in
    "ug": ("mass", 0.001),
    "mcg": ("mass", 0.001),
    "microgram": ("mass", 0.001),
    "micrograms": ("mass", 0.001),
    "ng": ("mass", 1e-6),
    "mg/kg": ("mass_per_kg", 1.0),
    "µg/kg": ("mass_per_kg", 0.001),
    "μg/kg": ("mass_per_kg", 0.001),
    "ug/kg": ("mass_per_kg", 0.001),
    "mcg/kg": ("mass_per_kg", 0.001),
    "ml": ("volume", 1.0),
    "iu": ("iu", 1.0),
}

#: Every ladder column, in card order.
LADDER = (
    "threshold",
    "light_lower",
    "light_upper",
    "common_lower",
    "common_upper",
    "strong_lower",
    "strong_upper",
    "heavy",
)

#: The two sequences that must genuinely rise. Tier *bands* are allowed to
#: overlap — drug.community and TripSit both publish light 10-50 / common 20-60,
#: meaning "50 mg is a big light dose and 20 mg is a small common one", which is
#: a real editorial position and not a contradiction. What cannot happen is a
#: tier's floor or ceiling falling below the tier beneath it.
LADDER_SEQUENCES = (
    ("lower bounds", ("threshold", "light_lower", "common_lower", "strong_lower")),
    ("upper bounds", ("light_upper", "common_upper", "strong_upper", "heavy")),
)

#: Bounds of one tier, which must not be inverted.
TIER_BOUNDS = (
    ("light", "light_lower", "light_upper"),
    ("common", "common_lower", "common_upper"),
    ("strong", "strong_lower", "strong_upper"),
)

#: Band overlaps: reported at LOW because they are usually upstream style, but a
#: *large* one (a light dose above the whole common range) is still worth eyes.
BAND_OVERLAPS = (
    ("light_upper", "common_lower"),
    ("common_upper", "strong_lower"),
    ("strong_upper", "heavy"),
)

#: Tiers tried in order for a cross-route comparison, each as (lower, upper).
#: Common is the tier both sources and both routes are most likely to carry and
#: the one the app shows first; light/strong are fallbacks for sparse rows.
TIERS = (
    ("common", "common_lower", "common_upper"),
    ("light", "light_lower", "light_upper"),
    ("strong", "strong_lower", "strong_upper"),
)

SEVERITIES = ("HIGH", "MEDIUM", "LOW")


@dataclass
class Row:
    """One `dose_ranges` row, normalized to a comparable scale."""

    id: int
    substance: str
    route: str
    raw_route: str
    source: str
    priority: int
    enabled: bool
    unit: str
    dimension: str | None
    values: dict[str, float] = field(default_factory=dict)

    def tier(self, lower: str, upper: str) -> float | None:
        """Midpoint of a tier, or whichever bound exists alone."""
        bounds = [self.values[key] for key in (lower, upper) if key in self.values]
        return sum(bounds) / len(bounds) if bounds else None


@dataclass
class Finding:
    check: str
    severity: str
    score: float  # how badly it is violated; sorts the report
    substance: str
    headline: str
    detail: str
    row_ids: list[int]
    #: Set when the DB already argues with itself about the offending row —
    #: other sources for the same route give a materially different number.
    outlier: str | None = None

    def as_dict(self) -> dict:
        return {
            "check": self.check,
            "severity": self.severity,
            "score": round(self.score, 3),
            "substance": self.substance,
            "headline": self.headline,
            "detail": self.detail,
            "row_ids": self.row_ids,
            "outlier": self.outlier,
        }


def normalize_route(raw: str) -> str:
    key = re.sub(r"\s+", "", (raw or "").strip().lower())
    return ROUTE_ALIASES.get(key, key)


def normalize_unit(raw: str) -> tuple[str | None, float]:
    key = re.sub(r"\s+", "", (raw or "").strip().lower())
    if key in UNITS:
        dimension, factor = UNITS[key]
        return dimension, factor
    return None, 1.0


def load_rows(conn: sqlite3.Connection) -> list[Row]:
    columns = ", ".join(f"d.{name}" for name in LADDER)
    sql = f"""
        SELECT d.id, s.canonical_name, d.route, src.slug, src.default_priority,
               src.default_enabled, d.unit, d.salt_form, d.isomer, {columns}
        FROM dose_ranges d
        JOIN substances s ON s.id = d.substance_id
        JOIN sources src ON src.id = d.source_id
        ORDER BY s.canonical_name, d.route, src.default_priority, d.id
    """
    rows: list[Row] = []
    for record in conn.execute(sql):
        (row_id, substance, raw_route, slug, priority, enabled, unit, salt, isomer) = record[:9]
        dimension, factor = normalize_unit(unit)
        values = {
            name: float(value) * factor
            for name, value in zip(LADDER, record[9:], strict=True)
            if value is not None
        }
        row = Row(
            id=row_id,
            # The facet rides in the substance label so a Sulfate ladder is
            # never compared against a freebase one — different mass per dose.
            substance=facet_label(substance, salt, isomer),
            route=normalize_route(raw_route),
            raw_route=raw_route,
            source=slug,
            priority=priority,
            enabled=bool(enabled),
            unit=unit,
            dimension=dimension,
            values=values,
        )
        rows.append(row)
    return rows


def facet_label(substance: str, salt: str | None, isomer: str | None) -> str:
    parts = [substance]
    if salt:
        parts.append(salt)
    if isomer:
        parts.append(f"{isomer}-isomer")
    return " · ".join(parts)


# ------------------------------------------------------------------ check ROUTE


def resolved_by_route(rows: list[Row]) -> dict[str, Row]:
    """The row the app would display per route: highest-priority source wins.

    Sources off by default never surface, so a violation among them is not
    something a user can see — LADDER and SOURCE still read those rows.
    """
    best: dict[str, Row] = {}
    for row in rows:
        if not row.enabled:
            continue
        current = best.get(row.route)
        if current is None or (row.priority, row.id) < (current.priority, current.id):
            best[row.route] = row
    return best


def check_routes(rows: list[Row], ratio_threshold: float) -> list[Finding]:
    findings: list[Finding] = []
    by_substance: dict[str, list[Row]] = defaultdict(list)
    for row in rows:
        # Only mass ladders are commensurable across routes; a mg/kg row and a
        # mg row describe different people.
        if row.dimension == "mass" and row.route in ROUTE_RANK:
            by_substance[row.substance].append(row)

    for substance, substance_rows in by_substance.items():
        resolved = resolved_by_route(substance_rows)
        routes = sorted(resolved, key=lambda name: ROUTE_RANK[name])
        for index, faster in enumerate(routes):
            for slower in routes[index + 1 :]:
                if ROUTE_RANK[faster] == ROUTE_RANK[slower]:
                    continue
                finding = compare_routes(
                    substance,
                    resolved[faster],
                    resolved[slower],
                    [row for row in substance_rows if row.route == faster],
                    ratio_threshold,
                )
                if finding:
                    findings.append(finding)
    return collapse_by_offender(findings)


def collapse_by_offender(findings: list[Finding]) -> list[Finding]:
    """One line per suspect row.

    A single wrong insufflation figure violates the ordering against oral *and*
    rectal *and* sublingual, which triples the apparent size of the problem
    while pointing at the same row. Keep the worst pair and name the rest.
    """
    worst: dict[int, Finding] = {}
    extras: dict[int, list[str]] = defaultdict(list)
    for finding in findings:
        offender = finding.row_ids[0]
        incumbent = worst.get(offender)
        if incumbent is None or finding.score > incumbent.score:
            if incumbent is not None:
                extras[offender].append(incumbent.headline)
            worst[offender] = finding
        else:
            extras[offender].append(finding.headline)
    for offender, finding in worst.items():
        if others := extras.get(offender):
            finding.detail += f"\n    also over {len(others)} more route(s): " + "; ".join(
                headline.split(" (")[0] for headline in others
            )
    return list(worst.values())


def compare_routes(
    substance: str,
    faster: Row,
    slower: Row,
    faster_peers: list[Row],
    ratio_threshold: float,
) -> Finding | None:
    for tier_name, lower, upper in TIERS:
        faster_dose = faster.tier(lower, upper)
        slower_dose = slower.tier(lower, upper)
        if faster_dose is None or slower_dose is None or slower_dose <= 0:
            continue
        ratio = faster_dose / slower_dose
        if ratio <= ratio_threshold:
            return None
        key = (substance.split(" · ")[0].lower(), faster.route, slower.route)
        if key in ROUTE_EXCEPTIONS:
            return None
        # A route two or more steps up the ladder overshooting is a stronger
        # claim than neighbours swapping, which real pharmacology does.
        gap = ROUTE_RANK[slower.route] - ROUTE_RANK[faster.route]
        severity = "HIGH" if ratio >= 2.5 or (ratio >= 1.8 and gap >= 2) else "MEDIUM"
        return Finding(
            check="ROUTE",
            severity=severity,
            score=ratio,
            substance=substance,
            headline=(
                f"{faster.route} needs {ratio:.1f}x the {slower.route} dose ({tier_name} tier)"
            ),
            detail=(
                f"{faster.route} {describe_tier(faster, lower, upper)} [{faster.source}]"
                f"  vs  {slower.route} {describe_tier(slower, lower, upper)} [{slower.source}]"
            ),
            row_ids=[faster.id, slower.id],
            outlier=peer_disagreement(faster, faster_peers, lower, upper),
        )
    return None


#: How far the offending row must sit from its route's other sources before the
#: DB counts as contradicting itself. Well below the SOURCE threshold: here it
#: is corroborating evidence for a violation already found, not a claim on its
#: own, so it should be sensitive.
PEER_OUTLIER_RATIO = 1.25


def peer_disagreement(row: Row, peers: list[Row], lower: str, upper: str) -> str | None:
    """Phrase describing how this route's other sources contradict `row`, if they do."""
    others = [
        peer.tier(lower, upper) for peer in peers if peer.id != row.id and peer.tier(lower, upper)
    ]
    mine = row.tier(lower, upper)
    if not others or not mine:
        return None
    reference = median(others)
    if reference <= 0 or mine / reference < PEER_OUTLIER_RATIO:
        return None
    return (
        f"{row.source} is also {mine / reference:.1f}x what the other "
        f"{len(others)} source(s) give for {row.route} ({format_dose(reference)} mg)"
    )


def describe_tier(row: Row, lower: str, upper: str) -> str:
    bounds = [row.values[key] for key in (lower, upper) if key in row.values]
    text = "-".join(format_dose(value) for value in bounds)
    return f"{text} mg"


def format_dose(value: float) -> str:
    if value >= 10:
        return f"{value:.0f}"
    if value >= 1:
        return f"{value:.1f}".rstrip("0").rstrip(".")
    return f"{value:.4g}"


# ----------------------------------------------------------------- check SOURCE


def check_sources(rows: list[Row], factor: float) -> list[Finding]:
    findings: list[Finding] = []
    grouped: dict[tuple[str, str], list[Row]] = defaultdict(list)
    for row in rows:
        if row.dimension == "mass":
            grouped[(row.substance, row.route)].append(row)

    for (substance, route), group in grouped.items():
        findings.extend(check_source_group(substance, route, group, factor))
    return findings


def check_source_group(
    substance: str, route: str, group: list[Row], factor: float
) -> list[Finding]:
    for tier_name, lower, upper in TIERS:
        doses = {row.id: row.tier(lower, upper) for row in group}
        usable = [row for row in group if doses[row.id]]
        if len(usable) < 2:
            continue  # this tier is too sparse to compare; try the next one
        if len(usable) == 2:
            # With two rows there is no majority to be an outlier from: the pair
            # simply disagrees, and calling either one wrong would be a coin
            # flip. Report it only when it is too large to be editorial taste.
            return check_source_pair(substance, route, usable, tier_name, lower, upper, factor * 2)
        # The consensus is the median of *everyone*, not of everyone-but-me.
        # Leave-one-out flips the median on a split group and then reports every
        # source as the outlier from every other — three lines for one argument.
        reference = median(doses[row.id] for row in usable)
        findings = []
        for row in usable:
            if reference <= 0:
                break
            ratio = max(doses[row.id] / reference, reference / doses[row.id])
            if ratio <= factor:
                continue
            findings.append(
                Finding(
                    check="SOURCE",
                    severity="HIGH" if ratio >= 2 * factor else "MEDIUM",
                    score=ratio,
                    substance=substance,
                    headline=(
                        f"{route}: {row.source} is {ratio:.1f}x the consensus of "
                        f"{len(usable)} sources ({tier_name} tier)"
                    ),
                    detail=(
                        f"{row.source} {describe_tier(row, lower, upper)}  vs  median "
                        f"{format_dose(reference)} mg of "
                        + ", ".join(
                            f"{other.source} {describe_tier(other, lower, upper)}"
                            for other in usable
                            if other.id != row.id
                        )
                    ),
                    row_ids=[row.id],
                )
            )
        return findings
    return []


def check_source_pair(
    substance: str,
    route: str,
    pair: list[Row],
    tier_name: str,
    lower: str,
    upper: str,
    threshold: float,
) -> list[Finding]:
    first, second = (row.tier(lower, upper) for row in pair)
    ratio = max(first / second, second / first)
    if ratio <= threshold:
        return []
    return [
        Finding(
            check="SOURCE",
            severity="MEDIUM",
            score=ratio,
            substance=substance,
            headline=f"{route}: two sources disagree {ratio:.1f}x ({tier_name} tier)",
            detail="  vs  ".join(
                f"{row.source} {describe_tier(row, lower, upper)}" for row in pair
            ),
            row_ids=[row.id for row in pair],
        )
    ]


# ----------------------------------------------------------------- check LADDER


def check_ladder(rows: list[Row]) -> list[Finding]:
    findings: list[Finding] = []
    for row in rows:
        findings.extend(check_row_ladder(row))
    findings.extend(check_unit_coherence(rows))
    return findings


def check_row_ladder(row: Row) -> list[Finding]:
    findings: list[Finding] = []

    def report(severity: str, score: float, headline: str, detail: str) -> None:
        findings.append(
            Finding(
                check="LADDER",
                severity=severity,
                score=score,
                substance=row.substance,
                headline=f"{row.raw_route}: {headline}",
                detail=f"[{row.source}] {detail} (unit {row.unit})",
                row_ids=[row.id],
            )
        )

    for name, value in row.values.items():
        if value <= 0:
            report("HIGH", 999.0, f"{name} is {value:g}", "a dose cannot be zero or negative")

    for label, sequence in LADDER_SEQUENCES:
        present = [(name, row.values[name]) for name in sequence if name in row.values]
        for (name, value), (next_name, next_value) in zip(present, present[1:], strict=False):
            if next_value < value:
                report(
                    "HIGH",
                    value / next_value if next_value > 0 else 999.0,
                    f"{name} {format_dose(value)} > {next_name} {format_dose(next_value)}",
                    f"the {label} stop rising",
                )

    for tier, lower, upper in TIER_BOUNDS:
        if lower in row.values and upper in row.values and row.values[upper] < row.values[lower]:
            report(
                "HIGH",
                row.values[lower] / max(row.values[upper], 1e-9),
                f"{tier} is {format_dose(row.values[lower])}-{format_dose(row.values[upper])}",
                "the range runs backwards",
            )

    for lower_tier_top, upper_tier_floor in BAND_OVERLAPS:
        if lower_tier_top not in row.values or upper_tier_floor not in row.values:
            continue
        top, floor = row.values[lower_tier_top], row.values[upper_tier_floor]
        if top <= floor or floor <= 0:
            continue
        overlap = top / floor
        # A whole tier swallowed by the one below it is no longer "the bands
        # touch" — the two tiers have stopped meaning different things.
        report(
            "MEDIUM" if overlap >= 3 else "LOW",
            overlap,
            f"{lower_tier_top} {format_dose(top)} > {upper_tier_floor} {format_dose(floor)}",
            "tier bands overlap",
        )

    return findings


def check_unit_coherence(rows: list[Row]) -> list[Finding]:
    """One substance+route measured two incompatible ways cannot be compared."""
    findings: list[Finding] = []
    grouped: dict[tuple[str, str], list[Row]] = defaultdict(list)
    for row in rows:
        grouped[(row.substance, row.route)].append(row)
    for (substance, route), group in grouped.items():
        dimensions = {row.dimension for row in group if row.dimension}
        unknown = [row for row in group if row.dimension is None]
        if len(dimensions) > 1:
            findings.append(
                Finding(
                    check="LADDER",
                    severity="MEDIUM",
                    score=1.0,
                    substance=substance,
                    headline=f"{route}: mixed unit kinds ({', '.join(sorted(dimensions))})",
                    detail=", ".join(f"{row.source} in {row.unit!r}" for row in group),
                    row_ids=[row.id for row in group],
                )
            )
        elif unknown and len(group) > 1:
            findings.append(
                Finding(
                    check="LADDER",
                    severity="LOW",
                    score=0.5,
                    substance=substance,
                    headline=f"{route}: unrecognized unit alongside a normal one",
                    detail=", ".join(f"{row.source} in {row.unit!r}" for row in group),
                    row_ids=[row.id for row in group],
                )
            )
    return findings


# ---------------------------------------------------------------------- report


def rank(findings: list[Finding]) -> list[Finding]:
    return sorted(
        findings,
        key=lambda finding: (
            SEVERITIES.index(finding.severity),
            finding.outlier is None,
            -finding.score,
            finding.substance,
        ),
    )


CHECK_TITLES = {
    "ROUTE": "ROUTE — a more bioavailable route asking for more drug",
    "SOURCE": "SOURCE — sources disagreeing about the same substance+route",
    "LADDER": "LADDER — a row contradicting itself",
}


def print_report(findings: list[Finding], checks: list[str], limit: int, skipped: int) -> None:
    by_check: dict[str, list[Finding]] = defaultdict(list)
    for finding in findings:
        by_check[finding.check].append(finding)

    for check in checks:
        rows = rank(by_check.get(check, []))
        counts = ", ".join(
            f"{sum(1 for f in rows if f.severity == level)} {level}"
            for level in SEVERITIES
            if any(f.severity == level for f in rows)
        )
        print(f"\n{CHECK_TITLES[check]}")
        print(f"  {len(rows)} finding(s){f' — {counts}' if counts else ''}")
        # Severity decides what is worth printing; --limit only truncates the
        # tail, so a HIGH finding can never be pushed off the bottom by a pile
        # of MEDIUMs above it.
        shown = [f for f in rows if f.severity == "HIGH"] or rows[:limit]
        if len(shown) < limit:
            shown = rows[: max(limit, len(shown))]
        for finding in shown:
            mark = f"[{finding.severity}·outlier]" if finding.outlier else f"[{finding.severity}]"
            print(f"\n  {mark} {finding.substance}")
            print(f"    {finding.headline}")
            print(f"    {finding.detail}")
            if finding.outlier:
                print(f"    ↳ {finding.outlier}")
            print(f"    dose_ranges.id {', '.join(str(i) for i in finding.row_ids)}")
        if len(rows) > len(shown):
            print(f"\n  … and {len(rows) - len(shown)} more (raise --limit or use --json)")

    if skipped:
        print(f"\nskipped {skipped} row(s) with a unit too qualified to compare (e.g. 'mg THC')")
    if any(f.check == "ROUTE" for f in findings):
        print(
            "\nA ROUTE finding that is real pharmacology, not bad data? Add it to "
            "ROUTE_EXCEPTIONS in this script:\n"
            '    ("substance name", "faster route", "slower route"): "why, in one line",'
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DEFAULT_DB, help="path to the built SQLite")
    parser.add_argument(
        "--ratio",
        type=float,
        default=1.5,
        help="ROUTE: flag when the more bioavailable route exceeds the other by this factor",
    )
    parser.add_argument(
        "--source-factor",
        type=float,
        default=2.0,
        help="SOURCE: flag a source differing from the median of the others by this factor",
    )
    parser.add_argument(
        "--check",
        choices=("route", "source", "ladder", "all"),
        default="all",
        help="run only one check",
    )
    parser.add_argument("--limit", type=int, default=15, help="findings printed per check")
    parser.add_argument("--json", type=Path, help="write every finding here")
    parser.add_argument(
        "--gate", action="store_true", help="exit 1 when a finding at --gate-severity or worse"
    )
    parser.add_argument("--gate-severity", choices=SEVERITIES, default="HIGH")
    args = parser.parse_args()

    if not args.db.exists():
        print(f"dose-sanity: no database at {args.db}", file=sys.stderr)
        return 2

    conn = sqlite3.connect(args.db)
    try:
        rows = load_rows(conn)
    finally:
        conn.close()

    checks = ["ROUTE", "SOURCE", "LADDER"] if args.check == "all" else [args.check.upper()]
    findings: list[Finding] = []
    if "ROUTE" in checks:
        findings += check_routes(rows, args.ratio)
    if "SOURCE" in checks:
        findings += check_sources(rows, args.source_factor)
    if "LADDER" in checks:
        findings += check_ladder(rows)

    skipped = sum(1 for row in rows if row.dimension is None)
    location = args.db.relative_to(REPO) if args.db.is_relative_to(REPO) else args.db
    print(f"dose-sanity: {len(rows)} dose row(s) in {location}")
    print_report(findings, checks, args.limit, skipped)

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        payload = [finding.as_dict() for finding in rank(findings)]
        args.json.write_text(json.dumps(payload, indent=1) + "\n")
        print(f"\nfull result → {args.json}")

    if args.gate:
        ceiling = SEVERITIES.index(args.gate_severity)
        failures = [f for f in findings if SEVERITIES.index(f.severity) <= ceiling]
        if failures:
            print(
                f"\ndose-sanity: FAILED — {len(failures)} finding(s) at "
                f"{args.gate_severity} or worse",
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
