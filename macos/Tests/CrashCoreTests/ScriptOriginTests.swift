import XCTest
@testable import CrashCore

/// BSA synthétique (v104 ou v105) : [dossier : [fichiers]], noms de dossiers et de fichiers inclus.
func makeBSA(_ dirs: [(String, [String])], version: Int = 105) -> [UInt8] {
    let rec = version == 105 ? 24 : 16
    let nf = dirs.reduce(0) { $0 + $1.1.count }
    let dnl = dirs.reduce(0) { $0 + $1.0.utf8.count + 1 }
    let fnl = dirs.reduce(0) { $0 + $1.1.reduce(0) { $0 + $1.utf8.count + 1 } }
    var b: [UInt8] = Array("BSA".utf8) + [0] + le32(version) + le32(36) + le32(0x3) + le32(dirs.count) + le32(nf)
        + le32(dnl) + le32(fnl) + le32(0)
    for (_, files) in dirs {
        b += le64(0) + le32(files.count) + (version == 105 ? le32(0) + le64(0) : le32(0))
    }
    precondition(b.count == 36 + rec * dirs.count)
    for (d, files) in dirs {
        b += [UInt8(d.utf8.count + 1)] + Array(d.utf8) + [0]
        for _ in files { b += le64(0) + le32(0) + le32(0) }
    }
    for (_, files) in dirs { for f in files { b += Array(f.utf8) + [0] } }
    return b
}

final class ScriptOriginTests: TempDirCase {
    func game() -> String {
        write("Game/SkyrimSE.exe", "")
        writeBytes("Game/Data/Skyrim - Misc.bsa", makeBSA([("seq", ["a.seq"]), ("scripts", ["ObjectReference.pex", "Actor.pex"])]))
        write("Game/ModOrganizer.ini", "[General]\n")
        write("Game/mods/ModA/Scripts/MyQuestScript.pex", "x")
        write("Game/mods/ModA/scripts/source/MyQuestScript.psc", "x")
        write("Game/mods/ModB/Scripts/MyQuestScript.pex", "x")
        writeBytes("Game/mods/ModC/ModC.bsa", makeBSA([("scripts", ["ObjectReference.pex"])], version: 104))
        write("Game/mods/Sep_separator/Scripts/Nope.pex", "x")
        return PyFS.join(tmp, "Game")
    }

    func testBSAListing() {
        let p = writeBytes("a.bsa", makeBSA([("meshes", ["x.nif"]), ("scripts", ["Foo.pex", "readme.txt"])]))
        XCTAssertEqual(ScriptOrigin.bsaScripts(p), ["Foo"])
    }

    func testTruncatedOrBogusBSA() {
        let full = makeBSA([("scripts", ["Foo.pex", "Bar.pex"])])
        XCTAssertEqual(ScriptOrigin.bsaScripts(writeBytes("t.bsa", Array(full.prefix(full.count - 5)))), [])
        XCTAssertEqual(ScriptOrigin.bsaScripts(writeBytes("h.bsa", Array(full.prefix(20)))), [])
        XCTAssertEqual(ScriptOrigin.bsaScripts(writeBytes("z.bsa", [UInt8](repeating: 0xFF, count: 200))), [])
        XCTAssertEqual(ScriptOrigin.bsaScripts(PyFS.join(tmp, "absent.bsa")), [])
    }

    func testIndexSources() {
        let idx = ScriptOrigin.buildIndex(game())
        XCTAssertEqual(ScriptOrigin.providers("MyQuestScript.psc", idx).map { $0.mod }, ["ModA", "ModB"])
        XCTAssertEqual(ScriptOrigin.providers("objectreference", idx),
                       [ScriptProvider(mod: "", archive: "Skyrim - Misc.bsa"), ScriptProvider(mod: "ModC", archive: "ModC.bsa")])
        XCTAssertTrue(ScriptOrigin.providers("Nope", idx).isEmpty)
        XCTAssertTrue(ScriptOrigin.buildIndex("").isEmpty)
    }

    func testAuditFinding() {
        let gdir = game()
        let log = """
        [10/08/2026 - 12:45:31AM] error: Native function GetAllItemsCount in empty state could find no matching function on linked type ObjectReference. Function will not be bound.
        [10/08/2026 - 12:45:32AM] error: Cannot open store for class "MyQuestScript", missing from disk
        [10/08/2026 - 12:45:33AM] error: Cannot open store for class "GoneScript", missing from disk

        """
        let r = Audit.auditPaths([write("Papyrus.0.log", log)], gameDir: gdir)
        guard let f = r.findings.first(where: { $0.title == "Provenance des scripts" }) else { return XCTFail(titles(r)) }
        XCTAssertTrue(f.detail.contains("GoneScript.pex : introuvable dans le jeu, les mods et les archives"), f.detail)
        XCTAssertTrue(f.detail.contains("MyQuestScript.pex : mod « ModA », mod « ModB » — plusieurs fournisseurs : conflit possible"), f.detail)
        XCTAssertTrue(f.detail.contains("ObjectReference.pex : jeu (Data) [Skyrim - Misc.bsa], mod « ModC » [ModC.bsa]"), f.detail)
        XCTAssertTrue(f.evidence.contains { $0.contains("ObjectReference.pex est remplacé par un mod") })
        XCTAssertTrue(f.evidence.contains { $0.hasPrefix("MyQuestScript.pex est présent") })
        XCTAssertTrue(r.toContext().contains("GoneScript.pex : introuvable"))
        let s = r.suspects.first { $0.name == "MyQuestScript.psc" }
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.reasons.contains("fourni par le mod « ModA, ModB »"), "\(s!.reasons)")
    }

    func testCleanModName() {
        XCTAssertEqual(ScriptOrigin.cleanModName("Abyss-83329-3-1-6-1708252797"), "Abyss")
        XCTAssertEqual(ScriptOrigin.cleanModName("MikanEyes v2.5 SE-18780-2-5"), "MikanEyes v2.5 SE")
        XCTAssertEqual(ScriptOrigin.cleanModName("Wade In Water Redone 71418 1.1.3 2026-08-24T21-06Z Ks18n0wt0"), "Wade In Water Redone")
        XCTAssertEqual(ScriptOrigin.cleanModName("Unofficial Skyrim Special Edition Patch"), "Unofficial Skyrim Special Edition Patch")
        XCTAssertEqual(ScriptOrigin.cleanModName("SkyUI_5_2_SE"), "SkyUI_5_2_SE")
    }

    func testDeploymentManifest() {
        write("V/SkyrimSE.exe", "")
        write("V/Data/Scripts/LooseScript.pex", "x")
        write("V/Data/Scripts/Untracked.pex", "x")
        writeBytes("V/Data/Abyss.bsa", makeBSA([("scripts", ["AbyssQuest.pex"])]))
        write("V/Data/vortex.deployment.json", """
        {"files":[{"relPath":"Scripts\\\\LooseScript.pex","source":"Loose Mod-1234-1-0-1700000000"},
                  {"relPath":"Abyss.bsa","source":"Abyss-83329-3-1-6-1708252797"},
                  {"relPath":"meshes/x.nif","source":"Other"}]}
        """)
        let idx = ScriptOrigin.buildIndex(PyFS.join(tmp, "V"))
        XCTAssertEqual(ScriptOrigin.providers("LooseScript", idx).map { $0.mod }, ["Loose Mod-1234-1-0-1700000000"])
        XCTAssertEqual(ScriptOrigin.providers("Untracked", idx).map { $0.mod }, [""])
        let abyss = ScriptOrigin.providers("AbyssQuest", idx)
        XCTAssertEqual(ScriptOrigin.label(abyss[0]), "mod « Abyss » [Abyss.bsa]")
    }

    func testArchiveReasonAndMergedFindings() {
        write("G/SkyrimSE.exe", "")
        writeBytes("G/Data/Skyshards.bsa", makeBSA([("scripts", ["DMN_SkyshardsFunctions.pex"])]))
        let block = String(repeating: """
        [11/03/2026 - 12:00:00AM] error: Cannot call X() on a None object, aborting function call
        stack:
        \t[Quest (000ABC)].DMN_SkyshardsFunctions.OnUpdate() - "DMN_SkyshardsFunctions.psc" Line 1

        """, count: 6)
        let r = Audit.auditPaths([write("Papyrus.0.log", block), write("Papyrus.1.log", "[11/02/2026 - 11:00:00PM] Papyrus log opened (PC)\n" + block)], gameDir: PyFS.join(tmp, "G"))
        let errs = r.findings.filter { $0.title.contains("erreurs Papyrus") }
        XCTAssertEqual(errs.count, 1, titles(r))
        XCTAssertTrue(errs[0].source.contains("Papyrus.0.log") && errs[0].source.contains("Papyrus.1.log"), errs[0].source)
        let s = r.suspects.first { $0.name == "DMN_SkyshardsFunctions" }
        XCTAssertTrue(s?.reasons.contains("fourni par l'archive « Skyshards.bsa »") ?? false, "\(String(describing: s?.reasons))")
    }
}
