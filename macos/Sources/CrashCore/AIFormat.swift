// Mise en forme des réponses de l'IA : sections colorées, listes, sans icônes (src/ai_format.py).
// Le prompt système impose des sections en MAJUSCULES (VERDICT, CAUSE, CONFIANCE, PREUVES, ACTIONS, MANQUE).

import Foundation

public enum AIFormat {
    public static let TEXT = "#dddddd"
    public static let MUTED = "#8f8f8f"
    public static let PALETTE = ["verdict": "#f59e0b", "cause": "#f87171", "confiance": "#38bdf8", "preuves": "#38bdf8", "actions": "#4ade80", "manque": "#aaaaaa"]
    static let LEVEL_COLORS = ["elevee": "#4ade80", "moyenne": "#fbbf24", "faible": "#f87171", "high": "#4ade80", "medium": "#fbbf24", "low": "#f87171",
                               "alta": "#4ade80", "media": "#fbbf24", "bassa": "#f87171", "baja": "#f87171"]
    public static let TITLES = ["verdict": N_("VERDICT"), "cause": N_("CAUSE"), "confiance": N_("CONFIANCE"),
                                "preuves": N_("PREUVES"), "actions": N_("ACTIONS"), "manque": N_("MANQUE")]
    static let ALIASES: [String: String] = [
        "verdict": "verdict", "resume": "verdict", "conclusion": "verdict",
        "cause": "cause", "cause probable": "cause", "cause la plus probable": "cause", "cause probable du crash": "cause",
        "confiance": "confiance", "niveau de confiance": "confiance",
        "preuves": "preuves", "preuves tirees des logs": "preuves", "indices": "preuves",
        "actions": "actions", "etapes": "actions", "verifications": "actions", "etapes de verification": "actions", "etapes concretes": "actions",
        "manque": "manque", "informations manquantes": "manque", "limites": "manque", "ce qui manque": "manque",
        "summary": "verdict", "verdetto": "verdict", "veredicto": "verdict",
        "probable cause": "cause", "causa": "cause", "causa probable": "cause",
        "confidence": "confiance", "affidabilita": "confiance", "confianza": "confiance",
        "evidence": "preuves", "prove": "preuves", "pruebas": "preuves",
        "azioni": "actions", "acciones": "actions", "steps": "actions",
        "missing": "manque", "missing information": "manque", "mancante": "manque",
        "falta": "manque", "cosa manca": "manque", "lo que falta": "manque",
    ]
    static let LABEL_RE = Rx(#"^\s*(?:#{1,6}\s*)?(?:\d+[.)]\s*)?[*_]*([^:*_\n]{3,40}?)[*_]*\s*[:：]\s*[*_]*\s*(.*)$"#)
    static let BARE_LABEL_RE = Rx(#"^\s*(?:#{1,6}\s*)?[*_]*([A-Za-zÀ-ÿ' ]{3,40}?)[*_]*\s*$"#)
    static let BULLET_RE = Rx(#"^\s*[-*•–]\s+(.*)$"#)
    static let NUM_RE = Rx(#"^\s*(\d+)[.)]\s+(.*)$"#)
    static let INLINE_RE = Rx(#"\*\*(.+?)\*\*|`([^`]+)`"#)
    static let RULE_RE = Rx(#"^\s*([-*_]\s*){3,}$"#)
    static let HEAD_RE = Rx(#"^\s*#{1,6}\s*"#)

    /// `unicodedata.normalize("NFD")` sans accents, en minuscules.
    static func norm(_ s: String) -> String {
        let d = s.pyStrip.lowercased().decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        for u in d.unicodeScalars where u.properties.generalCategory != .nonspacingMark { out.append(u) }
        return String(out)
    }
    static func sectionKey(_ label: String) -> String? { ALIASES[norm(label)] }

    public enum Inline { case plain(String), bold(String), code(String) }

    public enum Block {
        case label(key: String, rest: String)
        case numbered(accent: String, num: String, text: String)
        case bullet(accent: String, text: String)
        case plain(String)
    }

    public static func inlines(_ text: String) -> [Inline] {
        var out: [Inline] = []
        let ns = text as NSString
        var pos = 0
        for m in INLINE_RE.finditer(text) {
            out.append(.plain(ns.substring(with: NSRange(location: pos, length: m.start - pos))))
            if let b = m.group(1) { out.append(.bold(b)) } else { out.append(.code(m.group(2)!)) }
            pos = m.end
        }
        out.append(.plain(ns.substring(from: pos)))
        return out
    }

    public static func parse(_ answer: String) -> [Block] {
        var blocks: [Block] = []
        var key: String?
        for raw in answer.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.pyRStrip
            if line.pyIsBlank { continue }
            if RULE_RE.test(line) { continue }
            if let m = LABEL_RE.match(line), let k = sectionKey(m.group(1)!) {
                key = k
                blocks.append(.label(key: k, rest: m.group(2)!.pyStrip))
                continue
            }
            if let m = BARE_LABEL_RE.match(line), let k = sectionKey(m.group(1)!), BULLET_RE.match(line) == nil {
                key = k
                blocks.append(.label(key: k, rest: ""))
                continue
            }
            let accent = key.flatMap { PALETTE[$0] } ?? MUTED
            if let m = NUM_RE.match(line) { blocks.append(.numbered(accent: accent, num: m.group(1)!, text: m.group(2)!)); continue }
            if let m = BULLET_RE.match(line) { blocks.append(.bullet(accent: accent, text: m.group(1)!)); continue }
            blocks.append(.plain(HEAD_RE.sub("", line).pyStrip))
        }
        if blocks.isEmpty { blocks.append(.plain(answer.pyStrip)) }
        return blocks
    }

    /// Couleur du niveau de CONFIANCE d'après le premier mot (« Élevée. » -> vert…).
    public static func levelColor(_ rest: String, default d: String) -> String {
        let first = norm(rest).components(separatedBy: " ").first ?? ""
        return LEVEL_COLORS[first.pyStrip(".,;")] ?? d
    }

    // MARK: HTML (identique à la version Python, pour la comparaison)

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#x27;")
    }

    static func inlineHTML(_ text: String, base: String = TEXT) -> String {
        var out = ""
        for i in inlines(text) {
            switch i {
            case .plain(let s): out += esc(s)
            case .bold(let s): out += "<span style=\"color:#ffffff;font-weight:700\">\(esc(s))</span>"
            case .code(let s): out += "<span style=\"color:#fbbf24;font-family:Menlo,monospace\">\(esc(s))</span>"
            }
        }
        return "<span style=\"color:\(base)\">\(out)</span>"
    }

    public static func renderHTML(_ answer: String) -> String {
        var parts: [String] = []
        for b in parse(answer) {
            switch b {
            case .label(let key, let rest):
                let color = PALETTE[key]!
                let head = "<span style=\"color:\(color);font-weight:800;letter-spacing:1px\">\(esc(L(TITLES[key]!)))</span>"
                var body = ""
                if !rest.isEmpty {
                    if key == "confiance" {
                        body = " &nbsp;<span style=\"color:\(levelColor(rest, default: color));font-weight:700\">\(esc(rest.pyStrip("* ")))</span>"
                    } else { body = " &nbsp;" + inlineHTML(rest) }
                }
                parts.append("<p style=\"margin:12px 0 3px 0\">\(head)\(body)</p>")
            case .numbered(let accent, let num, let text):
                parts.append("<p style=\"margin:2px 0 2px 6px\"><span style=\"color:\(accent);font-weight:700\">\(num).</span> \(inlineHTML(text))</p>")
            case .bullet(let accent, let text):
                parts.append("<p style=\"margin:2px 0 2px 6px\"><span style=\"color:\(accent);font-weight:700\">&ndash;</span> \(inlineHTML(text))</p>")
            case .plain(let t):
                parts.append("<p style=\"margin:3px 0\">\(inlineHTML(t))</p>")
            }
        }
        return parts.joined()
    }
}
