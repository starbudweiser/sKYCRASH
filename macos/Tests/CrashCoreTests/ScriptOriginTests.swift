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
}
