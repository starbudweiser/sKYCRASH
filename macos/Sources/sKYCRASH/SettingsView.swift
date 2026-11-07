// Réglages (feuille) : Général, Dossiers de logs, IA, Base de connaissances. Les clés API vont dans le Trousseau, jamais dans la config.

import AppKit
import CrashCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Tab: CaseIterable { case general, folders, ai, knowledge }
    @State private var tab: Tab

    @State private var s: [String: String] = [:]
    @State private var folders: [(String, [String])] = []
    @State private var selectedFolder: String?
    @State private var geminiKey = ""
    @State private var jevKey = ""
    @State private var geminiModels: [String] = []
    @State private var ollamaModels: [String] = []
    @State private var status = ""
    @State private var busy = false
    @State private var loaded = false
    @State private var kbBusy = false

    private func title(_ t: Tab) -> String {
        switch t {
        case .general: L("Général")
        case .folders: L("Dossiers de logs")
        case .ai: L("IA")
        case .knowledge: L("Base de connaissances")
        }
    }

    private func flag(_ key: String, _ def: String = "1") -> Binding<Bool> {
        Binding(get: { (s[key] ?? def) == "1" }, set: { s[key] = $0 ? "1" : "0" })
    }
    private func text(_ key: String) -> Binding<String> {
        Binding(get: { s[key] ?? "" }, set: { s[key] = $0 })
    }

    init(model: AppModel, tab: Tab = .general) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: Socle.M.space3) {
            Text(L("Réglages")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong).frame(maxWidth: .infinity, alignment: .leading)
            SocleSegmented(options: Tab.allCases, selection: tab, label: title, tone: { _ in .strong }) { tab = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(Socle.C.border)
            ScrollView {
                Group {
                    switch tab {
                    case .general: general
                    case .folders: foldersTab
                    case .ai: ai
                    case .knowledge: knowledge
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Socle.M.space2)
            }
            Text(status).socle(Socle.T.body).foregroundStyle(Socle.C.warning).frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
            HStack(spacing: Socle.M.space3) {
                Spacer()
                Button(L("Annuler")) { dismiss() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                Button("OK") { apply() }.buttonStyle(SocleButtonStyle(.action)).fixedSize().keyboardShortcut(.defaultAction)
            }
        }
        .padding(Socle.M.space5)
        .frame(width: 680, height: 600)
        .background(Socle.C.bg)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            s = model.settings
            folders = model.gameFolders
            geminiModels = AIClient.FALLBACK_GEMINI_MODELS
            if let cur = s["gemini_model"], !cur.isEmpty, !geminiModels.contains(cur) { geminiModels.insert(cur, at: 0) }
            if let cur = s["ollama_model"], !cur.isEmpty { ollamaModels = [cur] }
        }
    }

    // MARK: Onglets

    private func row<V: View>(_ label: String, @ViewBuilder _ content: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Socle.M.space3) {
            Text(label).socle(Socle.T.label).foregroundStyle(Socle.C.text).frame(width: 190, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func note(_ t: String) -> some View {
        Text(branded: t).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            row(L("Dossier du jeu")) {
                HStack(spacing: Socle.M.space2) {
                    TextField(L("Auto (CrossOver) — ou dossier contenant SkyrimSE.exe"), text: text("game_dir")).socleField()
                    Button(L("Choisir…")) { pickGameDir() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                }
            }
            row(L("Surveillance")) {
                Toggle(L("Surveiller les dossiers : nouveau crash = notification + audit automatique"), isOn: flag("auto_watch"))
                    .toggleStyle(.checkbox)
            }
            row(L("Échange avec mORTEX")) {
                Toggle(L("Exporter les analyses pour mORTEX (fichier crash_events.jsonl, sans chemin personnel)"), isOn: flag("export_events"))
                    .toggleStyle(.checkbox)
            }
        }.socle(Socle.T.body)
    }

    private var foldersTab: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            note(L("Dossiers où sKYCRASH cherche les logs de crash, SKSE et Papyrus.") + " "
                 + L("Le dossier SKSE (journal SKSE et rapports de Crash Logger) est toujours analysé, même s'il n'est pas dans la liste."))
            ForEach(folders.indices, id: \.self) { g in
                List(selection: $selectedFolder) {
                    ForEach(folders[g].1, id: \.self) { f in
                        Text(f).socle(Socle.T.body).tag(f).lineLimit(1).truncationMode(.middle)
                    }
                }
                .scrollContentBackground(.hidden).background(Socle.C.surface).frame(height: 260)
                HStack(spacing: Socle.M.space3) {
                    Button(L("Ajouter…")) { addFolder(g) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    Button(L("Retirer")) { removeFolder(g) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().disabled(selectedFolder == nil)
                    Spacer()
                }
            }
        }
    }

    private var ai: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            row(L("Fournisseur")) {
                Picker("", selection: text("provider")) { Text("gemini").tag("gemini"); Text("ollama").tag("ollama") }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 220)
            }
            row(L("Modèle Gemini")) {
                HStack(spacing: Socle.M.space2) {
                    ModelField(text: text("gemini_model"), models: geminiModels)
                    Button(L("Actualiser")) { refreshGemini() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().disabled(busy)
                }
            }
            row(L("Clé API Gemini")) {
                SecureField(AIClient.hasKey() ? L("(clé enregistrée)") : L("Coller la clé API"), text: $geminiKey).socleField()
            }
            row(L("URL Ollama")) { TextField("", text: text("ollama_url")).socleField() }
            row(L("Modèle Ollama")) {
                HStack(spacing: Socle.M.space2) {
                    ModelField(text: text("ollama_model"), models: ollamaModels)
                    Button(L("Actualiser")) { refreshOllama() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().disabled(busy)
                }
            }
            row(L("Clé Jev (vérification)")) {
                HStack(spacing: Socle.M.space2) {
                    SecureField(JevClient.hasKey() ? L("(clé enregistrée)") : L("Facultatif : clé TypeSafe"), text: $jevKey).socleField()
                    Button(L("Voir le solde ↗")) { NSWorkspace.shared.open(URL(string: JevClient.CONSOLE_URL)!) }
                        .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                }
            }
            row("") {
                let u = JevClient.monthUsage()
                note(L("Ce mois-ci : {n} requête(s) Jev · {t} jetons ({i} en entrée, {o} en sortie), comptés par l'appli. Le solde de crédits n'est visible que sur la console TypeSafe.",
                       ["n": u.requests, "t": grouped(u.inputTokens + u.outputTokens), "i": grouped(u.inputTokens), "o": grouped(u.outputTokens)]))
            }
            row(L("Connaissances")) {
                Toggle(L("Utiliser les fiches de connaissances modding Skyrim (dossier skills/)"), isOn: flag("use_skills")).toggleStyle(.checkbox)
            }
            row("") { Toggle(L("Recherche web Google (Gemini uniquement, plus lent)"), isOn: flag("web_search", "0")).toggleStyle(.checkbox) }
            row(L("Confidentialité")) {
                Toggle(L("Anonymiser les chemins et e-mails avant envoi à Gemini"), isOn: flag("anonymize")).toggleStyle(.checkbox)
            }
            note(L("La clé est stockée dans le Trousseau macOS (jamais en clair dans la config). ")
                 + L("Avec Gemini, le rapport d'audit et des extraits de logs sont envoyés à Google. Ollama reste 100 % local.") + " "
                 + L("Avec une clé Jev (TypeSafe), chaque conseil de l'assistant est confronté aux faits vérifiés de l'installation, envoyés à TypeSafe ; les conseils contredits sont retirés."))
        }.socle(Socle.T.body)
    }

    private func grouped(_ n: Int) -> String { fmtInt(n) }

    private var knowledge: some View {
        VStack(alignment: .leading, spacing: Socle.M.space3) {
            row(L("Veille")) {
                Toggle(L("Veille automatique : mettre à jour la base de connaissances (GitHub, Steam, Reddit, SKSE)"), isOn: flag("auto_knowledge")).toggleStyle(.checkbox)
            }
            row("") { Button(L("Mettre à jour maintenant")) { refreshKnowledge() }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize().disabled(kbBusy) }
            row("") {
                let last = KnowledgeUpdater.status().lastRun
                note(L("Dernière mise à jour de la base : {d}", ["d": last.map { Wall(timestamp: $0).format("%d/%m/%Y %H:%M") } ?? L("jamais")]))
            }
        }.socle(Socle.T.body)
    }

    // MARK: Actions

    private func pickGameDir() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.title = L("Dossier de Skyrim Special Edition")
        p.directoryURL = URL(fileURLWithPath: (s["game_dir"] ?? "").isEmpty ? NSHomeDirectory() : s["game_dir"]!)
        if p.runModal() == .OK, let u = p.url { s["game_dir"] = u.path }
    }

    private func addFolder(_ g: Int) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.title = L("Sélectionner un dossier pour {game}", ["game": folders[g].0])
        let mg = Config.docs + "/My Games"
        p.directoryURL = URL(fileURLWithPath: PyFS.isDir(mg) ? mg : Config.docs)
        if p.runModal() == .OK, let u = p.url, !folders[g].1.contains(u.path) { folders[g].1.append(u.path) }
    }

    private func removeFolder(_ g: Int) {
        guard let sel = selectedFolder, let i = folders[g].1.firstIndex(of: sel) else { return }
        folders[g].1.remove(at: i)
        selectedFolder = nil
    }

    private func refresh(_ label: String, _ fn: @escaping @Sendable () throws -> [String], _ done: @escaping ([String]) -> Void) {
        busy = true
        status = L("Récupération des modèles {label}…", ["label": label])
        Task.detached {
            do {
                let models = try fn()
                await MainActor.run { busy = false; done(models); status = L("{n} modèle(s) {label} disponible(s).", ["n": models.count, "label": label]) }
            } catch {
                await MainActor.run { busy = false; status = L("Liste indisponible ({msg}). Vous pouvez saisir le nom du modèle.", ["msg": "\(error)"]) }
            }
        }
    }

    private func refreshGemini() {
        let key = geminiKey.pyStrip.isEmpty ? nil : geminiKey.pyStrip  // clé saisie, sinon celle du Trousseau
        refresh("Gemini", { try AIClient.listGeminiModels(key: key) }) { m in
            var list = m
            if let cur = s["gemini_model"], !cur.isEmpty, !list.contains(cur) { list.insert(cur, at: 0) }
            geminiModels = list
        }
    }

    private func refreshOllama() {
        let url = (s["ollama_url"] ?? "").pyStrip
        refresh("Ollama", { try AIClient.listOllamaModels(url) }) { m in
            var list = m
            if let cur = s["ollama_model"], !cur.isEmpty, !list.contains(cur) { list.insert(cur, at: 0) }
            ollamaModels = list
        }
    }

    private func refreshKnowledge() {
        kbBusy = true
        status = L("Mise à jour de la base de connaissances…")
        Task.detached {
            let rep = KnowledgeUpdater.updateAll(force: true)
            await MainActor.run {
                kbBusy = false
                status = rep.skipped ? L("Mise à jour déjà en cours.")
                    : L("Base de connaissances : {u} source(s) mise(s) à jour, {f} en échec.", ["u": rep.updated.count, "f": rep.failed.count])
                model.showKbStatus(rep)
            }
        }
    }

    private func apply() {
        var new = s
        func def(_ k: String) { if (new[k] ?? "").pyStrip.isEmpty { new[k] = AIClient.defaultSetting(k) } else { new[k] = new[k]!.pyStrip } }
        for k in ["gemini_model", "ollama_url", "ollama_model"] { def(k) }
        new["game_dir"] = (new["game_dir"] ?? "").pyStrip
        model.applySettings(new, folders: folders, geminiKey: geminiKey.pyStrip, jevKey: jevKey.pyStrip)
        dismiss()
    }
}

/// Champ de modèle éditable avec liste déroulante (comme la liste modifiable d'origine).
struct ModelField: View {
    @Binding var text: String
    let models: [String]

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text).socleField()
            Menu {
                ForEach(models, id: \.self) { m in Button(m) { text = m } }
            } label: { Image(systemName: "chevron.down").foregroundStyle(Socle.C.textMuted) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        }
    }
}
