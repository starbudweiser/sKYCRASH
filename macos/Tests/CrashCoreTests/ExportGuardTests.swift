import XCTest
@testable import CrashCore

let CRASH_DLL = """
Skyrim SSE v1.5.97
CRASH TIME: 2026-10-08 16:20:11
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 BadPlugin.dll+0012AB
PROBABLE CALL STACK:
  [0] 0x7FF612345678 BadPlugin.dll+12AB
  [1] 0x7FF611111111 BadPlugin.dll+9999
Possible relevant objects: MyArmor.esp, BSTriShape

"""
let CRASH_NONE = """
Skyrim SSE v1.5.97
CRASH TIME: 2026-10-09 09:00:00
Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF612345678 SkyrimSE.exe+0012AB

"""

final class ExportTests: TempDirCase {
    var out: String { PyFS.join(tmp, "exports", "crash_events.jsonl") }
    func lines() -> [J] { (PyFS.readText(out) ?? "").pyFileLines.compactMap { J.parse($0) } }
    func runExport(_ files: [String]) -> Int {
        ExportEvents.exportReport(Audit.auditPaths(files), gameDir: "", path: out)
    }

    func testKnownSuspectAndContract() {
        XCTAssertEqual(runExport([write("crash-2026-10-08-16-20-11.log", CRASH_DLL)]), 1)
        let e = lines()[0]
        XCTAssertEqual(e.object!.map { $0.0 }, ["schema", "crash_time", "log_name", "game_runtime", "skse_runtime", "verdict", "suspects", "plugins_hash", "bottle"])
        XCTAssertEqual(e["schema"]?.intValue, 1)
        XCTAssertEqual(e["crash_time"]?.string, "2026-10-08T16:20:11")
        XCTAssertEqual(e["game_runtime"]?.string, "1.5.97")
        let sus = e["suspects"]!.array!
        let by = Dictionary(uniqueKeysWithValues: sus.map { ($0["name"]!.string!, $0) })
        XCTAssertEqual(by["BadPlugin.dll"]?["kind"]?.string, "dll")
        XCTAssertEqual(by["MyArmor.esp"]?["kind"]?.string, "plugin")
        XCTAssertEqual(sus[0]["name"]?.string, "BadPlugin.dll")
        for s in sus { XCTAssertTrue(["dll", "plugin", "object", "mod", "env"].contains(s["kind"]!.string!)) }
    }

    func testLogWithoutSuspect() {
        XCTAssertEqual(runExport([write("crash-2026-10-09-09-00-00.log", CRASH_NONE)]), 1)
        let sus = lines()[0]["suspects"]!.array!
        XCTAssertTrue(sus.filter { ["dll", "plugin"].contains($0["kind"]!.string!) }.isEmpty)
    }

    func testReanalysisNoDuplicate() {
        let files = [write("crash-2026-10-08-16-20-11.log", CRASH_DLL)]
        _ = runExport(files)
        XCTAssertEqual(runExport(files), 0)
        XCTAssertEqual(lines().count, 1)
    }

    func testTwoCrashesTwoLinesOwnSuspects() {
        _ = runExport([write("crash-2026-10-08-16-20-11.log", CRASH_DLL), write("crash-2026-10-09-09-00-00.log", CRASH_NONE)])
        var ev: [String: J] = [:]
        for e in lines() { ev[e["log_name"]!.string!] = e }
        XCTAssertEqual(ev.count, 2)
        func names(_ n: String) -> [String] { ev[n]!["suspects"]!.array!.map { $0["name"]!.string! } }
        XCTAssertTrue(names("crash-2026-10-08-16-20-11.log").contains("BadPlugin.dll"))
        XCTAssertFalse(names("crash-2026-10-09-09-00-00.log").contains("BadPlugin.dll"))
    }

    func testAppendOnlyKeepsExistingLines() throws {
        try FileManager.default.createDirectory(atPath: PyFS.dirname(out), withIntermediateDirectories: true)
        let legacy = "{\"schema\":1,\"crash_time\":\"2026-10-01T00:00:00\",\"log_name\":\"crash-old.log\",\"suspects\":[]}\nligne illisible\n"
        try legacy.write(toFile: out, atomically: true, encoding: .utf8)
        XCTAssertEqual(runExport([write("crash-2026-10-08-16-20-11.log", CRASH_DLL)]), 1)
        XCTAssertTrue((PyFS.readText(out) ?? "").hasPrefix(legacy))
    }

    func testScrubAndBottle() {
        XCTAssertFalse(ExportEvents.scrub("/Users/bob/Documents/x.log et C:\\Users\\bob\\y").contains("bob"))
        XCTAssertEqual(ExportEvents.bottleName("/Users/bob/Library/Application Support/CrossOver/Bottles/Skyrim/drive_c/Games/Skyrim"), "Skyrim")
        XCTAssertNil(ExportEvents.bottleName("/jeux/Skyrim"))
        XCTAssertNil(ExportEvents.bottleName(""))
    }

    func testPluginsHashStable() {
        let game = PyFS.join(tmp, "Bottle", "drive_c", "Games", "Skyrim")
        try? FileManager.default.createDirectory(atPath: PyFS.join(game, "Data"), withIntermediateDirectories: true)
        let pt = PyFS.join(tmp, "Bottle", "drive_c", "users", "crossover", "AppData", "Local", "Skyrim Special Edition", "plugins.txt")
        write(pt, "# x\n*Skyrim.esm\n*A.esp\nB.esp\n")
        let h1 = ExportEvents.pluginsHash(game)
        XCTAssertEqual(h1?.count, 64)
        write(pt, "*skyrim.esm\n*a.esp\n")
        XCTAssertEqual(ExportEvents.pluginsHash(game), h1)
        XCTAssertEqual(ExportEvents.bottleName(game), "Bottle")
    }

    func testSampleLogAnonymisation() throws {
        let sample = PyFS.join(repoRoot, "data", "sample_logs", "crash-2026-10-07-22-35-01.log")
        try XCTSkipUnless(PyFS.isFile(sample), "journal d'exemple absent")
        let p = write("crash-2026-10-07-22-35-01.log", PyFS.readText(sample)!)
        _ = runExport([p])
        let raw = PyFS.readText(out)!
        let names = lines()[0]["suspects"]!.array!.filter { $0["kind"]?.string == "env" }.map { $0["name"]!.string! }
        XCTAssertTrue(names.contains("wine_layer"))
        XCTAssertFalse(raw.contains("/Users/")); XCTAssertFalse(raw.contains("REGISTERS"))
        XCTAssertEqual(lines()[0]["game_runtime"]?.string, "1.5.97")
    }
}

final class GuardTests: TempDirCase {
    func facts() -> Inventory {
        var f = Inventory()
        f.tools = [("crashlogger", true), ("enginefixes", true)]
        f.skseInstalled = true; f.addressLibrary = true
        f.cc = (75, 75)
        f.plugins = (889, 120, 769, true, nil)
        return f
    }
    let BAD = """
    VERDICT: crash au chargement.
    ACTIONS:
    1. Installer Crash Logger SSE pour générer un fichier de crash horodaté dans SKSE/Crashlogs/.
    2. Télécharger le contenu Creation Club manquant via le jeu ou retirer les mods qui l'exigent.
    3. Nettoyer la sauvegarde avec ReSaver (FallrimTools) pour supprimer les instances de scripts orphelins.
    4. Vérifier avec LOOT ou votre gestionnaire que la limite stricte de 254 plugins non-ESL n'est pas dépassée.
    5. Désactiver DynamicMusicAndSounds.dll puis recharger la partie.
    MANQUE: un crash log récent dans SKSE/Crashlogs.
    """

    func testRemovesContradictedAdviceAndRenumbers() {
        let (out, removed) = Guard.apply(BAD, facts())
        XCTAssertEqual(removed, ["Crash Logger SSE", "Creation Club", "limite de 254 plugins"])
        XCTAssertTrue(out.contains("1. Nettoyer la sauvegarde avec ReSaver"))
        XCTAssertTrue(out.contains("2. Désactiver DynamicMusicAndSounds.dll"))
        XCTAssertFalse(out.contains("Crashlogs"))
        XCTAssertTrue(out.contains("3 conseil(s) retiré(s)"))
    }

    func testEnglishAnswer() {
        let (out, removed) = Guard.apply("ACTIONS:\n1. Install Crash Logger SSE.\n2. Check the 254 plugin limit.\n3. Disable Foo.dll.", facts())
        XCTAssertEqual(removed.count, 2)
        XCTAssertTrue(out.contains("1. Disable Foo.dll."))
    }

    func testKeepsAdviceWhenFactFalse() {
        var f = Inventory()
        f.tools = [("crashlogger", false)]
        f.plugins = (0, 0, 0, false, nil)
        let (out, removed) = Guard.apply(BAD, f)
        XCTAssertTrue(removed.isEmpty); XCTAssertEqual(out, BAD)
    }

    func testJudgeRemovesFlaggedItemsOnly() {
        var seen: [String] = []
        let judge: Guard.Judge = { items, _ in seen += items; return items.map { $0.contains("ENB") } }
        let (out, removed) = Guard.apply(BAD + "\n6. Désinstaller ENB, absent de votre jeu.", facts(), judge: judge)
        XCTAssertEqual(removed.last, Guard.JEV_LABEL)
        XCTAssertFalse(out.contains("ENB"))
        XCTAssertTrue(out.contains("2. Désactiver DynamicMusicAndSounds.dll"))
        XCTAssertFalse(seen.joined(separator: " ").contains("Installer Crash Logger"))
    }

    func testServiceErrorKeepsPatterns() {
        let judge: Guard.Judge = { _, _ in throw JevError("hors ligne") }
        let a = Guard.apply(BAD, facts(), judge: judge), b = Guard.apply(BAD, facts())
        XCTAssertEqual(a.0, b.0); XCTAssertEqual(a.1, b.1)
    }

    func testJevRequestShape() {
        let (state, q) = Guard.jevRequest(["a", "b", "c"], facts())
        XCTAssertEqual(state["advice"]?.array?.count, 3)
        XCTAssertTrue(state["installation_facts"]!.string!.contains("Faits vérifiés"))
        XCTAssertTrue(q["c1"]!["instructions"]!.string!.contains("`advice[1]`"))
        XCTAssertEqual(q["c2"]?["type"]?.string, "choice")
    }

    func testInventoryFromDisk() {
        let game = PyFS.join(tmp, "Bottle", "drive_c", "Games", "Skyrim Special Edition")
        for n in ["CrashLogger.dll", "EngineFixes.dll"] { write(PyFS.join(game, "Data/SKSE/Plugins", n), "") }
        write(PyFS.join(game, "skse64_1_6_1170.dll"), "")
        write(PyFS.join(game, "Skyrim.ccc"), "ccA.esl\nccB.esm\n")
        for n in ["ccA.esl", "ccB.esm", "Skyrim.esm"] { write(PyFS.join(game, "Data", n), "") }
        let f = Inventory.build(game, [], [])
        XCTAssertTrue(f.tool("crashlogger")); XCTAssertFalse(f.tool("trainwreck"))
        XCTAssertEqual(f.skseInstalled, true)
        XCTAssertEqual(f.cc?.listed, 2); XCTAssertEqual(f.cc?.present, 2)
        XCTAssertEqual(f.bottle, "Bottle")
        let ctx = f.toContext()
        XCTAssertTrue(ctx.contains("Faits vérifiés")); XCTAssertTrue(ctx.contains("Crash Logger SSE")); XCTAssertTrue(ctx.contains("2 fichier(s) présents sur 2"))
    }
}

final class AIFormatTests: XCTestCase {
    let sample = """
    VERDICT: Plugin SKSE fautif.
    CAUSE: `CompassNavigationOverhaul.dll` plante au chargement.
    CONFIANCE: Moyenne, un seul log.
    PREUVES:
    - **skse64.log** : exception au chargement
    - Engine Fixes v5.9.1
    ACTIONS:
    1. Désactiver le mod.
    2. Relancer le jeu.
    MANQUE: un second crash log.
    """
    override func setUp() { I18n.setLang("fr") }

    func testSectionsColoredNoIcons() {
        let h = AIFormat.renderHTML(sample)
        for l in ["VERDICT", "CAUSE", "CONFIANCE", "PREUVES", "ACTIONS", "MANQUE"] { XCTAssertTrue(h.contains(l)) }
        XCTAssertTrue(h.contains(AIFormat.PALETTE["actions"]!))
        XCTAssertTrue(h.contains(AIFormat.LEVEL_COLORS["moyenne"]!))
        XCTAssertTrue(h.contains("font-family:Menlo"))
        XCTAssertFalse(h.contains("VERDICT:"))
    }

    func testEscapeAndMarkdownNoise() {
        let h = AIFormat.renderHTML("## **Cause probable** : <b>x</b>\n---\ntexte")
        XCTAssertTrue(h.contains("&lt;b&gt;")); XCTAssertFalse(h.contains("<b>")); XCTAssertFalse(h.contains("##"))
    }

    func testFreeTextAndEmpty() {
        XCTAssertTrue(AIFormat.renderHTML("Réponse simple : oui.").contains("Réponse simple"))
        XCTAssertFalse(AIFormat.renderHTML("").isEmpty)
    }
}
