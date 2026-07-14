"""Integrity gate for the hand-curated substance overlay in the bundled DB.

The overlay (`data/curated/substances/*.json`) is ingested as the highest-
priority source `piru-curated`, so a bad curated file silently overrides good
upstream data. These tests encode the failure modes found in the 2026-07 overlay
audit (see `pipeline/audit/survey_curated_overlay.py` and the memory note
`curated-overlay-audit`) as regression gates:

  1. Every curated file resolves to a real DB substance (no orphaned/dead files).
  2. No curated file name is chemistry-noise (the build drops it at ingest, so
     the override never lands — a silent no-op file).
  3. No CROSS-CATEGORY dose/duration clone blocks — an identical ladder shared by
     substances in different categories is a copy-paste template, not real data
     (2-FDCK≡Lithium orotate, Escitalopram≡Prochlorperazine, …).
  4. No exact-InChIKey duplicate substance rows — same exact key on two rows is a
     merge failure or identifier corruption. (Connectivity-block matches are
     legitimate stereoisomer families and are deliberately NOT flagged.)

Each check carries a documented allowlist of *currently-known* debt. The overlay
cleanup pass (`pipeline/audit/clean_curated_overlay.py`) removes these and the
allowlists shrink toward empty; meanwhile any NEW violation fails immediately.

Run from the repo root (needs the built DB):
    python3 pipeline/build/tests/test_overlay_integrity.py
"""

import sqlite3
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parents[3]
_DB = _REPO / "Piru/Data/piru-substances.sqlite"
sys.path.insert(0, str(_REPO / "pipeline/audit"))
sys.path.insert(0, str(_REPO / "pipeline"))

import collision_registry  # noqa: E402
import overlay_lib as L  # noqa: E402

is_chemistry_noise = L.is_chemistry_noise


# ---------------------------------------------------------------------------
# Documented known debt (shrink as clean_curated_overlay.py lands). An entry
# here is a "known, not-yet-fixed" violation, not an approved exception — the
# goal state is empty sets. New violations outside these sets fail the suite.
# ---------------------------------------------------------------------------
_KNOWN_UNRESOLVED: set[str] = set()  # cleanup deleted the last one (plus-cpca.json)

# Cross-category clone clusters (identical dose/duration block spanning ≥2
# categories). Keyed by frozenset of member substance names.
# Residual after the 2026-07 cleanup pass (clean_curated_overlay.py stripped the
# clones that had upstream fallback). These remaining clusters have NO non-curated
# source for the cloned route, so auto-stripping would lose all dose/duration data
# — they need a human to supply real per-compound numbers. Shrink as fixed.
_KNOWN_CROSS_CATEGORY_DOSE = {
    frozenset({"CBN-O", "Delta-8-THC", "HHC", "Zinc Picolinate"}),
    frozenset({"Labetalol", "Magnesium Glycinate", "Phosphatidylserine", "Sabroxy"}),
    frozenset({"Asenapine", "Dronabinol", "Epidiolex"}),
    frozenset({"Carbamazepine", "Cimetidine"}),
    frozenset({"Diphenhydramine", "Hydroxyzine"}),
    frozenset({"Epitalon", "THCP"}),
    frozenset({"Ketotifen", "Nabilone"}),
    frozenset({"Lemborexant", "Selegiline"}),
    frozenset({"Metoprolol", "Topiramate"}),
}
_KNOWN_CROSS_CATEGORY_DURATION = {
    frozenset({"Alpha-Lipoic Acid", "Guaifenesin", "Sumatriptan"}),
    frozenset({"Gepirone", "Thiothixene"}),
    frozenset({"Methocarbamol", "Vitamin C"}),
}
# Exact-InChIKey collisions across distinct rows: merge failures / corruption.
# Emptied by Stage 0.0a — every cluster that used to appear here is now resolved:
# the corrupt-key clusters (Ephedrine/Pseudoephedrine, 4F-PHP/a-PHP, Dextro/Levo-
# methorphan, Butonitazene/Metodesnitazene, 4-HO-DiPT/4-HO-MPT) got distinct
# PubChem-verified keys via IDENTIFIER_CORRECTIONS; the same-drug dupes (HXE/
# Hydroxetamine, Ethketamine/Ethylketamine, Marinol) merge via the collision
# registry's forced merges; and Cannabis's plant structure is nulled so it no
# longer carries THC's key. See data/curated/inchikey-collisions.json. Any new
# exact-key collision now fails immediately — this set must stay empty.
_KNOWN_INCHIKEY_DUPS: set[str] = set()


def _load():
    con = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True)
    try:
        return L.load_db(con)
    finally:
        con.close()


@unittest.skipUnless(_DB.exists(), f"built DB missing at {_DB}")
class OverlayIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.db = _load()
        cls.files = L.load_curated_files()

    # --- 1. every curated file resolves to a DB substance ---
    def test_every_curated_file_resolves(self):
        unresolved = set()
        for fp, entry in self.files:
            if entry is None:
                self.fail(f"curated file failed to parse: {fp.name}")
            name = entry.get("name") or fp.stem
            if L.resolve(self.db, name, entry.get("aliases")) is None:
                unresolved.add(name)
        new = unresolved - _KNOWN_UNRESOLVED
        self.assertEqual(new, set(), f"curated files resolving to no DB substance: {sorted(new)}")
        stale = _KNOWN_UNRESOLVED - unresolved
        self.assertEqual(
            stale, set(), f"allowlist entries no longer unresolved (tighten it): {sorted(stale)}"
        )

    # --- 2. no chemistry-noise curated file names (dropped at ingest) ---
    def test_no_chemnoise_curated_names(self):
        noise = {
            (entry.get("name") or fp.stem)
            for fp, entry in self.files
            if entry and is_chemistry_noise(entry.get("name") or "")
        }
        new = noise - _KNOWN_UNRESOLVED
        self.assertEqual(
            new, set(), f"curated files with chemistry-noise names (silent no-ops): {sorted(new)}"
        )

    # --- 3. no cross-category clone blocks ---
    def _cross_category(self, kind):
        # Rebuild fingerprints straight from curated files + resolved categories,
        # then apply the SAME clone-cluster rule the survey/clean tools use
        # (via L.clone_clusters) so the guard can't drift from the code it guards.
        from collections import defaultdict

        fps = defaultdict(list)
        cats = {}
        for fp, entry in self.files:
            if entry is None:
                continue
            name = entry.get("name") or fp.stem
            rec = L.resolve(self.db, name, entry.get("aliases"))
            cats[name] = L.resolved_category(entry, rec)
            analysis = L.analyze_file(entry, rec)
            key = "dose_fingerprints" if kind == "dose" else "dur_fingerprints"
            for fpkey, route in analysis[key]:
                fps[fpkey].append((name, route))
        return {
            frozenset(c["substances"]) for c in L.clone_clusters(fps, cats) if c["cross_category"]
        }

    def test_no_cross_category_dose_clones(self):
        found = self._cross_category("dose")
        new = found - _KNOWN_CROSS_CATEGORY_DOSE
        self.assertEqual(
            new,
            set(),
            "new cross-category dose clone blocks (copy-paste templates):\n  "
            + "\n  ".join(sorted(", ".join(sorted(s)) for s in new)),
        )

    def test_no_cross_category_duration_clones(self):
        found = self._cross_category("dur")
        new = found - _KNOWN_CROSS_CATEGORY_DURATION
        self.assertEqual(
            new,
            set(),
            "new cross-category duration clone blocks:\n  "
            + "\n  ".join(sorted(", ".join(sorted(s)) for s in new)),
        )

    # --- 4. no exact-InChIKey duplicate substance rows ---
    def test_no_exact_inchikey_duplicates(self):
        found = {g["inchikey"] for g in L.inchikey_duplicates(self.db)}
        new = found - _KNOWN_INCHIKEY_DUPS
        self.assertEqual(
            new,
            set(),
            f"new exact-InChIKey duplicate rows (merge failure / corruption): {sorted(new)}",
        )
        stale = _KNOWN_INCHIKEY_DUPS - found
        self.assertEqual(
            stale, set(), f"allowlist InChIKeys no longer duplicated (tighten it): {sorted(stale)}"
        )

    # --- tooling smoke test: the audit lib can read the DB and derive candidates ---
    def test_isomer_families_derivable(self):
        fams = L.isomer_families(self.db)
        parents = {f["parent"] for f in fams}
        # Ketamine/Esketamine is the canonical example the spec names; it must derive.
        self.assertIn("Ketamine", parents, "expected Ketamine as a stereoisomer fold parent")
        ket = next(f for f in fams if f["parent"] == "Ketamine")
        codes = {v["name"]: v["isomer"] for v in ket["variants"]}
        self.assertEqual(codes.get("Esketamine"), "S")

    # --- the curated isomer fold seed stays valid (every name is a real row) ---
    def test_isomer_seed_map_valid(self):
        import json

        seed = json.loads((L.REPO / "data/curated/isomer-families.json").read_text())
        for fam in seed["families"]:
            self.assertIsNotNone(
                L.resolve(self.db, fam["parent"]), f"isomer parent not in DB: {fam['parent']}"
            )
            for v in fam["variants"]:
                self.assertIsNotNone(
                    L.resolve(self.db, v["name"]), f"isomer variant not in DB: {v['name']}"
                )
                self.assertIn(v["isomer"], {"R", "S", "D", "L"}, f"bad isomer code: {v}")
        # A folded variant is never itself a fold parent (no chains).
        parents = {f["parent"] for f in seed["families"]}
        variants = {v["name"] for f in seed["families"] for v in f["variants"]}
        self.assertEqual(parents & variants, set(), "isomer variant also listed as a parent")

    # --- 5. collision registry dispositions actually hold in the built DB ---
    def _key_of(self, name):
        row = self.con.execute(
            "SELECT inchikey FROM substances WHERE canonical_name = ?", (name,)
        ).fetchone()
        return row[0] if row else "__MISSING__"

    def test_collision_registry_distinct_have_distinct_keys(self):
        """Every 'distinct' cluster's members that carry a full InChIKey must NOT
        share one — the Stage 0.0a corrections made these genuinely-different (or
        structure-null) so PSID FAMILY seeding can trust them (spec 0.1 criterion)."""
        self.con = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True)
        try:
            for members in collision_registry.distinct_clusters():
                keys = [self._key_of(n) for n in members]
                present = [k for k in keys if k not in ("__MISSING__", None) and len(k) >= 27]
                self.assertEqual(
                    len(present),
                    len(set(present)),
                    f"distinct cluster shares a full InChIKey (0.0a regressed): "
                    f"{dict(zip(members, keys, strict=True))}",
                )
        finally:
            self.con.close()

    def test_collision_registry_merges_applied(self):
        """Every 'merge' cluster collapsed: the winner (`into`) survives as a
        canonical row and each loser is gone (folded to an alias)."""
        self.con = sqlite3.connect(f"file:{_DB}?mode=ro", uri=True)
        try:
            for cluster in collision_registry.load().get("merge", []):
                into = cluster["into"]
                self.assertNotEqual(
                    self._key_of(into), "__MISSING__", f"merge winner missing: {into}"
                )
                for loser in cluster["members"]:
                    if loser == into:
                        continue
                    self.assertEqual(
                        self._key_of(loser),
                        "__MISSING__",
                        f"merge loser still a canonical row (not folded): {loser} -> {into}",
                    )
        finally:
            self.con.close()


if __name__ == "__main__":
    unittest.main()
