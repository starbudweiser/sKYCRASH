// Provenance des scripts Papyrus (.pex) : quel mod ou quelle archive BSA fournit un script cité dans les logs.
// Sources : Data/Scripts et Data/*.bsa du jeu, puis chaque mod MO2 (dossier Scripts/ et BSA à sa racine).
// Pas de « gagnant » : l'ordre de priorité de MO2 n'est pas lu ; plusieurs fournisseurs = conflit possible.

import Foundation

public struct ScriptProvider: Equatable {
    /// Mod MO2, ou vide pour le dossier Data du jeu.
    public var mod: String
    /// Nom de l'archive BSA, ou vide pour un fichier lâche.
    public var archive: String
}

public enum ScriptOrigin {
    public typealias Index = [String: [ScriptProvider]]
    static let MAX_BSA_INDEX = 64 << 20

    static func add(_ index: inout Index, _ script: String, _ p: ScriptProvider) {
        let k = script.lowercased()
        var list = index[k] ?? []
        if !list.contains(p) { list.append(p) }
        index[k] = list
    }

    /// Enfant de `dir` dont le nom vaut `name` sans tenir compte de la casse.
    static func child(_ dir: String, _ name: String) -> String? {
        guard let names = PyFS.listdir(dir) else { return nil }
        return names.first { $0.lowercased() == name }.map { PyFS.join(dir, $0) }
    }

    static func stem(_ file: String) -> String { PyFS.splitext(file).0 }

    /// Ajoute les .pex lâches de `dir/Scripts` et les scripts des BSA de `dir`.
    static func scan(_ dir: String, mod: String, _ index: inout Index) {
        if let sdir = child(dir, "scripts"), PyFS.isDir(sdir) {
            for n in PyFS.listdir(sdir) ?? [] where n.lowercased().hasSuffix(".pex") {
                add(&index, stem(n), ScriptProvider(mod: mod, archive: ""))
            }
        }
        for n in pySorted(PyFS.listdir(dir) ?? []) where n.lowercased().hasSuffix(".bsa") {
            for s in bsaScripts(PyFS.join(dir, n)) { add(&index, s, ScriptProvider(mod: mod, archive: n)) }
        }
    }

    /// Noms (sans .pex) des scripts d'une archive BSA v103/104/105 ; vide si illisible.
    /// Lit seulement l'index du début du fichier (en-tête, dossiers, noms), sans rien décompresser.
    public static func bsaScripts(_ path: String) -> [String] {
        guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        let head = [UInt8](fh.readData(ofLength: 36))
        guard head.count == 36, head[0..<4] == [0x42, 0x53, 0x41, 0x00] else { return [] }
        func u32(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        let ver = u32(head, 4), offset = u32(head, 8), flags = u32(head, 12)
        let nd = u32(head, 16), nf = u32(head, 20), dnl = u32(head, 24), fnl = u32(head, 28)
        guard [103, 104, 105].contains(ver), offset == 36, flags & 1 != 0, flags & 2 != 0 else { return [] }
        let rec = ver == 105 ? 24 : 16
        let need = rec * nd + dnl + nd + 16 * nf + fnl
        guard need > 0, need <= MAX_BSA_INDEX else { return [] }
        let b = [UInt8](fh.readData(ofLength: need))
        guard b.count == need else { return [] }
        var counts: [Int] = []
        for i in 0..<nd { counts.append(u32(b, i * rec + 8)) }
        var pos = rec * nd, dirs: [String] = []
        for c in counts {
            guard pos < b.count else { return [] }
            let l = Int(b[pos])
            guard l >= 1, pos + 1 + l <= b.count else { return [] }
            dirs.append(String(decoding: b[(pos + 1)..<(pos + l)], as: UTF8.self).lowercased())
            pos += 1 + l + 16 * c
            guard pos <= b.count else { return [] }
        }
        guard counts.reduce(0, +) == nf, pos + fnl <= b.count else { return [] }
        let names = b[pos..<(pos + fnl)].split(separator: 0, omittingEmptySubsequences: false)
        guard names.count >= nf else { return [] }
        var out: [String] = [], k = 0
        for (d, c) in zip(dirs, counts) {
            let inScripts = d == "scripts" || d.hasPrefix("scripts\\") || d.hasPrefix("scripts/")
            for _ in 0..<c {
                let n = String(decoding: names[k], as: UTF8.self)
                if inScripts && n.lowercased().hasSuffix(".pex") { out.append(stem(n)) }
                k += 1
            }
        }
        return out
    }

    /// {script en minuscules : [fournisseurs]} pour le jeu et les mods MO2 ; vide sans dossier du jeu.
    public static func buildIndex(_ gameDir: String) -> Index {
        var index: Index = [:]
        if gameDir.isEmpty { return index }
        if let data = child(gameDir, "data"), PyFS.isDir(data) { scan(data, mod: "", &index) }
        let modsDir = ModOrigin.mo2ModsDir(gameDir)
        if !modsDir.isEmpty {
            for mod in pySorted(PyFS.listdir(modsDir) ?? []) {
                let dir = PyFS.join(modsDir, mod)
                if !PyFS.isDir(dir) || mod.hasSuffix("_separator") || PyFS.isLink(dir) { continue }
                scan(dir, mod: mod, &index)
            }
        }
        return index
    }

    public static func providers(_ script: String, _ index: Index) -> [ScriptProvider] {
        var s = PyFS.basename(script)
        if s.lowercased().hasSuffix(".psc") || s.lowercased().hasSuffix(".pex") { s = stem(s) }
        return index[s.lowercased()] ?? []
    }

    /// « mod » ou « jeu », suivi de l'archive entre parenthèses s'il y en a une.
    public static func label(_ p: ScriptProvider) -> String {
        let who = p.mod.isEmpty ? L("jeu (Data)") : L("mod « {mod} »", ["mod": p.mod])
        return p.archive.isEmpty ? who : who + " [" + p.archive + "]"
    }
}
