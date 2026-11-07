// État et actions de l'appli : analyse des logs, audit, export du diagnostic, purge, chat IA, surveillance, veille.
// Traduction de la classe CrashAnalyzer de la version Python ; le travail lourd (CrashCore) tourne hors du thread principal.

import AppKit
import CrashCore
import Observation
import SwiftUI

let APP_NAME = "sKYCRASH"
let LOGO_ORANGE = Color(red: 1, green: 0x7a / 255.0, blue: 0)  // « s » dans l'orange de l'iris du logo

struct LogRow: Identifiable, Equatable {
    var id: String { path }
    let name: String, folder: String, path: String, game: String
    let when: String
    let isError: Bool
}

struct ChatEntry: Identifiable {
    enum Who { case user, assistant, error }
    let id = UUID()
    let who: Who
    let text: String
}

/// Résultats passés d'un thread à l'autre (les rapports sont des objets, jamais modifiés après l'audit).
struct Box<T>: @unchecked Sendable { let value: T }

@MainActor @Observable
final class AppModel {
    // Réglages et dossiers
    var settings = Config.loadSettings()
    var gameFolders = Config.loadConfig()

    // Zone de rapport (en haut à gauche) et liste des logs
    var reportText = AttributedString()
    var logRows: [LogRow] = []
    var auditReport: AuditReport?

    // Chat IA
    var chat: [ChatEntry] = []
    var chatInput = ""
    var thinkingStep: Int?
    private var chatHistory: [ChatMessage] = []

    // Activité
    var auditBusy = false
    var exportBusy = false
    var chatBusy = false
    var kbStatus = ""
    var kbTooltip = ""

    // Fenêtres de dialogue (feuilles)
    var showSettings = false
    var viewingLog: (path: String, name: String)?
    var tick = 0  // force le redessin des textes statiques après un changement de langue

    weak var window: NSWindow?
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var watchTask: Task<Void, Never>?
    private var knownCrashes = Set<String>()
    private var knownLogs = Set<String>()
    private var declinedGameDir: String?
    private var thinkTimer: Timer?
    private var kbTimer: Timer?
    private var analyzeGeneration = 0
    private let preview = Config.folderOverride != nil

    // MARK: Démarrage

    func start() {
        analyzeLogs()
        knownCrashes = crashNames()
        knownLogs = Set(Config.listLogs(allFolders()).map(\.path))
        setupWatch()
        showKbStatus()
        kbTimer = Timer.scheduledTimer(withTimeInterval: KnowledgeUpdater.PERIODIC_INTERVAL_H * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maybeUpdateKnowledge(KnowledgeUpdater.PERIODIC_INTERVAL_H) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.maybeUpdateKnowledge(KnowledgeUpdater.LAUNCH_INTERVAL_H) }
    }

    func allFolders() -> [String] { Config.withSkseDir(gameFolders).flatMap { $0.1 } }

    var gameDir: String { settings["game_dir"] ?? "" }
    var exportEnabled: Bool { (settings["export_events"] ?? "1") == "1" }

    // MARK: Veille (base de connaissances)

    func maybeUpdateKnowledge(_ intervalH: Double) {
        if (settings["auto_knowledge"] ?? "1") != "1" || preview { return }
        if !KnowledgeUpdater.due(intervalH: intervalH) { return }
        kbStatus = L("Base de connaissances : mise à jour…")
        Task.detached {
            let rep = KnowledgeUpdater.updateAll()
            await MainActor.run { self.showKbStatus(rep) }
        }
    }

    func showKbStatus(_ rep: KnowledgeUpdater.Report? = nil) {
        kbTooltip = ""
        if (settings["auto_knowledge"] ?? "1") != "1" { kbStatus = L("Base de connaissances : veille désactivée"); return }
        let last = KnowledgeUpdater.status().lastRun
        let when = last.map { Wall(timestamp: $0).format("%d/%m %H:%M") } ?? L("jamais")
        var text = L("Base de connaissances : {n} sources, mise à jour {d}", ["n": KnowledgeUpdater.SOURCES.count, "d": when])
        if let rep, !rep.failed.isEmpty {
            text += " — " + L("{f} en échec", ["f": rep.failed.count])
            kbTooltip = rep.failed.items.map { "\($0.0) : \($0.1)" }.joined(separator: "\n")
        }
        kbStatus = text
    }

    // MARK: Texte coloré

    nonisolated static func run(_ s: String, _ color: Color, bold: Bool = false) -> AttributedString {
        var a = AttributedString(s)
        a.foregroundColor = color
        if bold { a.inlinePresentationIntent = .stronglyEmphasized }
        return a
    }

    // MARK: Analyse rapide des logs

    func analyzeLogs() {
        analyzeGeneration += 1
        let gen = analyzeGeneration
        let games = Config.withSkseDir(gameFolders)
        Task.detached(priority: .userInitiated) {
            var text = AttributedString()
            var results: [String: Bool] = [:]
            var anyFolder = false
            var all: [(name: String, folder: String, path: String, mtime: Double, game: String)] = []
            for (game, folders) in games {
                var gameErrors: [(String, String, String)] = []
                for f in Config.listLogs(folders) {
                    anyFolder = true
                    let err = Config.scanForErrors(f.path)
                    results[f.path] = err != nil
                    if let err { gameErrors.append((f.name, err, PyFS.basename(f.folder))) }
                    all.append((f.name, f.folder, f.path, f.mtime, game))
                }
                text += Self.run("● \(game)\n", Socle.C.warning, bold: true)
                if gameErrors.isEmpty {
                    text += Self.run("  ✅ " + L("Aucun problème détecté.") + "\n\n", Socle.C.success)
                } else {
                    for (name, msg, folder) in gameErrors {
                        text += Self.run("  • [\(folder)] \(name) : ", Socle.C.text)
                        text += Self.run("\(msg)\n", Socle.C.danger)
                    }
                    text += AttributedString("\n")
                }
            }
            if !anyFolder {
                text += Self.run(L("Aucun fichier .log trouvé. Configurez les dossiers dans Réglages… > Dossiers de logs.") + "\n", Socle.C.text)
            }
            let rows = all.stableSorted { $0.mtime > $1.mtime }.prefix(Config.MAX_CARDS).map { l in
                LogRow(name: l.name, folder: l.folder, path: l.path, game: l.game,
                       when: Wall(timestamp: l.mtime).format("%d/%m %H:%M"), isError: results[l.path] ?? false)
            }
            let box = Box(value: (text, Array(rows)))
            await MainActor.run {
                guard gen == self.analyzeGeneration else { return }
                self.reportText = box.value.0
                self.logRows = box.value.1
            }
        }
    }

    // MARK: Audit approfondi

    func runAudit() {
        let files = Config.gatherAuditFiles(allFolders())
        if files.isEmpty {
            reportText = Self.run(L("Aucun log à auditer. Configurez les dossiers dans Réglages… > Dossiers de logs."), Socle.C.text)
            return
        }
        auditBusy = true
        reportText = Self.run(L("Audit en cours…"), Socle.C.text)
        let game = gameDir, export = exportEnabled
        Task.detached(priority: .userInitiated) {
            let report = ExportEvents.auditAndExport(files, gameDir: game, enabled: export)
            let box = Box(value: report)
            await MainActor.run { self.auditDone(box.value) }
        }
    }

    private func auditDone(_ report: AuditReport) {
        auditBusy = false
        auditReport = report
        reportText = Self.renderAudit(report)
        offerGameDir(report)
    }

    static func renderAudit(_ r: AuditReport) -> AttributedString {
        var t = AttributedString()
        t += run(L("AUDIT — {verdict}", ["verdict": r.verdict]) + "\n", Socle.C.warning, bold: true)
        let install = r.gameDir.isEmpty
            ? L("Installation non localisée — indiquez le dossier du jeu dans Réglages… > Général pour activer les contrôles de version.")
            : L("Installation : {dir}", ["dir": r.gameDir])
        t += run("\(install)\n\n", Socle.C.textSubtle)
        if !r.suspects.isEmpty {
            t += run(L("Suspects classés") + "\n", Socle.C.text, bold: true)
            for (i, s) in r.suspects.enumerated() {
                t += run("  \(i + 1). \(s.name) ", i == 0 ? Socle.C.danger : Socle.C.text)
                t += run(L("(score {score}) ", ["score": s.score]) + (s.reasons.first ?? "") + "\n", Socle.C.textSubtle)
            }
            t += AttributedString("\n")
        }
        for f in r.findings.stableSorted(by: { $0.severity > $1.severity }) {
            let color = f.severity == SEV_CRIT ? Socle.C.danger : (f.severity == SEV_WARN ? Socle.C.warning : Socle.C.success)
            t += run("[\(sevLabel(f.severity))] ", color, bold: true)
            t += run("\(f.title) — \(f.source)\n", Socle.C.text)
            if !f.detail.isEmpty { t += run("    \(f.detail)\n", Socle.C.textMuted) }
            for e in f.evidence.prefix(2) { t += run("    > \(e.pyPrefix(200))\n", Socle.C.textSubtle) }
            if !f.suggestion.isEmpty { t += run("    " + L("Piste : {s}", ["s": f.suggestion]) + "\n", Socle.C.accentText) }
        }
        return t
    }

    /// Le dossier du jeu des réglages n'existe plus mais l'installation a été retrouvée : proposer de l'adopter.
    private func offerGameDir(_ report: AuditReport) {
        guard let found = report.extras.gameDirFound, !gameDir.isEmpty, found != declinedGameDir else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("Le dossier du jeu des réglages n'existe plus. Utiliser l'installation retrouvée ?")
        alert.informativeText = L("Ancien : {old}\nRetrouvé : {new}", ["old": gameDir, "new": found])
        alert.addButton(withTitle: L("Utiliser ce dossier"))
        alert.addButton(withTitle: L("Plus tard"))
        alert.window.title = L("Dossier du jeu")
        if alert.runModal() == .alertFirstButtonReturn {
            settings["game_dir"] = found
            Config.saveSettings(settings)
        } else { declinedGameDir = found }
    }

    // MARK: Export du diagnostic

    func exportDiagnostic() {
        let files = Config.gatherAuditFiles(allFolders())
        if files.isEmpty {
            info(L("Aucun log à exporter. Configurez les dossiers dans Réglages… > Dossiers de logs."))
            return
        }
        let panel = NSSavePanel()
        panel.title = L("Exporter le diagnostic")
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        let desktop = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        panel.directoryURL = PyFS.isDir(desktop.path) ? desktop : URL(fileURLWithPath: NSHomeDirectory())
        panel.nameFieldStringValue = Diagnostic.defaultFilename()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDiagnostic(to: url, files: files, reveal: true)
    }

    /// Écrit le dossier de diagnostic dans `url` (audit complet puis export mORTEX si activé).
    func exportDiagnostic(to url: URL, files: [String]? = nil, reveal: Bool = false) {
        let files = files ?? Config.gatherAuditFiles(allFolders())
        exportBusy = true
        let game = gameDir, anon = (settings["anonymize"] ?? "1") == "1", export = exportEnabled
        Task.detached(priority: .userInitiated) {
            let report = ExportEvents.auditAndExport(files, gameDir: game, enabled: export)
            let md = Diagnostic.build(report, anonymize: anon, appName: APP_NAME)
            do {
                try md.write(to: url, atomically: false, encoding: .utf8)
                let box = Box(value: report)
                await MainActor.run {
                    self.exportBusy = false
                    self.auditReport = box.value
                    self.reportText = Self.renderAudit(box.value)
                    self.offerGameDir(box.value)
                    if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }  // le fichier apparaît sélectionné dans le Finder
                }
            } catch {
                await MainActor.run {
                    self.exportBusy = false
                    self.warn(L("Export impossible : {msg}", ["msg": error.localizedDescription]))
                }
            }
        }
    }

    // MARK: Fichier unique, glisser-déposer

    func selectLogFile() {
        let panel = NSOpenPanel()
        panel.title = L("Ouvrir Log")
        panel.allowedContentTypes = [.init(filenameExtension: "log"), .init(filenameExtension: "txt")].compactMap { $0 }
        panel.directoryURL = URL(fileURLWithPath: PyFS.isDir(Config.docs) ? Config.docs : NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanFile(url.path)
    }

    func scanFile(_ path: String) {
        if !PyFS.isFile(path) { warn(L("Fichier introuvable.")); return }
        let name = PyFS.basename(path)
        Task.detached {
            let err = Config.scanForErrors(path)
            await MainActor.run {
                if let err {
                    self.reportText = Self.run("• \(name) : ", Socle.C.text) + Self.run("\(err)\n", Socle.C.danger)
                } else {
                    self.reportText = Self.run("✅ " + L("Aucun problème détecté dans {name}.", ["name": name]), Socle.C.success)
                }
            }
        }
    }

    // MARK: Purge

    func purgeAllLogs() {
        let folders = allFolders()
        let logs = Config.listLogs(folders)
        if logs.isEmpty { info(L("Aucun fichier log à supprimer.")); return }
        let dirs = pySorted(Array(Set(logs.map(\.folder))))
        let crashes = logs.filter { Config.isCrashName($0.name) }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.window.title = L("Purger les logs")
        alert.messageText = L("Supprimer définitivement {n} fichier(s) log ?", ["n": logs.count - crashes])
        alert.informativeText = L("Dossiers concernés :") + "\n" + dirs.joined(separator: "\n") + "\n\n"
            + (crashes > 0 ? L("Les {k} rapport(s) de plantage sont archivés dans « {dir} » : l'historique les garde.", ["k": crashes, "dir": Insights.ARCHIVE_DIR]) + "\n" : "")
            + L("Les autres logs sont supprimés : action irréversible.")
        let yes = alert.addButton(withTitle: L("Supprimer"))
        yes.hasDestructiveAction = true
        alert.addButton(withTitle: L("Annuler"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let (deleted, archived, errors) = Config.purgeLogs(folders)
        analyzeLogs()
        knownCrashes = crashNames()
        var msg = L("{n} fichier(s) supprimé(s).", ["n": deleted])
        if archived > 0 { msg += " " + L("{n} rapport(s) de plantage archivé(s).", ["n": archived]) }
        if errors.isEmpty { info(msg) } else { warn(msg + "\n\n" + L("Échecs :") + "\n" + errors.prefix(10).joined(separator: "\n")) }
    }

    // MARK: Réglages

    func applySettings(_ new: [String: String], folders: [(String, [String])], geminiKey: String, jevKey: String) {
        settings = new
        Config.saveSettings(settings)
        let changed = folders.map { $0.1 } != gameFolders.map { $0.1 }
        if changed {
            gameFolders = folders
            Config.saveConfig(gameFolders)
            knownCrashes = crashNames()
        }
        setupWatch()
        showKbStatus()
        if changed {
            analyzeLogs()
            if auditReport != nil { auditReport = nil; runAudit() }
        }
        if !geminiKey.isEmpty {
            do { try AIClient.setApiKey(geminiKey) } catch { warn("\(error)") }
        }
        if !jevKey.isEmpty {
            do { try JevClient.setApiKey(jevKey) } catch { warn("\(error)") }
        }
    }

    // MARK: Langue

    /// Choix du menu Langue : « auto » ou fr/en/it/es. Les textes de l'audit étant produits dans la langue active, l'audit est refait.
    func setLanguage(_ choice: String) {
        settings["language"] = I18n.langs[choice] != nil ? choice : "auto"
        Config.saveSettings(settings)
        I18n.setLang(Config.resolveLanguage(settings["language"]))
        tick += 1
        showKbStatus()
        analyzeLogs()
        if auditReport != nil { auditReport = nil; runAudit() }
    }

    // MARK: Chat IA

    func explainCrash() {
        chatInput = L("Quelle est la cause la plus probable du dernier crash ? Que dois-je vérifier en premier ?")
        sendChat()
    }

    func sendChat() {
        let question = chatInput.pyStrip
        if question.isEmpty || chatBusy { return }
        chatInput = ""
        chat.append(ChatEntry(who: .user, text: question))
        chatHistory.append(ChatMessage(role: "user", content: question))
        let history = Array(chatHistory.suffix(12))
        let st = settings
        let existing = auditReport.map { Box(value: $0) }
        let files = Config.gatherAuditFiles(allFolders())
        chatBusy = true
        startThinking()
        Task.detached(priority: .userInitiated) {
            do {
                let report = existing?.value ?? Audit.auditPaths(files, gameDir: st["game_dir"] ?? "")
                var answer = try AIClient.chat(st, auditContext: report.toContext(), history: history)
                answer = Guard.apply(answer, report.extras.inventory, judge: Guard.defaultJudge()).0
                let box = Box(value: (report, answer))
                await MainActor.run { self.chatDone(box.value.0, box.value.1) }
            } catch {
                await MainActor.run { self.chatFailed("\(error)") }
            }
        }
    }

    private func chatDone(_ report: AuditReport, _ answer: String) {
        stopThinking()
        if auditReport == nil { auditReport = report; reportText = Self.renderAudit(report) }
        chatHistory.append(ChatMessage(role: "assistant", content: answer))
        chat.append(ChatEntry(who: .assistant, text: answer))
        chatBusy = false
    }

    private func chatFailed(_ msg: String) {
        stopThinking()
        if chatHistory.last?.role == "user" { chatHistory.removeLast() }
        chat.append(ChatEntry(who: .error, text: msg))
        chatBusy = false
    }

    private func startThinking() {
        thinkingStep = 0
        thinkTimer?.invalidate()
        thinkTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.thinkingStep = (self?.thinkingStep ?? 0) + 1 }
        }
    }

    private func stopThinking() {
        thinkTimer?.invalidate()
        thinkTimer = nil
        thinkingStep = nil
    }

    // MARK: Surveillance des dossiers

    private func crashNames() -> Set<String> {
        let rx = try! NSRegularExpression(pattern: #"^(crash[-_]|.*netscriptframework)"#, options: .caseInsensitive)
        return Set(Config.listLogs(allFolders()).filter {
            rx.firstMatch(in: $0.name, range: NSRange(location: 0, length: ($0.name as NSString).length)) != nil
        }.map(\.path))
    }

    func setupWatch() {
        watchers.forEach { $0.cancel() }
        watchers = []
        guard (settings["auto_watch"] ?? "1") == "1" else { return }
        for dir in allFolders() where PyFS.isDir(dir) {
            let fd = open(dir, O_EVTONLY)
            if fd < 0 { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleLogsChanged() } }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
    }

    private func scheduleLogsChanged() {
        watchTask?.cancel()
        watchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // laisse le jeu finir d'écrire ses fichiers
            if !Task.isCancelled { self.onLogsChanged() }
        }
    }

    private func onLogsChanged() {
        let current = crashNames()
        let new = current.subtracting(knownCrashes)
        knownCrashes = current
        let allNow = Set(Config.listLogs(allFolders()).map(\.path))
        if allNow == knownLogs && new.isEmpty { return }  // simple réécriture d'un log existant : on garde le rapport affiché
        knownLogs = allNow
        analyzeLogs()
        guard let last = new.sorted(by: pyLess).last else { return }
        notify(APP_NAME, L("Nouveau crash détecté : {name}", ["name": PyFS.basename(last)]))
        if !auditBusy { runAudit() }
    }

    /// Notification macOS (osascript). Silencieux en cas d'échec.
    private func notify(_ title: String, _ message: String) {
        Task.detached {
            func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \"\(esc(message))\" with title \"\(esc(title))\""]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
    }

    // MARK: Messages

    func info(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.alertStyle = .informational
        a.addButton(withTitle: "OK")
        a.window.title = APP_NAME
        a.runModal()
    }

    func warn(_ text: String) {
        let a = NSAlert()
        a.messageText = text
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        a.window.title = APP_NAME
        a.runModal()
    }

    func openLog(_ row: LogRow) { viewingLog = (row.path, row.name) }
}
