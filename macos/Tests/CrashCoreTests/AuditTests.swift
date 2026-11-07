import XCTest
@testable import CrashCore

let CRASH = """
Skyrim SE v1.6.1170
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 BadPlugin.dll+0012AB
PROBABLE CALL STACK:
  [0] 0x7FF612345678 BadPlugin.dll+12AB
  [1] 0x7FF611111111 BadPlugin.dll+9999
  [2] 0x7FF622222222 SkyrimSE.exe+1234567
  [3] 0x7FF633333333 kernel32.dll+1
  [4] 0x7FF644444444 d3d11.dll+55
Possible relevant objects: MyArmor.esp, BSTriShape

"""
let SKSE = """
skse64 loader
plugin Data\\SKSE\\Plugins\\Good.dll (00000001 Good 00000001) loaded correctly
plugin Data\\SKSE\\Plugins\\Old.dll (00000000 Old 00000000) disabled, no version data

"""
let PAPYRUS = String(repeating: """
[10/08/2026 - 04:22:11PM] error: Cannot call GetFormID() on a None object, aborting function call
stack:
\t[Quest (000ABC)].SpamScript.OnUpdate() - "SpamScript.psc" Line 42

""", count: 6) + "[10/08/2026 - 04:23:00PM] error: Cannot open store for class \"RemovedModScript\", missing from disk\n"

final class AuditTests: TempDirCase {
    func testFullAudit() {
        let paths = [write("crash-2026.log", CRASH), write("skse64.log", SKSE), write("Papyrus.0.log", PAPYRUS)]
        let r = Audit.auditPaths(paths)
        let names = r.suspects.map { $0.name }
        XCTAssertEqual(names.first, "BadPlugin.dll")
        XCTAssertTrue(names.contains("Old.dll"))
        XCTAssertTrue(names.contains("SpamScript"))
        XCTAssertFalse(names.contains("kernel32.dll"))
        XCTAssertTrue(r.verdict.contains("suspect principal"))
        XCTAssertTrue(r.toMarkdown().contains("EXCEPTION_ACCESS_VIOLATION"))
    }

    func testNoLogs() { XCTAssertEqual(Audit.auditPaths([]).verdict, "aucun crash log trouvé") }

    func testMissingFileIgnored() { XCTAssertTrue(Audit.auditPaths(["/nonexistent/crash.log"]).findings.isEmpty) }

    func testContextCapped() {
        let r = Audit.auditPaths([write("crash-a.log", CRASH)])
        XCTAssertLessThanOrEqual(r.toContext(maxChars: 500).pyLen, 500)
    }

    func testCrashLoggerLogIsNotACrash() {
        let txt = "[2026-10-08 13:59:18] [info] NOTE: This is not a crashlog. Crashlogs have the name crash-[TIMESTAMP].log\n[info] CrashLogger 1.12.1.0 is loading...\n"
        let p = write("CrashLogger.log", txt)
        XCTAssertEqual(Audit.classifyLog(p, Audit.readLines(p)), "other")
    }

    func testSkseExceptionNamesCulprit() {
        let txt = "SKSE64 runtime: initialize (version = 2.0.20 01050610 01DD571C6E3CB52A, os = 6.2)\n"
            + "plugin X\\A.dll (00000001 Alpha 00000001) loaded correctly (handle 1)\n"
            + "plugin X\\B.dll (00000001 Beta 00000001) loaded correctly (handle 2)\n"
            + "sending message type 0 to plugin 2\n"
            + "registering plugin listener for UIFramework at 2 of 5\n"
            + "exception occurred while loading plugins\ninit complete\n"
        let r = Audit.auditPaths([write("skse64.log", txt)])
        XCTAssertEqual(r.suspects.first?.name, "Beta.dll")
        XCTAssertTrue(r.toMarkdown().contains("Exception SKSE"))
    }

    func testCrashLoggerStackSectionAndWine() {
        let txt = "Skyrim SSE v1.5.97\nUnhandled exception \"EXCEPTION_ACCESS_VIOLATION\" at 0x0002D51C2FA4\n"
            + "SYSTEM SPECS:\n\tCPU: GenuineIntel VirtualApple @ 2.50GHz\n\tPHYSICAL MEMORY: 60.00 GB/64.00 GB\n"
            + "PROBABLE CALL STACK:\n\nREGISTERS:\n\tRAX 0x0 (size_t) [0]\n"
            + "STACK:\n\t[RSP+0] 0x1 (void* -> SkyrimSE.exe+10702CC\tmov rax)\n"
            + "\t[RSP+8] 0x2 (void* -> tbbmalloc.dll+000AA8D\tmov r13)\n"
            + "\t[RSP+10] 0x3 (void* -> Culprit.dll+0001\tret)\n"
            + "MODULES:\n\tCulprit.dll    0x0001\n"
        let r = Audit.auditPaths([write("crash-2026.log", txt)])
        let md = r.toMarkdown()
        XCTAssertTrue(md.contains("couche de compatibilité"))
        XCTAssertTrue(md.contains("Pile d'appels vide"))
        XCTAssertTrue(md.contains("presque saturée"))
        XCTAssertTrue(r.suspects.map { $0.name }.contains("Culprit.dll"))
    }

    func testPapyrusCCAndDuplicates() {
        let txt = "[01:59:47PM] Cannot open store for class \"ccBGS_ARSwitchScript\", missing file?\n"
            + "[01:59:47PM] Error: Script CCHorseArmorChangeScript cannot be bound to Q (010030B5) because\n"
            + "[01:59:44PM] error: Native function GetAllItemsCount in empty state could find no matching function\n"
        let r = Audit.auditPaths([write("Papyrus.0.log", txt), write("Papyrus.1.log", txt)])
        let md = r.toMarkdown()
        XCTAssertEqual(md.components(separatedBy: "Contenu Creation Club manquant").count - 1, 1)
        XCTAssertTrue(md.contains("Fonctions natives Papyrus non liées"))
    }

    func testReadLinesUtf16AndBlankLines() {
        var bytes: [UInt8] = [0xFF, 0xFE]
        for u in "abc\r\r\n\r\ndef\n".utf16 { bytes += [UInt8(u & 0xFF), UInt8(u >> 8)] }
        let p = writeBytes("u16.log", bytes)
        XCTAssertEqual(Audit.readLines(p), ["abc", "def"])
        let bad = writeBytes("bad.log", [0x61, 0xFF, 0x62, 0x0A, 0xC3, 0x28, 0x63])
        XCTAssertEqual(Audit.readLines(bad), ["ab", "(c"])
    }

    func testPyHelpers() {
        XCTAssertEqual("a\u{0B}b\u{85}c\r\nd\re".pyLines, ["a", "b", "c", "d", "e"])
        XCTAssertEqual("\u{A0} x \u{2003}".pyStrip, "x")
        XCTAssertEqual("x".pyLines, ["x"])
        let c = Counter(["b", "a", "b", "c", "a", "d"])
        XCTAssertEqual(c.mostCommon(3).map { $0.0 }, ["b", "a", "c"])
        XCTAssertEqual(try! Wall.parse("2026-10-14 02:46:21").format("%d/%m %H:%M:%S"), "14/10 02:46:21")
    }
}

final class CompatTests: TempDirCase {
    func fakeExe(_ path: String, _ ver: (Int, Int, Int, Int) = (1, 5, 97, 0)) {
        let ms = (ver.0 << 16) | ver.1, ls = (ver.2 << 16) | ver.3
        let bytes = [UInt8]("MZ".utf8) + [UInt8](repeating: 0, count: 100) + [0xBD, 0x04, 0xEF, 0xFE] + le32(0x10000) + le32(ms) + le32(ls) + le32(0) + [UInt8](repeating: 0, count: 50)
        FileManager.default.createFile(atPath: path, contents: Data(bytes))
    }
    let skseLog = [
        "SKSE64 runtime: initialize (version = 2.0.20 01050610 01DD571C6E3CB52A, os = 6.2 (9200))",
        "plugin directory = C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\",
        "checking plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\A.dll",
        "plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\A.dll (00000001 A 00000001) loaded correctly (handle 1)",
        "checking plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\Broken.dll",
        "checking plugin C:\\Games\\Skyrim Special Edition\\Data\\SKSE\\Plugins\\\\msdia140.dll",
    ]

    func testDecodeRuntime() {
        XCTAssertTrue(Compat.decodeRuntime("01050610")! == (1, 5, 97))
        XCTAssertEqual(Compat.runtimeLabel("01050610"), "1.5.97 (SE)")
        XCTAssertNil(Compat.decodeRuntime("zz"))
    }

    func testAddressLibraryName() {
        XCTAssertEqual(Compat.addressLibraryName((1, 5, 97, 0)), "version-1-5-97-0.bin")
        XCTAssertEqual(Compat.addressLibraryName((1, 6, 1170, 0)), "versionlib-1-6-1170-0.bin")
    }

    func testNotLoadedIgnoresHelperDll() {
        let info = Compat.sksePlugins(skseLog)
        XCTAssertEqual(Compat.notLoaded(info), ["Broken.dll"])
        XCTAssertTrue(info.pluginDir!.hasSuffix("Plugins"))
    }

    func testExeVersion() {
        let p = PyFS.join(tmp, "SkyrimSE.exe")
        fakeExe(p, (1, 6, 1170, 0))
        XCTAssertTrue(Compat.readExeVersion(p)! == (1, 6, 1170, 0))
        XCTAssertNil(Compat.readExeVersion(PyFS.join(tmp, "absent.exe")))
    }

    func testInstallAudit() {
        fakeExe(PyFS.join(tmp, "SkyrimSE.exe"), (1, 6, 1170, 0))
        try? FileManager.default.createDirectory(atPath: PyFS.join(tmp, "Data/SKSE/Plugins"), withIntermediateDirectories: true)
        write("Data/SKSE/Plugins/A.dll", "x")
        let log = write("skse64.log", skseLog.joined(separator: "\n"))
        let r = Audit.auditPaths([log], gameDir: tmp)
        let t = titles(r)
        XCTAssertEqual(r.gameDir, tmp)
        XCTAssertTrue(t.contains("Address Library introuvable (versionlib-1-6-1170-0.bin)"))
        XCTAssertTrue(t.contains("Version du jeu différente du runtime SKSE"))
        XCTAssertTrue(t.contains("vérifié mais non chargé : Broken.dll"))
    }

    func testFindGameDirUserChoice() {
        fakeExe(PyFS.join(tmp, "SkyrimSE.exe"))
        XCTAssertEqual(Compat.findGameDir(pluginDirWin: nil, userDir: tmp), tmp)
    }

    func testCatalogRoleInSuspect() {
        let lines = Array(skseLog[0..<2]) + [
            "checking plugin C:\\x\\Plugins\\\\CompassNavigationOverhaul.dll",
            "plugin 24 allocated 16 bytes from branch pool",
            "plugin C:\\x\\Plugins\\\\CompassNavigationOverhaul.dll (00000001 CompassNavigationOverhaul 00000001) loaded correctly (handle 24)",
            "sending message type 0 to plugin 24",
            "exception occurred while loading plugins",
        ]
        let r = Audit.auditPaths([write("skse64.log", lines.joined(separator: "\n"))])
        XCTAssertEqual(r.suspects.first?.name, "CompassNavigationOverhaul.dll")
        XCTAssertTrue(r.suspects[0].reasons.contains { $0.contains("rôle connu") })
    }

    func testLightPluginFlag() {
        let light = writeBytes("a.esp", Array("TES4".utf8) + le32(0) + le32(0x200))
        let full = writeBytes("b.esp", Array("TES4".utf8) + le32(0) + le32(0x1))
        XCTAssertTrue(Compat.isLightPlugin(light))
        XCTAssertFalse(Compat.isLightPlugin(full))
        XCTAssertTrue(Compat.isLightPlugin(PyFS.join(tmp, "absent.esl")))
    }
}

final class WineAndPrivacyTests: TempDirCase {
    let wine = """
    Skyrim SE v1.5.97.0
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

    func testAnonymize() {
        let t = "/Users/stephan/Documents/x.log C:\\Users\\Bob\\a.log /home/alice/b drive_c/users/crossover/z /Bottles/Skyrim/foo mail me@ex.com"
        let out = AIClient.anonymize(t)
        for s in ["stephan", "Bob", "alice", "crossover/z", "Skyrim/foo", "me@ex.com"] { XCTAssertFalse(out.contains(s), s) }
        XCTAssertTrue(out.contains("<user>")); XCTAssertTrue(out.contains("<email>"))
        XCTAssertEqual(AIClient.anonymize("SKSE 2.0.20 v1.5.97.0"), "SKSE 2.0.20 v1.5.97.0")
    }

    func testDefaultProviderOffline() {
        let (p, m) = AIClient.detectDefaultProvider(baseURL: "http://127.0.0.1:9")
        XCTAssertEqual(p, "gemini"); XCTAssertEqual(m, "")
    }

    func testWineFindings() {
        let r = Audit.auditPaths([write("crash-2026-01-01-00-00-00.log", wine)])
        let t = titles(r)
        XCTAssertTrue(t.contains("D3DMetal")); XCTAssertTrue(t.contains("Rosetta")); XCTAssertTrue(t.contains("Mémoire unifiée"))
        I18n.setLang("es")
        let t2 = titles(Audit.auditPaths([PyFS.join(tmp, "crash-2026-01-01-00-00-00.log")]))
        XCTAssertTrue(t2.contains("Memoria unificada")); XCTAssertFalse(t2.contains("Mémoire unifiée"))
    }

    func testCrashLogger125AndModOrigin() {
        let c125 = """
        CRASH TIME: 2026-10-18 23:34:28
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
        write("ModOrganizer.ini", "[General]\n")
        write("mods/Community Shaders/SKSE/Plugins/ShaderMod.dll", "x")
        write("mods/Tweaks/SKSE/Plugins/OtherTweaks.dll", "x")
        write("mods/Tweaks/textures/sky.dds", "x")
        write("mods/Misc_separator/meta.ini", "x")
        let game = PyFS.join(tmp, "STOCK GAME")
        write(PyFS.join(game, "SkyrimSE.exe"), "")
        let index = ModOrigin.buildIndex(game)
        XCTAssertEqual(ModOrigin.originOf("ShaderMod.dll", index), ["Community Shaders"])
        XCTAssertEqual(ModOrigin.originOf("Data/SKSE/Plugins/othertweaks.DLL", index), ["Tweaks"])
        XCTAssertEqual(ModOrigin.originOf("sky.dds", index), [])
        let log = write("logs/crash-2026-10-18.log", c125)
        let r = Audit.auditPaths([log], gameDir: game)
        let md = r.toMarkdown()
        XCTAssertTrue(md.contains("C++ Exception")); XCTAssertFalse(md.contains("exception inconnue"))
        XCTAssertTrue(md.contains("Exception C++ : DX::com_exception")); XCTAssertTrue(md.contains("E_NOINTERFACE"))
        XCTAssertFalse(md.contains("Pile d'appels vide"))
        XCTAssertEqual(r.suspects[0].name, "ShaderMod.dll")
        XCTAssertTrue(r.suspects[0].reasons.contains { $0.contains("exception C++") })
        XCTAssertTrue(r.suspects[0].reasons.contains("fourni par le mod « Community Shaders »"))
        XCTAssertEqual(ModOrigin.buildIndex("").count, 0)
        let other = NSTemporaryDirectory() + "skycrash-vide-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: other) }
        XCTAssertEqual(ModOrigin.buildIndex(other).count, 0)
    }

    func testMabbajackSnapshot() {
        try? FileManager.default.createDirectory(atPath: PyFS.join(tmp, ".mabbajack"), withIntermediateDirectories: true)
        let snap = #"{"format":1,"manifest":[["mods/Community Shaders/SKSE/Plugins/ShaderMod.dll","h","a",1,"FromArchive"],["mods/USSEP/Unofficial Skyrim Special Edition Patch.esp","h","a",1,"FromArchive"],["Stock Game/SkyrimSE.exe","h","a",1,"FromArchive"]]}"#
        // gzip fabriqué avec /usr/bin/gzip
        let src = write("snap.json", snap)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); p.arguments = ["-k", "-f", src]; try! p.run(); p.waitUntilExit()
        try! FileManager.default.moveItem(atPath: src + ".gz", toPath: PyFS.join(tmp, ".mabbajack/installation.json.gz"))
        let index = ModOrigin.buildIndex(tmp)
        XCTAssertEqual(ModOrigin.originOf("ShaderMod.dll", index), ["Community Shaders"])
        XCTAssertEqual(ModOrigin.originOf("unofficial skyrim special edition patch.esp", index), ["USSEP"])
        XCTAssertEqual(ModOrigin.originOf("SkyrimSE.exe", index), [])
    }
}
