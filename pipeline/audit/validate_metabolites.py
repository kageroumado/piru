#!/usr/bin/env python3
"""Validate and merge active-metabolite research into one enrichment file.

Research agents write per-class JSON batches; this checks them against the
schema `add_metabolism` expects, rejects the failure modes an LLM researcher is
prone to (fabricated or malformed citations, guessed numbers, potency values
with no stated basis), and merges the survivors into
`data/enrichment/raw/metabolites-active.json`.

    python3 pipeline/audit/validate_metabolites.py <input-dir> [--write] [--verify-citations]

Without `--write` it reports only. Every rejection is printed with its reason —
a silently dropped record would leave the DB looking complete when it isn't.

`--verify-citations` resolves every DOI against Crossref and every PMID against
NCBI, and prints the resolved title next to the drug it was cited for. Shape
checks cannot catch a *well-formed but invented* DOI, which is the failure mode
that matters most here; this can. Read the titles — a real DOI cited for the
wrong drug is still wrong.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DB = REPO / "Piru/Data/piru-substances.sqlite"
OUT = REPO / "data/enrichment/raw/metabolites-active.json"

# A citation must be something `cite()` will actually store. This cannot prove
# the reference *exists*, but it does catch the invented free-text
# "Smith et al. 2019" shape and obviously malformed DOIs.
DOI_RE = re.compile(r"^doi:10\.\d{4,9}/\S+$", re.IGNORECASE)
PMID_RE = re.compile(r"^pmid:\d{4,9}$", re.IGNORECASE)

# `url:` references are accepted only from regulators and national libraries. An
# FDA prescribing label is a better source for a drug's PK than most journal
# articles, and `cite()` stores it (it is not in _NON_LITERATURE_HOSTS) — so
# rejecting it outright, as this script first did, threw away good data. A URL
# anywhere else is not a citation: it is where the model happened to read.
CITABLE_URL_HOSTS = (
    "accessdata.fda.gov",
    "fda.gov",
    "ncbi.nlm.nih.gov/books",
    "dailymed.nlm.nih.gov",
    "ema.europa.eu",
    "medicines.org.uk",
    "pubmed.ncbi.nlm.nih.gov",
)
BARE_URL_RE = re.compile(r"^https?://\S+$", re.IGNORECASE)

POTENCY_BASES = {"clinical", "receptor_affinity", "in_vitro", "unknown"}

# Sanity bounds. A half-life outside these is a unit error (hours logged as
# minutes, or days as hours) far more often than a real value.
MIN_HALF_LIFE = 0.5  # 30 seconds
MAX_HALF_LIFE = 60 * 24 * 400  # 400 days


def normalize_reference(value: object) -> object:
    """Strip a decorative `word:` prefix from a URL reference.

    Researchers label URLs variously — `url:https://…`, `fda_label:https://…`.
    `parse_reference` keeps the URL either way but files the prefix as the
    citation's *title*, so the app would render a reference literally titled
    "fda_label". The bare URL is the clean form, and normalizing here means one
    agent's labelling habit can't cost a whole batch its citations.
    """
    if not isinstance(value, str):
        return value
    stripped = value.strip()
    match = re.match(r"^[a-z_]+:(https?://\S+)$", stripped, re.IGNORECASE)
    return match.group(1) if match else stripped


def valid_citation(value: object) -> bool:
    if not isinstance(value, str):
        return False
    if DOI_RE.match(value) or PMID_RE.match(value):
        return True
    candidate = normalize_reference(value)
    if isinstance(candidate, str) and BARE_URL_RE.match(candidate):
        lowered = candidate.lower()
        return any(host in lowered for host in CITABLE_URL_HOSTS)
    return False


#: Crossref asks callers to identify themselves; doing so also gets the faster
#: "polite pool". Not a real mailbox — a project identifier.
_UA = "piru-metabolite-validator/1.0 (https://kagerou.glass; mailto:mail@kagerou.glass)"


def resolve_citation(ref: str) -> tuple[bool, str]:
    """Resolve a reference to (found, title). Network; used only under
    ``--verify-citations``. A well-formed DOI that resolves to nothing is an
    invented one — the failure mode a regex can never catch."""
    try:
        if ref.lower().startswith("doi:"):
            doi = ref[4:]
            request = urllib.request.Request(
                f"https://api.crossref.org/works/{urllib.parse.quote(doi)}",
                headers={"Accept": "application/json", "User-Agent": _UA},
            )
            with urllib.request.urlopen(request, timeout=25) as response:
                message = json.load(response)["message"]
            titles = message.get("title") or ["(untitled)"]
            return (True, titles[0])
        if ref.lower().startswith("pmid:"):
            pmid = ref[5:]
            request = urllib.request.Request(
                "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
                f"?db=pubmed&retmode=json&id={pmid}",
                headers={"User-Agent": _UA},
            )
            with urllib.request.urlopen(request, timeout=25) as response:
                payload = json.load(response)["result"]
            record = payload.get(pmid) or {}
            if not record or record.get("error"):
                return (False, "not found")
            return (True, record.get("title", "(untitled)"))
    except urllib.error.HTTPError as exc:
        return (False, f"HTTP {exc.code}")
    except Exception as exc:  # network flake shouldn't read as fabrication
        return (False, f"lookup failed: {type(exc).__name__}")
    return (True, "(url — not machine-checkable)")


def verify_all_citations(pairs: list[tuple[str, str]]) -> None:
    """`pairs` is [(where, reference)]. Prints one line per unique reference."""
    seen: dict[str, list[str]] = {}
    for where, ref in pairs:
        seen.setdefault(ref, []).append(where)
    print(f"\n--- verifying {len(seen)} unique citation(s) ---")
    missing = 0
    for ref in sorted(seen):
        if not (ref.lower().startswith("doi:") or ref.lower().startswith("pmid:")):
            continue
        found, title = resolve_citation(ref)
        cited_for = ", ".join(sorted({w.split(":", 1)[-1].split(".")[0] for w in seen[ref]}))
        status = "OK  " if found else "GONE"
        if not found:
            missing += 1
        print(f"  {status} {ref}\n         cited for: {cited_for}\n         title: {title[:100]}")
        time.sleep(0.2)
    print(f"  ({missing} unresolvable)" if missing else "  (all resolved)")


def known_substances() -> dict[str, str]:
    """normalized name/alias -> canonical name, for resolving parent records."""
    if not DB.exists():
        return {}
    con = sqlite3.connect(DB)
    out: dict[str, str] = {}
    for canonical, norm in con.execute("SELECT canonical_name, normalized_name FROM substances"):
        out[norm.lower()] = canonical
        out[canonical.lower()] = canonical
    for canonical, alias in con.execute(
        "SELECT s.canonical_name, a.alias FROM aliases a JOIN substances s ON s.id = a.substance_id"
    ):
        out.setdefault(alias.lower(), canonical)
    con.close()
    return out


def canonicalize(name: str, known: dict[str, str]) -> tuple[str, str | None]:
    """Resolve a researched name onto the DB's canonical name.

    Returns ``(name, note)``. Researchers write disambiguated titles —
    "Heroin (diacetylmorphine)", "Pethidine (meperidine)" — which match nothing.
    Left alone, ``upsert_substance`` would happily CREATE a second Heroin, so
    every dose ever logged against the real one would miss the new metabolite
    data. Strip the parenthetical and try the inner name as an alias too
    (Meperidine is an alias of Demerol, so the parenthetical is the resolvable
    half).
    """
    if not known:
        return (name, None)
    if name.lower() in known:
        return (known[name.lower()], None)

    candidates: list[str] = []
    if "(" in name:
        outer = name.split("(", 1)[0].strip()
        inner = name[name.find("(") + 1 : name.rfind(")")].strip() if ")" in name else ""
        candidates += [outer, inner]
    candidates.append(name.replace("-", " ").strip())

    for candidate in candidates:
        if candidate and candidate.lower() in known:
            resolved = known[candidate.lower()]
            return (resolved, f"name {name!r} resolved to DB substance {resolved!r}")
    return (name, f"name {name!r} does not resolve to any DB substance or alias")


def check_number(value: object, field: str, errors: list[str]) -> float | None:
    if value is None:
        return None
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        errors.append(f"{field}: not a number ({value!r})")
        return None
    return float(value)


def validate_metabolite(row: dict, where: str, errors: list[str], warnings: list[str]) -> bool:
    ok = True
    if not row.get("enzyme"):
        errors.append(f"{where}: missing enzyme (add_metabolism would silently drop the row)")
        ok = False
    if not row.get("metabolite_name"):
        warnings.append(f"{where}: no metabolite_name — enzyme-only row")

    half_life = check_number(
        row.get("metabolite_half_life_min"), f"{where}.metabolite_half_life_min", errors
    )
    if half_life is not None and not (MIN_HALF_LIFE <= half_life <= MAX_HALF_LIFE):
        errors.append(
            f"{where}: metabolite_half_life_min {half_life} out of range — probable unit error"
        )
        ok = False
    # A number with no citation is exactly the guessed value we must not ship.
    if half_life is not None and not valid_citation(row.get("reference")):
        errors.append(
            f"{where}: metabolite_half_life_min present but reference is not citable ({row.get('reference')!r}) — uncited number, dropping"
        )
        ok = False

    potency = check_number(
        row.get("metabolite_potency_vs_parent_pct"),
        f"{where}.metabolite_potency_vs_parent_pct",
        errors,
    )
    basis = row.get("metabolite_potency_basis")
    if potency is not None:
        if basis not in POTENCY_BASES:
            errors.append(
                f"{where}: potency {potency} with invalid basis {basis!r} — must be one of {sorted(POTENCY_BASES)}"
            )
            ok = False
        elif basis == "unknown":
            warnings.append(
                f"{where}: potency {potency} has basis 'unknown' — not usable as an effect multiplier"
            )

    fraction = check_number(
        row.get("formation_fraction_pct"), f"{where}.formation_fraction_pct", errors
    )
    if fraction is not None and not (0 <= fraction <= 100):
        errors.append(f"{where}: formation_fraction_pct {fraction} outside 0-100")
        ok = False

    if row.get("reference") is not None and not valid_citation(row.get("reference")):
        warnings.append(
            f"{where}: reference {row.get('reference')!r} is not citable — citation dropped on ingest"
        )
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("input_dir", type=Path, help="Directory containing per-class JSON batches")
    parser.add_argument(
        "--write", action="store_true", help="Emit the merged enrichment file (dry run without)"
    )
    parser.add_argument(
        "--verify-citations", action="store_true", help="Resolve every DOI/PMID and print titles"
    )
    args = parser.parse_args()
    src = args.input_dir
    write = args.write

    known = known_substances()
    merged: list[dict] = []
    errors: list[str] = []
    warnings: list[str] = []
    stats = {
        "files": 0,
        "records": 0,
        "metabolite_rows": 0,
        "with_half_life": 0,
        "with_parent_hl": 0,
    }
    citations: list[tuple[str, str]] = []

    for path in sorted(src.glob("*.json")):
        stats["files"] += 1
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"{path.name}: unparseable JSON — {exc}")
            continue
        if not isinstance(data, list):
            errors.append(f"{path.name}: top level is {type(data).__name__}, expected a list")
            continue

        for rec in data:
            if not isinstance(rec, dict) or not rec.get("name"):
                errors.append(f"{path.name}: record without a name")
                continue
            name, note = canonicalize(rec["name"], known)
            where = f"{path.name}:{name}"
            if note:
                if "does not resolve" in note:
                    errors.append(
                        f"{where}: {note} — ingest would CREATE a duplicate; fix the name"
                    )
                else:
                    warnings.append(f"{where}: {note}")

            parent_hl = check_number(
                rec.get("parent_half_life_min"), f"{where}.parent_half_life_min", errors
            )
            if parent_hl is not None:
                if not (MIN_HALF_LIFE <= parent_hl <= MAX_HALF_LIFE):
                    errors.append(f"{where}: parent_half_life_min {parent_hl} out of range")
                    parent_hl = None
                elif not valid_citation(rec.get("parent_half_life_reference")):
                    errors.append(
                        f"{where}: parent_half_life_min present but reference is not citable ({rec.get('parent_half_life_reference')!r}) — uncited number, dropping"
                    )
                    parent_hl = None
                else:
                    stats["with_parent_hl"] += 1
                    citations.append((where, rec["parent_half_life_reference"]))

            kept: list[dict] = []
            for index, row in enumerate(rec.get("metabolism") or []):
                if not isinstance(row, dict):
                    errors.append(f"{where}.metabolism[{index}]: not an object")
                    continue
                if row.get("reference") and valid_citation(row.get("reference")):
                    citations.append((where, row["reference"]))
                if validate_metabolite(row, f"{where}.metabolism[{index}]", errors, warnings):
                    if row.get("reference") is not None:
                        row["reference"] = normalize_reference(row["reference"])
                    kept.append(row)
                    stats["metabolite_rows"] += 1
                    if row.get("metabolite_half_life_min") is not None:
                        stats["with_half_life"] += 1

            out: dict = {"name": name}
            if parent_hl is not None:
                out["parent_half_life_min"] = parent_hl
                out["parent_half_life_reference"] = normalize_reference(
                    rec["parent_half_life_reference"]
                )
                if rec.get("parent_half_life_notes"):
                    out["parent_half_life_notes"] = rec["parent_half_life_notes"]
            if kept:
                out["metabolism"] = kept
            # A record carrying neither a parent half-life nor a usable metabolite
            # row would add nothing but an upsert.
            if len(out) > 1:
                merged.append(out)
                stats["records"] += 1

    print(
        f"files={stats['files']} records={stats['records']} metabolite_rows={stats['metabolite_rows']} "
        f"with_metabolite_half_life={stats['with_half_life']} with_parent_half_life={stats['with_parent_hl']}"
    )
    if warnings:
        print(f"\n--- {len(warnings)} warning(s) ---")
        for w in warnings:
            print(f"  WARN {w}")
    if errors:
        print(f"\n--- {len(errors)} error(s) ---")
        for e in errors:
            print(f"  ERR  {e}")

    if args.verify_citations and citations:
        verify_all_citations(citations)

    if write:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
        print(f"\nwrote {OUT.relative_to(REPO)} ({len(merged)} records)")
    else:
        print("\n(dry run — pass --write to emit the merged enrichment file)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
