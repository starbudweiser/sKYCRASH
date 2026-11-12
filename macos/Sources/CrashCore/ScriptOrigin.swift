// Provenance des scripts Papyrus (.pex) : quel mod ou quelle archive BSA fournit un script cité dans les logs.
// Sources : Data/Scripts et Data/*.bsa du jeu, puis chaque mod MO2 (dossier Scripts/ et BSA à sa racine).
// Fichiers déployés par Vortex ou mORTEX : le mod source est lu dans Data/*.deployment.json (relPath → source).
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
    /// `deployed` : {chemin relatif en minuscules (« scripts/x.pex », « x.bsa ») : mod source} d'un gestionnaire.
    static func scan(_ dir: String, mod: String, deployed: [String: String] = [:], _ index: inout Index) {
        func owner(_ rel: String) -> String { mod.isEmpty ? (deployed[rel.lowercased()] ?? "") : mod }
        if let sdir = child(dir, "scripts"), PyFS.isDir(sdir) {
            for n in PyFS.listdir(sdir) ?? [] where n.lowercased().hasSuffix(".pex") {
                add(&index, stem(n), ScriptProvider(mod: owner("scripts/" + n), archive: ""))
            }
        }
        for n in pySorted(PyFS.listdir(dir) ?? []) where n.lowercased().hasSuffix(".bsa") {
            let m = owner(n)
            for s in bsaScripts(PyFS.join(dir, n)) { add(&index, s, ScriptProvider(mod: m, archive: n)) }
        }
    }

    /// Mods sources des scripts et archives d'après les manifestes de déploiement (Vortex, mORTEX) de `dataDir`.
    public static func deployedSources(_ dataDir: String) -> [String: String] {
        var out: [String: String] = [:]
        for n in pySorted(PyFS.listdir(dataDir) ?? []) where n.lowercased().hasSuffix(".deployment.json") {
            guard let raw = PyFS.read(PyFS.join(dataDir, n)),
                  let root = (try? JSONSerialization.jsonObject(with: Data(raw))) as? [String: Any],
                  let files = root["files"] as? [[String: Any]] else { continue }
            for f in files {
                guard let rel = (f["relPath"] as? String)?.replacingOccurrences(of: "\\", with: "/").lowercased(),
                      let src = f["source"] as? String, !src.isEmpty else { continue }
                let isScript = rel.hasPrefix("scripts/") && rel.hasSuffix(".pex") && rel.dropFirst(8).firstIndex(of: "/") == nil
                let isBSA = rel.hasSuffix(".bsa") && !rel.contains("/")
                if (isScript || isBSA) && out[rel] == nil { out[rel] = src }
            }
        }
        return out
    }

    static let NEXUS_NEW_RE = Rx(#"\s+\d+\s+\S+\s+\d{4}-\d{2}-\d{2}T\d{2}-\d{2}Z\s+\S+$"#)
    static let NEXUS_OLD_RE = Rx(#"-\d{2,}(?:-[0-9A-Za-z]+)+$"#)

    /// Nom de mod sans le suffixe d'archive Nexus (« Abyss-83329-3-1-6-1708252797 » → « Abyss »,
    /// « Wade In Water Redone 71418 1.1.3 2026-08-24T21-06Z Ks18n0wt0 » → « Wade In Water Redone »).
    public static func cleanModName(_ name: String) -> String {
        for re in [NEXUS_NEW_RE, NEXUS_OLD_RE] {
            let c = re.sub("", name).pyStrip
            if c != name && !c.isEmpty { return c }
        }
        return name
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
        if let data = child(gameDir, "data"), PyFS.isDir(data) { scan(data, mod: "", deployed: deployedSources(data), &index) }
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
        let who = p.mod.isEmpty ? L("jeu (Data)") : L("mod « {mod} »", ["mod": cleanModName(p.mod)])
        return p.archive.isEmpty ? who : who + " [" + p.archive + "]"
    }
}
