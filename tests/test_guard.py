"""Fiche d'installation et filet de sécurité sur les réponses de l'assistant."""
import os
import tempfile
import unittest

import guard
import inventory

FACTS = {
    "tools": {"crashlogger": True, "enginefixes": True},
    "skse_installed": True, "address_library": True,
    "cc": {"listed": 75, "present": 75},
    "plugins": {"active": 889, "full": 120, "light": 769, "limit_ok": True},
}

BAD = """VERDICT: crash au chargement.
ACTIONS:
1. Installer Crash Logger SSE pour générer un fichier de crash horodaté dans SKSE/Crashlogs/.
2. Télécharger le contenu Creation Club manquant via le jeu ou retirer les mods qui l'exigent.
3. Nettoyer la sauvegarde avec ReSaver (FallrimTools) pour supprimer les instances de scripts orphelins.
4. Vérifier avec LOOT ou votre gestionnaire que la limite stricte de 254 plugins non-ESL n'est pas dépassée.
5. Désactiver DynamicMusicAndSounds.dll puis recharger la partie.
MANQUE: un crash log récent dans SKSE/Crashlogs."""


class GuardTests(unittest.TestCase):
    def test_removes_contradicted_advice_and_renumbers(self):
        out, removed = guard.apply(BAD, FACTS)
        self.assertEqual(removed, ["Crash Logger SSE", "Creation Club", "limite de 254 plugins"])
        self.assertIn("1. Nettoyer la sauvegarde avec ReSaver", out)
        self.assertIn("2. Désactiver DynamicMusicAndSounds.dll", out)
        self.assertNotIn("Crashlogs", out)
        self.assertIn("3 conseil(s) retiré(s)", out)

    def test_english_answer(self):
        out, removed = guard.apply("ACTIONS:\n1. Install Crash Logger SSE.\n2. Check the 254 plugin limit.\n"
                                   "3. Disable Foo.dll.", FACTS)
        self.assertEqual(len(removed), 2)
        self.assertIn("1. Disable Foo.dll.", out)

    def test_keeps_advice_when_fact_unknown_or_false(self):
        out, removed = guard.apply(BAD, {"tools": {"crashlogger": False}, "plugins": {"limit_ok": False}})
        self.assertEqual(removed, [])
        self.assertEqual(out, BAD)


class JevJudgeTests(unittest.TestCase):
    def test_judge_removes_flagged_items_only(self):
        seen = []

        def judge(items, facts):
            seen.extend(items)
            return ["ENB" in t for t in items]

        out, removed = guard.apply(BAD + "\n6. Désinstaller ENB, absent de votre jeu.", FACTS, judge)
        self.assertEqual(removed[-1], guard.JEV_LABEL)
        self.assertNotIn("ENB", out)
        self.assertIn("2. Désactiver DynamicMusicAndSounds.dll", out)
        self.assertNotIn("Installer Crash Logger", " ".join(seen))  # déjà retiré par les motifs

    def test_service_error_keeps_patterns(self):
        def judge(items, facts):
            raise guard.jev_client.JevError("hors ligne")

        self.assertEqual(guard.apply(BAD, FACTS, judge), guard.apply(BAD, FACTS))

    def test_jev_judge_threshold(self):
        def fake(state, questions):
            self.assertEqual(state["advice"], ["a", "b", "c"])
            self.assertIn("Faits vérifiés", state["installation_facts"])
            self.assertIn("`advice[1]`", questions["c1"]["instructions"])
            p = {"c0": 0.95, "c1": 0.6, "c2": 0.1}
            return {k: {"choice": "contradicts" if v > 0.5 else "consistent",
                        "probabilities": {"contradicts": v}} for k, v in p.items()}

        old = guard.jev_client.system_one
        guard.jev_client.system_one = fake
        try:
            self.assertEqual(guard.jev_judge(["a", "b", "c"], FACTS), [True, False, False])
        finally:
            guard.jev_client.system_one = old


class InventoryTests(unittest.TestCase):
    def test_facts_from_disk(self):
        with tempfile.TemporaryDirectory() as d:
            game = os.path.join(d, "Bottle", "drive_c", "Games", "Skyrim Special Edition")
            plug = os.path.join(game, "Data", "SKSE", "Plugins")
            os.makedirs(plug)
            for n in ("CrashLogger.dll", "EngineFixes.dll"):
                open(os.path.join(plug, n), "wb").close()
            open(os.path.join(game, "skse64_1_6_1170.dll"), "wb").close()
            with open(os.path.join(game, "Skyrim.ccc"), "w") as f:
                f.write("ccA.esl\nccB.esm\n")
            for n in ("ccA.esl", "ccB.esm", "Skyrim.esm"):
                open(os.path.join(game, "Data", n), "wb").close()
            facts = inventory.build(game, [], [])
            self.assertTrue(facts["tools"]["crashlogger"])
            self.assertFalse(facts["tools"]["trainwreck"])
            self.assertTrue(facts["skse_installed"])
            self.assertEqual(facts["cc"], {"listed": 2, "present": 2})
            self.assertEqual(facts["bottle"], "Bottle")
            ctx = inventory.to_context(facts)
            self.assertIn("Faits vérifiés", ctx)
            self.assertIn("Crash Logger SSE", ctx)
            self.assertIn("2 fichier(s) présents sur 2", ctx)


if __name__ == "__main__":
    unittest.main()
