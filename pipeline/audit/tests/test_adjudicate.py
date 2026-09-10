"""Tests for the deterministic parts of pipeline/audit/adjudicate.py.

What needs pinning is everything that turns messy text or a pile of numbers
into a decision: which receptor spellings are the same receptor, which copied
values count as one vote, which side of a split a consensus lands on, and
whether a feature that fired can still be read off the output. Each test below
is a case that was wrong at some point while the tool was being written.

No database and no network — every input is a literal.

Run from the repo root:
    python3 pipeline/audit/tests/test_adjudicate.py
"""

import importlib.util
import json
import sqlite3
import sys
import unittest
from pathlib import Path

_AUDIT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_AUDIT))
sys.path.insert(0, str(_AUDIT.parent))
_spec = importlib.util.spec_from_file_location("adjudicate", _AUDIT / "adjudicate.py")
_mod = importlib.util.module_from_spec(_spec)
# Registered before execution because `@dataclass` resolves its own module out
# of sys.modules; a module loaded by path alone is not there yet and the
# decorator raises rather than building the class.
sys.modules["adjudicate"] = _mod
_spec.loader.exec_module(_mod)

WEIGHTS = _mod.Weights.load(_AUDIT / "adjudicator_weights.json")


def value(source, number=None, text=None, **provenance):
    return _mod.Value(source=source, numeric=number, text=text, provenance=provenance)


def cell(column="dose", key="dose|oral|||recreational|mass|common_lower", values=()):
    return _mod.Cell(
        column=column,
        key=key,
        substance_id=1,
        substance_uid="TESTKEY",
        substance="Test",
        popularity=0.5,
        values=list(values),
        unit="mg",
    )


class TargetNormalization(unittest.TestCase):
    def test_the_many_spellings_of_one_receptor_meet(self):
        for spelling in (
            "MOR",
            "mu-opioid",
            "μ-opioid receptor",
            "μ-opioid (MOR)",
            "MOR (mu-opioid receptor)",
        ):
            self.assertEqual(_mod.normalize_target(spelling).cell, "MOR", spelling)

    def test_assay_context_does_not_split_a_target(self):
        # Species and tissue say where the number was measured, not what it is of.
        self.assertEqual(_mod.normalize_target("NMDA receptor (rat cortex)").cell, "NMDA")
        self.assertEqual(_mod.normalize_target("DAT (human, HEK293)").cell, "DAT")

    def test_a_different_molecule_keeps_its_own_cell(self):
        # Two enantiomers of methadone are not one measurement of MOR.
        left = _mod.normalize_target("MOR (R-methadone)").cell
        right = _mod.normalize_target("MOR (S-methadone)").cell
        self.assertNotEqual(left, right)
        self.assertNotEqual(left, "MOR")

    def test_subunit_composition_written_either_side_is_one_target(self):
        self.assertEqual(
            _mod.normalize_target("α4β2 nAChR").cell,
            _mod.normalize_target("nAChR (α4β2)").cell,
        )

    def test_the_trailing_letter_of_a_subunit_is_not_the_next_subunit(self):
        # `α4β2` folds to `alpha4beta2`; a greedy optional letter ate the `b`
        # and left the receptor unrecognizable.
        self.assertEqual(_mod.normalize_target("α4β2 nAChR").base, "nAChR")

    def test_a_named_site_folds_across_spellings(self):
        for spelling in ("GABA-A BZD site", "GABAA (benzo site)", "GABA-A benzodiazepine site"):
            self.assertEqual(
                _mod.normalize_target(spelling).cell, "GABA-A [subtype:benzodiazepine]", spelling
            )

    def test_the_alpha2delta_family_is_not_read_as_subunits(self):
        # `α2δ-1` looks exactly like a subunit run and is the receptor's name.
        self.assertEqual(_mod.normalize_target("α2δ-1 (rat brain)").cell, "alpha-2-delta-1")

    def test_nested_parentheses_do_not_leak_into_the_base(self):
        parsed = _mod.normalize_target("α4β2 nAChR (HS, (α4)₂(β2)₃)")
        self.assertEqual(parsed.base, "nAChR")


class Parsing(unittest.TestCase):
    def test_affinity_string(self):
        self.assertEqual(_mod.parse_affinity("Ki 4519 nM"), ("Ki", 4519.0, False))
        self.assertEqual(_mod.parse_affinity("IC50 = 2.5 µM"), ("IC50", 2500.0, False))

    def test_affinity_range_becomes_its_geometric_mean(self):
        measure, number, is_range = _mod.parse_affinity("Ki 10-1000 nM")
        self.assertEqual(measure, "Ki")
        self.assertAlmostEqual(number, 100.0)
        self.assertTrue(is_range)

    def test_duration_text(self):
        self.assertEqual(_mod.parse_duration_text("2-3 hours"), (120.0, 180.0))
        self.assertEqual(_mod.parse_duration_text("90 minutes"), (90.0, 90.0))
        self.assertIsNone(_mod.parse_duration_text(""))

    def test_a_qualified_unit_is_recognized_and_marked(self):
        # `mg THC` measures a different thing than `mg`, so it must not be
        # silently compared — but dropping it loses the row entirely.
        dimension, factor, qualified = _mod.normalize_unit("mg THC")
        self.assertEqual((dimension, factor), ("mass", 1.0))
        self.assertTrue(qualified)
        self.assertEqual(_mod.normalize_unit("mg"), ("mass", 1.0, False))

    def test_micrograms_reach_milligrams(self):
        self.assertEqual(_mod.normalize_unit("µg"), ("mass", 0.001, False))


class CasCheckDigit(unittest.TestCase):
    def test_real_numbers_check(self):
        for cas in ("57-27-2", "54-11-5", "113-45-1", "148553-50-8"):
            self.assertIs(_mod.cas_check_digit_ok(cas), True, cas)

    def test_a_wrong_digit_fails(self):
        self.assertIs(_mod.cas_check_digit_ok("57-27-3"), False)

    def test_a_non_cas_string_has_no_verdict(self):
        self.assertIsNone(_mod.cas_check_digit_ok("not-a-cas"))
        self.assertIsNone(_mod.cas_check_digit_ok(None))


class InChIKeyClaims(unittest.TestCase):
    def test_a_flat_key_and_a_stereo_key_are_one_claim(self):
        # A source that publishes a SMILES with no stereochemistry is making a
        # representation choice, not claiming the racemate — the same tolerance
        # build/check_identifier_integrity.py draws.
        self.assertTrue(
            _mod.same_inchikey_claim("BQJCRHHNABKAKU-UHFFFAOYSA-N", "BQJCRHHNABKAKU-NOSXKOESSA-N")
        )

    def test_two_specified_stereoisomers_are_two_claims(self):
        self.assertFalse(
            _mod.same_inchikey_claim("AYXYPKUFHZROOJ-SSDOTTSWSA-N", "AYXYPKUFHZROOJ-ZETCQYMHSA-N")
        )

    def test_a_different_skeleton_is_never_one_claim(self):
        self.assertFalse(
            _mod.same_inchikey_claim("OMDKHOOGGJRLLX-UHFFFAOYSA-N", "CIDMXLOVFPIHDS-UHFFFAOYSA-N")
        )


class Clustering(unittest.TestCase):
    def test_copies_form_one_cluster(self):
        subject = cell(
            values=[
                value("psychonautwiki", 225.0),
                value("freeodwiki", 225.0),
                value("dosewiki-api", 225.0),
                value("tripsit", 300.0),
            ]
        )
        self.assertEqual(_mod.cluster_values(subject, WEIGHTS), 2)

    def test_copies_do_not_outvote_one_independent_claim(self):
        # Three copies of one ladder and one measurement is two claims, and the
        # heavier *source* decides, not the larger pile of repetitions.
        subject = cell(
            values=[
                value("a", 100.0),
                value("b", 100.0),
                value("c", 100.0),
                value("d", 10.0),
            ]
        )
        _mod.cluster_values(subject, WEIGHTS)
        light = {"a": 0.2, "b": 0.2, "c": 0.2, "d": 1.0}
        self.assertEqual(_mod.cell_consensus(subject, light, WEIGHTS, None), 10.0)

    def test_leaving_a_value_out_leaves_its_copies_out(self):
        # Keeping the copies while dropping the original would let one upstream
        # error corroborate itself.
        subject = cell(values=[value("a", 100.0), value("b", 100.0), value("c", 10.0)])
        _mod.cluster_values(subject, WEIGHTS)
        uniform = {"a": 1.0, "b": 1.0, "c": 1.0}
        reference = _mod.cell_consensus(subject, uniform, WEIGHTS, subject.values[0].cluster)
        self.assertEqual(reference, 10.0)


class SameSourceRows(unittest.TestCase):
    def test_two_rows_from_one_source_are_one_vote(self):
        # drug.community publishes 0.25 and 0.2 for JWH-018's inhaled light
        # dose. Left apart they were two clusters that outvoted the three
        # sources saying 1, and the curated value was then the lone dissenter.
        subject = cell(
            values=[
                value("piru-curated", 1.0),
                value("psychonautwiki", 1.0),
                value("dosewiki-api", 1.0),
                value("drug.community", 0.25),
                value("drug.community", 0.2),
            ]
        )
        self.assertEqual(_mod.cluster_values(subject, WEIGHTS), 2)

    def test_a_source_disagreeing_with_itself_is_recorded(self):
        subject = cell(values=[value("drug.community", 40.0), value("drug.community", 20.0)])
        _mod.cluster_values(subject, WEIGHTS)
        self.assertEqual(subject.values[0].provenance["within_source_spread"], 2.0)
        self.assertGreater(_mod.within_source_feature(subject.values[0]), 0.0)

    def test_two_upstream_records_stay_two_claims(self):
        # Two dose.wiki articles claiming one Piru row are two claims about
        # which molecule it is, not one article listing two numbers.
        subject = cell(
            column="chemistry",
            key="chemistry|inchikey",
            values=[
                value("dosewiki-api", text="OMDKHOOGGJRLLX-UHFFFAOYSA-N", slug="4-aco-met"),
                value("dosewiki-api", text="CIDMXLOVFPIHDS-UHFFFAOYSA-N", slug="4-aco-mipt"),
            ],
        )
        self.assertEqual(_mod.cluster_values(subject, WEIGHTS), 2)


class ThinClassPrior(unittest.TestCase):
    def _prior(self, peers):
        subject = cell(
            column="duration",
            key="duration|intravenous|||comeup|max",
            values=[
                value("dosewiki", 0.0833),
                value("psychonautwiki", 0.0833),
                value("drug.community", 29.5),
            ],
        )
        substance = _mod.Substance(
            id=1,
            uid=None,
            name="Heroin",
            popularity=0.9,
            inchikey=None,
            cas=None,
            formula=None,
            molecular_weight=None,
            smiles=None,
            drug_class=None,
            classes=["classical-opioids"],
        )
        priors = {("class_context", "classical-opioids", subject.key): peers}
        return _mod.class_prior_for(subject, substance, priors, WEIGHTS)

    def test_peers_echoing_one_party_do_not_count_as_evidence(self):
        # Three of heroin's five classical-opioid peers are a number
        # drug.community published alone; a prior fitted on those then rules for
        # drug.community against the two sources contradicting it.
        echoes = frozenset({"drug.community"})
        peers = {
            2: (4.5, echoes),
            3: (10.0, echoes),
            4: (28.2, echoes),
            5: (20.0, frozenset({"dosewiki", "psychonautwiki"})),
            6: (5.0, frozenset({"dosewiki", "psychonautwiki"})),
        }
        prior = self._prior(peers)
        self.assertIsNotNone(prior)
        self.assertLess(prior.members, int(WEIGHTS.class_prior["min_class_members"]))

    def test_peers_with_their_own_backing_do_count(self):
        outside = frozenset({"tripsit", "medtap"})
        peers = {index: (float(index), outside) for index in range(2, 9)}
        prior = self._prior(peers)
        self.assertGreaterEqual(prior.members, int(WEIGHTS.class_prior["min_class_members"]))


class DerivedSources(unittest.TestCase):
    def test_a_recomputation_never_corroborates_the_row_it_was_computed_from(self):
        # rdkit-smiles is derived from piru-stored's own SMILES. Counting it as a
        # second vote let Piru corroborate itself and made every outside
        # correction read as the lone dissenter.
        subject = cell(
            column="chemistry",
            key="chemistry|inchikey",
            values=[
                value("piru-stored", text="BQJCRHHNABKAKU-NOSXKOESSA-N"),
                value("rdkit-smiles", text="BQJCRHHNABKAKU-NOSXKOESSA-N"),
                value("dosewiki-api", text="BQJCRHHNABKAKU-KBQPJGBKSA-N"),
            ],
        )
        self.assertEqual(_mod.cluster_values(subject, WEIGHTS), 2)
        uniform = dict.fromkeys(("piru-stored", "rdkit-smiles", "dosewiki-api"), 1.0)
        # One vote each side, so the heavier source cannot be outvoted by a
        # recomputation of itself.
        members = _mod.cluster_members(subject)
        weights_by_cluster = [
            _mod.cluster_weight(values, uniform, WEIGHTS) for values in members.values()
        ]
        self.assertLess(max(weights_by_cluster), 2.0)

    def test_a_disagreeing_recomputation_is_recorded_on_the_parent(self):
        subject = cell(
            column="chemistry",
            key="chemistry|inchikey",
            values=[
                value("piru-stored", text="AAAAAAAAAAAAAA-SSDOTTSWSA-N"),
                value("rdkit-smiles", text="AAAAAAAAAAAAAA-ZETCQYMHSA-N"),
            ],
        )
        self.assertEqual(_mod.cluster_values(subject, WEIGHTS), 1)
        parent = subject.values[0]
        self.assertTrue(parent.provenance.get("derived_disagrees"))
        self.assertTrue(subject.values[1].provenance.get("derived_from"), "piru-stored")

    def test_the_parent_speaks_for_the_cluster(self):
        subject = cell(values=[value("piru-stored", 10.0), value("rdkit-smiles", 1000.0)])
        _mod.cluster_values(subject, WEIGHTS)
        uniform = {"piru-stored": 1.0, "rdkit-smiles": 1.0}
        self.assertEqual(_mod.cell_consensus(subject, uniform, WEIGHTS, None), 10.0)


class Symmetry(unittest.TestCase):
    def test_a_standoff_is_scored_the_same_on_both_sides(self):
        subject = cell(
            column="chemistry",
            key="chemistry|inchikey",
            values=[
                value("piru-stored", text="AAAAAAAAAAAAAA-SSDOTTSWSA-N"),
                value("dosewiki-api", text="AAAAAAAAAAAAAA-ZETCQYMHSA-N"),
            ],
        )
        subject.values[0].features = {"source_unreliability": 0.1, "citation_missing": 1.0}
        subject.values[1].features = {"source_unreliability": 0.9, "citation_missing": 1.0}
        _mod.symmetrize(subject, WEIGHTS)
        self.assertEqual(subject.values[0].probability, subject.values[1].probability)


class LadderConsistency(unittest.TestCase):
    def test_a_ladder_that_stops_rising_names_both_bands(self):
        violations = _mod.ladder_violations(
            {"threshold": 5.0, "light_lower": 10.0, "common_lower": 8.0}
        )
        self.assertEqual(violations["break"], {"light_lower", "common_lower"})

    def test_an_inverted_tier_is_not_a_point_estimate(self):
        violations = _mod.ladder_violations({"light_lower": 20.0, "light_upper": 10.0})
        self.assertEqual(violations["inverted"], {"light_lower", "light_upper"})
        self.assertEqual(violations["point"], set())

    def test_min_equals_max_is_a_point_estimate(self):
        violations = _mod.ladder_violations({"common_lower": 30.0, "common_upper": 30.0})
        self.assertEqual(violations["point"], {"common_lower", "common_upper"})


class Slips(unittest.TestCase):
    def test_a_thousandfold_ratio_is_a_unit_slip(self):
        self.assertEqual(_mod.slip_features(1000.0, WEIGHTS)["slip_1000x"], 1.0)
        self.assertEqual(_mod.slip_features(0.001, WEIGHTS)["slip_1000x"], 1.0)

    def test_an_ordinary_disagreement_is_not_a_slip(self):
        self.assertEqual(sum(_mod.slip_features(2.7, WEIGHTS).values()), 0.0)


class Probability(unittest.TestCase):
    def test_a_corroborated_value_scores_low(self):
        features = dict.fromkeys(WEIGHTS.features, 0.0)
        self.assertLess(_mod.logistic(features, WEIGHTS), 0.1)

    def test_every_weight_named_in_the_file_is_a_feature_the_code_emits(self):
        emitted = {
            "log_delta",
            "sole_dissenter",
            "no_corroboration",
            "copy_only_support",
            "class_z",
            "citation_missing",
            "source_unreliability",
            "ladder_break",
            "bounds_inverted",
            "point_estimate",
            "route_order_violation",
            "unit_qualified",
            "context_conflict",
            "identity_skeleton_mismatch",
            "identity_stereo_mismatch",
            "cas_checkdigit_fail",
            "inchikey_smiles_mismatch",
            "unit_basis_mismatch",
            "within_source_disagreement",
            "assay_context_differs",
            "class_signal_thin",
            "slip_1000x",
            "slip_100x",
            "slip_10x",
        }
        self.assertEqual(set(WEIGHTS.features), emitted)

    def test_citation_quality_is_bounded(self):
        best = _mod.citation_quality(
            {
                "citation": {"doi": "10.1/x", "is_review": True},
                "confidence": "HIGH",
                "assay_context": True,
            },
            WEIGHTS,
        )
        self.assertLessEqual(best, 1.0)
        self.assertEqual(_mod.citation_quality({}, WEIGHTS), 0.0)


class WeightedMedian(unittest.TestCase):
    def test_weight_moves_the_median(self):
        self.assertEqual(_mod.weighted_median([(1.0, 1.0), (10.0, 5.0)]), 10.0)

    def test_zero_weight_does_not_vote(self):
        self.assertEqual(_mod.weighted_median([(1.0, 0.0), (10.0, 1.0)]), 10.0)

    def test_nothing_to_average_has_no_answer(self):
        self.assertIsNone(_mod.weighted_median([]))


class ClassPrior(unittest.TestCase):
    def test_a_tight_class_still_has_a_floor(self):
        prior = _mod.ClassPrior(level="class_context", members=8, median_log=1.0, mad_log=0.15)
        # 100x above a class centred on 10 mg is a large z, not an infinite one.
        self.assertGreater(prior.z(1000.0), 5.0)

    def test_class_keys_run_most_specific_first(self):
        substance = _mod.Substance(
            id=1,
            uid=None,
            name="x",
            popularity=0.0,
            inchikey=None,
            cas=None,
            formula=None,
            molecular_weight=None,
            smiles=None,
            drug_class="SSRI",
            classes=["fentanyl-anilidopiperidines"],
            interaction_classes=["opioid"],
            categories=["Opioid"],
        )
        levels = [level for level, _key in _mod.class_keys(substance, WEIGHTS)]
        self.assertEqual(levels, ["class_context", "drug_class", "interaction_class", "category"])


class WeightsFile(unittest.TestCase):
    def test_the_file_holds_every_tunable(self):
        raw = json.loads((_AUDIT / "adjudicator_weights.json").read_text())
        for section in (
            "clustering",
            "reliability",
            "class_prior",
            "slips",
            "citation",
            "features",
            "bias",
            "thresholds",
            "evidence_levels",
            "dosewiki",
        ):
            self.assertIn(section, raw)

    def test_a_pin_overrides_the_derived_weight(self):
        # piru-curated exists to override a consensus that copied a wrong
        # number, so its distance from that consensus is not its reliability.
        self.assertIn("piru-curated", WEIGHTS.pinned)

    def test_the_derived_source_names_its_parent(self):
        self.assertEqual(WEIGHTS.dependencies.get("rdkit-smiles"), "piru-stored")

    def test_an_explanatory_feature_moves_no_probability(self):
        # assay_context_differs names why two numbers differ; scoring it would
        # report a rat EC50 against a human one as a transcription error.
        self.assertEqual(WEIGHTS.features["assay_context_differs"], 0.0)

    def test_evidence_levels_are_ordered(self):
        levels = WEIGHTS.evidence_levels
        counts = [
            levels[name]
            for name in ("none", "single", "weak", "moderate", "strong")
            if not name.startswith("_")
        ]
        self.assertEqual(counts, sorted(counts))


class DoseWikiJoin(unittest.TestCase):
    def _record(self, slug, relationship, confidence="high"):
        return _mod.DoseWikiRecord(
            slug=slug,
            substance_id=7,
            relationship=relationship,
            confidence=confidence,
            expert_reviewed=False,
            data={},
        )

    def test_a_contested_join_never_votes_on_a_number(self):
        # dose.wiki's `4-aco-met` page holds a different molecule than Piru's
        # row; its dose ladder describes that other molecule.
        picked = _mod.pick_numeric_dosewiki([self._record("4-aco-met", "different")], WEIGHTS)
        self.assertEqual(picked, {})

    def test_an_absent_ingest_leaves_the_evidence_records_in_play(self):
        # The ingest may not have landed; nothing may assume it has.
        conn = sqlite3.connect(":memory:")
        conn.execute(
            "CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT, display_name TEXT, "
            "default_priority INTEGER, default_enabled INTEGER)"
        )
        self.assertEqual(_mod.dosewiki_in_db(conn), {})

    def test_an_ingested_substance_stops_the_evidence_record_voting(self):
        conn = sqlite3.connect(":memory:")
        conn.execute(
            "CREATE TABLE sources (id INTEGER PRIMARY KEY, slug TEXT, display_name TEXT, "
            "default_priority INTEGER, default_enabled INTEGER)"
        )
        conn.execute("INSERT INTO sources VALUES (1, 'dosewiki', 'dose.wiki', 3, 1)")
        for table in _mod.DOSEWIKI_DB_TABLES.values():
            conn.execute(f"CREATE TABLE {table} (substance_id INTEGER, source_id INTEGER)")
        conn.execute("INSERT INTO dose_ranges VALUES (7, 1)")
        ingested = _mod.dosewiki_in_db(conn)
        self.assertEqual(ingested["dose"], {7})
        self.assertEqual(ingested["duration"], set())

    def test_the_best_join_wins_when_two_records_claim_one_row(self):
        picked = _mod.pick_numeric_dosewiki(
            [
                self._record("b-slug", "unverified", "low"),
                self._record("a-slug", "identical", "high"),
            ],
            WEIGHTS,
        )
        self.assertEqual(picked[7].slug, "a-slug")


if __name__ == "__main__":
    unittest.main(verbosity=2)
