"""Vérifie que chaque texte passé à L()/N_() possède une traduction complète."""
import ast
import re
import unittest
from pathlib import Path

import i18n

ROOT = Path(__file__).resolve().parent.parent / "src"
FIELD_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)[^}]*\}")


def collect_keys() -> set:
    keys = set()
    for path in ROOT.glob("*.py"):
        if path.name.startswith(("test_", ".")) or path.name == "i18n_strings.py":
            continue
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                    and node.func.id in ("L", "N_") and node.args
                    and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)):
                keys.add(node.args[0].value)
    return keys


class TestI18n(unittest.TestCase):
    def test_all_keys_translated(self):
        from i18n_strings import TR
        missing = sorted(k for k in collect_keys() if k not in TR)
        self.assertEqual(missing, [], f"{len(missing)} clé(s) sans traduction")
        for k, tr in TR.items():
            self.assertEqual(len(tr), 3, k)
            for lang, t in zip(("en", "it", "es"), tr):
                self.assertTrue(t.strip(), f"{lang} vide : {k}")
                self.assertEqual(set(FIELD_RE.findall(k)), set(FIELD_RE.findall(t)), f"{lang} : {k}")

    def test_no_stale_keys(self):
        from i18n_strings import TR
        stale = sorted(set(TR) - collect_keys())
        self.assertEqual(stale, [], "clés orphelines dans TR")

    def test_switch(self):
        try:
            i18n.set_lang("en")
            self.assertEqual(i18n.L("Envoyer"), "Send")
            i18n.set_lang("it")
            self.assertEqual(i18n.L("Envoyer"), "Invia")
            i18n.set_lang("es")
            self.assertEqual(i18n.L("Envoyer"), "Enviar")
            self.assertEqual(i18n.L("{n} fichier(s) supprimé(s).", n=2).count("2"), 1)
        finally:
            i18n.set_lang("fr")
        self.assertEqual(i18n.L("Envoyer"), "Envoyer")

    def test_engine_translated(self):
        import audit_engine
        try:
            i18n.set_lang("en")
            self.assertEqual(audit_engine.sev_label(audit_engine.SEV_CRIT), "CRITICAL")
        finally:
            i18n.set_lang("fr")


if __name__ == "__main__":
    unittest.main()
