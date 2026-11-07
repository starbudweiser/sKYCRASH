// Filet de sécurité sur les réponses de l'assistant IA, sans IA (src/guard.py) : retire les conseils qui
// contredisent la fiche d'installation vérifiée. Les motifs couvrent le français, l'anglais, l'italien et l'espagnol.

import Foundation

public enum Guard {
    static let ACTION = #"(?:install|t[ée]l[ée]charg|download|scaric|descarg|ajout|add|aggiung|añad|met(?:tre|s) en place)"#
    static let CHECK = #"(?:v[ée]rifi|check|controll|comprueb|verific|assur|ensure|make sure)"#

    struct Rule { let check: (Inventory) -> Bool; let rx: Rx; let label: String }
    static let RULES: [Rule] = [
        Rule(check: { $0.tool("crashlogger") }, rx: Rx(ACTION + #".{0,60}crash ?logger|crash ?logger.{0,40}"# + ACTION, i: true), label: "Crash Logger SSE"),
        Rule(check: { $0.tool("enginefixes") }, rx: Rx(ACTION + #".{0,60}engine ?fixes"#, i: true), label: "SSE Engine Fixes"),
        Rule(check: { $0.addressLibrary == true }, rx: Rx(#"(?:"# + ACTION + "|" + CHECK + #").{0,60}address ?library"#, i: true), label: "Address Library"),
        Rule(check: { $0.skseInstalled == true }, rx: Rx(ACTION + #".{0,40}\bskse(?:64)?\b(?!\s*plugin)"#, i: true), label: "SKSE"),
        Rule(check: { f in f.cc.map { $0.listed > 0 && $0.present >= $0.listed } ?? false },
             rx: Rx(#"creation ?club|\bcc\b.{0,30}(?:manquant|missing|mancant|falt)"#, i: true), label: "Creation Club"),
        Rule(check: { $0.plugins?.limitOk == true },
             rx: Rx(#"\b254\b|(?:limite?|limit)\b.{0,40}plugins?|plugins?.{0,40}(?:limite?|limit)\b"#, i: true), label: N_("limite de 254 plugins")),
    ]
    static let ITEM = Rx(#"^\s*(?:\d+[.)]|[-•*])\s+"#)
    static let NUMBERED = Rx(#"^(\s*)\d+([.)])(\s+)"#)
    static let CRASHLOGS_DIR = Rx(#"SKSE[\\/]+Crash ?logs[\\/]?"#, i: true)
    public static let JEV_LABEL = N_("contradiction avec les faits (Jev)")
    public static let JEV_THRESHOLD = 0.8
    public static let JEV_MAX_ITEMS = 20

    public typealias Judge = ([String], Inventory) throws -> [Bool]

    /// (réponse corrigée, libellés des conseils retirés)
    public static func apply(_ text: String, _ facts: Inventory?, judge: Judge? = nil) -> (String, [String]) {
        guard !text.isEmpty, let facts else { return (text, []) }
        let active = RULES.filter { $0.check(facts) }
        var removed: [String] = []
        let lines = text.pyLines
        var drop = Set<Int>()
        for (i, line) in lines.enumerated() where ITEM.match(line) != nil {
            if let hit = active.first(where: { $0.rx.test(line) })?.label {
                drop.insert(i)
                if !removed.contains(hit) { removed.append(hit) }
            }
        }
        if let judge {
            let todo = Array(lines.indices.filter { ITEM.match(lines[$0]) != nil && !drop.contains($0) }.prefix(JEV_MAX_ITEMS))
            let verdicts = (try? (todo.isEmpty ? [] : judge(todo.map { ITEM.sub("", lines[$0]).pyStrip }, facts))) ?? []
            for (i, bad) in zip(todo, verdicts) where bad {
                drop.insert(i)
                if !removed.contains(JEV_LABEL) { removed.append(JEV_LABEL) }
            }
        }
        let out = lines.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
        var n = 0
        var fixed: [String] = []
        for var line in out {
            if let m = NUMBERED.match(line) {
                n += 1
                let ns = line as NSString
                line = "\(m.group(1)!)\(n)\(m.group(2)!)\(m.group(3)!)" + ns.substring(from: m.end)
            } else if !line.pyIsBlank && ITEM.match(line) == nil {
                n = 0
            }
            fixed.append(line)
        }
        var result = fixed.joined(separator: "\n")
        if facts.tool("crashlogger") { result = CRASHLOGS_DIR.sub("SKSE/", result) }
        if !removed.isEmpty {
            result += "\n\n" + L("(sKYCRASH : {n} conseil(s) retiré(s), déjà en place ou vérifié : {l}.)",
                                 ["n": removed.count, "l": removed.map { L($0) }.joined(separator: ", ")])
        }
        return (result, removed)
    }

    /// Requête envoyée à Jev pour juger chaque conseil (construite sans envoi : testable).
    public static func jevRequest(_ items: [String], _ facts: Inventory) -> (state: J, questions: J) {
        let criteria: J = .obj([
            ("contradicts", .str("The advice asks to install, download, enable, verify or fix something that `installation_facts` shows is already installed, present or satisfied, or it states something about this installation (a version, a folder, a file's role) that `installation_facts` contradicts.")),
            ("consistent", .str("The advice agrees with `installation_facts` or builds on them.")),
            ("not_covered", .str("`installation_facts` says nothing about what this advice concerns.")),
        ])
        let questions: J = .obj(items.indices.map { i in
            ("c\(i)", .obj([("type", .str("choice")), ("criteria", criteria),
                            ("instructions", .str("How does the troubleshooting advice `advice[\(i)]` relate to the verified facts about this Skyrim installation in `installation_facts`?"))]))
        })
        let state: J = .obj([("installation_facts", .str(facts.toContext())), ("advice", .arr(items.map { .str($0) }))])
        return (state, questions)
    }

    /// Jev : chaque conseil contredit-il la fiche d'installation vérifiée ? (une Choice par conseil)
    public static func jevJudge(_ items: [String], _ facts: Inventory) throws -> [Bool] {
        let (state, questions) = jevRequest(items, facts)
        let answers = try JevClient.systemOne(state: state, questions: questions)
        return items.indices.map { i in
            guard let a = answers["c\(i)"], a["choice"]?.string == "contradicts" else { return false }
            return (a["probabilities"]?["contradicts"]?.doubleValue ?? 0) >= JEV_THRESHOLD
        }
    }

    /// `jevJudge` si une clé TypeSafe est disponible, sinon nil (motifs seuls).
    public static func defaultJudge() -> Judge? { JevClient.apiKey() != nil ? jevJudge : nil }
}
