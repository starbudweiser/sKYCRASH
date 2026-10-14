import os
import struct
import tempfile
import unittest

import audit_engine
import compat


def fake_exe(path, ver=(1, 5, 97, 0)):
    ms = (ver[0] << 16) | ver[1]
    ls = (ver[2] << 16) | ver[3]
    with open(path, "wb") as f:
        f.write(b"MZ" + b"\0" * 100 + b"\xbd\x04\xef\xfe" + struct.pack("<IIII", 0x10000, ms, ls, 0) + b"\0" * 50)


SKSE_LOG = [
    "SKSE64 runtime: initialize (version = 2.0.20 01050610 01DD571C6E3CB52A, os = 6.2 (9200))",
    "plugin directory = C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\",
    "checking plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\A.dll",
    "plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\A.dll (00000001 A 00000001) loaded correctly (handle 1)",
    "checking plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\Broken.dll",
    "checking plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\msdia140.dll",
]


class CompatTests(unittest.TestCase):
    def test_decode_runtime(self):
        self.assertEqual(compat.decode_runtime("01050610"), (1, 5, 97))
        self.assertEqual(compat.runtime_label("01050610"), "1.5.97 (SE)")
        self.assertIsNone(compat.decode_runtime("zz"))

    def test_address_library_name(self):
        self.assertEqual(compat.address_library_name((1, 5, 97)), "version-1-5-97-0.bin")
        self.assertEqual(compat.address_library_name((1, 6, 1170)), "versionlib-1-6-1170-0.bin")

    def test_not_loaded_ignores_helper_dll(self):
        info = compat.skse_plugins(SKSE_LOG)
        self.assertEqual(compat.not_loaded(info), ["Broken.dll"])
        self.assertTrue(info["plugin_dir"].endswith("Plugins"))

    def test_exe_version(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "SkyrimSE.exe")
            fake_exe(p, (1, 6, 1170, 0))
            self.assertEqual(compat.read_exe_version(p), (1, 6, 1170, 0))
            self.assertIsNone(compat.read_exe_version(os.path.join(d, "absent.exe")))

    def test_install_audit(self):
        with tempfile.TemporaryDirectory() as d:
            fake_exe(os.path.join(d, "SkyrimSE.exe"), (1, 6, 1170, 0))
            plug = os.path.join(d, "Data", "SKSE", "Plugins")
            os.makedirs(plug)
            open(os.path.join(plug, "A.dll"), "wb").write(b"x")
            log = os.path.join(d, "skse64.log")
            open(log, "w").write("\n".join(SKSE_LOG))
            r = audit_engine.audit_paths([log], game_dir=d)
            titles = " | ".join(f.title for f in r.findings)
            self.assertEqual(r.game_dir, d)
            self.assertIn("Address Library introuvable (versionlib-1-6-1170-0.bin)", titles)
            self.assertIn("Version du jeu différente du runtime SKSE", titles)
            self.assertIn("vérifié mais non chargé : Broken.dll", titles)

    def test_find_game_dir_user_choice(self):
        with tempfile.TemporaryDirectory() as d:
            fake_exe(os.path.join(d, "SkyrimSE.exe"))
            self.assertEqual(compat.find_game_dir(None, d), d)

    def test_catalog_role_in_suspect(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "skse64.log")
            lines = list(SKSE_LOG[:2]) + [
                "checking plugin C:\\x\\Plugins\\\\CompassNavigationOverhaul.dll",
                "plugin 24 allocated 16 bytes from branch pool",
                "plugin C:\\x\\Plugins\\\\CompassNavigationOverhaul.dll (00000001 CompassNavigationOverhaul 00000001) loaded correctly (handle 24)",
                "sending message type 0 to plugin 24",
                "exception occurred while loading plugins",
            ]
            open(log, "w").write("\n".join(lines))
            r = audit_engine.audit_paths([log])
            top = r.suspects[0]
            self.assertEqual(top[0], "CompassNavigationOverhaul.dll")
            self.assertTrue(any("rôle connu" in x for x in top[2]))


if __name__ == "__main__":
    unittest.main()
