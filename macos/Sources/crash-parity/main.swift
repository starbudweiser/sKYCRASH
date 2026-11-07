// Sort en JSON le résultat complet d'une analyse (audit, recoupements, inventaire, dossier Markdown, ligne d'export,
// filet de sécurité, mise en forme IA, requêtes IA) pour le comparer à la version Python (scripts de parité).
//
// Usage :
//   crash-parity analyze [--game-dir DIR] [--lang fr|en|it|es] FICHIER_LOG...
//   crash-parity save FICHIER.ess
//   crash-parity answers FICHIER_REPONSES [--lang ...]        (mise en forme, anonymisation)
//   crash-parity parse KIND FICHIER                             (analyseur de la veille sur une réponse enregistrée)
// Aucun appel réseau, rien n'est écrit (les clés ne sont jamais lues : SKYRIM_CA_NO_KEYCHAIN=1 imposé).

import CrashCore
import Foundation

setenv("SKYRIM_CA_NO_KEYCHAIN", "1", 1)

func arr(_ a: [String]) -> J { .arr(a.map { .str($0) }) }
func opt(_ s: String?) -> J { s.map { .str($0) } ?? .null }
func wall(_ w: Wall?) -> J { w.map { .str($0.format("%Y-%m-%d %H:%M:%S")) } ?? .null }

func inventoryJSON(_ f: Inventory?) -> J {
    guard let f else { return .obj([]) }
    var o: [(String, J)] = [("game_dir", .str(f.gameDir))]
    if !f.gameDir.isEmpty {
        o.append(("game_version", opt(f.gameVersion)))
        o.append(("tools", .obj((f.tools ?? []).map { ($0.0, J.bool($0.1)) })))
        o.append(("skse_installed", .bool(f.skseInstalled ?? false)))
        if let a = f.addressLibrary { o.append(("address_library", .bool(a))) }
        o.append(("enb", .bool(f.enb ?? false)))
        o.append(("reshade", .bool(f.reshade ?? false)))
        o.append(("proxies", .obj((f.proxies ?? []).map { ($0.0, J.str($0.1)) })))
        if let cc = f.cc { o.append(("cc", .obj([("listed", .int(cc.listed)), ("present", .int(cc.present))]))) }
        if let p = f.plugins {
            o.append(("plugins", .obj([("active", .int(p.active)), ("full", .int(p.full)), ("light", .int(p.light)),
                                       ("limit_ok", .bool(p.limitOk)), ("plugins_txt", opt(p.pluginsTxt))])))
        }
        if let b = f.bottle { o.append(("bottle", .str(b))) }
    }
    if let v = f.skseVersion { o.append(("skse_version", .str(v))) }
    let cl = f.crashLogs
    o.append(("crash_logs", .obj([("active", .int(cl.active)), ("archived", .int(cl.archived)), ("dir", .str(cl.dir)),
                                  ("last", cl.last.map { .arr([.str($0.0), .str($0.1)]) } ?? .null)])))
    if let v = f.crashloggerVersion { o.append(("crashlogger_version", .str(v))) }
    return .obj(o)
}

func historyJSON(_ h: [CrashSummary]) -> J {
    .arr(h.map { c in
        .obj([("path", .str(c.path)), ("time", wall(c.time)), ("where", .str(c.where)), ("uptime", c.uptime.map { .int($0) } ?? .null),
              ("objects", arr(c.objects)), ("skse", arr(c.skse.sorted())), ("plugins", arr(c.plugins))])
    })
}

func reportJSON(_ r: AuditReport) -> J {
    let ex = r.extras
    var extras: [(String, J)] = []
    if let h = ex.history { extras.append(("history", historyJSON(h))) }
    if let t = ex.timeline { extras.append(("timeline", .arr(t.map { .arr([wall($0.at), .str($0.label), .str($0.src)]) }))) }
    if let d = ex.skseDiff { extras.append(("skse_diff", .obj([("since", wall(d.since)), ("added", arr(d.added)), ("removed", arr(d.removed))]))) }
    if let s = ex.save {
        extras.append(("save", .obj([("path", .str(s.path)), ("player", .str(s.player)), ("location", .str(s.location)), ("saved_at", wall(s.savedAt)),
                                     ("count", .int(s.count)), ("missing", arr(s.missing)), ("added", arr(s.added)), ("plugins_txt", opt(s.pluginsTxt))])))
    }
    if let d = ex.domains {
        extras.append(("domains", .obj([("labels", .str(d.labels)), ("dlls", .arr(d.dlls.map { .arr([.str($0.0), .int($0.1)]) })), ("plugins", arr(d.plugins))])))
    }
    extras.append(("inventory", inventoryJSON(ex.inventory)))
    if let g = ex.gameDirFound { extras.append(("game_dir_found", .str(g))) }
    var si: J = .null
    if let s = r.skseInfo {
        si = .obj([("checked", arr(s.checked)), ("loaded", .obj(s.loaded.keys.sorted().map { ($0, J.arr([.str(s.loaded[$0]!.0), .int(s.loaded[$0]!.1)])) })),
                   ("plugin_dir", opt(s.pluginDir))])
    }
    return .obj([
        ("verdict", .str(r.verdict)),
        ("suspects", .arr(r.suspects.map { .arr([.str($0.name), .int($0.score), arr($0.reasons)]) })),
        ("findings", .arr(r.findings.map { f in
            .obj([("severity", .int(f.severity)), ("category", .str(f.category)), ("title", .str(f.title)), ("detail", .str(f.detail)),
                  ("source", .str(f.source)), ("evidence", arr(f.evidence)), ("suggestion", .str(f.suggestion))])
        })),
        ("analysed", arr(r.analysed)),
        ("excerpts", .obj(r.excerpts.items.map { ($0.0, J.str($0.1)) })),
        ("game_dir", .str(r.gameDir)), ("skse_runtime", .str(r.skseRuntime)), ("skse_info", si),
        ("extras", .obj(extras)),
    ])
}

func fixedNow() -> Date { Date(timeIntervalSince1970: (try! Wall(2026, 11, 7, 12, 0, 0)).timestamp) }

func analyze(_ files: [String], gameDir: String, answers: [String]) -> J {
    let report = Audit.auditPaths(files, gameDir: gameDir)
    // lignes d'export : un événement par crash analysé (sans écrire)
    var crashes: [(String, [String])] = [], others: [String] = []
    for p in report.analysed {
        let lines = Audit.readLines(p)
        if Audit.classifyLog(p, lines) == "crash" { crashes.append((p, lines)) } else { others.append(p) }
    }
    var events: [J] = []
    for (p, lines) in crashes {
        let rep = crashes.count == 1 ? report : Audit.auditPaths([p] + others, gameDir: gameDir)
        events.append(.str(ExportEvents.buildEvent(p, lines, rep).line))
    }
    let guards: [J] = answers.map { a in
        let (text, removed) = Guard.apply(a, report.extras.inventory)
        return .obj([("text", .str(text)), ("removed", arr(removed))])
    }
    // requêtes IA construites sans envoi
    var chat: [J] = []
    let hist = [ChatMessage(role: "user", content: "Quelle est la cause ? /Users/bob/x.log bob@example.com")]
    for provider in ["gemini", "ollama"] {
        var s = Dictionary(uniqueKeysWithValues: AIClient.DEFAULT_SETTINGS)
        s["provider"] = provider; s["web_search"] = provider == "gemini" ? "1" : "0"; s["language"] = "en"
        if let p = try? AIClient.prepare(s, auditContext: report.toContext(), history: hist) {
            let payload = provider == "gemini" ? AIClient.geminiPayload(s, p.system, p.messages) : AIClient.ollamaPayload(s, p.system, p.messages)
            chat.append(.obj([("provider", .str(provider)), ("system", .str(p.system)), ("payload", payload)]))
        }
    }
    var jev: J = .null
    if let inv = report.extras.inventory {
        let (state, questions) = Guard.jevRequest(["Installer Crash Logger SSE.", "Réduire les textures."], inv)
        jev = JevClient.requestBody(state: state, questions: questions)
    }
    return .obj([
        ("report", reportJSON(report)),
        ("markdown", .str(report.toMarkdown())),
        ("context", .str(report.toContext())),
        ("diagnostic", .str(Diagnostic.build(report, anonymize: true, appName: "sKYCRASH", now: fixedNow()))),
        ("diagnostic_raw", .str(Diagnostic.build(report, anonymize: false, appName: "sKYCRASH", now: fixedNow()))),
        ("events", .arr(events)),
        ("guard", .arr(guards)),
        ("chat", .arr(chat)),
        ("jev", jev),
    ])
}

func answersJSON(_ path: String) -> J {
    let text = try! String(contentsOfFile: path, encoding: .utf8)
    let answers = text.components(separatedBy: "\n=====\n").map { $0.hasSuffix("\n=====") ? String($0.dropLast(6)) : $0 }
    return .arr(answers.map { a in
        .obj([("html", .str(AIFormat.renderHTML(a))), ("anonymized", .str(AIClient.anonymize(a))), ("scrub", .str(ExportEvents.scrub(a)))])
    })
}

func parseJSON(_ kind: String, _ path: String) -> J {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    do {
        let items: [String]
        switch kind {
        case "github_releases": items = try KnowledgeUpdater.parseGithubReleases(data)
        case "github_issues": items = try KnowledgeUpdater.parseGithubIssues(data)
        case "steam_news": items = try KnowledgeUpdater.parseSteamNews(data)
        case "reddit_rss": items = try KnowledgeUpdater.parseRedditRSS(data)
        case "crossover_changelog": items = try KnowledgeUpdater.parseCrossoverChangelog(data)
        case "skse_site": items = try KnowledgeUpdater.parseSkseSite(data)
        default: return .obj([("error", .str("kind inconnu"))])
        }
        let src = KnowledgeUpdater.SOURCES.first { $0.kind == kind }!
        return .obj([("items", arr(items)), ("note", .str(KnowledgeUpdater.renderNote(src, items, "2026-11-07")))])
    } catch let e as KnowledgeUpdater.Failure { return .obj([("error", .str(e.message))]) }
    catch { return .obj([("error", .str("\(error)"))]) }
}

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { FileHandle.standardError.write(Data("usage: crash-parity analyze|save|answers|parse …\n".utf8)); exit(2) }
args.removeFirst()
var gameDir = ""
var lang = "fr"
var rest: [String] = []
var i = 0
while i < args.count {
    if args[i] == "--game-dir", i + 1 < args.count { gameDir = args[i + 1]; i += 2 }
    else if args[i] == "--lang", i + 1 < args.count { lang = args[i + 1]; i += 2 }
    else { rest.append(args[i]); i += 1 }
}
I18n.setLang(lang)
let out: J
switch cmd {
case "analyze":
    let answersFile = ProcessInfo.processInfo.environment["PARITY_ANSWERS"]
    let answers = answersFile.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?.components(separatedBy: "\n=====\n") ?? []
    out = analyze(rest, gameDir: gameDir, answers: answers)
case "save":
    do {
        let s = try SaveGame.readSave(rest[0])
        out = .obj([("player", .str(s.player)), ("level", .int(s.level)), ("location", .str(s.location)),
                    ("saved_at", .str(Wall(timestamp: s.savedAt).format("%Y-%m-%d %H:%M:%S"))), ("plugins", arr(s.plugins)), ("light", arr(s.light))])
    } catch { out = .obj([("error", .str("\(error)"))]) }
case "files":
    let cfg = Config.withSkseDir(Config.loadConfig())
    let folders = cfg.flatMap { $0.1 }
    let logs = Config.listLogs(folders)
    out = .obj([("folders", arr(folders)), ("audit_files", arr(Config.gatherAuditFiles(folders))),
                ("logs", .arr(logs.map { [$0.name, $0.folder, $0.path] }.sorted { $0.lexicographicallyPrecedes($1) }.map { arr($0) })),
                ("errors", .obj(logs.map { ($0.path, opt(Config.scanForErrors($0.path))) }))])
case "answers": out = answersJSON(rest[0])
case "parse": out = parseJSON(rest[0], rest[1])
default: out = .obj([("error", .str("commande inconnue"))])
}
print(out.dump(compact: true))
