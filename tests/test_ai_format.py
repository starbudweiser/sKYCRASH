import unittest

import ai_format


SAMPLE = """VERDICT: Plugin SKSE fautif.
CAUSE: `CompassNavigationOverhaul.dll` plante au chargement.
CONFIANCE: Moyenne, un seul log.
PREUVES:
- **skse64.log** : exception au chargement
- Engine Fixes v5.9.1
ACTIONS:
1. Désactiver le mod.
2. Relancer le jeu.
MANQUE: un second crash log."""


class FormatTests(unittest.TestCase):
    def test_sections_colored_no_icons(self):
        h = ai_format.render_html(SAMPLE)
        for label in ("VERDICT", "CAUSE", "CONFIANCE", "PREUVES", "ACTIONS", "MANQUE"):
            self.assertIn(label, h)
        self.assertIn(ai_format.PALETTE["actions"], h)
        self.assertIn(ai_format.LEVEL_COLORS["moyenne"], h)
        self.assertIn("font-family:Menlo", h)  # `code`
        self.assertNotIn("VERDICT:", h)

    def test_escape_and_markdown_noise(self):
        h = ai_format.render_html("## **Cause probable** : <b>x</b>\n---\ntexte")
        self.assertIn("&lt;b&gt;", h)
        self.assertNotIn("<b>", h)
        self.assertNotIn("##", h)

    def test_free_text_fallback(self):
        h = ai_format.render_html("Réponse simple : oui.")
        self.assertIn("Réponse simple", h)

    def test_empty(self):
        self.assertIsInstance(ai_format.render_html(""), str)


if __name__ == "__main__":
    unittest.main()
