// Configuration (config.json), liste des logs, purge : fonctions de src/Skyrim_Crash_Analyzer.py sans interface.

import Foundation

public enum Config {
    public static var docs: String { NSHomeDirectory() + "/Documents" }
    static let MAX_LOG_BYTES = 20 * 1024 * 1024
    static let TAIL_LINES = 80
    public static let MAX_CARDS = 18
    public static let MAX_ARCHIVED_CRASHES = 50

    static let ERROR_RE = Rx(#"(failed|error|cannot|missing|exception|access violation|null pointer)"#, i: true)
    static let LOG_NAME_RE = Rx(#"\.log(\.?\d+)?$"#, i: true)
    static let CRASH_NAME_RE = Rx(#"^crash[-_].*\.log$"#, i: true)

    /// Dossiers par défaut : {jeu: [dossiers]} dans l'ordre.
    public static func defaultFolders() -> [(String, [String])] {
        let mg = docs + "/My Games"
        return [("SKYRIM", [mg + "/Skyrim Special Edition/SKSE", mg + "/Skyrim Special Edition/SKSE/Crashlogs", mg + "/Skyrim Special Edition/Logs/Script"])]
    }

    static func readConfigFile() -> J {
        if let t = PyFS.readText(AppPaths.configFile), let j = J.parse(t), j.object != nil { return j }
        return .obj([])
    }

    static func writeConfigFile(_ data: J) {
        try? FileManager.default.createDirectory(atPath: AppPaths.appDir, withIntermediateDirectories: true)
        do { try data.dump(compact: false, indent: 2).write(toFile: AppPaths.configFile, atomically: false, encoding: .utf8) }
        catch { FileHandle.standardError.write(Data("Config save failed: \(error)\n".utf8)) }
    }

    /// Mode préversion : dossiers imposés par SKYRIM_CA_FOLDERS, config utilisateur intacte.
    public static var folderOverride: [String]? {
        guard let o = ProcessInfo.processInfo.environment["SKYRIM_CA_FOLDERS"], !o.isEmpty else { return nil }
        return o.components(separatedBy: ":").filter { !$0.isEmpty }
    }

    public static func loadConfig() -> [(String, [String])] {
        var cfg = defaultFolders()
        if let o = folderOverride { cfg[0].1 = o; return cfg }
        let data = readConfigFile()
        for i in cfg.indices {
            if let arr = data[cfg[i].0]?.array, arr.allSatisfy({ $0.string != nil }) { cfg[i].1 = arr.map { $0.string! } }
        }
        return cfg
    }

    public static func saveConfig(_ cfg: [(String, [String])]) {
        if folderOverride != nil { return }
        var data = readConfigFile()
        for (game, folders) in cfg { data = data.setting(game, .arr(folders.map { .str($0) })) }
        writeConfigFile(data)
    }

    public static func loadSettings() -> [String: String] {
        var s = Dictionary(uniqueKeysWithValues: AIClient.DEFAULT_SETTINGS)
        let stored = readConfigFile()["settings"]
        if let obj = stored?.object {
            for (k, v) in obj where s[k] != nil { if let str = v.string { s[k] = str } }
        }
        if stored?.object == nil || stored?["provider"] == nil {
            let (provider, model) = AIClient.detectDefaultProvider(baseURL: s["ollama_url"]!)
            s["provider"] = provider
            if !model.isEmpty { s["ollama_model"] = model }
        }
        // « auto » (ou valeur absente/inconnue) : langue du système, résolue à l'usage par `resolveLanguage`
        if I18n.langs[s["language"] ?? ""] == nil { s["language"] = "auto" }
        return s
    }

    public static func saveSettings(_ settings: [String: String]) {
        let order = AIClient.DEFAULT_SETTINGS.map { $0.0 }
        let obj: J = .obj(order.compactMap { k in settings[k].map { (k, J.str($0)) } })
        writeConfigFile(readConfigFile().setting("settings", obj))
    }

    /// Langue à afficher pour un choix mémorisé (« auto » ou fr/en/it/es) : celle du système, anglais si non prise en charge.
    public static func resolveLanguage(_ choice: String?) -> String {
        if let c = choice, I18n.langs[c] != nil { return c }
        return I18n.systemLang()
    }

    /// Langue du démarrage : celle des réglages, sinon celle du système.
    public static func startupLang() -> String {
        resolveLanguage(readConfigFile()["settings"]?["language"]?.string)
    }

    // MARK: logs

    /// Lit un log (utf-8, sinon utf-16), sans retirer les lignes vides. Tronque les fichiers volumineux.
    public static func readLines(_ path: String) -> [String] {
        guard let size = PyFS.size(path), let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        do {
            if size > MAX_LOG_BYTES { try fh.seek(toOffset: UInt64(size - MAX_LOG_BYTES)) }
            let raw = [UInt8](try fh.readToEnd() ?? Data())
            if raw.count >= 2, (raw[0] == 0xFF && raw[1] == 0xFE) || (raw[0] == 0xFE && raw[1] == 0xFF) { return decodeUTF16Ignore(raw[...]).pyLines }
            return decodeUTF8Ignore(raw[...]).pyLines
        } catch { return [] }
    }

    public static func scanForErrors(_ path: String) -> String? {
        for line in readLines(path).suffix(TAIL_LINES).reversed() where ERROR_RE.test(line) { return line.pyStrip }
        return nil
    }

    public static func isCrashName(_ name: String) -> Bool { CRASH_NAME_RE.test(name) }
    public static func isLogName(_ name: String) -> Bool { LOG_NAME_RE.test(name) }

    public struct LogFile { public let name: String; public let folder: String; public let path: String; public let mtime: Double }

    /// Les .log/.log0 existants des dossiers donnés.
    public static func listLogs(_ folders: [String]) -> [LogFile] {
        var out: [LogFile] = []
        for folder in folders where PyFS.isDir(folder) {
            guard let names = PyFS.listdir(folder) else { continue }
            for n in names {
                let p = PyFS.join(folder, n)
                if isLogName(n) && PyFS.isFile(p) && !PyFS.isLink(p), let m = PyFS.mtime(p) { out.append(LogFile(name: n, folder: folder, path: p, mtime: m)) }
            }
        }
        return out
    }

    /// Fichiers .log/.txt des dossiers configurés, les plus récents d'abord (les crash logs récents passent toujours).
    public static func gatherAuditFiles(_ folders: [String], limit: Int = 40) -> [String] {
        var found: [(Double, String)] = []
        for folder in folders where PyFS.isDir(folder) {
            guard let names = PyFS.listdir(folder) else { continue }
            for n in names where n.lowercased().hasSuffix(".log") || n.lowercased().hasSuffix(".txt") {
                let p = PyFS.join(folder, n)
                if PyFS.isFile(p), let m = PyFS.mtime(p) { found.append((m, p)) }
            }
        }
        found.sort { $0.0 != $1.0 ? $0.0 > $1.0 : pyLess($1.1, $0.1) }
        let crashes = Array(found.filter { CRASH_NAME_RE.test(PyFS.basename($0.1)) }.map { $0.1 }.prefix(Audit.MAX_CRASH_LOGS))
        let rest = found.map { $0.1 }.filter { !crashes.contains($0) }
        return crashes + Array(rest.prefix(max(0, limit - crashes.count)))
    }

    /// Dossier « My Games/Skyrim Special Edition/SKSE » : journal SKSE et rapports de Crash Logger.
    public static func skseLogDir(_ folders: [String]) -> String {
        for d in Insights.docsDirs(folders) + [docs + "/My Games/Skyrim Special Edition"] {
            let s = PyFS.join(d, "SKSE")
            if PyFS.isDir(s) { return s }
        }
        return ""
    }

    /// Dossiers configurés + dossier SKSE, toujours analysé même s'il a été retiré des réglages.
    public static func withSkseDir(_ gameFolders: [(String, [String])]) -> [(String, [String])] {
        var out = gameFolders
        let every = out.flatMap { $0.1 }
        let d = skseLogDir(every)
        if !d.isEmpty && !out.isEmpty && !Set(every.map { PyFS.normpath($0) }).contains(PyFS.normpath(d)) { out[0].1.append(d) }
        return out
    }

    static func archiveCrash(_ path: String, _ folder: String) throws {
        let destDir = PyFS.join(folder, Insights.ARCHIVE_DIR)
        try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        let (stem, ext) = PyFS.splitext(PyFS.basename(path))
        var dest = PyFS.join(destDir, stem + ext)
        var k = 1
        while PyFS.exists(dest) { dest = PyFS.join(destDir, "\(stem)-\(k)\(ext)"); k += 1 }
        try FileManager.default.moveItem(atPath: path, toPath: dest)
        var old: [(Double, String)] = []
        for n in PyFS.listdir(destDir) ?? [] where CRASH_NAME_RE.test(n) { if let m = PyFS.mtime(PyFS.join(destDir, n)) { old.append((m, n)) } }
        old.sort { $0.0 != $1.0 ? $0.0 < $1.0 : pyLess($0.1, $1.1) }
        for (_, n) in old.dropLast(MAX_ARCHIVED_CRASHES) { try FileManager.default.removeItem(atPath: PyFS.join(destDir, n)) }
    }

    /// Supprime les logs des dossiers donnés (non récursif) ; les crash logs sont archivés. (supprimés, archivés, erreurs)
    public static func purgeLogs(_ folders: [String]) -> (Int, Int, [String]) {
        var deleted = 0, archived = 0
        var errors: [String] = []
        for f in listLogs(folders) {
            do {
                if CRASH_NAME_RE.test(f.name) { try archiveCrash(f.path, f.folder); archived += 1 }
                else { try FileManager.default.removeItem(atPath: f.path); deleted += 1 }
            } catch { errors.append("\(f.name) : \(error.localizedDescription)") }
        }
        return (deleted, archived, errors)
    }
}
