// Recoupements entre sources, sans IA : chronologie du plantage, historique des crash logs, sauvegarde comparée
// aux plugins actuels, domaine des objets en cause. Traduction de src/insights.py.

import Foundation

public enum Insights {
    static let BASE_MASTERS = ["skyrim.esm", "update.esm", "dawnguard.esm", "hearthfires.esm", "dragonborn.esm"]
    public static let MAX_HISTORY = 12
    static let MAX_SAVE_AGE_DAYS = 7
    public static let ARCHIVE_DIR = "sKYCRASH-archive"

    static let CRASH_TIME_RE = Rx(#"^CRASH TIME:\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"#)
    static let CRASH_NAME_RE = Rx(#"crash-(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})"#, i: true)
    static let UPTIME_RE = Rx(#"Process Uptime:\s*(\d+):(\d{2}):(\d{2})"#)
    static let AT_RE = Rx(#"\bat 0x[0-9A-Fa-f]+\s+(.+)$"#)
    static let OBJ_TYPE_RE = Rx(#"\(([A-Za-z_][\w:]*)\*\)"#)
    static let PLUGIN_LINE_RE = Rx(#"^\s*\[[^\]]+\]\s+(.+?\.es[mpl])\s*$"#, i: true)
    static let DLL_LINE_RE = Rx(#"^\s+(\S.*?\.dll)\b"#, i: true)
    static let TS_RE = Rx(#"\[(?:(\d{4}-\d{2}-\d{2})[ T])?(\d{2}):(\d{2}):(\d{2})(?:[.,]\d+)?"#)
    static let WARN_RE = Rx(#"\[(?:w|e|warn|warning|err|error)\]"#, i: true)

    static let EVENTS: [(String, String, Rx)] = [
        ("save", N_("chargement d'une sauvegarde"), Rx(#"loading save|load(?:ing)? ?game|kPreLoadGame|kPostLoadGame|PostLoadGame|PreLoadGame"#, i: true)),
        ("newgame", N_("nouvelle partie"), Rx(#"kNewGame|\bnew game\b"#, i: true)),
        ("menu", N_("menu principal"), Rx(#"main ?menu"#, i: true)),
    ]
    static let DOMAINS: [(String, Rx, Rx)] = [
        ("audio", Rx(#"Sound|Music|Audio|Acoustic"#, i: true), Rx(#"sound|music|audio|occlusion|acoustic|ambien|bird|flock"#, i: true)),
        ("region", Rx(#"TESRegion|TESWeather|TESClimate|\bSky\b"#, i: true), Rx(#"region|weather|storm|climate|cloud|rain|snow|fog|environs"#, i: true)),
        ("anim", Rx(#"^hk|Havok|Behavior|Animation"#, i: true), Rx(#"anim|behavior|havok|pandora|nemesis|\boar\b|\bdar\b"#, i: true)),
    ]
    static let DOMAIN_LABELS = ["audio": N_("son et musique"), "region": N_("régions et météo"), "anim": N_("animations")]
    public static let CRASH_EVENT = N_("plantage")

    // MARK: crash logs

    public static func crashTime(_ path: String, _ lines: [String]) throws -> Wall? {
        for l in lines.prefix(5) {
            if let m = CRASH_TIME_RE.match(l.pyStrip) { return try Wall.parse(m.group(1)!) }
        }
        if let m = CRASH_NAME_RE.search(PyFS.basename(path)) {
            let n = m.groups.map { Int($0!)! }
            return try Wall(n[0], n[1], n[2], n[3], n[4], n[5])
        }
        return PyFS.mtime(path).map { Wall(timestamp: $0) }
    }

    static func section(_ lines: [String], _ title: String) -> [String] {
        var out: [String] = [], inside = false
        for l in lines {
            let st = l.pyStrip
            if !l.firstIsSpace && st.hasSuffix(":") && st.uppercased() == st {
                if inside { break }
                inside = st == title
                continue
            }
            if inside { out.append(l) }
        }
        return out
    }

    public static func summarizeCrash(_ path: String, _ lines: [String]) throws -> CrashSummary {
        var whereAt = ""
        for l in lines.prefix(40) where l.lowercased().contains("unhandled") {
            let st = l.pyStrip
            let w = AT_RE.search(st)?.group(1) ?? st
            whereAt = (w.components(separatedBy: "\t").first ?? w).pyStrip
            break
        }
        let up = lines.prefix(80).lazy.compactMap { UPTIME_RE.search($0) }.first
        var objs: [String] = []
        for l in section(lines, "POSSIBLE RELEVANT OBJECTS:") { objs += OBJ_TYPE_RE.findall(l) }
        let skse = Set(section(lines, "SKSE PLUGINS:").compactMap { DLL_LINE_RE.match($0)?.group(1) })
        let plugins = section(lines, "PLUGINS:").compactMap { PLUGIN_LINE_RE.match($0)?.group(1) }
        return CrashSummary(
            path: path, time: try crashTime(path, lines), where: whereAt,
            uptime: up.map { Int($0.group(1)!)! * 3600 + Int($0.group(2)!)! * 60 + Int($0.group(3)!)! },
            objects: uniqueKeepingOrder(objs), skse: skse, plugins: plugins)
    }

    static func crashHistory(_ folders: [String]) throws -> [CrashSummary] {
        var paths = Set<String>()
        for d in folders {
            paths.formUnion(PyFS.glob(PyFS.join(d, "crash-*.log")))
            paths.formUnion(PyFS.glob(PyFS.join(d, ARCHIVE_DIR, "crash-*.log")))
        }
        var items: [(Double, String)] = []
        for p in paths { if let m = PyFS.mtime(p) { items.append((m, p)) } }
        items.sort { $0.0 != $1.0 ? $0.0 > $1.0 : pyLess($1.1, $0.1) }
        return try items.prefix(MAX_HISTORY).map { try summarizeCrash($0.1, Audit.readLines($0.1)) }
    }

    // MARK: chronologie

    static func events(_ entries: [Audit.Entry], _ crashAt: Wall, _ windowS: Int) -> [TimelineEntry] {
        let start = crashAt.adding(-(windowS + 5))
        var best = ODict<TimelineEntry>()
        for e in entries where e.kind != "crash" {
            for l in e.lines {
                guard let ev = EVENTS.first(where: { $0.2.test(l) }) else { continue }
                guard let m = TS_RE.search(l) else { continue }
                let day = m.group(1) ?? crashAt.format("%Y-%m-%d")
                guard let at = try? Wall.parse("\(day) \(m.group(2)!):\(m.group(3)!):\(m.group(4)!)") else { continue }
                if start <= at && at <= crashAt.adding(1) {
                    if best[ev.0] == nil || at > best[ev.0]!.at {
                        best[ev.0] = TimelineEntry(at: at, label: ev.1, src: PyFS.basename(e.path))
                    }
                }
            }
        }
        return best.values.sorted {
            if $0.at != $1.at { return $0.at < $1.at }
            if $0.label != $1.label { return pyLess($0.label, $1.label) }
            return pyLess($0.src, $1.src)
        }
    }

    // MARK: plugins actifs

    /// (plugins actifs et installés, fichiers de Data en minuscules, chemin du plugins.txt)
    public static func activePlugins(_ gameDir: String) -> ([String], Set<String>, String?) {
        let dataDir = PyFS.join(gameDir, "Data")
        guard let names = PyFS.listdir(dataDir) else { return ([], [], nil) }
        let data = Set(names.map { $0.lowercased() })
        var implicit = BASE_MASTERS.filter { data.contains($0) }
        if let t = PyFS.readText(PyFS.join(gameDir, "Skyrim.ccc")) {
            implicit += t.pyFileLines.map { $0.pyStrip }.filter { !$0.isEmpty && data.contains($0.lowercased()) }
        }
        let ptxt = Compat.findPluginsTxt(gameDir)
        var listed: [String] = []
        if let ptxt, let t = PyFS.readText(ptxt) {
            for l in t.pyFileLines where l.hasPrefix("*") {
                let name = String(l.pyStrip.unicodeScalars.dropFirst())
                if data.contains(name.lowercased()) { listed.append(name) }
            }
        }
        var seen = Set<String>(), out: [String] = []
        for p in implicit + listed where seen.insert(p.lowercased()).inserted { out.append(p) }
        return (out, data, ptxt)
    }

    /// Dossiers « My Games/Skyrim Special Edition » déduits des dossiers de logs (…/SKSE, …/Logs/Script).
    public static func docsDirs(_ folders: [String]) -> [String] {
        var out: [String] = []
        for d in folders {
            var cur = PyFS.normpath(d)
            for _ in 0..<3 {
                if PyFS.isDir(PyFS.join(cur, "Saves")) {
                    if !out.contains(cur) { out.append(cur) }
                    break
                }
                cur = PyFS.dirname(cur)
            }
        }
        return out
    }

    static func warnCount(_ logDir: String, _ stem: String) -> Int {
        guard let t = PyFS.readText(PyFS.join(logDir, stem + ".log")) else { return 0 }
        return t.pyFileLines.filter { WARN_RE.test($0) }.count
    }

    static func fmt(_ dt: Wall?) -> String { dt.map { $0.format("%d/%m %H:%M:%S") } ?? "?" }

    // MARK: analyse

    static func analyse(_ report: AuditReport, _ scores: Scores, _ entries: [Audit.Entry], _ gameDir: String) throws {
        let folders = pySorted(Array(Set(entries.map { PyFS.dirname($0.path) })))
        let history = try crashHistory(folders)
        report.extras.history = history
        let latest: CrashSummary? = (history.first.map { !$0.path.components(separatedBy: "/").contains(ARCHIVE_DIR) } ?? false) ? history[0] : nil

        // 1. chronologie du dernier plantage
        if let latest, let ltime = latest.time {
            let evs = events(entries, ltime, latest.uptime == nil || latest.uptime == 0 ? 600 : latest.uptime!)
            report.extras.timeline = evs + [TimelineEntry(at: ltime, label: CRASH_EVENT, src: PyFS.basename(latest.path))]
            if let saveEv = evs.last(where: { $0.label == EVENTS[0].1 }) {
                let gap = ltime.secs - saveEv.at.secs
                report.findings.append(Finding(
                    SEV_WARN, "chronologie", L("Plantage {s} s après le chargement d'une sauvegarde", ["s": gap]),
                    L("Chargement repéré à {t} dans {src} ; plantage à {c}.", ["t": fmt(saveEv.at), "src": saveEv.src, "c": fmt(ltime)]),
                    L("chronologie"), [],
                    L("Tester une partie neuve depuis le menu principal (console : coc <lieu>) : si elle tient, la sauvegarde est en cause (plugins ajoutés ou retirés depuis).")))
            } else if let up = latest.uptime, up < 60 {
                report.findings.append(Finding(
                    SEV_WARN, "chronologie", L("Plantage {s} s après le lancement du jeu", ["s": up]),
                    L("Avant ou pendant le menu principal : chargement des plugins et des données."),
                    L("chronologie"), [], L("Vérifier les masters manquants et les plugins SKSE récents.")))
            }
        }

        // 2. historique
        if !history.isEmpty {
            let lines = history.filter { $0.time != nil }.map { "\(fmt($0.time)) — \($0.where.isEmpty ? "?" : $0.where)" }
            let same = history.filter { c in !c.where.isEmpty && latest != nil && c.where == latest!.where }.count
            report.findings.append(Finding(
                SEV_INFO, "historique", L("{n} crash log(s) dans l'historique", ["n": history.count]),
                L("Même point de plantage que le dernier : {k} fois.", ["k": same]), L("historique"), Array(lines.prefix(6))))
            let prev = history.dropFirst().first { !$0.skse.isEmpty }
            if let latest, !latest.skse.isEmpty, let prev {
                let added = pySorted(Array(latest.skse.subtracting(prev.skse)))
                let removed = pySorted(Array(prev.skse.subtracting(latest.skse)))
                if !added.isEmpty || !removed.isEmpty {
                    var detail: [String] = []
                    if !added.isEmpty { detail.append(L("Ajoutées : {l}", ["l": added.prefix(12).joined(separator: ", ")])) }
                    if !removed.isEmpty { detail.append(L("Retirées : {l}", ["l": removed.prefix(12).joined(separator: ", ")])) }
                    report.findings.append(Finding(
                        added.isEmpty ? SEV_INFO : SEV_WARN, "historique",
                        L("DLL SKSE modifiées depuis le plantage du {d}", ["d": fmt(prev.time)]),
                        detail.joined(separator: " — "), L("historique"), [],
                        L("Une DLL apparue juste avant un nouveau type de plantage est un suspect prioritaire.")))
                    for d in added { scores.bump(d, 2, L("DLL SKSE apparue depuis le plantage précédent")) }
                }
                if let pt = prev.time { report.extras.skseDiff = SkseDiff(since: pt, added: added, removed: removed) }
            }
        }

        // 3. sauvegarde comparée aux plugins actuels
        var addedSinceSave: [String] = []
        let (act, _, ptxt) = gameDir.isEmpty ? ([], Set<String>(), nil) : activePlugins(gameDir)
        if !act.isEmpty {
            let before: Double? = latest?.time.map { $0.timestamp }
            var save: SaveInfo?
            outer: for docs in docsDirs(folders) {
                for p in SaveGame.latestSaves(PyFS.join(docs, "Saves"), before: before, limit: 1) {
                    if let s = try? SaveGame.readSave(p) { save = s; break outer }
                    break
                }
            }
            if let s = save, let before, before != 0, before - s.savedAt > Double(MAX_SAVE_AGE_DAYS * 86400) { save = nil }
            if let save {
                let activeLow = Set(act.map { $0.lowercased() })
                let inSave = Set(save.allPlugins.map { $0.lowercased() })
                let missing = save.allPlugins.filter { !activeLow.contains($0.lowercased()) }
                addedSinceSave = act.filter { !inSave.contains($0.lowercased()) }
                let savedAt = Wall(timestamp: save.savedAt)
                report.extras.save = SaveExtra(path: save.path, player: save.player, location: save.location, savedAt: savedAt,
                                               count: save.allPlugins.count, missing: missing, added: addedSinceSave, pluginsTxt: ptxt)
                let name = PyFS.splitext(PyFS.basename(save.path)).0
                let when = savedAt.format("%d/%m %H:%M")
                if !missing.isEmpty {
                    report.findings.append(Finding(
                        SEV_WARN, "sauvegarde", L("{n} plugin(s) de la sauvegarde « {s} » ne sont plus actifs", ["n": missing.count, "s": name]),
                        L("Sauvegarde du {d} ({loc}).", ["d": when, "loc": save.location]), L("sauvegarde"), Array(missing.prefix(8)),
                        L("Réactiver ces plugins pour charger la partie, ou nettoyer la sauvegarde (ReSaver) après les avoir retirés proprement.")))
                }
                if !addedSinceSave.isEmpty {
                    report.findings.append(Finding(
                        addedSinceSave.count >= 10 ? SEV_WARN : SEV_INFO, "sauvegarde",
                        L("{n} plugin(s) ajoutés depuis la sauvegarde « {s} »", ["n": addedSinceSave.count, "s": name]),
                        L("Sauvegarde du {d} ({loc}), {k} plugins à l'époque.", ["d": when, "loc": save.location, "k": save.allPlugins.count]),
                        L("sauvegarde"), Array(addedSinceSave.prefix(8)),
                        L("Ajouter des plugins en cours de partie (régions, météo, sons, PNJ) peut faire planter au chargement. Tester une partie neuve (coc) ; si elle tient, retirer les ajouts récents.")))
                }
            }
        }

        // 4. domaine des objets en cause
        if let latest, !latest.objects.isEmpty {
            let doms = DOMAINS.filter { d in latest.objects.contains { d.1.test($0) } }
            if !doms.isEmpty {
                let logDir = PyFS.dirname(latest.path)
                var dlls: [(String, Int)] = [], plugs: [String] = []
                for d in doms {
                    for dll in pySorted(Array(latest.skse)) where d.2.test(dll) && !dlls.contains(where: { $0.0 == dll }) {
                        dlls.append((dll, warnCount(logDir, PyFS.splitext(dll).0)))
                    }
                    let known = plugs
                    plugs += addedSinceSave.filter { d.2.test($0) && !known.contains($0) }
                }
                let labels = doms.map { L(DOMAIN_LABELS[$0.0]!) }.joined(separator: ", ")
                var parts: [String] = []
                if !dlls.isEmpty {
                    parts.append(L("DLL chargées : {l}", ["l": dlls.prefix(10).map { $0.0 + ($0.1 != 0 ? L(" ({n} avertissements)", ["n": $0.1]) : "") }.joined(separator: ", ")]))
                }
                if !plugs.isEmpty { parts.append(L("Plugins ajoutés depuis la sauvegarde : {l}", ["l": plugs.prefix(10).joined(separator: ", ")])) }
                report.extras.domains = DomainsExtra(labels: labels, dlls: dlls, plugins: plugs)
                report.findings.append(Finding(
                    SEV_WARN, "domaine", L("Objets en cause : {d}", ["d": labels]),
                    parts.isEmpty ? L("Aucune DLL ni plugin récent lié à ce domaine.") : parts.joined(separator: " — "), L("recoupement"),
                    [latest.objects.prefix(6).joined(separator: ", ")],
                    L("Tester en désactivant un par un ces DLL et plugins, en commençant par les plus récents.")))
                for (d, w) in dlls { scores.bump(d, w != 0 ? 3 : 2, L("lié aux objets en cause ({d})", ["d": labels])) }
                for p in plugs { scores.bump(p, 2, L("ajouté depuis la sauvegarde, lié aux objets en cause")) }
            }
        }
    }
}
