// Dossier de diagnostic : un seul fichier Markdown avec tout le contexte d'un plantage (src/diagnostic.py).

import Foundation

public enum Diagnostic {
    static let CRASH_SECTIONS = ["POSSIBLE RELEVANT OBJECTS:", "CALL STACK ([P]robable / [S]tack scan):", "PROBABLE CALL STACK:", "REGISTERS:"]
    static let MAX_SECTION_LINES = 60

    static func fmt(_ dt: Wall?) -> String { dt.map { $0.format("%d/%m/%Y %H:%M:%S") } ?? "?" }

    static func crashExcerpt(_ path: String) -> [String] {
        let lines = Audit.readLines(path)
        var out = ["```text"] + lines.prefix(12).map { $0.pyRStrip }
        for title in CRASH_SECTIONS {
            guard let start = lines.firstIndex(where: { $0.pyStrip == title }) else { continue }
            out.append(""); out.append(title)
            for l in lines[min(start + 1, lines.count)..<min(start + 1 + MAX_SECTION_LINES, lines.count)] {
                if !l.firstIsSpace && Audit.SECTION_RE.test(l.pyStrip) { break }
                out.append(l.pyRStrip)
            }
        }
        out.append("```")
        return out
    }

    static func recentDlls(_ gameDir: String, limit: Int = 25) -> [(Double, String, Int)] {
        let plug = PyFS.join(gameDir, "Data", "SKSE", "Plugins")
        guard let names = PyFS.listdir(plug) else { return [] }
        var items: [(Double, String, Int)] = []
        for n in names where n.lowercased().hasSuffix(".dll") {
            let p = PyFS.join(plug, n)
            guard let m = PyFS.mtime(p), let s = PyFS.size(p) else { return [] }
            items.append((m, n, s))
        }
        items.sort { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            if a.1 != b.1 { return pyLess(b.1, a.1) }
            return a.2 > b.2
        }
        return Array(items.prefix(limit))
    }

    static func logWarnings(_ folder: String, limit: Int = 20) -> [(Int, String, [String])] {
        guard let names = PyFS.listdir(folder) else { return [] }
        var out: [(Int, String, [String])] = []
        for n in names where n.lowercased().hasSuffix(".log") && !n.lowercased().hasPrefix("crash-") {
            guard let t = PyFS.readText(PyFS.join(folder, n)) else { continue }
            let lines = t.pyFileLines.filter { Insights.WARN_RE.test($0) }.map { $0.pyRStrip }
            if !lines.isEmpty { out.append((lines.count, n, Array(lines.prefix(2)))) }
        }
        out.sort { a, b in
            if a.0 != b.0 { return a.0 > b.0 }
            return pyLess(b.1, a.1)
        }
        return Array(out.prefix(limit))
    }

    public static func build(_ report: AuditReport, anonymize: Bool = true, appName: String = "sKYCRASH", now: Date = Date()) -> String {
        let ex = report.extras
        let history = ex.history ?? []
        let latest = history.first
        var md = [L("# Dossier de diagnostic {app}", ["app": appName]), "",
                  L("Généré le {d}.", ["d": fmt(Wall(timestamp: now.timeIntervalSince1970))])]
        if !report.gameDir.isEmpty { md.append(L("Installation : `{dir}`", ["dir": report.gameDir])) }
        let audit = report.toMarkdown().replacingOccurrences(of: "\n## ", with: "\n### ")
        let facts = ex.inventory?.toContext() ?? ""
        if !facts.isEmpty { md += ["", facts] }
        md += ["", audit.hasPrefix("# ") ? "#" + audit : audit, ""]

        md += [L("## Chronologie du dernier plantage"), ""]
        if let tl = ex.timeline, !tl.isEmpty {
            md += tl.map { "- \(fmt($0.at)) — \(L($0.label)) (\($0.src))" }
        } else { md.append(L("Aucun événement horodaté trouvé dans les journaux.")) }
        md.append("")

        md += [L("## Historique des plantages"), ""]
        if !history.isEmpty {
            md += [L("| Date | Point de plantage | Durée de jeu | Objets en cause |"), "|---|---|---|---|"]
            for c in history {
                let up = c.uptime.map { "\($0 / 60) min " + String(format: "%02d", $0 % 60) + " s" } ?? "?"
                md.append("| \(fmt(c.time)) | `\(c.where.isEmpty ? "?" : c.where)` | \(up) | \(c.objects.prefix(4).joined(separator: ", ")) |")
            }
            if let diff = ex.skseDiff {
                md += ["", L("DLL SKSE depuis le plantage du {d} : ajoutées {a} ; retirées {r}.",
                             ["d": fmt(diff.since), "a": diff.added.isEmpty ? "-" : diff.added.joined(separator: ", "),
                              "r": diff.removed.isEmpty ? "-" : diff.removed.joined(separator: ", ")])]
            }
        } else { md.append(L("Aucun crash log Crash Logger SSE trouvé.")) }
        md.append("")

        md += [L("## Sauvegarde et plugins actuels"), ""]
        if let save = ex.save {
            md += [L("Sauvegarde : `{name}` — {player}, {loc}, enregistrée le {d}, {n} plugins.",
                     ["name": PyFS.basename(save.path), "player": save.player, "loc": save.location, "d": fmt(save.savedAt), "n": save.count]),
                   L("Liste des plugins actuels : `{p}`", ["p": save.pluginsTxt ?? "?"]), "",
                   L("Plugins de la sauvegarde qui ne sont plus actifs ({n}) :", ["n": save.missing.count])]
            md += save.missing.isEmpty ? ["- " + L("aucun")] : save.missing.map { "- \($0)" }
            md += ["", L("Plugins ajoutés depuis la sauvegarde ({n}) :", ["n": save.added.count])]
            md += save.added.isEmpty ? ["- " + L("aucun")] : save.added.map { "- \($0)" }
        } else { md.append(L("Sauvegarde ou liste des plugins introuvable (dossier du jeu inconnu ?).")) }
        md.append("")

        if !report.gameDir.isEmpty {
            md += [L("## DLL SKSE les plus récentes"), ""]
            md += recentDlls(report.gameDir).map { "- \(Wall(timestamp: $0.0).format("%d/%m/%Y %H:%M")) — \($0.1) (\($0.2 / 1024) Ko)" }
            md.append("")
        }

        if let latest {
            let folder = PyFS.dirname(latest.path)
            md += [L("## Avertissements des journaux de plugins"), ""]
            let warns = logWarnings(folder)
            for (n, name, sample) in warns {
                md.append(L("- **{name}** : {n} ligne(s)", ["name": name, "n": n]))
                md += sample.map { "  - `\($0.pyPrefix(200))`" }
            }
            if warns.isEmpty { md.append(L("Aucun avertissement repéré.")) }
            md += ["", L("## Extrait du dernier crash log ({name})", ["name": PyFS.basename(latest.path)]), ""]
            md += crashExcerpt(latest.path)
        }

        let text = md.joined(separator: "\n") + "\n"
        return anonymize ? AIClient.anonymize(text) : text
    }

    public static func defaultFilename(now: Date = Date()) -> String {
        Wall(timestamp: now.timeIntervalSince1970).format("sKYCRASH-diagnostic-%Y-%m-%d-%H%M.md")
    }
}
