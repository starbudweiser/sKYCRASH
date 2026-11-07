// Mod d'origine des fichiers suspects (DLL SKSE, plugins) : traduction de src/mod_origin.py.

import Foundation

public enum ModOrigin {
    public static let EXTS = [".dll", ".esp", ".esm", ".esl"]
    static let SNAPSHOT = ".mabbajack/installation.json.gz"
    static let MAX_FILES = 400_000

    public typealias Index = [String: [String]]

    static func add(_ index: inout Index, _ name: String, _ mod: String) {
        var mods = index[name.lowercased()] ?? []
        if !mods.contains(mod) { mods.append(mod) }
        index[name.lowercased()] = mods
    }

    static func fromMabbajack(_ gameDir: String, _ index: inout Index) -> Bool {
        let path = PyFS.join(gameDir, SNAPSHOT)
        guard PyFS.isFile(path) else { return false }
        guard let gz = PyFS.read(path), let raw = Zlib.inflate(gz, windowBits: 31),
              let snap = (try? JSONSerialization.jsonObject(with: Data(raw))) as? [String: Any] else { return true }
        for entry in (snap["manifest"] as? [Any]) ?? [] {
            var first = ""
            if let a = entry as? [Any], let f = a.first { first = pyStr(f) }
            else if let s = entry as? String, let c = s.first { first = String(c) }
            let parts = first.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/")
            if parts.count >= 3, parts[0].lowercased() == "mods", parts.last!.lowercased().hasSuffixAny(EXTS) {
                add(&index, parts.last!, parts[1])
            }
        }
        return true
    }

    static func pyStr(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    static func mo2ModsDir(_ gameDir: String) -> String {
        for base in [gameDir, PyFS.dirname(gameDir)] {
            if PyFS.isFile(PyFS.join(base, "ModOrganizer.ini")) && PyFS.isDir(PyFS.join(base, "mods")) { return PyFS.join(base, "mods") }
        }
        return ""
    }

    static func fromMO2(_ gameDir: String, _ index: inout Index) -> Bool {
        let modsDir = mo2ModsDir(gameDir)
        if modsDir.isEmpty { return false }
        var seen = 0
        let skip: Set<String> = ["meshes", "textures", "sound", "music", "interface"]
        // os.walk en profondeur d'abord, sans suivre les liens ; retourne true quand le garde-fou est atteint
        func walk(_ top: String, _ mod: String) -> Bool {
            guard let names = PyFS.listdir(top) else { return false }
            var dirs: [String] = [], files: [String] = []
            for n in names {
                let p = PyFS.join(top, n)
                if PyFS.isDir(p) { dirs.append(n) } else { files.append(n) }
            }
            dirs = dirs.filter { !skip.contains($0.lowercased()) }
            for name in files {
                seen += 1
                if name.lowercased().hasSuffixAny(EXTS) { add(&index, name, mod) }
            }
            if seen > MAX_FILES { return true }
            for d in dirs {
                let p = PyFS.join(top, d)
                if PyFS.isLink(p) { continue }
                if walk(p, mod) { return true }
            }
            return false
        }
        for mod in pySorted(PyFS.listdir(modsDir) ?? []) {
            let rootDir = PyFS.join(modsDir, mod)
            if !PyFS.isDir(rootDir) || mod.hasSuffix("_separator") { continue }
            if walk(rootDir, mod) { return true }
        }
        return true
    }

    /// {nom de fichier en minuscules: [mods]} ; vide si aucune source n'est trouvée.
    public static func buildIndex(_ gameDir: String) -> Index {
        var index: Index = [:]
        if gameDir.isEmpty { return index }
        if fromMabbajack(gameDir, &index) { return index }
        _ = fromMO2(gameDir, &index)
        return index
    }

    public static func originOf(_ name: String, _ index: Index) -> [String] {
        index[PyFS.basename(name).lowercased()] ?? []
    }
}
