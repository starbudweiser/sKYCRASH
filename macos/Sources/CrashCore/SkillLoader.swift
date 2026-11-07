// Fiches de connaissances (skills) modding Skyrim injectées dans le prompt de l'IA (src/skill_loader.py).

import Foundation

public enum SkillLoader {
    public static let MAX_SKILLS_CHARS = 15000
    public static let MAX_AUTO_CHARS = 4500
    static let MAX_FILE_BYTES = 64 * 1024

    /// Dossier « data » (skills/ et knowledge_seed/) : dans l'appli, Contents/Resources/data ; SKYRIM_CA_DATA_DIR pour les essais.
    nonisolated(unsafe) public static var dataDir: String = {
        if let o = ProcessInfo.processInfo.environment["SKYRIM_CA_DATA_DIR"], !o.isEmpty { return o }
        if let r = Bundle.main.resourcePath, PyFS.isDir(PyFS.join(r, "data")) { return PyFS.join(r, "data") }
        return "data"
    }()
    public static var bundledDir: String { PyFS.join(dataDir, "skills") }
    public static var seedDir: String { PyFS.join(dataDir, "knowledge_seed") }

    public struct Skill {
        public var title: String
        public var keywords: [String]
        public var always: Bool
        public var auto: Bool
        public var body: String
    }

    static func parse(_ text: String, fallbackTitle: String) -> Skill {
        var meta: [String: String] = [:]
        var body = text
        if text.hasPrefix("---") {
            let ns = text as NSString
            let r = ns.range(of: "\n---", options: [], range: NSRange(location: 3, length: ns.length - 3))
            if r.location != NSNotFound {
                for line in ns.substring(with: NSRange(location: 3, length: r.location - 3)).pyLines {
                    if let i = line.firstIndex(of: ":") {
                        meta[String(line[..<i]).pyStrip.lowercased()] = String(line[line.index(after: i)...]).pyStrip
                    }
                }
                body = ns.substring(from: r.location + 4).pyLStrip("\n")
            }
        }
        let keywords = (meta["keywords"] ?? "").components(separatedBy: ",").map { $0.pyStrip.lowercased() }.filter { !$0.isEmpty }
        func flag(_ k: String) -> Bool { ["1", "true", "oui", "yes"].contains((meta[k] ?? "").lowercased()) }
        let title = (meta["title"] ?? "").isEmpty ? fallbackTitle : meta["title"]!
        return Skill(title: title, keywords: keywords, always: flag("always"), auto: flag("auto"), body: body.pyStrip)
    }

    /// {nom_de_fichier: fiche}. Les dossiers suivants écrasent les précédents.
    public static func loadSkills(extraDirs: [String] = []) -> ODict<Skill> {
        var skills = ODict<Skill>()
        for d in [bundledDir, seedDir, AppPaths.knowledgeDir, AppPaths.skillsDir] + extraDirs {
            guard let names = PyFS.listdir(d) else { continue }
            for n in pySorted(names.filter { $0.hasSuffix(".md") }) {
                let p = PyFS.join(d, n)
                guard let size = PyFS.size(p), size <= MAX_FILE_BYTES, let t = PyFS.readText(p) else { continue }
                skills[n] = parse(t, fallbackTitle: PyFS.splitext(n).0)
            }
        }
        return skills
    }

    /// Texte des fiches pertinentes (toujours-actives + mots-clés trouvés), borné en taille.
    public static func selectSkills(_ context: String, _ question: String = "", skills: ODict<Skill>? = nil,
                                    maxChars: Int = MAX_SKILLS_CHARS, maxAutoChars: Int = MAX_AUTO_CHARS) -> String {
        let skills = skills ?? loadSkills()
        let hay = (context + "\n" + question).lowercased()
        var scored: [(Int, Int, String, Skill)] = []
        for (name, s) in skills.items {
            let hits = s.keywords.filter { hay.contains($0) }.count
            if s.auto {
                if hits > 0 { scored.append((2, -hits, name, s)) }
            } else if s.always || hits > 0 {
                scored.append((s.always ? 0 : 1, -hits, name, s))
            }
        }
        scored = scored.stableSorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            return pyLess(a.2, b.2)
        }
        var out: [String] = []
        var used = 0, usedAuto = 0
        for (_, _, _, s) in scored {
            let block = "### \(s.title)\n\(s.body)"
            if used + block.pyLen > maxChars { continue }
            if s.auto {
                if usedAuto + block.pyLen > min(maxAutoChars, maxChars / 3) { continue }
                usedAuto += block.pyLen
            }
            out.append(block)
            used += block.pyLen
        }
        return out.joined(separator: "\n\n")
    }
}
