"""Every hand-written exception is either cited or openly a judgment call.

Five places let a human overrule the sources — the per-source dose exceptions,
the class dose ceilings, the engine flags, the adjudicated removal list, and the
two duration constants in `sqlite.py`. All five are invisible once applied: a
suppressed ladder looks exactly like a ladder that was never there, and a
removed row looks exactly like a row nobody ever scraped. So each entry has to
say what it rests on.

Two kinds of answer are allowed:

  * a `citation` — a PMID, DOI, ISBN, label set id, PubChem CID, CAS number,
    trial id, patent number or a PIHKAL/TIHKAL entry — for the fact the entry's
    prose asserts; or
  * an explicit `reason_only` sentence saying why no source can be cited, and
    then the entry's name must already be in `reason-only-baseline.json`.

That baseline is a **ratchet**: an entry missing from it fails (no new
uncited exception), and a baseline line that no longer matches anything fails
too (the list shrinks as entries are sourced or deleted, and never quietly
grows stale). Nothing here may be relaxed to make a build pass — a gate or an
exception that cannot be justified gets deleted instead, which is a data change
with a diff, not a silent weakening.

Run from the repo root:
    python3 pipeline/build/tests/test_exception_sourcing.py
"""

import importlib.util
import json
import re
import sqlite3
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "pipeline/build"))
import dose_gates  # noqa: E402

BASELINE = Path(__file__).resolve().parent / "reason-only-baseline.json"
EXCEPTIONS = REPO / "data/curated/dose-source-exceptions.json"
FLAGS = REPO / "data/curated/substance-flags.json"
REMOVED = REPO / "data/curated/removed-substances.json"
DB_PATH = REPO / "Piru/Data/piru-substances.sqlite"

#: What counts as pinning a claim to something a reader can go and check.
IDENTIFIER = re.compile(
    r"""pmid:\s*\d+          # PubMed id
      | doi:\s*10\.          # DOI, written as doi:10.…
      | \b10\.\d{4,}/        # …or bare
      | ISBN\s*[\d-]{10,}
      | set_id\s*[0-9a-f-]{8,}
      | DailyMed[^|]*§       # a label cited down to its section
      | SmPC[^|]*§
      | \bCID\s*\d+          # PubChem
      | \bCAS\s*\d{2,7}-\d{2}-\d
      | \bNCT\d{8}
      | \b[PT]IHKAL\s*\#?\s*\d+
      | Patent\s*(No\.?|number)
      | https?://
    """,
    re.IGNORECASE | re.VERBOSE,
)


def _load_build_module():
    spec = importlib.util.spec_from_file_location(
        "piru_build_sourcing", REPO / "pipeline/build/sqlite.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _cited(value) -> bool:
    """True when `value` (a string or a list of them) pins at least one claim."""
    if isinstance(value, (list, tuple)):
        return any(_cited(v) for v in value)
    return bool(value) and bool(IDENTIFIER.search(str(value)))


def reason_only_rows() -> dict[str, list[str]]:
    """Every entry across the five files that carries a reason instead of a
    citation, keyed the way the baseline lists it.

    Used by the tests below and by nothing else — regenerate the baseline by
    printing this, never by hand-editing a failure away.
    """
    out: dict[str, list[str]] = {}

    rows = []
    for slug, entries in json.loads(EXCEPTIONS.read_text()).items():
        if slug.startswith("_"):
            continue
        for entry in entries:
            if not _cited(entry.get("citation")):
                rows.append(f"{slug} | {entry['name']} | {entry.get('drop') or 'doses'}")
    out["dose-source-exceptions"] = sorted(rows)

    rows = []
    for name, flags in json.loads(FLAGS.read_text())["substances"].items():
        for flag, evidence in flags.items():
            if not _cited(evidence.get("citation")):
                rows.append(f"{name} | {flag}")
    out["substance-flags"] = sorted(rows)

    rows = []
    for entry in json.loads(REMOVED.read_text())["removed"]:
        if not _cited([entry.get("citation"), entry.get("reason"), entry.get("evidence")]):
            rows.append(f"{entry['name']} | {entry['verdict']}")
    out["removed-substances"] = sorted(rows)

    build = _load_build_module()
    out["duration-scrub"] = sorted(
        name
        for name, (_reason, citation) in build.Build.DURATION_SCRUB_NAMES.items()
        if not _cited(citation)
    )
    out["duration-to-doa"] = sorted(
        f"{name} | {route}"
        for name, entries in build.Build.DURATION_TO_DOA.items()
        for route, _mn, _mx, _unit, citation in entries
        if not _cited(citation)
    )
    return out


class ReasonOnlyRatchet(unittest.TestCase):
    """The shrink-only list of entries that no source can settle."""

    @classmethod
    def setUpClass(cls):
        cls.actual = reason_only_rows()
        cls.baseline = json.loads(BASELINE.read_text())

    def test_no_new_uncited_exception(self):
        for section, rows in self.actual.items():
            new = sorted(set(rows) - set(self.baseline.get(section, ())))
            self.assertEqual(
                new,
                [],
                f"{section}: cite these or delete them — never add a line to {BASELINE.name}",
            )

    def test_the_baseline_only_shrinks(self):
        for section, rows in self.baseline.items():
            gone = sorted(set(rows) - set(self.actual.get(section, ())))
            self.assertEqual(
                gone, [], f"{section}: sourced or deleted — remove these lines from {BASELINE.name}"
            )

    def test_every_reason_only_entry_says_why(self):
        """A bare absence of a citation is not a reason. The entry must state,
        in a sentence, what was looked for and why it is not there."""
        thin = []
        for slug, entries in json.loads(EXCEPTIONS.read_text()).items():
            if slug.startswith("_"):
                continue
            for entry in entries:
                if _cited(entry.get("citation")):
                    continue
                if len((entry.get("reason_only") or "").split()) < 12:
                    thin.append(f"{slug}: {entry['name']}")
        for name, flags in json.loads(FLAGS.read_text())["substances"].items():
            for flag, evidence in flags.items():
                if _cited(evidence.get("citation")):
                    continue
                if len((evidence.get("reason_only") or "").split()) < 12:
                    thin.append(f"{name}: {flag}")
        self.assertEqual(thin, [], "reason_only must be a sentence, not an empty field")


class DoseSourceExceptions(unittest.TestCase):
    def test_every_entry_carries_a_citation_or_a_reason(self):
        bad = []
        for slug, entries in json.loads(EXCEPTIONS.read_text()).items():
            if slug.startswith("_"):
                continue
            for entry in entries:
                has_reason = bool((entry.get("reason_only") or "").strip())
                if not _cited(entry.get("citation")) and not has_reason:
                    bad.append(f"{slug}: {entry['name']}")
        self.assertEqual(bad, [], "dose exceptions with neither a citation nor a reason")

    def test_a_citation_is_not_prose(self):
        """`citation` holds identifiers, not an argument — the argument is
        `note`. A sentence in this field reads as sourced without being it.
        The cap is generous because an agency report's full title plus its ISBN
        runs long, and that whole string is still a reference."""
        wordy = []
        for slug, entries in json.loads(EXCEPTIONS.read_text()).items():
            if slug.startswith("_"):
                continue
            for cite in (entry.get("citation") for entry in entries):
                for one in cite if isinstance(cite, list) else [cite] if cite else []:
                    if len(str(one).split()) > 40:
                        wordy.append(f"{slug}: {str(one)[:40]}…")
        self.assertEqual(wordy, [], "citation fields holding prose")


class ClassDoseGates(unittest.TestCase):
    """A class ceiling deletes rows, so it is cited outright — no ratchet."""

    @classmethod
    def setUpClass(cls):
        cls.gates = dose_gates.load_gates()
        cls.names = None
        if DB_PATH.exists():
            con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
            cls.names = {r[0].lower() for r in con.execute("SELECT canonical_name FROM substances")}
            con.close()

    def test_every_gate_is_cited_and_reasoned(self):
        self.assertTrue(self.gates)
        for gate in self.gates:
            where = gate["class_context"]
            self.assertTrue(_cited(gate.get("citation")), f"{where}: ceiling needs a citation")
            self.assertGreater(len((gate.get("reason") or "").split()), 8, where)
            self.assertGreater(float(gate["max_tier_mg"]), 0)

    def test_every_exempt_substance_is_cited_and_real(self):
        """An exemption is the opposite claim to the ceiling's, on one member,
        so it needs its own source — and it must name a substance that exists,
        or it silently exempts nothing."""
        for gate in self.gates:
            for exempt in gate.get("exempt_substances") or []:
                name = exempt["substance"]
                self.assertTrue(_cited(exempt.get("citation")), f"{name}: exemption needs a source")
                self.assertGreater(len((exempt.get("reason") or "").split()), 8, name)
                if self.names is not None:
                    self.assertIn(name.lower(), self.names, name)

    def test_an_exempt_substance_keeps_its_ladder(self):
        """The exemption has to reach the gate, not just the file."""
        exempt = {
            e["substance"]
            for gate in self.gates
            for e in gate.get("exempt_substances") or []
            if gate["class_context"] == "benzimidazole-nitazenes"
        }
        self.assertIn("Clonitazene", exempt)
        con = sqlite3.connect(":memory:")
        con.executescript(
            "CREATE TABLE substances (id INTEGER PRIMARY KEY, canonical_name TEXT);"
            "CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT);"
            "CREATE TABLE class_contexts (id INTEGER PRIMARY KEY, slug TEXT);"
            "CREATE TABLE substance_classes (substance_id INTEGER, class_context_id INTEGER);"
            "CREATE TABLE dose_ranges (id INTEGER PRIMARY KEY, substance_id INTEGER, route TEXT,"
            " source_id INTEGER, unit TEXT, threshold REAL, light_lower REAL, light_upper REAL,"
            " common_lower REAL, common_upper REAL, strong_lower REAL, strong_upper REAL,"
            " heavy REAL, citation_id INTEGER);"
        )
        con.execute("INSERT INTO substances VALUES (1, 'Clonitazene'), (2, 'Etonitazene')")
        con.execute("INSERT INTO sources VALUES (1, 'tripsit')")
        con.execute("INSERT INTO class_contexts VALUES (1, 'benzimidazole-nitazenes')")
        con.execute("INSERT INTO substance_classes VALUES (1, 1), (2, 1)")
        con.executemany(
            "INSERT INTO dose_ranges (substance_id, source_id, route, unit, common_lower,"
            " common_upper) VALUES (?, 1, 'oral', 'mg', ?, ?)",
            [(1, 5, 10), (2, 5, 10)],
        )
        gate = [g for g in self.gates if g["class_context"] == "benzimidazole-nitazenes"]
        deleted = dose_gates.apply_class_ceilings(con.cursor(), gate, dose_gates.GateResult())
        kept = [r[0] for r in con.execute("SELECT substance_id FROM dose_ranges")]
        self.assertEqual((deleted, kept), (1, [1]))


class SubstanceFlags(unittest.TestCase):
    def test_every_flag_row_is_a_mapping_with_evidence(self):
        payload = json.loads(FLAGS.read_text())
        bad = []
        for name, flags in payload["substances"].items():
            if not isinstance(flags, dict):
                bad.append(f"{name}: flags must map each flag to its evidence")
                continue
            for flag, evidence in flags.items():
                if flag not in payload["_flags"]:
                    bad.append(f"{name}: unknown flag {flag!r}")
                if not isinstance(evidence, dict):
                    bad.append(f"{name}/{flag}: evidence must be an object")
                elif (
                    not _cited(evidence.get("citation"))
                    and not (evidence.get("reason_only") or "").strip()
                ):
                    bad.append(f"{name}/{flag}: neither a citation nor a reason")
        self.assertEqual(bad, [])

    def test_a_cited_flag_reaches_the_database(self):
        """The citation is only worth having if it ships with the row."""
        if not DB_PATH.exists():
            self.skipTest("no built database")
        cited = {
            name
            for name, flags in json.loads(FLAGS.read_text())["substances"].items()
            for evidence in flags.values()
            if _cited(evidence.get("citation"))
        }
        con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        rows = dict(
            con.execute(
                "SELECT s.canonical_name, COUNT(f.citation_id) FROM substance_flags f"
                " JOIN substances s ON s.id = f.substance_id GROUP BY 1"
            )
        )
        con.close()
        missing = sorted(n for n in cited if rows.get(n, 0) == 0 and n in rows)
        self.assertEqual(missing, [], "flag rows shipped without their citation_id")


class RemovedSubstances(unittest.TestCase):
    def test_a_pharmacology_or_market_claim_is_cited(self):
        """Covered by the ratchet above; this asserts the field is well-formed
        where it is present, so a typo cannot read as a citation."""
        wrong = []
        for entry in json.loads(REMOVED.read_text())["removed"]:
            cite = entry.get("citation")
            if cite is None:
                continue
            if not _cited(cite):
                wrong.append(f"{entry['name']}: {str(cite)[:48]}")
        self.assertEqual(wrong, [], "citation fields that pin nothing")


if __name__ == "__main__":
    unittest.main(verbosity=2)
