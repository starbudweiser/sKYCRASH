// Modèles communs au moteur : constats, rapport, scores, dictionnaires ordonnés (comme les dict de Python).

import Foundation

public let SEV_CRIT = 3, SEV_WARN = 2, SEV_INFO = 1

/// Dictionnaire qui garde l'ordre d'insertion (un `dict` de Python).
public struct ODict<V> {
    public private(set) var keys: [String] = []
    private var map: [String: V] = [:]
    public init() {}
    public subscript(_ k: String) -> V? {
        get { map[k] }
        set {
            if let nv = newValue {
                if map[k] == nil { keys.append(k) }
                map[k] = nv
            } else if map[k] != nil {
                map[k] = nil
                keys.removeAll { $0 == k }
            }
        }
    }
    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }
    public var values: [V] { keys.map { map[$0]! } }
    public var items: [(String, V)] { keys.map { ($0, map[$0]!) } }
    public func has(_ k: String) -> Bool { map[k] != nil }
}

public struct Finding {
    public var severity: Int
    public var category: String
    public var title: String
    public var detail: String
    public var source: String
    public var evidence: [String]
    public var suggestion: String
    public init(_ severity: Int, _ category: String, _ title: String, _ detail: String = "", _ source: String = "",
                _ evidence: [String] = [], _ suggestion: String = "") {
        self.severity = severity; self.category = category; self.title = title
        self.detail = detail; self.source = source; self.evidence = evidence; self.suggestion = suggestion
    }
}

public struct Suspect {
    public var name: String
    public var score: Int
    public var reasons: [String]
}

/// Scores des suspects : nom -> (points, raisons), dans l'ordre de première apparition.
public final class Scores {
    struct Entry { var score = 0; var reasons: [String] = [] }
    var d = ODict<Entry>()
    public init() {}
    public func bump(_ name: String, _ pts: Int, _ reason: String) {
        var e = d[name] ?? Entry()
        e.score += pts
        if !e.reasons.contains(reason) { e.reasons.append(reason) }
        d[name] = e
    }
    var sortedItems: [(String, Int, [String])] {
        d.items.map { ($0.0, $0.1.score, $0.1.reasons) }.stableSorted { $0.1 > $1.1 }
    }
}

/// Informations lues dans skse64.log.
public struct SkseInfo {
    public var checked: [String] = []
    public var loaded: [String: (String, Int)] = [:]
    public var pluginDir: String?
    public var loadedCount: Int { loaded.count }
}

public struct CrashSummary {
    public var path: String
    public var time: Wall?
    public var `where`: String
    public var uptime: Int?
    public var objects: [String]
    public var skse: Set<String>
    public var plugins: [String]
}

public struct SaveExtra {
    public var path: String
    public var player: String
    public var location: String
    public var savedAt: Wall
    public var count: Int
    public var missing: [String]
    public var added: [String]
    public var pluginsTxt: String?
}

public struct DomainsExtra {
    public var labels: String
    public var dlls: [(String, Int)]
    public var plugins: [String]
}

public struct SkseDiff {
    public var since: Wall
    public var added: [String]
    public var removed: [String]
}

public struct TimelineEntry {
    public var at: Wall
    public var label: String
    public var src: String
}

/// Recoupements gardés pour l'export et le dossier de diagnostic.
public struct Extras {
    public var history: [CrashSummary]?
    public var timeline: [TimelineEntry]?
    public var skseDiff: SkseDiff?
    public var save: SaveExtra?
    public var domains: DomainsExtra?
    public var inventory: Inventory?
    public var gameDirFound: String?
    public init() {}
}

public final class AuditReport {
    public var findings: [Finding] = []
    public var suspects: [Suspect] = []
    public var analysed: [String] = []
    public var excerpts = ODict<String>()
    public var verdict = ""
    public var gameDir = ""
    public var skseInfo: SkseInfo?
    public var skseRuntime = ""
    public var extras = Extras()
    public init() {}

    public func toMarkdown() -> String {
        var out = [L("# Audit — verdict : {verdict}", ["verdict": verdict]), ""]
        if !suspects.isEmpty {
            out.append(L("## Suspects classés"))
            for (i, s) in suspects.enumerated() {
                out.append("\(i + 1). **\(s.name)** (score \(s.score)) — " + s.reasons.prefix(3).joined(separator: "; "))
            }
            out.append("")
        }
        out.append(L("## Constats"))
        for f in findings.stableSorted(by: { $0.severity > $1.severity }) {
            out.append("- [\(sevLabel(f.severity))] (\(f.category)) \(f.title) — \(f.source)")
            if !f.detail.isEmpty { out.append("    \(f.detail)") }
            for e in f.evidence.prefix(3) { out.append("    > \(e)") }
            if !f.suggestion.isEmpty { out.append(L("    Piste : {tip}", ["tip": f.suggestion])) }
        }
        return out.joined(separator: "\n")
    }

    public func toContext(maxChars: Int = 60000) -> String {
        let facts = extras.inventory.map { $0.toContext() } ?? ""
        var parts = (facts.isEmpty ? [] : [facts, ""]) + [toMarkdown(), "", L("## Extraits de logs")]
        for (path, text) in excerpts.items {
            parts.append("### \(PyFS.basename(path))\n\(text)")
        }
        return parts.joined(separator: "\n").pyPrefix(maxChars)
    }
}

public func sevLabel(_ sev: Int) -> String {
    switch sev {
    case SEV_CRIT: return L("CRITIQUE")
    case SEV_WARN: return L("AVERTISSEMENT")
    default: return L("INFO")
    }
}
