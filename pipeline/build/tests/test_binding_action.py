"""Tests for `normalise_binding_action` in pipeline/build/sqlite.py.

`BindingAction(rawValue:)` returns nil for anything outside the Swift enum, and
a row that fails to decode renders as an unlabelled affinity — so an action the
app cannot read says nothing at all on screen. Every input below is a real
authored value that did exactly that.

    python3 pipeline/build/tests/test_binding_action.py
"""

import importlib.util
import unittest
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "sqlite_build", Path(__file__).resolve().parent.parent / "sqlite.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
normalise = _mod.normalise_binding_action
ACTIONS = _mod.BINDING_ACTIONS


class Passthrough(unittest.TestCase):
    def test_an_enum_value_is_untouched(self):
        self.assertEqual(normalise("agonist"), ("agonist", None))
        self.assertEqual(normalise("reuptakeInhibitor"), ("reuptakeInhibitor", None))

    def test_absent_action_is_the_weakest_reading(self):
        self.assertEqual(normalise(None), ("modulator", None))
        self.assertEqual(normalise(""), ("modulator", None))


class Qualifiers(unittest.TestCase):
    def test_a_trailing_parenthetical_moves_to_the_note(self):
        self.assertEqual(normalise("agonist (presumed)"), ("agonist", "presumed"))
        self.assertEqual(
            normalise("reuptakeInhibitor (non-competitive)"),
            ("reuptakeInhibitor", "non-competitive"),
        )


class Prose(unittest.TestCase):
    def test_prose_forms_map_to_the_enum(self):
        self.assertEqual(normalise("weak agonist")[0], "agonist")
        self.assertEqual(normalise("weak agonist / partial agonist")[0], "partialAgonist")
        self.assertEqual(normalise("partial agonist")[0], "partialAgonist")

    def test_a_sentence_opening_with_an_action_keeps_all_of_itself_as_the_note(self):
        # The parenthetical split alone turned nitrous's mechanism into "PAG".
        action, note = normalise(
            "indirect agonist via endogenous enkephalin/dynorphin release in "
            "periaqueductal gray (PAG)"
        )
        self.assertEqual(action, "modulator")
        self.assertIn("enkephalin", note)
        self.assertIn("PAG", note)

    def test_acting_through_endogenous_release_is_not_claimed_as_binding(self):
        # `agonist` would assert a receptor interaction nothing measured.
        self.assertEqual(normalise("indirect agonist at mu-opioid")[0], "modulator")


class Gate(unittest.TestCase):
    def test_an_unknown_action_is_returned_unchanged_for_the_build_to_catch(self):
        # Guessing here would be the silent failure this exists to prevent.
        action, _ = normalise("allosteric potentiator of something novel")
        self.assertNotIn(action, ACTIONS)


if __name__ == "__main__":
    unittest.main(verbosity=2)
