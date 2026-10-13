import os
import tempfile
import unittest

import audit_engine as ae

CRASH = """Skyrim SE v1.6.1170
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 BadPlugin.dll+0012AB
PROBABLE CALL STACK:
  [0] 0x7FF612345678 BadPlugin.dll+12AB
  [1] 0x7FF611111111 BadPlugin.dll+9999
  [2] 0x7FF622222222 SkyrimSE.exe+1234567
  [3] 0x7FF633333333 kernel32.dll+1
  [4] 0x7FF644444444 d3d11.dll+55
Possible relevant objects: MyArmor.esp, BSTriShape
"""

SKSE = """skse64 loader
plugin Data\\SKSE\\Plugins\\Good.dll (00000001 Good 00000001) loaded correctly
plugin Data\\SKSE\\Plugins\\Old.dll (00000000 Old 00000000) disabled, no version data
"""

PAPYRUS = """[10/08/2026 - 04:22:11PM] error: Cannot call GetFormID() on a None object, aborting function call
stack:
\t[Quest (000ABC)].SpamScript.OnUpdate() - "SpamScript.psc" Line 42
""" * 6 + """[10/08/2026 - 04:23:00PM] error: Cannot open store for class "RemovedModScript", missing from disk
"""


def write(d, name, content):
    p = os.path.join(d, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(content)
    return p


class AuditTests(unittest.TestCase):
    def test_full_audit(self):
        with tempfile.TemporaryDirectory() as d:
            paths = [write(d, "crash-2026.log", CRASH), write(d, "skse64.log", SKSE),
                     write(d, "Papyrus.0.log", PAPYRUS)]
            r = ae.audit_paths(paths)
            names = [s[0] for s in r.suspects]
            self.assertEqual(names[0], "BadPlugin.dll")
            self.assertIn("Old.dll", names)
            self.assertIn("SpamScript", names)
            self.assertNotIn("kernel32.dll", names)
            self.assertIn("suspect principal", r.verdict)
            self.assertIn("EXCEPTION_ACCESS_VIOLATION", r.to_markdown())

    def test_no_logs(self):
        r = ae.audit_paths([])
        self.assertEqual(r.verdict, "aucun crash log trouvé")

    def test_missing_file_ignored(self):
        r = ae.audit_paths(["/nonexistent/crash.log"])
        self.assertEqual(r.findings, [])

    def test_context_capped(self):
        with tempfile.TemporaryDirectory() as d:
            r = ae.audit_paths([write(d, "crash-a.log", CRASH)])
            self.assertLessEqual(len(r.to_context(500)), 500)

    def test_crashlogger_log_is_not_a_crash(self):
        txt = ("[2026-10-08 13:59:18] [info] NOTE: This is not a crashlog. Crashlogs have the name "
               "crash-[TIMESTAMP].log\n[info] CrashLogger 1.12.1.0 is loading...\n")
        with tempfile.TemporaryDirectory() as d:
            p = write(d, "CrashLogger.log", txt)
            self.assertEqual(ae.classify_log(p, ae.read_lines(p)), "other")
            self.assertEqual(ae.audit_paths([p]).verdict, "pas de crash log, anomalies secondaires uniquement"
                             if ae.audit_paths([p]).findings else "aucun crash log trouvé")

    def test_skse_exception_names_culprit(self):
        txt = ("SKSE64 runtime: initialize (version = 2.0.20 01050610 01DD571C6E3CB52A, os = 6.2)\n"
               "plugin X\\A.dll (00000001 Alpha 00000001) loaded correctly (handle 1)\n"
               "plugin X\\B.dll (00000001 Beta 00000001) loaded correctly (handle 2)\n"
               "sending message type 0 to plugin 2\n"
               "registering plugin listener for UIFramework at 2 of 5\n"
               "exception occurred while loading plugins\ninit complete\n")
        with tempfile.TemporaryDirectory() as d:
            r = ae.audit_paths([write(d, "skse64.log", txt)])
            self.assertEqual(r.suspects[0][0], "Beta.dll")
            self.assertIn("Exception SKSE", r.to_markdown())

    def test_crashlogger_stack_section_and_wine(self):
        txt = ("Skyrim SSE v1.5.97\nUnhandled exception \"EXCEPTION_ACCESS_VIOLATION\" at 0x0002D51C2FA4\n"
               "SYSTEM SPECS:\n\tCPU: GenuineIntel VirtualApple @ 2.50GHz\n\tPHYSICAL MEMORY: 60.00 GB/64.00 GB\n"
               "PROBABLE CALL STACK:\n\nREGISTERS:\n\tRAX 0x0 (size_t) [0]\n"
               "STACK:\n\t[RSP+0] 0x1 (void* -> SkyrimSE.exe+10702CC\tmov rax)\n"
               "\t[RSP+8] 0x2 (void* -> tbbmalloc.dll+000AA8D\tmov r13)\n"
               "\t[RSP+10] 0x3 (void* -> Culprit.dll+0001\tret)\n"
               "MODULES:\n\tCulprit.dll    0x0001\n")
        with tempfile.TemporaryDirectory() as d:
            r = ae.audit_paths([write(d, "crash-2026.log", txt)])
            md = r.to_markdown()
            self.assertIn("couche de compatibilité", md)
            self.assertIn("Pile d'appels vide", md)
            self.assertIn("presque saturée", md)
            self.assertIn("Culprit.dll", [s[0] for s in r.suspects])

    def test_papyrus_cc_and_duplicates(self):
        txt = ('[01:59:47PM] Cannot open store for class "ccBGS_ARSwitchScript", missing file?\n'
               '[01:59:47PM] Error: Script CCHorseArmorChangeScript cannot be bound to Q (010030B5) because\n'
               '[01:59:44PM] error: Native function GetAllItemsCount in empty state could find no matching function\n')
        with tempfile.TemporaryDirectory() as d:
            r = ae.audit_paths([write(d, "Papyrus.0.log", txt), write(d, "Papyrus.1.log", txt)])
            md = r.to_markdown()
            self.assertEqual(md.count("Contenu Creation Club manquant"), 1)   # copies identiques ignorées
            self.assertIn("Fonctions natives Papyrus non liées", md)


if __name__ == "__main__":
    unittest.main()
