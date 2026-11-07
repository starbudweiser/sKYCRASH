// Point d'entrée : fenêtre AppKit unique (1400 × 950, redimensionnable) qui héberge l'interface SwiftUI, splash animé,
// menus (Fichier, Édition, Langue, Fenêtre), À propos et mise à jour automatique.

import AppKit
import CrashCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let model = AppModel()
    let env = ProcessInfo.processInfo.environment

    // Le splash part avant que SwiftUI ouvre la fenêtre principale, pour pouvoir la retenir jusqu'à t = 2 s.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Socle.brand(APP_NAME, color: LOGO_ORANGE)  // « s » dans l'orange de l'iris du logo
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        Splash.shared.start(Splash.Config(title: APP_NAME, subtitle: L("ANALYSE DE CRASH"), footer: version.isEmpty ? "" : "v" + version,
                                          accent: LOGO_ORANGE))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        buildMenu()

        let host = NSHostingView(rootView: ContentView(model: model).splashGated())
        window = NSWindow(contentRect: NSRect(origin: .zero, size: WINDOW_SIZE),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = APP_NAME
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(Socle.C.bg)
        window.contentMinSize = NSSize(width: 1100, height: 700)
        let avail = NSScreen.main?.visibleFrame.height ?? 1080
        window.setContentSize(NSSize(width: WINDOW_SIZE.width, height: min(WINDOW_SIZE.height, max(700, avail - 60))))
        window.socleCenter()
        model.window = window
        model.start()

        // Essais en arrière-plan : SPLASH_QUIET=1 lance l'appli (splash et fenêtre) sans prendre le focus ni passer devant le travail en cours
        if env["SKYCRASH_NOUPDATE"] == nil {
            UpdateEngine.shared.configure(repo: "sKYCRASH", lang: { I18n.lang })
            UpdateEngine.shared.canInstall = { [weak self] in !(self?.model.auditBusy ?? false) && !(self?.model.chatBusy ?? false) }  // jamais pendant une analyse
            UpdateEngine.shared.start()  // nouvelle version ? (au plus une fois par jour)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { UpdateEngine.shared.installAppMenuItem() }
        }
        scripted()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Menus

    @objc func chooseLanguage(_ sender: NSMenuItem) {
        model.setLanguage(sender.representedObject as? String ?? "auto")
        window.title = APP_NAME
        buildMenu()
        UpdateEngine.shared.installAppMenuItem()
    }
    @objc func showAbout(_ sender: Any?) { About.show() }
    @objc func showSettings(_ sender: Any?) { model.showSettings = true }
    @objc func openLog(_ sender: Any?) { model.selectLogFile() }
    @objc func exportDiagnostic(_ sender: Any?) { model.exportDiagnostic() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        // Pas de couleur dans les menus : le nom de l'appli y est en texte normal
        appMenu.addItem(withTitle: L("À propos de sKYCRASH"), action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        let prefs = appMenu.addItem(withTitle: L("Réglages…"), action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Masquer sKYCRASH"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: L("Masquer les autres"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L("Tout afficher"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quitter sKYCRASH"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("Fichier"))
        fileMenu.addItem(withTitle: L("Ouvrir un log…"), action: #selector(openLog), keyEquivalent: "o").target = self
        fileMenu.addItem(withTitle: L("Exporter le diagnostic…"), action: #selector(exportDiagnostic), keyEquivalent: "e").target = self
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("Édition"))
        editMenu.addItem(withTitle: L("Couper"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Menu « Langue » : Automatique + 4 langues, coche sur le choix courant
        let langItem = NSMenuItem()
        let langMenu = NSMenu(title: L("Langue"))
        let current = I18n.langs[model.settings["language"] ?? ""] != nil ? model.settings["language"]! : "auto"
        func add(_ title: String, _ code: String) {
            let item = langMenu.addItem(withTitle: title, action: #selector(chooseLanguage), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == current ? .on : .off
        }
        add(L("Automatique (système)"), "auto")
        langMenu.addItem(.separator())
        for code in ["fr", "en", "es", "it"] { add(I18n.langs[code]!, code) }
        langItem.submenu = langMenu
        main.addItem(langItem)

        let winItem = NSMenuItem()
        let winMenu = NSMenu(title: L("Fenêtre"))
        winMenu.addItem(withTitle: L("Réduire"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu
        main.addItem(winItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = winMenu
    }

    // MARK: Essais pilotés par l'environnement (aucune interaction, aucune fenêtre au premier plan)

    /// SKYCRASH_RUN : étapes séparées par « ; » parmi audit, chat:<question>, settings, lang:<code>, log:<chemin>, scan:<chemin>.
    /// SKYCRASH_SNAPSHOT=<png> (après SKYCRASH_DELAY s, 3,5 par défaut) enregistre la fenêtre ; SKYCRASH_DUMP=<fichier> écrit l'état ; puis l'appli quitte.
    private func scripted() {
        if let run = env["SKYCRASH_RUN"] {
            for (i, step) in run.components(separatedBy: ";").enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 0.8) { [self] in
                    if step == "audit" { model.runAudit() }
                    else if step == "settings" { model.showSettings = true }
                    else if step == "about" { About.show() }
                    else if step.hasPrefix("export:") { model.exportDiagnostic(to: URL(fileURLWithPath: String(step.dropFirst(7)))) }
                    else if step.hasPrefix("chat:") { model.chatInput = String(step.dropFirst(5)); model.sendChat() }
                    else if step.hasPrefix("lang:") { model.setLanguage(String(step.dropFirst(5))); buildMenu() }
                    else if step.hasPrefix("scan:") { model.scanFile(String(step.dropFirst(5))) }
                    else if step.hasPrefix("log:") { model.viewingLog = (String(step.dropFirst(4)), PyFS.basename(String(step.dropFirst(4)))) }
                }
            }
        }
        guard let out = env["SKYCRASH_SNAPSHOT"] else { return }
        let delay = Double(env["SKYCRASH_DELAY"] ?? "") ?? 3.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            if let dump = env["SKYCRASH_DUMP"] {
                var t = "menus:\n"
                for item in NSApp.mainMenu?.items ?? [] {
                    t += " [\(item.submenu?.title ?? "")] " + (item.submenu?.items.map { ($0.state == .on ? "✓" : "") + ($0.isSeparatorItem ? "-" : $0.title) }.joined(separator: " | ") ?? "") + "\n"
                }
                t += "rapport:\n" + String(model.reportText.characters) + "\n---\nlogs: \(model.logRows.count)\n"
                t += "kb: \(model.kbStatus)\nlangue: \(I18n.lang)\nbusy: audit=\(model.auditBusy) chat=\(model.chatBusy)\n"
                for e in model.chat { t += "chat[\(e.who)]: \(e.text)\n" }
                try? t.write(toFile: dump, atomically: true, encoding: .utf8)
            }
            func shot(_ view: NSView, _ file: String) {
                view.layoutSubtreeIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
                }
            }
            shot(window.contentView!, out)
            // fenêtres annexes ouvertes (À propos, feuilles) : <png>-<n>.png
            var n = 0
            for w in NSApp.windows where w !== window && w.contentView != nil && w.frame.width > 100 && !(w is NSPanel) {
                n += 1
                shot(w.contentView!, out.replacingOccurrences(of: ".png", with: "-\(n).png"))
            }
            // onglets des réglages : SKYCRASH_SETTINGS_SHOTS=1
            if env["SKYCRASH_SETTINGS_SHOTS"] != nil {
                for (i, tab) in SettingsView.Tab.allCases.enumerated() {
                    let host = NSHostingView(rootView: SettingsView(model: model, tab: tab))
                    host.frame = NSRect(x: 0, y: 0, width: 680, height: 700)
                    let tmp = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                    tmp.contentView = host
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                    shot(host, out.replacingOccurrences(of: ".png", with: "-settings\(i).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}

I18n.setLang(Config.startupLang())

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
