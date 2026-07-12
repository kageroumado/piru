#!/usr/bin/env python3
"""Clean up the hand-curated substance overlay: remove deadweight and false data,
flag suspicious patterns for manual review.

DRY-RUN BY DEFAULT — prints the plan and changes nothing. Pass ``--apply`` to
execute. Every mutation is a curated-JSON edit or a file move to Trash (never a
hard delete), so ``git`` / Trash recover anything.

Actions (in decreasing confidence):

  DELETE-FILE   A curated file whose name is chemistry-noise or resolves to no DB
                substance — the build drops it at ingest, so it is a silent no-op.
                Moved to Trash.

  STRIP-DOSE /  A curated dose/duration block that is a CROSS-CATEGORY clone
  STRIP-DUR     (byte-identical ladder shared with a substance in a different
                category = copy-paste template) AND whose substance has
                non-curated upstream data for that route. Removing the override
                lets real upstream data win. If a route is left with no doses,
                no duration and no other data, the route is dropped; a file left
                with no meaningful override keeps its identity fields.

  FLAG          Everything suspicious but not safe to auto-fix: cross-category
                clones with NO upstream fallback (deleting would lose all data),
                same-category clone templates, exact-InChIKey duplicate rows
                (identifier/merge bugs — fixed in the pipeline, not here), and
                stereoisomer fold candidates. Printed for a human; never changed.

Run from the repo root:
    python3 pipeline/audit/clean_curated_overlay.py            # dry run
    python3 pipeline/audit/clean_curated_overlay.py --apply    # execute
    python3 pipeline/audit/clean_curated_overlay.py --flags     # only the flag report
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import overlay_lib as L  # noqa: E402

is_chemistry_noise = L.is_chemistry_noise


def _dump(entry: dict) -> str:
    return json.dumps(entry, indent=2, ensure_ascii=False) + "\n"


def build_plan(db: dict) -> dict:
    files = L.load_curated_files()

    # Pass 1: per-file analysis + clone fingerprint accumulation.
    recs, dose_fps, dur_fps, cats = {}, defaultdict(list), defaultdict(list), {}
    for fp, entry in files:
        if entry is None:
            continue
        name = entry.get("name") or fp.stem
        rec = L.resolve(db, name, entry.get("aliases"))
        recs[fp] = (entry, name, rec)
        cats[name] = L.resolved_category(entry, rec)
        analysis = L.analyze_file(entry, rec)
        for key, route in analysis["dose_fingerprints"]:
            dose_fps[key].append((name, route))
        for key, route in analysis["dur_fingerprints"]:
            dur_fps[key].append((name, route))

    # Cross-category clone routes: (substance, route) -> True if the block is a
    # cross-category clone. Keyed per route so we strip only the offending route.
    def cross_cat_routes(fps):
        flagged = {}
        for _key, members in fps.items():
            subs = {s for s, _ in members}
            if len(subs) < 2:
                continue
            categories = {cats.get(s) for s in subs if cats.get(s)}
            if len(categories) >= 2:
                for s, route in members:
                    flagged[(s, route)] = True
        return flagged

    xdose = cross_cat_routes(dose_fps)
    xdur = cross_cat_routes(dur_fps)

    deletes, strips, flags = [], [], []

    for fp, (entry, name, rec) in recs.items():
        # DELETE-FILE: chemistry-noise or unresolved.
        if is_chemistry_noise(name) or rec is None:
            deletes.append(
                {
                    "file": fp.name,
                    "name": name,
                    "reason": "chemnoise/unresolved (dropped at ingest)",
                }
            )
            continue

        edited = json.loads(_dump(entry))  # deep copy
        changed = False
        route_actions = []
        surviving_routes = []
        for r in edited.get("routes") or []:
            if not isinstance(r, dict):
                surviving_routes.append(r)
                continue
            route = r.get("route", "")
            # A non-curated source provides this route's dose/duration → stripping
            # the curated clone falls back to real upstream data.
            has_up_dose = bool(rec and (set(rec["doses"].get(route, {})) - {L.CURATED_SOURCE}))
            has_up_dur = bool(rec and (set(rec["durations"].get(route, {})) - {L.CURATED_SOURCE}))

            if r.get("doses") and (name, route) in xdose:
                if has_up_dose:
                    r.pop("doses", None)
                    route_actions.append(f"strip-dose:{route}→upstream")
                    changed = True
                else:
                    flags.append({"kind": "clone-dose-no-fallback", "name": name, "route": route})
            if r.get("duration") and (name, route) in xdur:
                if has_up_dur:
                    r.pop("duration", None)
                    route_actions.append(f"strip-dur:{route}→upstream")
                    changed = True
                else:
                    flags.append({"kind": "clone-dur-no-fallback", "name": name, "route": route})

            # Drop a route left with nothing useful.
            meaningful = any(k for k in r if k not in ("route", "unit"))
            if meaningful:
                surviving_routes.append(r)
            else:
                route_actions.append(f"drop-empty-route:{route}")
                changed = True

        if changed:
            if surviving_routes:
                edited["routes"] = surviving_routes
            else:
                edited.pop("routes", None)
            strips.append(
                {"file": fp.name, "name": name, "actions": route_actions, "new": _dump(edited)}
            )

    # Repo-wide flags (not per-file overlay edits): identifier/merge bugs + folds.
    for g in L.inchikey_duplicates(db):
        flags.append(
            {"kind": "inchikey-dup", "inchikey": g["inchikey"], "substances": g["substances"]}
        )
    for f in L.isomer_families(db):
        flags.append(
            {
                "kind": "isomer-fold",
                "parent": f["parent"],
                "variants": [(v["name"], v["isomer"]) for v in f["variants"]],
            }
        )
    # Same-category (template) clones — lower confidence, flag only.
    for kind, fps in (("dose", dose_fps), ("dur", dur_fps)):
        for _key, members in fps.items():
            subs = sorted({s for s, _ in members})
            if len(subs) < 2:
                continue
            categories = {cats.get(s) for s in subs if cats.get(s)}
            if len(categories) == 1:
                flags.append(
                    {
                        "kind": f"clone-{kind}-same-category",
                        "category": next(iter(categories)),
                        "substances": subs,
                    }
                )

    return {"deletes": deletes, "strips": strips, "flags": flags}


def print_plan(plan: dict) -> None:
    d, s = plan["deletes"], plan["strips"]
    print(f"DELETE-FILE ({len(d)}):")
    for a in d:
        print(f"   {a['file']:44s} {a['reason']}")
    print(f"\nSTRIP override fields ({len(s)} files):")
    for a in s:
        print(f"   {a['file']:44s} {', '.join(a['actions'])}")
    print()
    print_flags(plan)


def print_flags(plan: dict) -> None:
    by_kind = defaultdict(list)
    for f in plan["flags"]:
        by_kind[f["kind"]].append(f)
    print("FLAG (manual review — not changed):")
    for kind in sorted(by_kind):
        items = by_kind[kind]
        print(f"  {kind} ({len(items)}):")
        for f in items[:40]:
            if kind == "inchikey-dup":
                print(f"     {f['inchikey']}: {', '.join(f['substances'])}")
            elif kind == "isomer-fold":
                vs = ", ".join(f"{n}({c or '?'})" for n, c in f["variants"])
                print(f"     {f['parent']} ← {vs}")
            elif kind.endswith("same-category"):
                print(f"     [{f['category']}] {', '.join(f['substances'])}")
            else:
                print(f"     {f.get('name')} / {f.get('route')}")
        if len(items) > 40:
            print(f"     … +{len(items) - 40} more")


def apply_plan(plan: dict) -> None:
    for a in plan["strips"]:
        (L.CURATED_DIR / a["file"]).write_text(a["new"])
        print(f"  stripped {a['file']}: {', '.join(a['actions'])}")
    for a in plan["deletes"]:
        path = L.CURATED_DIR / a["file"]
        subprocess.run(["trash", str(path)], check=True)
        print(f"  trashed {a['file']}")
    print(f"\nApplied: {len(plan['strips'])} strips, {len(plan['deletes'])} deletes.")
    print("Now rebuild: pipeline/build.sh fast  →  then re-run the integrity tests.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="execute the plan (default: dry run)")
    ap.add_argument("--flags", action="store_true", help="print only the flag report")
    ap.add_argument("--db", default=str(L.DB))
    args = ap.parse_args()

    if not Path(args.db).exists():
        print(f"error: DB not found at {args.db}; run pipeline/build.sh first", file=sys.stderr)
        return 2

    con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    db = L.load_db(con)
    con.close()
    plan = build_plan(db)

    if args.flags:
        print_flags(plan)
        return 0
    print_plan(plan)
    if args.apply:
        print("\n--- APPLYING ---")
        apply_plan(plan)
    else:
        print("\n(dry run — pass --apply to execute)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
