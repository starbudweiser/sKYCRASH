"""Tests : anonymisation, fournisseur par défaut, diagnostics Wine/CrossOver."""
import tempfile
import unittest
from pathlib import Path

import ai_client
import audit_engine
import i18n

WINE_LOG = """Skyrim SE v1.5.97.0
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 SkyrimSE.exe+0123456
SYSTEM SPECS:
OS: Wine 9.0 (winemac.drv)
CPU: VirtualApple @ 2.50GHz
GPU #1: Apple M1 Max
GPU MEMORY: 2.54/103.68 GB
PHYSICAL MEMORY: 21.75 GB/64.00 GB
PROBABLE CALL STACK:
\t[0] 0x7FF612345678 SkyrimSE.exe+0123456
MODULES:
\tC:/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk/external/D3DMetal.framework/D3DMetal
\tsl.interposer.dll
"""


class TestAnonymize(unittest.TestCase):
    def test_paths_and_email(self):
        t = ("/Users/stephan/Documents/x.log C:\\Users\\Bob\\a.log /home/alice/b "
             "drive_c/users/crossover/z /Bottles/Skyrim/foo mail me@ex.com")
        out = ai_client.anonymize(t)
        for s in ("stephan", "Bob", "alice", "crossover/z", "Skyrim/foo", "me@ex.com"):
            self.assertNotIn(s, out)
        self.assertIn("<user>", out)
        self.assertIn("<email>", out)

    def test_versions_untouched(self):
        self.assertEqual(ai_client.anonymize("SKSE 2.0.20 v1.5.97.0"), "SKSE 2.0.20 v1.5.97.0")

    def test_default_provider_offline(self):
        self.assertEqual(ai_client.detect_default_provider("http://127.0.0.1:9"), ("gemini", ""))


class TestWine(unittest.TestCase):
    def setUp(self):
        i18n.set_lang("fr")

    def tearDown(self):
        i18n.set_lang("fr")

    def _audit(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "crash-2026-01-01-00-00-00.log"
            p.write_text(WINE_LOG, encoding="utf-8")
            return audit_engine.audit_paths([str(p)], "")

    def test_wine_findings(self):
        titles = " | ".join(f.title for f in self._audit().findings)
        self.assertIn("D3DMetal", titles)
        self.assertIn("Rosetta", titles)
        self.assertIn("Mémoire unifiée", titles)

    def test_wine_findings_translated(self):
        i18n.set_lang("es")
        titles = " | ".join(f.title for f in self._audit().findings)
        self.assertIn("Memoria unificada", titles)
        self.assertNotIn("Mémoire unifiée", titles)


if __name__ == "__main__":
    unittest.main()
