import XCTest
@testable import CrashCore

func lz4Literals(_ data: [UInt8]) -> [UInt8] {
    let n = data.count
    if n < 15 { return [UInt8(n << 4)] + data }
    var out: [UInt8] = [0xF0]
    var rest = n - 15
    while rest >= 255 { out.append(255); rest -= 255 }
    out.append(UInt8(rest))
    return out + data
}

func crashLog(_ when: String, _ whereAt: String, _ objects: [String], _ skse: [String], _ plugins: [String], uptime: String = "00:00:41") -> String {
    var l = ["CRASH TIME: \(when)", "Skyrim SSE v1.6.1170",
             "Unhandled exception \"EXCEPTION_ACCESS_VIOLATION\" at 0x6FFFFD0805EF \(whereAt)\txchg [rsi+0x10], eax",
             "PROCESS INFO:", "\tProcess Uptime: \(uptime) (41000ms)", "POSSIBLE RELEVANT OBJECTS:"]
    l += objects.enumerated().map { "\tRSP+\(String($0.offset * 8, radix: 16, uppercase: true)): (\($0.element)*)" }
    l += ["CALL STACK ([P]robable / [S]tack scan):", "\t[ 0][P] 0x6FFFFD0805EF \(whereAt)", "SKSE PLUGINS:"]
    l += skse.map { "\t\($0) v1.0" }
    l += ["PLUGINS:"]
    l += plugins.enumerated().map { "\t[" + String(format: "%2d", $0.offset) + "]     \($0.element)" }
    return l.joined(separator: "\n") + "\n"
}

final class InsightsTests: TempDirCase {
    func fakeSave(_ path: String, plugins: [String], light: [String], saved: Wall, compressed: Bool = true) {
        var body: [UInt8] = [78] + le32(0) + [UInt8(plugins.count)] + plugins.flatMap { wstr($0) }
        body += le16(light.count) + light.flatMap { wstr($0) } + [UInt8](repeating: 0, count: 64)
        let filetime = UInt64((saved.timestamp + 11644473600) * 1e7)
        let header: [UInt8] = le32(12) + le32(7) + wstr("Rhys") + le32(34) + wstr("Rivebois") + wstr("17e jour") + wstr("NordRace")
            + le16(0) + [UInt8](repeating: 0, count: 8) + le64(filetime) + le32(2) + le32(1) + le16(compressed ? 2 : 0)
        let shot = [UInt8](repeating: 0, count: 8)
        let packed: [UInt8] = compressed ? le32(body.count) + le32(lz4Literals(body).count) + lz4Literals(body) : body
        let all = Array(SaveGame.MAGIC) + le32(header.count) + header + shot + packed
        try? FileManager.default.createDirectory(atPath: PyFS.dirname(path), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data(all))
    }

    func testReadSaveLz4AndPlain() throws {
        for compressed in [true, false] {
            let p = PyFS.join(tmp, "s\(compressed).ess")
            fakeSave(p, plugins: ["Skyrim.esm", "Mod.esp"], light: ["Light.esl"], saved: try Wall(2026, 10, 13, 18, 23, 0), compressed: compressed)
            let s = try SaveGame.readSave(p)
            XCTAssertEqual(s.player, "Rhys"); XCTAssertEqual(s.level, 34); XCTAssertEqual(s.location, "Rivebois")
            XCTAssertEqual(s.allPlugins, ["Skyrim.esm", "Mod.esp", "Light.esl"])
            XCTAssertEqual(Wall(timestamp: s.savedAt).format("%d/%m %H:%M"), "13/10 18:23")
        }
    }

    func testNotASave() {
        let p = write("x.ess", "hello")
        XCTAssertThrowsError(try SaveGame.readSave(p))
    }

    func testCrossChecks() throws {
        let docs = PyFS.join(tmp, "My Games", "Skyrim Special Edition")
        let skseDir = PyFS.join(docs, "SKSE")
        let game = PyFS.join(tmp, "Bottles", "Skyrim", "drive_c", "Games", "Skyrim Special Edition")
        let data = PyFS.join(game, "Data")
        for p in ["Skyrim.esm", "Update.esm", "Old.esp", "Birds and Flocks.esp", "Unique Region Names.esp"] { write(PyFS.join(data, p), "TES4") }
        write(PyFS.join(game, "SkyrimSE.exe"), "MZ")
        write(PyFS.join(tmp, "Bottles", "Skyrim", "drive_c", "users", "u", "AppData", "Local", "Skyrim Special Edition", "Plugins.txt"),
              "*Old.esp\n*Birds and Flocks.esp\n*Unique Region Names.esp\n")
        let save = PyFS.join(docs, "Saves", "RHYS.ess")
        fakeSave(save, plugins: ["Skyrim.esm", "Update.esm", "Old.esp", "Removed.esp"], light: [], saved: try Wall(2026, 10, 13, 18, 23, 0))
        setMtime(save, try Wall(2026, 10, 13, 18, 23, 0))

        let plugins = ["Skyrim.esm", "Update.esm", "Old.esp"]
        let older = write(PyFS.join(skseDir, "crash-2026-10-14-02-07-54.log"),
                          crashLog("2026-10-14 02:07:54", "SkyrimSE.exe+01D74A0", ["TESObjectREFR"], ["EngineFixes.dll"], plugins))
        let latest = write(PyFS.join(skseDir, "crash-2026-10-14-02-46-21.log"),
                           crashLog("2026-10-14 02:46:21", "EngineFixes.dll+00F05EF", ["TESRegionDataSound", "TESRegion", "BSMusicManager"],
                                    ["EngineFixes.dll", "DynamicMusicAndSounds.dll"], plugins))
        setMtime(older, try Wall(2026, 10, 14, 2, 7, 54))
        setMtime(latest, try Wall(2026, 10, 14, 2, 46, 21))
        let sps = write(PyFS.join(skseDir, "SPS.log"),
                        "[02:46:08.323] [ 276 ] [I] [TextureStream] Reset (main menu)\n[02:46:10.242] [ 276 ] [I] [TextureStream] Reset (loading save game)\n")
        let dms = write(PyFS.join(skseDir, "DynamicMusicAndSounds.log"), String(repeating: "[02:45:54.221] [ 776 ] [W] [SNDR:0403391E] no source path\n", count: 3))

        let r = Audit.auditPaths([latest, older, sps, dms], gameDir: game)
        let t = titles(r)
        XCTAssertTrue(t.contains("Plantage 11 s après le chargement d'une sauvegarde"), t)
        XCTAssertTrue(t.contains("2 crash log(s) dans l'historique"))
        XCTAssertTrue(t.contains("DLL SKSE modifiées depuis le plantage du 14/10 02:07:54"))
        XCTAssertTrue(t.contains("1 plugin(s) de la sauvegarde « RHYS » ne sont plus actifs"))
        XCTAssertTrue(t.contains("2 plugin(s) ajoutés depuis la sauvegarde « RHYS »"))
        XCTAssertTrue(t.contains("Objets en cause : son et musique, régions et météo"))
        let dom = r.findings.first { $0.category == "domaine" }!
        XCTAssertTrue(dom.detail.contains("DynamicMusicAndSounds.dll (3 avertissements)"))
        XCTAssertTrue(dom.detail.contains("Birds and Flocks.esp"))
        XCTAssertTrue(dom.detail.contains("Unique Region Names.esp"))
        XCTAssertTrue(r.suspects.map { $0.name }.contains("DynamicMusicAndSounds.dll"))
        XCTAssertEqual(r.extras.save?.missing, ["Removed.esp"])

        let md = Diagnostic.build(r, anonymize: true)
        for title in ["## Audit", "## Chronologie du dernier plantage", "## Historique des plantages", "## Sauvegarde et plugins actuels",
                      "## Avertissements des journaux de plugins", "## Extrait du dernier crash log"] {
            XCTAssertTrue(md.contains(title), title)
        }
        XCTAssertTrue(md.contains("chargement d'une sauvegarde (SPS.log)"))
        XCTAssertTrue(md.contains("- Removed.esp"))
        XCTAssertTrue(md.contains("POSSIBLE RELEVANT OBJECTS:"))
        XCTAssertTrue(md.contains("**DynamicMusicAndSounds.log** : 3 ligne(s)"))
    }

    func testPurgeArchivesCrashLogs() {
        let crash = write("crash-2026-10-14-02-46-21.log", crashLog("2026-10-14 02:46:21", "EngineFixes.dll+00F05EF", ["TESRegion"], ["A.dll"], []))
        write("SPS.log", "x")
        let (deleted, archived, errors) = Config.purgeLogs([tmp])
        XCTAssertEqual(deleted, 1); XCTAssertEqual(archived, 1); XCTAssertTrue(errors.isEmpty)
        XCTAssertFalse(PyFS.exists(crash))
        XCTAssertTrue(PyFS.isFile(PyFS.join(tmp, Insights.ARCHIVE_DIR, PyFS.basename(crash))))
        let hist = try! Insights.crashHistory([tmp])
        XCTAssertEqual(hist.count, 1)
        let r = Audit.auditPaths([write("skse64.log", "SKSE64 runtime")])
        XCTAssertNil(r.extras.timeline)
    }
}
