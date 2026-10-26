"""Crash Logger 1.25+ (exception C++, nouvelle pile d'appels) et mod d'origine des suspects."""
import gzip
import json
import os
import tempfile
import unittest

import audit_engine as ae
import mod_origin

CRASH_125 = """CRASH TIME: 2026-10-18 23:34:28
Skyrim SSE v1.7.104
CrashLoggerSSE v1-25-0-0 Aug 21 2026 09:19:20

Unhandled exception "C++ Exception" at 0x6FFFFFC1CF77 kernelbase.dll+000CF77\tadd rsp, 0xC8

C++ EXCEPTION:
\tType: (DX::com_exception*)
\tInfo: HRESULT 0x80004002 (E_NOINTERFACE)
\tThrow Location: ShaderMod.dll+0501009

CALL STACK ([P]robable / [S]tack scan):
\t[ 0][P] 0x6FFFFFC1CF77            kernelbase.dll+000CF77
\t[ 1][P] 0x6FFFE5D11009      ShaderMod.dll+0501009\tint3
\t[ 2][P] 0x6FFFE2A57334      OtherTweaks.dll+0027334

REGISTERS:
\tRAX 0x1         (void*)
"""


def write(d, name, content):
    p = os.path.join(d, name)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(content)
    return p


class CrashLogger125Tests(unittest.TestCase):
    def test_cpp_exception(self):
        with tempfile.TemporaryDirectory() as d:
            r = ae.audit_paths([write(d, "crash-2026-10-18.log", CRASH_125)])
        md = r.to_markdown()
        self.assertIn("C++ Exception", md)
        self.assertNotIn("exception inconnue", md)
        self.assertIn("Exception C++ : DX::com_exception", md)
        self.assertIn("E_NOINTERFACE", md)
        self.assertIn("D3DMetal", md)
        self.assertEqual(r.suspects[0][0], "ShaderMod.dll")
        self.assertTrue(any("exception C++" in reason for reason in r.suspects[0][2]))

    def test_new_call_stack_title_is_not_empty(self):
        with tempfile.TemporaryDirectory() as d:
            r = ae.audit_paths([write(d, "crash-2026-10-18.log", CRASH_125)])
        self.assertNotIn("Pile d'appels vide", r.to_markdown())


class ModOriginTests(unittest.TestCase):
    def test_mo2_instance(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "ModOrganizer.ini", "[General]\n")
            write(d, "mods/Community Shaders/SKSE/Plugins/ShaderMod.dll", "x")
            write(d, "mods/Tweaks/SKSE/Plugins/OtherTweaks.dll", "x")
            write(d, "mods/Tweaks/textures/sky.dds", "x")
            write(d, "mods/Misc_separator/meta.ini", "x")
            game = os.path.join(d, "STOCK GAME")
            write(game, "SkyrimSE.exe", "")
            index = mod_origin.build_index(game)
            self.assertEqual(mod_origin.origin_of("ShaderMod.dll", index), ["Community Shaders"])
            self.assertEqual(mod_origin.origin_of("Data/SKSE/Plugins/othertweaks.DLL", index), ["Tweaks"])
            self.assertEqual(mod_origin.origin_of("sky.dds", index), [])

    def test_mabbajack_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, ".mabbajack"))
            snap = {"format": 1, "manifest": [
                ["mods/Community Shaders/SKSE/Plugins/ShaderMod.dll", "h", "a", 1, "FromArchive"],
                ["mods/USSEP/Unofficial Skyrim Special Edition Patch.esp", "h", "a", 1, "FromArchive"],
                ["Stock Game/SkyrimSE.exe", "h", "a", 1, "FromArchive"],
            ]}
            with gzip.open(os.path.join(d, ".mabbajack", "installation.json.gz"), "wt", encoding="utf-8") as f:
                json.dump(snap, f)
            index = mod_origin.build_index(d)
            self.assertEqual(mod_origin.origin_of("ShaderMod.dll", index), ["Community Shaders"])
            self.assertEqual(mod_origin.origin_of("unofficial skyrim special edition patch.esp", index), ["USSEP"])
            self.assertEqual(mod_origin.origin_of("SkyrimSE.exe", index), [])

    def test_no_source(self):
        self.assertEqual(mod_origin.build_index(""), {})
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(mod_origin.build_index(d), {})

    def test_suspect_reason(self):
        with tempfile.TemporaryDirectory() as d:
            write(d, "ModOrganizer.ini", "[General]\n")
            write(d, "mods/Community Shaders/SKSE/Plugins/ShaderMod.dll", "x")
            game = os.path.join(d, "STOCK GAME")
            write(game, "SkyrimSE.exe", "")
            log = write(d, "logs/crash-2026-10-18.log", CRASH_125)
            r = ae.audit_paths([log], game_dir=game)
        top = r.suspects[0]
        self.assertEqual(top[0], "ShaderMod.dll")
        self.assertIn("fourni par le mod « Community Shaders »", top[2])


if __name__ == "__main__":
    unittest.main()
