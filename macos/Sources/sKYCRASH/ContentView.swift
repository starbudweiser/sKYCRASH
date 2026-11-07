// Interface : à gauche rapport, liste des logs et actions ; à droite l'assistant IA. Design Socle (tokens, boutons plats).

import AppKit
import CrashCore
import SwiftUI
import UniformTypeIdentifiers

let WINDOW_SIZE = CGSize(width: 1400, height: 950)

extension Color {
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Bouton destructif (purge) : aplat rouge atténué, texte clair, comme le rôle « danger » de la version d'origine.
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }
    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            configuration.label
                .socle(Socle.T.button)
                .foregroundStyle(Socle.C.dangerSoft)
                .padding(.horizontal, Socle.M.space4)
                .frame(maxWidth: .infinity, minHeight: Socle.M.sizeControlLg)
                .background(configuration.isPressed ? Socle.C.dangerBg : (hover && enabled ? Socle.C.dangerFill : Socle.C.dangerBg),
                            in: RoundedRectangle(cornerRadius: Socle.M.radius))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : Socle.M.opacityDisabled)
                .onHover { hover = $0 }
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        let _ = model.tick
        HSplitView {
            leftPanel.frame(minWidth: 620, idealWidth: 830)
            chatPanel.frame(minWidth: 380, idealWidth: 570)
        }
        .background(Socle.C.bg)
        .overlay {
            if dropTargeted {
                Rectangle().stroke(Socle.C.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])).padding(6).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.scanFile(url.path) } }
            }
            return true
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .sheet(isPresented: Binding(get: { model.viewingLog != nil }, set: { if !$0 { model.viewingLog = nil } })) {
            if let v = model.viewingLog { LogViewerSheet(path: v.path, name: v.name) { model.viewingLog = nil } }
        }
    }

    // MARK: Colonne de gauche

    private var leftPanel: some View {
        VStack(spacing: Socle.M.space5) {
            HStack(spacing: Socle.M.space3) {
                Button(L("Analyser les logs")) { model.analyzeLogs() }
                    .buttonStyle(SocleButtonStyle(.action))
                Button(L("Audit approfondi")) { model.runAudit() }
                    .buttonStyle(SocleButtonStyle(.primary)).disabled(model.auditBusy)
                Button(L("Fichier…")) { model.selectLogFile() }
                    .buttonStyle(SocleButtonStyle(.secondary))
                Button(L("Réglages…")) { model.showSettings = true }
                    .buttonStyle(SocleButtonStyle(.secondary))
                    .help(L("Langue, dossiers de logs, IA, base de connaissances (⌘,)"))
            }
            .lineLimit(1).minimumScaleFactor(0.8)

            ScrollView {
                Text(model.reportText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(15)
            }
            .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))

            logList

            HStack(spacing: Socle.M.space3) {
                Button(L("Exporter le diagnostic…")) { model.exportDiagnostic() }
                    .buttonStyle(SocleButtonStyle(.secondary)).disabled(model.exportBusy)
                    .help(L("Un seul fichier avec tout le contexte du plantage, à transmettre (⌘E)"))
                Button(L("Purger les logs")) { model.purgeAllLogs() }
                    .buttonStyle(DangerButtonStyle())
                    .help(L("Supprime les .log / .log0 des répertoires configurés"))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.top, 30).padding(.leading, 30).padding(.trailing, 20).padding(.bottom, 30)
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.logRows) { row in
                    LogRowView(row: row) { model.openLog(row) }
                }
            }
            .padding(4)
        }
        .frame(minHeight: 120, maxHeight: 220)
        .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
    }

    // MARK: Colonne de droite : assistant IA

    private var chatPanel: some View {
        VStack(spacing: Socle.M.space5) {
            HStack(spacing: Socle.M.space3) {
                Text(L("Assistant IA")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                Spacer(minLength: 0)
                Text(model.kbStatus).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
                    .help(model.kbTooltip)
            }
            .frame(height: Socle.M.sizeControlLg)

            ChatList(model: model)
                .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))

            HStack(spacing: Socle.M.space3) {
                TextField(L("Votre question…"), text: $model.chatInput)
                    .socleField().onSubmit { model.sendChat() }
                Button(model.thinkingStep.map { String(repeating: "●", count: $0 % 3 + 1) } ?? L("Envoyer")) { model.sendChat() }
                    .buttonStyle(SocleButtonStyle(.primary)).fixedSize().disabled(model.chatBusy)
            }
            Button(L("Expliquer le crash")) { model.explainCrash() }
                .buttonStyle(SocleButtonStyle(.secondary)).disabled(model.chatBusy)
        }
        .padding(.top, 30).padding(.leading, 20).padding(.trailing, 30).padding(.bottom, 30)
    }
}

struct LogRowView: View {
    let row: LogRow
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Text("●").font(.system(size: 12)).foregroundStyle(row.isError ? Socle.C.danger : Socle.C.success).frame(width: 14)
                Text(row.name).socle(Socle.T.labelStrong).foregroundStyle(Socle.C.textStrong).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Text("\(row.game) · \(PyFS.basename(row.folder)) · \(row.when)").socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).lineLimit(1)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(hover ? Socle.C.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(row.path)
    }
}

/// Fenêtre de lecture d'un log (900 × 650), texte monospace sélectionnable.
struct LogViewerSheet: View {
    let path: String
    let name: String
    let close: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Lecture : {name}", ["name": name])).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                Spacer()
                Button(L("Fermer"), action: close).buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
            }
            .padding(Socle.M.space3)
            PlainTextView(text: text).background(Socle.C.bgSunken)
        }
        .frame(width: 900, height: 650)
        .background(Socle.C.bg)
        .task {
            let p = path
            text = await Task.detached { Config.readLines(p).joined(separator: "\n") }.value
        }
    }
}

/// Zone de texte AppKit (lecture seule) : reste fluide sur les journaux de plusieurs Mo.
struct PlainTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        let tv = sv.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = NSColor(Socle.C.text)
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 10, height: 10)
        sv.drawsBackground = false
        return sv
    }
    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
        tv.textColor = NSColor(Socle.C.text)
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    }
}

// MARK: Chat

struct ChatList: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.chat.isEmpty && model.thinkingStep == nil {
                        Text(L("Posez une question sur le dernier crash…")).socle(Socle.T.bodyLg).foregroundStyle(Socle.C.textSubtle)
                    }
                    ForEach(model.chat) { entry in
                        ChatEntryView(entry: entry).padding(.bottom, 14)
                    }
                    if let step = model.thinkingStep {
                        Text(L("Assistant réfléchit") + " " + String(repeating: ".", count: step % 3 + 1))
                            .socle(Socle.T.bodyLg).foregroundStyle(Socle.C.textSubtle)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .onChange(of: model.chat.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: model.thinkingStep == nil) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .frame(minWidth: 300)
    }
}

struct ChatEntryView: View {
    let entry: ChatEntry

    private var header: (String, Color) {
        switch entry.who {
        case .user: (L("Vous"), Socle.C.accentText)
        case .assistant: (L("Assistant"), Socle.C.warning)
        case .error: (L("Erreur"), Socle.C.danger)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header.0).socle(Socle.T.bodyLg).fontWeight(.heavy).foregroundStyle(header.1)
            switch entry.who {
            case .assistant: AIAnswerView(answer: entry.text)
            default: Text(Socle.branded(entry.text)).socle(Socle.T.bodyLg).foregroundStyle(Socle.C.text).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Réponse de l'IA : sections colorées (VERDICT, CAUSE…), listes, sans icônes (AIFormat).
struct AIAnswerView: View {
    let answer: String

    private func inline(_ text: String, base: Color = Socle.C.text) -> AttributedString {
        var out = AttributedString()
        for part in AIFormat.inlines(text) {
            switch part {
            case .plain(let s): var a = Socle.branded(s); a.foregroundColor = base; out += a
            case .bold(let s):
                var a = AttributedString(s); a.foregroundColor = Socle.C.textStrong; a.inlinePresentationIntent = .stronglyEmphasized; out += a
            case .code(let s):
                var a = AttributedString(s); a.foregroundColor = Color(hex: "#fbbf24"); a.font = .system(size: 13, design: .monospaced); out += a
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(AIFormat.parse(answer).enumerated()), id: \.offset) { _, block in
                switch block {
                case .label(let key, let rest):
                    let color = Color(hex: AIFormat.PALETTE[key] ?? AIFormat.MUTED)
                    Text(label(key, rest, color))
                        .padding(.top, 10).textSelection(.enabled)
                case .numbered(let accent, let num, let text):
                    Text(marker("\(num).", accent) + AttributedString(" ") + inline(text)).padding(.leading, 6).textSelection(.enabled)
                case .bullet(let accent, let text):
                    Text(marker("–", accent) + AttributedString(" ") + inline(text)).padding(.leading, 6).textSelection(.enabled)
                case .plain(let t):
                    Text(inline(t)).textSelection(.enabled)
                }
            }
        }
        .socle(Socle.T.bodyLg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marker(_ s: String, _ accent: String) -> AttributedString {
        var a = AttributedString(s); a.foregroundColor = Color(hex: accent); a.inlinePresentationIntent = .stronglyEmphasized; return a
    }

    private func label(_ key: String, _ rest: String, _ color: Color) -> AttributedString {
        var head = AttributedString(L(AIFormat.TITLES[key] ?? key))
        head.foregroundColor = color
        head.inlinePresentationIntent = .stronglyEmphasized
        head.kern = 1
        guard !rest.isEmpty else { return head }
        if key == "confiance" {
            var r = AttributedString(rest.pyStrip("* "))
            r.foregroundColor = Color(hex: AIFormat.levelColor(rest, default: AIFormat.PALETTE[key]!))
            r.inlinePresentationIntent = .stronglyEmphasized
            return head + AttributedString("  ") + r
        }
        return head + AttributedString("  ") + inline(rest)
    }
}
