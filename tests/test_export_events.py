import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path

import audit_engine as ae
import export_events as ex

SAMPLES = Path(__file__).resolve().parent.parent / "data" / "sample_logs"
CRASH_SAMPLE = SAMPLES / "crash-2026-10-07-22-35-01.log"

CRASH_DLL = """Skyrim SSE v1.5.97
CRASH TIME: 2026-10-08 16:20:11
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 BadPlugin.dll+0012AB
PROBABLE CALL STACK:
  [0] 0x7FF612345678 BadPlugin.dll+12AB
  [1] 0x7FF611111111 BadPlugin.dll+9999
Possible relevant objects: MyArmor.esp, BSTriShape
"""
CRASH_NONE = """Skyrim SSE v1.5.97
CRASH TIME: 2026-10-09 09:00:00
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 SkyrimSE.exe+0012AB
"""


def run_export(files, out):
    rep = ae.audit_paths(files)
    return rep, ex.export_report(rep, "", out)


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp())
        self.out = self.d / "exports" / "crash_events.jsonl"

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def lines(self):
        return [json.loads(l) for l in self.out.read_text(encoding="utf-8").splitlines()]

    def write(self, name, text):
        p = self.d / name
        p.write_text(text, encoding="utf-8")
        return str(p)

    def test_known_suspect_and_contract(self):
        _r, n = run_export([self.write("crash-2026-10-08-16-20-11.log", CRASH_DLL)], self.out)
        self.assertEqual(n, 1)
        (e,) = self.lines()
        self.assertEqual(e["schema"], 1)
        self.assertEqual(set(e), {"schema", "crash_time", "log_name", "game_runtime", "skse_runtime", "verdict",
                                  "suspects", "plugins_hash", "bottle"})
        self.assertEqual(e["crash_time"], "2026-10-08T16:20:11")
        self.assertEqual(e["game_runtime"], "1.5.97")
        by = {s["name"]: s for s in e["suspects"]}
        self.assertEqual(by["BadPlugin.dll"]["kind"], "dll")
        self.assertEqual(by["MyArmor.esp"]["kind"], "plugin")
        self.assertTrue(by["BadPlugin.dll"]["reasons"])
        self.assertEqual(e["suspects"][0]["name"], "BadPlugin.dll")
        for s in e["suspects"]:
            self.assertIn(s["kind"], {"dll", "plugin", "object", "mod", "env"})

    def test_log_without_suspect(self):
        _r, n = run_export([self.write("crash-2026-10-09-09-00-00.log", CRASH_NONE)], self.out)
        self.assertEqual(n, 1)
        (e,) = self.lines()
        self.assertFalse([s for s in e["suspects"] if s["kind"] in ("dll", "plugin")])

    def test_reanalysis_no_duplicate(self):
        files = [self.write("crash-2026-10-08-16-20-11.log", CRASH_DLL)]
        run_export(files, self.out)
        _r, n = run_export(files, self.out)
        self.assertEqual(n, 0)
        self.assertEqual(len(self.lines()), 1)

    def test_two_crashes_two_lines_own_suspects(self):
        files = [self.write("crash-2026-10-08-16-20-11.log", CRASH_DLL),
                 self.write("crash-2026-10-09-09-00-00.log", CRASH_NONE)]
        run_export(files, self.out)
        ev = {e["log_name"]: e for e in self.lines()}
        self.assertEqual(len(ev), 2)
        self.assertIn("BadPlugin.dll", [s["name"] for s in ev["crash-2026-10-08-16-20-11.log"]["suspects"]])
        self.assertNotIn("BadPlugin.dll", [s["name"] for s in ev["crash-2026-10-09-09-00-00.log"]["suspects"]])

    def test_sample_log_wine_env_and_anonymisation(self):
        shutil.copy(CRASH_SAMPLE, self.d / CRASH_SAMPLE.name)
        run_export([str(self.d / CRASH_SAMPLE.name)], self.out)
        raw = self.out.read_text(encoding="utf-8")
        (e,) = self.lines()
        env = {s["name"] for s in e["suspects"] if s["kind"] == "env"}
        self.assertIn("wine_layer", env)
        self.assertNotIn("/Users/", raw)
        self.assertNotIn(Path.home().name, raw)
        self.assertNotIn("REGISTERS", raw)
        self.assertEqual(e["game_runtime"], "1.5.97")

    def test_scrub_and_bottle(self):
        self.assertNotIn("bob", ex.scrub("/Users/bob/Documents/x.log et C:\\Users\\bob\\y"))
        self.assertEqual(ex.bottle_name("/Users/bob/Library/Application Support/CrossOver/Bottles/Skyrim/drive_c/Games/Skyrim"),
                         "Skyrim")
        self.assertIsNone(ex.bottle_name("/jeux/Skyrim"))
        self.assertIsNone(ex.bottle_name(""))

    def test_plugins_hash_stable(self):
        game = self.d / "Bottle" / "drive_c" / "Games" / "Skyrim"
        (game / "Data").mkdir(parents=True)
        pt = self.d / "Bottle" / "drive_c" / "users" / "crossover" / "AppData" / "Local" / "Skyrim Special Edition"
        pt.mkdir(parents=True)
        (pt / "plugins.txt").write_text("# x\n*Skyrim.esm\n*A.esp\nB.esp\n", encoding="utf-8")
        h1 = ex.plugins_hash(str(game))
        self.assertEqual(len(h1), 64)
        (pt / "plugins.txt").write_text("*skyrim.esm\n*a.esp\n", encoding="utf-8")
        self.assertEqual(ex.plugins_hash(str(game)), h1)  # casse et inactifs sans effet
        self.assertEqual(ex.bottle_name(str(game)), "Bottle")

    def test_disabled_writes_nothing(self):
        p = self.write("crash-2026-10-08-16-20-11.log", CRASH_DLL)
        ex.os.environ[ex.EXPORT_ENV] = str(self.d / "exports")
        try:
            ex.audit_and_export([p], "", enabled=False)
            self.assertFalse(self.out.exists())
            ex.audit_and_export([p], "", enabled=True)
            self.assertTrue(self.out.exists())
        finally:
            del ex.os.environ[ex.EXPORT_ENV]


if __name__ == "__main__":
    unittest.main()
