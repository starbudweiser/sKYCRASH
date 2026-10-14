"""Recoupements : sauvegarde (.ess), chronologie, historique des crash logs, domaine des objets."""
import os
import struct
import tempfile
import unittest
from datetime import datetime

import audit_engine
import compat
import savegame


def wstr(s: str) -> bytes:
    b = s.encode("utf-8")
    return struct.pack("<H", len(b)) + b


def lz4_literals(data: bytes) -> bytes:
    """Bloc LZ4 valide fait d'une seule séquence de littéraux (suffisant pour le décodeur)."""
    n = len(data)
    if n < 15:
        return bytes([n << 4]) + data
    out, rest = bytearray([0xF0]), n - 15
    while rest >= 255:
        out.append(255)
        rest -= 255
    out.append(rest)
    return bytes(out) + data


def fake_save(path: str, plugins: list, light: list, saved: datetime, compressed: bool = True):
    body = bytes([78]) + struct.pack("<I", 0) + bytes([len(plugins)]) + b"".join(wstr(p) for p in plugins)
    body += struct.pack("<H", len(light)) + b"".join(wstr(p) for p in light) + b"\x00" * 64
    filetime = int((saved.timestamp() + 11644473600) * 1e7)
    header = (struct.pack("<II", 12, 7) + wstr("Rhys") + struct.pack("<I", 34) + wstr("Rivebois")
              + wstr("17e jour") + wstr("NordRace") + struct.pack("<Hff", 0, 0.0, 0.0)
              + struct.pack("<QII", filetime, 2, 1) + struct.pack("<H", 2 if compressed else 0))
    shot = b"\x00" * (2 * 1 * 4)
    packed = (struct.pack("<II", len(body), len(lz4_literals(body))) + lz4_literals(body)) if compressed else body
    with open(path, "wb") as f:
        f.write(savegame.MAGIC + struct.pack("<I", len(header)) + header + shot + packed)


def crash_log(when: str, where: str, objects: list, skse: list, plugins: list, uptime="00:00:41") -> str:
    return "\n".join([
        f"CRASH TIME: {when}",
        "Skyrim SSE v1.6.1170",
        f'Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x6FFFFD0805EF {where}\txchg [rsi+0x10], eax',
        "PROCESS INFO:",
        f"\tProcess Uptime: {uptime} (41000ms)",
        "POSSIBLE RELEVANT OBJECTS:",
        *[f"\tRSP+{i * 8:X}: ({o}*)" for i, o in enumerate(objects)],
        "CALL STACK ([P]robable / [S]tack scan):",
        f"\t[ 0][P] 0x6FFFFD0805EF {where}",
        "SKSE PLUGINS:",
        *[f"\t{d} v1.0" for d in skse],
        "PLUGINS:",
        *[f"\t[{i:2}]     {p}" for i, p in enumerate(plugins)],
        "",
    ])


def write(path: str, text: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


class SaveGameTests(unittest.TestCase):
    def test_read_save_lz4_and_plain(self):
        with tempfile.TemporaryDirectory() as d:
            for compressed in (True, False):
                p = os.path.join(d, f"s{compressed}.ess")
                fake_save(p, ["Skyrim.esm", "Mod.esp"], ["Light.esl"], datetime(2026, 10, 13, 18, 23), compressed)
                s = savegame.read_save(p)
                self.assertEqual((s.player, s.level, s.location), ("Rhys", 34, "Rivebois"))
                self.assertEqual(s.all_plugins, ["Skyrim.esm", "Mod.esp", "Light.esl"])
                self.assertEqual(datetime.fromtimestamp(s.saved_at).strftime("%d/%m %H:%M"), "13/10 18:23")

    def test_not_a_save(self):
        with tempfile.TemporaryDirectory() as d:
            p = write(os.path.join(d, "x.ess"), "hello")
            with self.assertRaises(ValueError):
                savegame.read_save(p)

    def test_light_flag(self):
        with tempfile.TemporaryDirectory() as d:
            light, full = os.path.join(d, "a.esp"), os.path.join(d, "b.esp")
            open(light, "wb").write(b"TES4" + struct.pack("<II", 0, 0x200))
            open(full, "wb").write(b"TES4" + struct.pack("<II", 0, 0x1))
            self.assertTrue(compat.is_light_plugin(light))
            self.assertFalse(compat.is_light_plugin(full))
            self.assertTrue(compat.is_light_plugin(os.path.join(d, "absent.esl")))


class InsightTests(unittest.TestCase):
    def test_cross_checks(self):
        with tempfile.TemporaryDirectory() as d:
            docs = os.path.join(d, "My Games", "Skyrim Special Edition")
            skse_dir = os.path.join(docs, "SKSE")
            game = os.path.join(d, "Bottles", "Skyrim", "drive_c", "Games", "Skyrim Special Edition")
            data = os.path.join(game, "Data")
            for p in ("Skyrim.esm", "Update.esm", "Old.esp", "Birds and Flocks.esp", "Unique Region Names.esp"):
                write(os.path.join(data, p), "TES4")
            write(os.path.join(game, "SkyrimSE.exe"), "MZ")
            write(os.path.join(d, "Bottles", "Skyrim", "drive_c", "users", "u", "AppData", "Local",
                               "Skyrim Special Edition", "Plugins.txt"),
                  "*Old.esp\n*Birds and Flocks.esp\n*Unique Region Names.esp\n")
            os.makedirs(os.path.join(docs, "Saves"))
            save = os.path.join(docs, "Saves", "RHYS.ess")
            fake_save(save, ["Skyrim.esm", "Update.esm", "Old.esp", "Removed.esp"], [], datetime(2026, 10, 13, 18, 23))
            os.utime(save, (datetime(2026, 10, 13, 18, 23).timestamp(),) * 2)

            plugins = ["Skyrim.esm", "Update.esm", "Old.esp"]
            older = write(os.path.join(skse_dir, "crash-2026-10-14-02-07-54.log"),
                          crash_log("2026-10-14 02:07:54", "SkyrimSE.exe+01D74A0", ["TESObjectREFR"],
                                    ["EngineFixes.dll"], plugins))
            latest = write(os.path.join(skse_dir, "crash-2026-10-14-02-46-21.log"),
                           crash_log("2026-10-14 02:46:21", "EngineFixes.dll+00F05EF",
                                     ["TESRegionDataSound", "TESRegion", "BSMusicManager"],
                                     ["EngineFixes.dll", "DynamicMusicAndSounds.dll"], plugins))
            os.utime(older, (datetime(2026, 10, 14, 2, 7, 54).timestamp(),) * 2)
            os.utime(latest, (datetime(2026, 10, 14, 2, 46, 21).timestamp(),) * 2)
            sps = write(os.path.join(skse_dir, "SPS.log"),
                        "[02:46:08.323] [ 276 ] [I] [TextureStream] Reset (main menu)\n"
                        "[02:46:10.242] [ 276 ] [I] [TextureStream] Reset (loading save game)\n")
            dms = write(os.path.join(skse_dir, "DynamicMusicAndSounds.log"),
                        "[02:45:54.221] [ 776 ] [W] [SNDR:0403391E] no source path\n" * 3)

            r = audit_engine.audit_paths([latest, older, sps, dms], game_dir=game)
            titles = " | ".join(f.title for f in r.findings)
            self.assertIn("Plantage 11 s après le chargement d'une sauvegarde", titles)
            self.assertIn("2 crash log(s) dans l'historique", titles)
            self.assertIn("DLL SKSE modifiées depuis le plantage du 14/10 02:07:54", titles)
            self.assertIn("1 plugin(s) de la sauvegarde « RHYS » ne sont plus actifs", titles)
            self.assertIn("2 plugin(s) ajoutés depuis la sauvegarde « RHYS »", titles)
            self.assertIn("Objets en cause : son et musique, régions et météo", titles)
            dom = next(f for f in r.findings if f.category == "domaine")
            self.assertIn("DynamicMusicAndSounds.dll (3 avertissements)", dom.detail)
            self.assertIn("Birds and Flocks.esp", dom.detail)
            self.assertIn("Unique Region Names.esp", dom.detail)
            self.assertIn("DynamicMusicAndSounds.dll", [n for n, _s, _r in r.suspects])
            self.assertEqual(r.extras["save"]["missing"], ["Removed.esp"])

            import diagnostic
            md = diagnostic.build(r, audit_engine.read_lines, anonymize=True)
            for title in ("## Audit", "## Chronologie du dernier plantage", "## Historique des plantages",
                          "## Sauvegarde et plugins actuels", "## Avertissements des journaux de plugins",
                          "## Extrait du dernier crash log"):
                self.assertIn(title, md)
            self.assertIn("chargement d'une sauvegarde (SPS.log)", md)
            self.assertIn("- Removed.esp", md)
            self.assertIn("POSSIBLE RELEVANT OBJECTS:", md)
            self.assertIn("**DynamicMusicAndSounds.log** : 3 ligne(s)", md)


class PurgeArchiveTests(unittest.TestCase):
    def test_purge_archives_crash_logs(self):
        import Skyrim_Crash_Analyzer as app
        import insights
        with tempfile.TemporaryDirectory() as d:
            crash = write(os.path.join(d, "crash-2026-10-14-02-46-21.log"),
                          crash_log("2026-10-14 02:46:21", "EngineFixes.dll+00F05EF", ["TESRegion"], ["A.dll"], []))
            write(os.path.join(d, "SPS.log"), "x")
            deleted, archived, errors = app.purge_logs([d])
            self.assertEqual((deleted, archived, errors), (1, 1, []))
            self.assertFalse(os.path.exists(crash))
            self.assertTrue(os.path.isfile(os.path.join(d, insights.ARCHIVE_DIR, os.path.basename(crash))))
            hist = insights.crash_history([d], audit_engine.read_lines)
            self.assertEqual(len(hist), 1)  # l'historique lit l'archive
            # un crash archivé ne sert qu'à l'historique, pas à la chronologie du « dernier » plantage
            r = audit_engine.audit_paths([write(os.path.join(d, "skse64.log"), "SKSE64 runtime")])
            self.assertNotIn("timeline", r.extras)


if __name__ == "__main__":
    unittest.main()
