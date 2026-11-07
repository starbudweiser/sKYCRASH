// Fiche d'installation vérifiée : ce qui est réellement présent dans le jeu, lu sur le disque (src/inventory.py).
// Envoyée à l'assistant IA comme FAITS, et utilisée par Guard pour retirer les conseils qui les contredisent.

import Foundation

public struct Inventory {
    public var gameDir = ""
    public var gameVersion: String?
    public var tools: [(String, Bool)]?
    public var skseInstalled: Bool?
    public var addressLibrary: Bool?
    public var enb: Bool?
    public var reshade: Bool?
    public var proxies: [(String, String)]?
    public var cc: (listed: Int, present: Int)?
    public var plugins: (active: Int, full: Int, light: Int, limitOk: Bool, pluginsTxt: String?)?
    public var bottle: String?
    public var skseVersion: String?
    public var crashLogs: (active: Int, archived: Int, dir: String, last: (String, String)?) = (0, 0, "", nil)
    public var crashloggerVersion: String?

    public func tool(_ key: String) -> Bool { tools?.first { $0.0 == key }?.1 ?? false }
}

extension Inventory {
    // clé -> (nom affiché, fichiers DLL dans Data/SKSE/Plugins, en minuscules)
    static let TOOLS: [(String, String, [String])] = [
        ("crashlogger", "Crash Logger SSE", ["crashlogger.dll"]),
        ("trainwreck", "Trainwreck", ["trainwreck.dll"]),
        ("enginefixes", "SSE Engine Fixes", ["enginefixes.dll"]),
        ("bugfixes", "Bug Fixes SSE", ["bugfixessse.dll"]),
        ("scrambledbugs", "Scrambled Bugs", ["scrambledbugs.dll"]),
        ("papyrustweaks", "Papyrus Tweaks NG", ["papyrustweaks.dll"]),
        ("displaytweaks", "SSE Display Tweaks", ["ssedisplaytweaks.dll"]),
        ("spid", "Spell Perk Item Distributor", ["po3_spellperkitemdistributor.dll"]),
        ("kid", "Keyword Item Distributor", ["po3_keyworditemdistributor.dll"]),
        ("bos", "Base Object Swapper", ["po3_baseobjectswapper.dll"]),
        ("papyrusextender", "powerofthree's Papyrus Extender", ["po3_papyrusextender.dll"]),
        ("tweaks", "powerofthree's Tweaks", ["po3_tweaks.dll"]),
        ("jcontainers", "JContainers", ["jcontainers64.dll"]),
        ("racemenu", "RaceMenu (skee64)", ["skee64.dll"]),
        ("mcmhelper", "MCM Helper", ["mcmhelper.dll"]),
        ("communityshaders", "Community Shaders", ["communityshaders.dll"]),
    ]
    static func toolLabel(_ key: String) -> String { TOOLS.first { $0.0 == key }!.1 }
    static let PROXY_DLLS = ["d3d11.dll", "dxgi.dll", "d3d12.dll"]
    static let PROXY_MARKERS: [([UInt8], String)] = [
        (Array("mDLSS".utf8), "pont mDLSS (DLSS vers MetalFX)"), (Array("crosire's ReShade".utf8), "ReShade"),
        (Array("ReShade".utf8), "ReShade"), (Array("ENBSeries".utf8), "ENB"), (Array("enbseries".utf8), "ENB"),
        (Array("DXVK".utf8), "DXVK"), (Array("dxmt".utf8), "DXMT"), (Array("Community Shaders".utf8), "Community Shaders"),
    ]
    static let SKSE_VERSION_RE = Rx(#"SKSE64 runtime: initialize \(version = ([\d.]+)"#)
    static let CRASHLOGGER_VER_RE = Rx(#"CrashLoggerSSE v([\d-]+)"#)

    /// Faits vérifiés. `entries` : logs lus par le moteur ; `history` : crash logs (actifs et archivés).
    static func build(_ gameDir: String, _ entries: [Audit.Entry], _ history: [CrashSummary]) -> Inventory {
        var f = Inventory()
        f.gameDir = gameDir
        if !gameDir.isEmpty {
            let ver = Compat.readExeVersion(PyFS.join(gameDir, "SkyrimSE.exe"))
            f.gameVersion = ver.map { "\($0.0).\($0.1).\($0.2).\($0.3)" }
            let plugDir = PyFS.join(gameDir, "Data", "SKSE", "Plugins")
            let dlls = Set((PyFS.listdir(plugDir) ?? []).map { $0.lowercased() })
            f.tools = TOOLS.map { ($0.0, $0.2.contains { dlls.contains($0) }) }
            f.skseInstalled = !PyFS.glob(PyFS.join(gameDir, "skse64_*.dll")).isEmpty
            if let ver { f.addressLibrary = dlls.contains(Compat.addressLibraryName(ver).lowercased()) }
            let root: Set<String> = PyFS.isDir(gameDir) ? Set((PyFS.listdir(gameDir) ?? []).map { $0.lowercased() }) : []
            f.enb = root.contains("enbseries.ini")
            f.reshade = root.contains("reshade.ini")
            f.proxies = PROXY_DLLS.filter { root.contains($0) }.map { ($0, proxyRole(PyFS.join(gameDir, $0))) }

            var ccc: [String] = []
            if let t = PyFS.readText(PyFS.join(gameDir, "Skyrim.ccc")) { ccc = t.pyFileLines.map { $0.pyStrip }.filter { !$0.isEmpty } }
            let dataDir = PyFS.join(gameDir, "Data")
            let data = Set((PyFS.listdir(dataDir) ?? []).map { $0.lowercased() })
            f.cc = (ccc.count, ccc.filter { data.contains($0.lowercased()) }.count)

            let (act, _, ptxt) = Insights.activePlugins(gameDir)
            let light = act.filter { Compat.isLightPlugin(PyFS.join(dataDir, $0)) }.count
            let full = act.count - light
            f.plugins = (act.count, full, light, full <= Compat.MAX_PLUGINS_NON_ESL, ptxt)
            let parts = PyFS.normpath(gameDir).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if let i = parts.firstIndex(of: "drive_c"), i >= 1 { f.bottle = parts[i - 1] }
        }

        for e in entries where e.kind == "skse" {
            if let m = e.lines.prefix(5).lazy.compactMap({ SKSE_VERSION_RE.search($0) }).first {
                f.skseVersion = m.group(1)
                break
            }
        }
        let active = history.filter { !$0.path.components(separatedBy: "/").contains(Insights.ARCHIVE_DIR) }
        let archived = history.count - active.count
        let folders = pySorted(Array(Set(entries.map { PyFS.dirname($0.path) })))
        let skseDir: String = {
            for d in Insights.docsDirs(folders) where PyFS.isDir(PyFS.join(d, "SKSE")) { return PyFS.join(d, "SKSE") }
            for e in entries where e.kind == "skse" { return PyFS.dirname(e.path) }
            return ""
        }()
        var last: (String, String)?
        if let h = history.first, let t = h.time { last = (t.format("%d/%m/%Y %H:%M"), h.where) }
        f.crashLogs = (active.count, archived,
                       history.first.map { PyFS.dirname($0.path).replacingOccurrences(of: "/" + Insights.ARCHIVE_DIR, with: "") } ?? skseDir,
                       last)
        for c in history {
            guard let fh = FileHandle(forReadingAtPath: c.path), let d = try? fh.read(upToCount: 4096) else { continue }
            try? fh.close()
            let head = decodeUTF8Ignore([UInt8](d)[...]).replacingOccurrences(of: "\r\n", with: "\n").pyPrefix(400)
            if let m = CRASHLOGGER_VER_RE.search(head) {
                f.crashloggerVersion = m.group(1)!.replacingOccurrences(of: "-", with: ".")
                break
            }
        }
        return f
    }

    /// Rôle d'une DLL graphique posée à la racine du jeu, d'après des marqueurs dans le binaire.
    static func proxyRole(_ path: String) -> String {
        guard let fh = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? fh.close() }
        guard let blob = try? fh.read(upToCount: 8 * 1024 * 1024) else { return "" }
        for (marker, role) in PROXY_MARKERS where blob.range(of: Data(marker)) != nil { return role }
        return "inconnu"
    }

    static func yes(_ b: Bool?) -> String { (b ?? false) ? L("oui") : L("non") }

    /// Bloc « faits vérifiés » pour l'assistant IA (en français, comme le reste du contexte).
    public func toContext() -> String {
        var out = [L("## Faits vérifiés sur l'installation (lus sur le disque : ne pas les remettre en cause)")]
        if let v = gameVersion, !v.isEmpty { out.append(L("- Jeu : SkyrimSE.exe {v}", ["v": v])) }
        if let s = skseInstalled {
            out.append(L("- SKSE installé : {b}", ["b": Inventory.yes(s)]) + ((skseVersion ?? "").isEmpty ? "" : " (v\(skseVersion!))"))
        }
        if let a = addressLibrary { out.append(L("- Address Library pour cette version : {b}", ["b": Inventory.yes(a)])) }
        let present = (tools ?? []).filter { $0.1 }.map { Inventory.toolLabel($0.0) }
        let absent = (tools ?? []).filter { !$0.1 }.map { Inventory.toolLabel($0.0) }
        if !present.isEmpty {
            let cl = crashloggerVersion ?? ""
            out.append(L("- Outils installés : {l}", ["l": present.map { $0 + ($0 == "Crash Logger SSE" && !cl.isEmpty ? " v\(cl)" : "") }.joined(separator: ", ")]))
        }
        if !absent.isEmpty { out.append(L("- Outils absents : {l}", ["l": absent.joined(separator: ", ")])) }
        if let cc { out.append(L("- Creation Club : {p} fichier(s) présents sur {n} listés dans Skyrim.ccc (chargés automatiquement)", ["p": cc.present, "n": cc.listed])) }
        if let pl = plugins {
            out.append(L("- Plugins actifs : {a} ({f} pleins, {l} légers ESL) — limite de 254 pleins : {ok}",
                         ["a": pl.active, "f": pl.full, "l": pl.light, "ok": pl.limitOk ? L("respectée") : L("DÉPASSÉE")]))
        }
        if let b = bottle, !b.isEmpty { out.append(L("- Jeu lancé sous CrossOver (bouteille « {b} »)", ["b": b])) }
        if (enb ?? false) || (reshade ?? false) {
            out.append(L("- Post-traitement : ENB {e}, ReShade {r}", ["e": Inventory.yes(enb), "r": Inventory.yes(reshade)]))
        }
        for (name, role) in proxies ?? [] {
            out.append(L("- {f} à la racine du jeu : {r} (ne pas le renommer ni le supprimer sans en tenir compte)", ["f": name, "r": role.isEmpty ? "?" : role]))
        }
        var line = L("- Crash logs : {a} actif(s), {k} archivé(s) par la purge", ["a": crashLogs.active, "k": crashLogs.archived])
        if !crashLogs.dir.isEmpty { line += " — " + L("Crash Logger écrit dans {d}", ["d": crashLogs.dir]) }
        if let l = crashLogs.last { line += " — " + L("dernier : {d} ({w})", ["d": l.0, "w": l.1.isEmpty ? "?" : l.1]) }
        out.append(line)
        return out.joined(separator: "\n")
    }
}
