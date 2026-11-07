// Export structuré des analyses de plantage, lu par mORTEX (contrat v1, docs/export_crash_events.md).
// Un fichier JSON Lines, une ligne par plantage analysé, en ajout seul. Aucun contenu brut de log ni chemin personnel.

import CryptoKit
import Darwin
import Foundation

public enum ExportEvents {
    public static let SCHEMA = 1
    public static let EXPORT_ENV = "SKYRIM_CA_EXPORT_DIR"
    public static let FILENAME = "crash_events.jsonl"
    static let MAX_REASONS = 4
    static let PLUGIN_EXTS = [".esp", ".esm", ".esl"]
    static let ENV_TAGS: Set<String> = ["mémoire", "graphique", "plateforme", "version", "plugins", "réglages"]
    static let HEADER_VER_RE = Rx(#"^Skyrim\s*\w*\s*v([\d.]+)"#, i: true)
    static let TAG_RE = Rx(#"^\[([^\]]+)\]"#)
    static let USER_PATH_RES = [Rx(#"/Users/[^/\s"']+"#), Rx(#"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s"']+"#, i: true)]

    public static func exportDir() -> String {
        if let o = ProcessInfo.processInfo.environment[EXPORT_ENV], !o.isEmpty { return o }
        return NSHomeDirectory() + "/Library/Application Support/SkyrimCrashAnalyzer/exports"
    }
    public static func exportPath() -> String { PyFS.join(exportDir(), FILENAME) }

    /// Retire chemins personnels et nom d'utilisateur d'un texte libre.
    public static func scrub(_ text: String) -> String {
        var t = text
        for rx in USER_PATH_RES { t = rx.sub("~", t) }
        let user = PyFS.basename(NSHomeDirectory())
        if user.pyLen >= 3 { t = Rx(reEscape(user), i: true).sub("user", t) }
        return t
    }

    static func bottleName(_ gameDir: String) -> String? {
        let parts = PyFS.normpath(gameDir).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let i = parts.firstIndex(of: "drive_c"), i >= 1 else { return nil }
        let s = scrub(parts[i - 1])
        return s.isEmpty ? nil : s
    }

    /// Étiquette de catégorie ramenée au français (clé stable), quelle que soit la langue de l'appli.
    static func frTag(_ tag: String) -> String {
        if translations[tag] != nil { return tag }
        for (fr, tr) in translations where tr.contains(tag) { return fr }
        return tag
    }

    public static func suspectKind(_ name: String) -> String {
        let low = name.lowercased()
        if low.hasSuffix(".dll") { return "dll" }
        if low.hasSuffixAny(PLUGIN_EXTS) { return "plugin" }
        return "object"
    }

    struct EventSuspect { var name: String; var kind: String; var score: Int; var reasons: [String] }

    static func suspects(_ report: AuditReport) -> [EventSuspect] {
        var out: [EventSuspect] = []
        for s in report.suspects {
            var name = s.name
            let kind: String
            if let m = TAG_RE.match(name) {
                let tag = frTag(m.group(1)!)
                if ENV_TAGS.contains(tag) { continue }
                name = tag; kind = "object"
            } else { kind = suspectKind(name) }
            out.append(EventSuspect(name: scrub(name), kind: kind, score: s.score, reasons: s.reasons.prefix(MAX_REASONS).map(scrub)))
        }
        return out
    }

    static func env(_ name: String, _ score: Int, _ reason: String) -> EventSuspect {
        EventSuspect(name: name, kind: "env", score: score, reasons: [reason])
    }

    static func envSuspects(_ lines: [String], _ report: AuditReport, _ gameVersion: String?) -> [EventSuspect] {
        var out: [EventSuspect] = []
        let specs = Audit.readSpecs(lines)
        let modules = Audit.readModules(lines)
        let isWine = Audit.WINE_RE.test(specs.values.joined(separator: " ")) || modules.contains { $0.lowercased().hasPrefix("wine") }
        if isWine {
            out.append(env("wine_layer", 3, "game running through CrossOver/Wine/GPTK"))
            if let r = Audit.detectRenderer(lines) { out.append(env("renderer:" + r, 1, "graphics translation layer: " + r)) }
            if modules.contains(where: { m in Audit.DLSS_HINTS.contains { m.lowercased().contains($0) } }) {
                out.append(env("dlss_unavailable", 2, "DLSS/Streamline modules loaded but unavailable under Wine"))
            }
        }
        let ram = Audit.MEM_RE.search(specs["PHYSICAL MEMORY"] ?? "")
        let vram = Audit.MEM_RE.search(specs["GPU MEMORY"] ?? "")
        let unified = isWine && ram != nil && vram != nil && Audit.num(vram!.group(2)!) >= Audit.num(ram!.group(2)!)
        if unified { out.append(env("unified_memory", 1, "GPU memory is shared with system RAM")) }
        for (key, label) in [("PHYSICAL MEMORY", "RAM"), ("GPU MEMORY", "VRAM")] {
            if unified && key == "GPU MEMORY" { continue }
            if let m = Audit.MEM_RE.search(specs[key] ?? ""), Audit.num(m.group(2)!) > 0, Audit.num(m.group(1)!) / Audit.num(m.group(2)!) >= 0.85 {
                out.append(env("memory_pressure", 5, "\(label) at \(Audit.fmt0(100 * Audit.num(m.group(1)!) / Audit.num(m.group(2)!)))% at crash time"))
            }
        }
        let rt = report.skseRuntime.isEmpty ? nil : Compat.decodeRuntime(report.skseRuntime)
        var gv: [Int]?
        if let g = gameVersion, Rx(#"[\d.]+"#).fullmatch(g) != nil {
            let nums = g.components(separatedBy: ".").prefix(3).map { Int($0) }
            if !nums.contains(where: { $0 == nil }) { gv = nums.map { $0! } }
        }
        if let gv, let rt, gv.count == 3, [rt.0, rt.1, rt.2] != gv {
            out.append(env("game_skse_mismatch", 10, "game \(gameVersion!) vs SKSE runtime \(rt.0).\(rt.1).\(rt.2)"))
        }
        if let inv = report.extras.inventory {
            if inv.addressLibrary == false { out.append(env("address_library_missing", 6, "Address Library file for this game version not found")) }
            if let pl = inv.plugins, !pl.limitOk {
                out.append(env("plugin_limit", 8, "\(pl.full) full plugins active, limit is \(Compat.MAX_PLUGINS_NON_ESL)"))
            }
            for (proxy, role) in inv.proxies ?? [] {
                out.append(env("graphics_proxy", 1, "\(proxy) at game root: \(role.isEmpty ? "unknown" : role)"))
            }
        }
        return out
    }

    /// SHA-256 de la liste ordonnée (ordre de chargement) des plugins actifs de plugins.txt, en minuscules.
    public static func pluginsHash(_ gameDir: String) -> String? {
        if gameDir.isEmpty { return nil }
        guard let ptxt = Compat.findPluginsTxt(gameDir), let t = PyFS.readText(ptxt) else { return nil }
        var active: [String] = []
        for l in t.pyFileLines where l.hasPrefix("*") {
            let rest = String(l.pyStrip.unicodeScalars.dropFirst())
            if !rest.isEmpty { active.append(rest.lowercased()) }
        }
        if active.isEmpty { return nil }
        return SHA256.hash(data: Data(active.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public struct Event {
        public var crashTime: String?
        public var logName: String
        var gameRuntime: String?
        var skseRuntime: String?
        var verdict: String
        var suspects: [EventSuspect]
        var pluginsHash: String?
        var bottle: String?

        public var json: J {
            func opt(_ s: String?) -> J { s.map { .str($0) } ?? .null }
            return .obj([
                ("schema", .int(SCHEMA)), ("crash_time", opt(crashTime)), ("log_name", .str(logName)),
                ("game_runtime", opt(gameRuntime)), ("skse_runtime", opt(skseRuntime)), ("verdict", .str(verdict)),
                ("suspects", .arr(suspects.map { .obj([("name", .str($0.name)), ("kind", .str($0.kind)), ("score", .int($0.score)),
                                                       ("reasons", .arr($0.reasons.map { .str($0) }))]) })),
                ("plugins_hash", opt(pluginsHash)), ("bottle", opt(bottle)),
            ])
        }
        /// Ligne telle que Python l'écrit (`json.dumps(..., ensure_ascii=False, separators=(",", ":"))`).
        public var line: String { json.dump(compact: true) }
    }

    /// Événement v1 d'un plantage. `report` : AuditReport dont les suspects portent sur ce crash.
    public static func buildEvent(_ crashPath: String, _ lines: [String], _ report: AuditReport) -> Event {
        let when = try? Insights.crashTime(crashPath, lines)
        var gameVersion = lines.prefix(5).lazy.compactMap { HEADER_VER_RE.match($0.pyStrip)?.group(1) }.first
        if gameVersion == nil || gameVersion!.isEmpty { gameVersion = report.extras.inventory?.gameVersion }
        let rt = report.skseRuntime.isEmpty ? nil : Compat.decodeRuntime(report.skseRuntime)
        return Event(
            crashTime: when?.format("%Y-%m-%dT%H:%M:%S"), logName: PyFS.basename(crashPath),
            gameRuntime: gameVersion, skseRuntime: rt.map { "\($0.0).\($0.1).\($0.2)" },
            verdict: scrub(report.verdict), suspects: suspects(report) + envSuspects(lines, report, gameVersion),
            pluginsHash: pluginsHash(report.gameDir), bottle: bottleName(report.gameDir))
    }

    static func key(_ logName: String, _ crashTime: String?) -> String { logName + "\u{0}" + (crashTime ?? "\u{1}null") }

    static func existingKeys(_ path: String) -> Set<String> {
        var keys = Set<String>()
        guard let t = PyFS.readText(path) else { return keys }
        for l in t.pyFileLines {
            guard let j = J.parse(l), let name = j["log_name"]?.string, let ct = j["crash_time"] else { continue }
            keys.insert(key(name, ct.string))
        }
        return keys
    }

    /// Ajoute la ligne si ce crash (nom du log + CRASH TIME) n'y est pas déjà. Retourne true si écrite.
    @discardableResult
    public static func appendEvent(_ event: Event, path: String? = nil) -> Bool {
        let p = path ?? exportPath()
        try? FileManager.default.createDirectory(atPath: PyFS.dirname(p), withIntermediateDirectories: true)
        let bytes = Array((event.line + "\n").utf8)
        let fd = open(p, O_RDWR | O_APPEND | O_CREAT, 0o644)
        if fd < 0 { return false }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        if existingKeys(p).contains(key(event.logName, event.crashTime)) { return false }
        let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress, bytes.count) }
        fsync(fd)
        return n == bytes.count
    }

    /// Écrit un événement par crash log analysé ; retourne le nombre de lignes ajoutées.
    @discardableResult
    public static func exportReport(_ report: AuditReport, gameDir: String = "", path: String? = nil) -> Int {
        var crashes: [(String, [String])] = [], others: [(String, [String])] = []
        for p in report.analysed {
            let lines = Audit.readLines(p)
            if Audit.classifyLog(p, lines) == "crash" { crashes.append((p, lines)) } else { others.append((p, lines)) }
        }
        var added = 0
        for (p, lines) in crashes {
            let rep = crashes.count == 1 ? report : Audit.auditPaths([p] + others.map { $0.0 }, gameDir: gameDir)
            if appendEvent(buildEvent(p, lines, rep), path: path) { added += 1 }
        }
        return added
    }

    /// Audit complet puis export (si activé). L'export n'échoue jamais l'audit.
    public static func auditAndExport(_ files: [String], gameDir: String, enabled: Bool = true) -> AuditReport {
        let report = Audit.auditPaths(files, gameDir: gameDir)
        if enabled { exportReport(report, gameDir: gameDir) }
        return report
    }
}
