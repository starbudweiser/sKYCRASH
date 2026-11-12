// Auto-alimentation de la base de connaissances (veille crashs Skyrim moddé) : traduction de src/knowledge_updater.py.
// Sources en liste blanche de domaines, HTTPS uniquement, aucune clé. Les notes sont des DONNÉES externes non fiables :
// texte nettoyé, lignes de type « prompt injection » retirées, taille bornée.

import Foundation

public enum KnowledgeUpdater {
    public static let STATE_NAME = "_state.json"
    public static let UA = "SkyrimCrashAnalyzer/1.0 (+local knowledge updater)"
    public static let ALLOWED_HOSTS: Set<String> = ["api.github.com", "api.steampowered.com", "www.reddit.com", "skse.silverlock.org", "www.codeweavers.com"]
    public static let TIMEOUT_S = 15.0
    public static let MAX_BYTES = 1_500_000
    public static let MAX_NOTE_CHARS = 6000
    public static let DEFAULT_INTERVAL_H = 24.0
    public static let LAUNCH_INTERVAL_H = 1.0
    public static let PERIODIC_INTERVAL_H = 6.0
    public static let SLOW_HOSTS = ["www.reddit.com": 6.0]
    public static let STEAM_APPID = 489830

    public enum Failure: Error { case update(String), rateLimited(String)
        public var message: String { switch self { case .update(let m), .rateLimited(let m): return m } }
    }

    public struct Source {
        public let id: String, kind: String, target: String, title: String, keywords: [String]
        init(_ id: String, _ kind: String, _ target: String, _ title: String, _ keywords: [String] = []) {
            self.id = id; self.kind = kind; self.target = target; self.title = title; self.keywords = keywords
        }
    }

    public static let SOURCES: [Source] = [
        Source("gh_crashlogger_releases", "github_releases", "alandtse/CrashLoggerSSE", "Crash Logger SSE — versions récentes", ["crash logger", "crashlogger", "crash-"]),
        Source("gh_crashlogger_issues", "github_issues", "alandtse/CrashLoggerSSE", "Crash Logger SSE — problèmes signalés", ["crash logger", "crashlogger"]),
        Source("gh_cs_releases", "github_releases", "community-shaders/skyrim-community-shaders", "Community Shaders — versions récentes", ["community shaders", "communityshaders", "shadercache"]),
        Source("gh_cs_issues", "github_issues", "community-shaders/skyrim-community-shaders", "Community Shaders — crashs signalés", ["community shaders", "communityshaders", "shadercache"]),
        Source("gh_papyrusextender", "github_releases", "powerof3/PapyrusExtenderSSE", "PapyrusExtender — versions récentes", ["papyrusextender", "papyrus extender", "po3_papyrusextender"]),
        Source("gh_baseobjectswapper", "github_releases", "powerof3/BaseObjectSwapper", "Base Object Swapper — versions récentes", ["baseobjectswapper", "base object swapper"]),
        Source("gh_skse", "github_releases", "ianpatt/skse64", "SKSE64 — versions publiées", ["skse64", "skse", "address library"]),
        Source("gh_loot", "github_releases", "loot/loot", "LOOT — versions récentes", ["loot", "masterlist", "load order"]),
        Source("gh_mo2", "github_releases", "ModOrganizer2/modorganizer", "Mod Organizer 2 — versions récentes", ["mo2", "mod organizer", "usvfs"]),
        Source("gh_mo2_issues", "github_issues", "ModOrganizer2/modorganizer", "Mod Organizer 2 — crashs signalés", ["mo2", "mod organizer", "usvfs"]),
        Source("gh_wabbajack", "github_releases", "wabbajack-tools/wabbajack", "Wabbajack — versions récentes", ["wabbajack"]),
        Source("gh_enginefixes", "github_releases", "aers/EngineFixesSkyrim64", "SSE Engine Fixes — versions récentes", ["enginefixes", "engine fixes", "tbbmalloc", "enginefixes.toml"]),
        Source("gh_enginefixes_issues", "github_issues", "aers/EngineFixesSkyrim64", "SSE Engine Fixes — crashs signalés", ["enginefixes", "engine fixes", "tbbmalloc"]),
        Source("gh_spid", "github_releases", "powerof3/Spell-Perk-Item-Distributor", "Spell Perk Item Distributor (SPID) — versions récentes", ["po3_spellperkitemdistributor", "spid", "_distr.ini"]),
        Source("gh_kid", "github_releases", "powerof3/Keyword-Item-Distributor", "Keyword Item Distributor (KID) — versions récentes", ["po3_keyworditemdistributor", "_kid.ini"]),
        Source("gh_dxmt", "github_releases", "3Shain/dxmt", "DXMT (Direct3D 11 sur Metal, CrossOver) — versions récentes", ["dxmt", "d3d11.dll", "metal", "crossover"]),
        Source("gh_dxvk", "github_releases", "doitsujin/dxvk", "DXVK (Direct3D sur Vulkan) — versions récentes", ["dxvk", "d3d11.dll", "dxgi.dll", "vulkan"]),
        Source("steam_skyrim", "steam_news", String(STEAM_APPID), "Skyrim SE/AE — annonces de mises à jour (Steam)", ["skyrimse.exe", "address library", "versionlib"]),
        Source("reddit_crash", "reddit_rss", "CTD OR crash", "r/skyrimmods — fils récents sur les crashs", []),
        Source("reddit_mac", "reddit_rss", "macgaming:skyrim", "r/macgaming — Skyrim sur Mac (CrossOver, GPTK)", ["crossover", "wine", "virtualapple", "d3dmetal", "dxmt"]),
        Source("crossover_changelog", "crossover_changelog", "https://www.codeweavers.com/crossover/changelog", "CrossOver — journal des versions (CodeWeavers)", ["crossover", "wine", "virtualapple", "d3dmetal", "dxmt", "moltenvk"]),
        Source("skse_site", "skse_site", "https://skse.silverlock.org/", "SKSE — page officielle des versions", ["skse", "skse64", "runtime", "address library"]),
    ]

    // MARK: nettoyage

    static let INJECTION = Rx(#"(ignore|disregard|forget)\s+(all\s+|any\s+)?(previous|prior|above|earlier)\s+(instructions?|prompts?)|system\s+prompt|you\s+are\s+now\b|nouvelle?s?\s+instructions?\s*:|ignore\s+les\s+instructions"#, i: true)
    static let TAG = Rx(#"<[^>]+>"#)
    static let MDLINK = Rx(#"\[([^\]]*)\]\((?:[^)]*)\)"#)
    static let URLRX = Rx(#"https?://\S+"#)
    static let CTRL = Rx(#"[\x00-\x08\x0b-\x1f\x7f]"#)
    static let DLL = Rx(#"\b([A-Za-z0-9_+\-]{4,60})\.dll\b"#, i: true)
    static let VER = Rx(#"\b1\.[56]\.\d{2,4}\b"#)
    static let MD_CHARS = Rx(#"[#>*_|]+"#)
    static let WS = Rx(#"\s+"#)

    /// Texte brut sûr et court : sans HTML/URL/Markdown lourd, sans lignes d'injection.
    public static func clean(_ text: String, _ limit: Int = 400) -> String {
        var t = HTMLEntities.unescape(text)
        t = TAG.sub(" ", t)
        t = MDLINK.sub("$1", t)
        t = URLRX.sub("", t)
        t = CTRL.sub(" ", t)
        t = t.replacingOccurrences(of: "`", with: "'").replacingOccurrences(of: "---", with: "—")
        var lines: [String] = []
        for var ln in t.pyLines {
            ln = MD_CHARS.sub(" ", ln)
            ln = WS.sub(" ", ln).pyStrip
            if ln.isEmpty { continue }
            if INJECTION.test(ln) { ln = "[ligne retirée]" }
            lines.append(ln)
        }
        let out = lines.joined(separator: " ")
        return out.pyPrefix(limit).pyRStrip + (out.pyLen > limit ? "…" : "")
    }

    /// Noms de DLL (avec et sans extension) et versions du jeu cités dans les textes.
    public static func extractKeywords(_ texts: [String]) -> [String] {
        var kws: [String] = []
        for t in texts {
            for m in DLL.finditer(t) {
                let stem = m.group(1)!.lowercased()
                kws.append(stem + ".dll")
                if stem.pyLen >= 6 { kws.append(stem) }
            }
            kws.append(contentsOf: VER.findall(t))
        }
        return Array(uniqueKeepingOrder(kws).prefix(40))
    }

    // MARK: HTTP

    /// `urllib.parse.quote` (« / » conservé).
    public static func quote(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-~/")) ?? s
    }

    static func checkURL(_ url: URL?) throws {
        guard let u = url, u.scheme == "https", let h = u.host, ALLOWED_HOSTS.contains(h) else {
            throw Failure.update("URL non autorisée : \(url?.host ?? "None")")
        }
    }

    public typealias Fetch = (String, String?, String) throws -> (Int, Data, String?)

    /// GET borné. Retourne (statut, corps, etag). 304 → corps vide.
    public static func httpGet(_ urlString: String, _ etag: String?, _ accept: String = "application/json") throws -> (Int, Data, String?) {
        let url = URL(string: urlString)
        try checkURL(url)
        var req = URLRequest(url: url!)
        req.setValue(UA, forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty, url!.host == "api.github.com" {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let r = try HTTP.send(req, timeout: TIMEOUT_S, maxBytes: MAX_BYTES)
            try checkURL(r.finalURL)
            return (r.status, r.body, r.headers["etag"])
        } catch let e as HTTPFailure {
            switch e.kind {
            case .status(let code, _):
                if code == 304 { return (304, Data(), etag) }
                if code == 403 || code == 429 { throw Failure.rateLimited("quota ou accès refusé (\(code))") }
                if code == -1 { throw Failure.update("réponse trop volumineuse") }
                throw Failure.update("HTTP \(code)")
            case .connection(let m), .timeout(let m): throw Failure.update("réseau : \(m)")
            }
        }
    }

    static func json(_ body: Data) throws -> J {
        guard let j = J.parse(data: Data(String(decoding: body, as: UTF8.self).utf8)) else { throw Failure.update("JSON illisible") }
        return j
    }
    static func date(_ s: J?) -> String {
        switch s {
        case .some(.str(let v)): return v.pyPrefix(10)
        case .some(.null), .none: return ""
        case .some(let o): return o.dump().pyPrefix(10)
        }
    }
    static func jstr(_ j: J?) -> String {
        switch j {
        case .some(.str(let s)): return s
        case .some(.int(let i)): return String(i)
        case .some(.null), .none: return "None"
        case .some(let o): return o.dump()
        }
    }
    static func truthy(_ j: J?) -> Bool {
        switch j {
        case .some(.str(let s)): return !s.isEmpty
        case .some(.int(let i)): return i != 0
        case .some(.bool(let b)): return b
        case .some(.arr(let a)): return !a.isEmpty
        case .some(.obj(let o)): return !o.isEmpty
        default: return false
        }
    }
    /// `x.get(k) or y.get(k2) or ""`
    static func firstTruthy(_ items: J?...) -> String {
        for i in items where truthy(i) { return jstr(i) }
        return ""
    }

    // MARK: analyseurs

    static let PR_TAG = Rx(#"(?:^|[-_.])pr\d+|nightly|dev\b"#, i: true)

    public static func parseGithubReleases(_ body: Data) throws -> [String] {
        var items: [String] = []
        for r in try json(body).array?.prefix(12) ?? [] {
            let tag = clean(jstr(r["tag_name"]).replacingOccurrences(of: "None", with: r["tag_name"] == nil ? "" : "None"), 40)
            if tag.isEmpty || PR_TAG.test(tag) { continue }
            var pre = ""
            if case .bool(true)? = r["prerelease"] { pre = " [préversion]" }
            items.append("\(tag) (\(date(r["published_at"])))\(pre) : \(clean(firstTruthy(r["body"], r["name"]), 380))")
            if items.count >= 4 { break }
        }
        return items
    }

    public static func parseGithubIssues(_ body: Data) throws -> [String] {
        let data = try json(body)
        var items: [String] = []
        let list: [J] = data.object != nil ? (data["items"]?.array ?? []) : (data.array ?? [])
        for it in list {
            if it["pull_request"] != nil { continue }
            let labels = (it["labels"]?.array ?? []).prefix(4).map { clean(jstr($0["name"] ?? .str("")), 20) }.joined(separator: ",")
            items.append("#\(jstr(it["number"])) [\(jstr(it["state"]))] \(clean(jstr(it["title"] ?? .str("")), 140)) (\(date(it["updated_at"]))\(labels.isEmpty ? "" : ", " + labels)) : \(clean(firstTruthy(it["body"]), 220))")
            if items.count >= 8 { break }
        }
        return items
    }

    static let STEAM_RELEVANT = Rx(#"update|patch|hotfix|fix|crash|version|\b1\.[56]\.\d+"#, i: true)

    public static func parseSteamNews(_ body: Data) throws -> [String] {
        var items: [String] = []
        for n in (try json(body)["appnews"]?["newsitems"]?.array ?? []).prefix(25) {
            let text = "\(jstr(n["title"] ?? .str(""))) \(jstr(n["contents"] ?? .str("")))"
            if !STEAM_RELEVANT.test(text) { continue }
            var d = ""
            if let ts = n["date"]?.intValue, ts != 0 { d = utcDate(Double(ts)) }
            items.append("\(d) \(clean(jstr(n["title"] ?? .str("")), 140)) : \(clean(jstr(n["contents"] ?? .str("")), 300))")
            if items.count >= 6 { break }
        }
        return items
    }

    static func utcDate(_ ts: Double) -> String {
        var t = time_t(ts), tmv = tm()
        gmtime_r(&t, &tmv)
        return String(format: "%04d-%02d-%02d", Int(tmv.tm_year) + 1900, Int(tmv.tm_mon) + 1, Int(tmv.tm_mday))
    }

    static let REDDIT_RELEVANT = Rx(#"crash|ctd|freez|won'?t (launch|start)|black screen|access violation|\.dll"#, i: true)
    static let DTD = Rx(#"<!(DOCTYPE|ENTITY)"#, i: true)

    final class AtomParser: NSObject, XMLParserDelegate {
        struct Entry { var title = "", content = "", updated = "" }
        var entries: [Entry] = []
        private var depth = 0
        private var current: Entry?
        private var field: String?
        private var buf = ""
        private var seenFirstChild = false
        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            let atom = namespaceURI == "http://www.w3.org/2005/Atom"
            if depth == 2 && atom && name == "entry" { current = Entry() }
            else if depth == 3, current != nil, atom, ["title", "content", "updated"].contains(name) { field = name; buf = ""; seenFirstChild = false }
            else if field != nil { seenFirstChild = true }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if field != nil && !seenFirstChild { buf += s } }
        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if depth == 3, let f = field, current != nil {
                switch f { case "title": current!.title = buf; case "content": current!.content = buf; default: current!.updated = buf }
                field = nil
            }
            if depth == 2, let c = current { entries.append(c); current = nil }
            depth -= 1
        }
    }

    public static func parseRedditRSS(_ body: Data) throws -> [String] {
        let raw = String(decoding: body, as: UTF8.self)
        if DTD.test(raw) { throw Failure.update("flux XML refusé (DTD)") }
        let parser = XMLParser(data: Data(raw.utf8))
        parser.shouldProcessNamespaces = true
        let delegate = AtomParser()
        parser.delegate = delegate
        guard parser.parse() else { throw Failure.update("flux RSS illisible") }
        var items: [String] = []
        for e in delegate.entries.prefix(25) {
            if !REDDIT_RELEVANT.test(e.title + " " + e.content) { continue }
            items.append("\(e.updated.pyPrefix(10)) \(clean(e.title, 150)) : \(clean(e.content, 260))")
            if items.count >= 8 { break }
        }
        return items
    }

    static let CX_VERSION = Rx(#"<a name="([\d.]+)"></a>\s*<span[^>]*>(.*?)</span>(.*?)(?=<a name="|$)"#, s: true)
    static let CX_ITEM = Rx(#"<li>(?!\s*<span)(.*?)</li>"#, s: true)
    static let CX_RELEVANT = Rx(#"skyrim|bethesda|direct3d|d3d1[01]|dxmt|d3dmetal|metal|crash|freeze|hang"#, i: true)

    /// Les 6 dernières versions de CrossOver, avec en priorité les correctifs utiles (D3D, Metal, crash, Skyrim).
    public static func parseCrossoverChangelog(_ body: Data) throws -> [String] {
        let raw = String(decoding: body, as: UTF8.self)
        var items: [String] = []
        for m in CX_VERSION.finditer(raw).prefix(6) {
            let head = clean(m.group(2)!, 80)
            let fixes = CX_ITEM.findall(m.group(3)!).map { clean($0, 160) }.filter { !$0.isEmpty }
            var useful = fixes.filter { CX_RELEVANT.test($0) }
            if useful.isEmpty { useful = Array(fixes.prefix(2)) }
            items.append("\(head) : " + useful.prefix(4).joined(separator: " ; "))
        }
        return items
    }

    static let SKSE_LINE = Rx(#"(skyrim|runtime|build|skse).*\d+\.\d+\.\d+|\d+\.\d+\.\d+.*(skyrim|runtime|build)"#, i: true)

    public static func parseSkseSite(_ body: Data) throws -> [String] {
        let text = TAG.sub("\n", String(decoding: body, as: UTF8.self))
        var out: [String] = []
        for l in text.pyLines {
            let ln = clean(l, 200)
            if !ln.isEmpty && SKSE_LINE.test(ln) && !out.contains(ln) { out.append(ln) }
            if out.count >= 12 { break }
        }
        return out
    }

    // MARK: sources

    static func request(for src: Source) throws -> (String, String, (Data) throws -> [String]) {
        switch src.kind {
        case "github_releases":
            return ("https://api.github.com/repos/\(src.target)/releases?per_page=8", "application/vnd.github+json", parseGithubReleases)
        case "github_issues":
            let q = "repo:\(src.target) is:issue (crash OR CTD OR freeze) in:title"
            return ("https://api.github.com/search/issues?sort=updated&per_page=10&q=" + quote(q), "application/vnd.github+json", parseGithubIssues)
        case "steam_news":
            return ("https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=\(Int(src.target)!)&count=25&maxlength=500", "application/json", parseSteamNews)
        case "reddit_rss":
            let parts = src.target.components(separatedBy: ":")
            let sub = parts.count > 1 ? parts.dropLast().joined(separator: ":") : ""
            let query = parts.last!
            return ("https://www.reddit.com/r/\(sub.isEmpty ? "skyrimmods" : sub)/search.rss?restrict_sr=1&sort=new&q=" + quote(query), "application/atom+xml", parseRedditRSS)
        case "crossover_changelog": return (src.target, "text/html", parseCrossoverChangelog)
        case "skse_site": return (src.target, "text/html", parseSkseSite)
        default: throw Failure.update("type de source inconnu : \(src.kind)")
        }
    }

    public static func renderNote(_ src: Source, _ items: [String], _ fetched: String) -> String {
        let kws = uniqueKeepingOrder(src.keywords + extractKeywords(items))
        let body = items.map { "- \($0)" }.joined(separator: "\n")
        let note = "---\ntitle: Veille — \(src.title)\nkeywords: \(kws.joined(separator: ", "))\nauto: true\n"
            + "updated: \(fetched)\n---\n"
            + "Source externe automatique (\(fetched)), NON vérifiée : indice à recouper avec les logs.\n\(body)\n"
        return note.pyPrefix(MAX_NOTE_CHARS)
    }

    // MARK: état

    static func statePath(_ dir: String) -> String { PyFS.join(dir, STATE_NAME) }

    public static func loadState(_ dir: String? = nil) -> J {
        if let t = PyFS.readText(statePath(dir ?? AppPaths.knowledgeDir)), let j = J.parse(t), j.object != nil { return j }
        return .obj([])
    }

    static func saveState(_ dir: String, _ state: J) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? state.dump(compact: false, indent: 1, ascii: true).write(toFile: statePath(dir), atomically: false, encoding: .utf8)
    }

    public static func due(intervalH: Double = DEFAULT_INTERVAL_H, dir: String? = nil, now: Double? = nil) -> Bool {
        let last = loadState(dir)["last_run"]?.doubleValue ?? 0
        return ((now ?? Date().timeIntervalSince1970) - last) >= intervalH * 3600
    }

    public struct Status { public var lastRun: Double?; public var files: Int; public var dir: String }

    public static func status(_ dir: String? = nil) -> Status {
        let d = dir ?? AppPaths.knowledgeDir
        let n = (PyFS.listdir(d) ?? []).filter { $0.hasPrefix("auto_") && $0.hasSuffix(".md") }.count
        return Status(lastRun: loadState(d)["last_run"]?.doubleValue, files: n, dir: d)
    }

    public struct Report {
        public var updated: [String] = []
        public var unchanged: [String] = []
        public var failed = ODict<String>()
        public var skipped = false
    }

    nonisolated(unsafe) static let lock = NSLock()

    /// Récupère les sources et réécrit les notes. Tolérant : une source en échec n'arrête pas les autres.
    public static func updateAll(dir: String? = nil, force: Bool = false, sources: [Source]? = nil, fetch: Fetch = httpGet,
                                 progress: ((_ done: Int, _ total: Int, _ title: String) -> Void)? = nil, sleep: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> Report {
        let out = dir ?? AppPaths.knowledgeDir
        var rep = Report()
        if !lock.try() { rep.skipped = true; return rep }
        defer { lock.unlock() }
        let srcList = sources ?? SOURCES
        var root = ODict<J>()
        for (k, v) in loadState(out).object ?? [] { root[k] = v }
        var etags = ODict<String>()
        for (k, v) in root["etags"]?.object ?? [] { if let s = v.string { etags[k] = s } }
        var srcs = ODict<J>()
        for (k, v) in root["sources"]?.object ?? [] { srcs[k] = v }
        func sync() {
            root["etags"] = .obj(etags.items.map { ($0.0, J.str($0.1)) })
            root["sources"] = .obj(srcs.items)
        }
        sync()
        let now = utcDate(Date().timeIntervalSince1970)
        var blocked = Set<String>()
        var lastCall: [String: Double] = [:]
        do { try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true) } catch {
            rep.failed["*"] = "dossier inaccessible : \(error.localizedDescription)"
            return rep
        }
        func st(_ ok: Bool, _ extra: [(String, J)]) -> J { .obj([("ok", .bool(ok))] + extra) }
        for (i, src) in srcList.enumerated() {
            progress?(i, srcList.count, src.title)
            defer { progress?(i + 1, srcList.count, src.title) }
            var host = ""
            do {
                let (url, accept, parser) = try request(for: src)
                host = URL(string: url)?.host ?? ""
                if blocked.contains(host) { throw Failure.rateLimited("hôte ignoré (quota atteint)") }
                if let slow = SLOW_HOSTS[host], let lc = lastCall[host] { sleep(max(0, slow - (Date().timeIntervalSince1970 - lc))) }
                lastCall[host] = Date().timeIntervalSince1970
                let path = PyFS.join(out, "auto_\(src.id).md")
                let (code, body, etag) = try fetch(url, (force || !PyFS.exists(path)) ? nil : etags[url], accept)
                if code == 304 {
                    rep.unchanged.append(src.id)
                    srcs[src.id] = st(true, [("fetched", .double(Date().timeIntervalSince1970)), ("count", srcs[src.id]?["count"] ?? .int(0))])
                    continue
                }
                let items = try parser(body)
                if items.isEmpty {
                    rep.unchanged.append(src.id)
                    srcs[src.id] = st(true, [("fetched", .double(Date().timeIntervalSince1970)), ("count", .int(0))])
                    continue
                }
                let tmp = path.replacingOccurrences(of: ".md", with: ".tmp")
                try renderNote(src, items, now).write(toFile: tmp, atomically: false, encoding: .utf8)
                _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
                if let etag { etags[url] = etag }
                rep.updated.append(src.id)
                srcs[src.id] = st(true, [("fetched", .double(Date().timeIntervalSince1970)), ("count", .int(items.count))])
            } catch let e as Failure {
                if case .rateLimited = e, let u = try? request(for: src).0, let h = URL(string: u)?.host { blocked.insert(h) }
                rep.failed[src.id] = e.message
                srcs[src.id] = st(false, [("error", .str(e.message)), ("fetched", .double(Date().timeIntervalSince1970))])
            } catch {
                rep.failed[src.id] = error.localizedDescription
                srcs[src.id] = st(false, [("error", .str(error.localizedDescription)), ("fetched", .double(Date().timeIntervalSince1970))])
            }
            sleep(0.15)
        }
        if rep.failed.count < srcList.count { root["last_run"] = .double(Date().timeIntervalSince1970) }
        sync()
        saveState(out, .obj(root.items))
        return rep
    }
}

/// `html.unescape` de Python : entités numériques et nommées courantes (avec ou sans « ; » pour les entités historiques).
enum HTMLEntities {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{a0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "bull": "•", "middot": "·", "times": "×", "deg": "°", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§",
        "para": "¶", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "check": "✓", "star": "☆", "iexcl": "¡", "iquest": "¿",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç",
        "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë", "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï",
        "ntilde": "ñ", "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø", "ugrave": "ù",
        "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "yuml": "ÿ", "szlig": "ß",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å", "AElig": "Æ", "Ccedil": "Ç",
        "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë", "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï",
        "Ntilde": "Ñ", "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø", "Ugrave": "Ù",
        "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "Yacute": "Ý",
    ]
    /// Entités acceptées sans point-virgule (HTML historique).
    static let legacy: Set<String> = ["amp", "lt", "gt", "quot", "nbsp", "copy", "reg", "deg", "pound", "yen", "cent", "sect", "para", "middot", "times",
        "laquo", "raquo", "iexcl", "iquest", "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc",
        "euml", "igrave", "iacute", "icirc", "iuml", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "oslash", "ugrave", "uacute", "ucirc",
        "uuml", "yacute", "yuml", "szlig", "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc",
        "Euml", "Igrave", "Iacute", "Icirc", "Iuml", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "Oslash", "Ugrave", "Uacute", "Ucirc",
        "Uuml", "Yacute"]
    static let rx = Rx(#"&(#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\t\n\f <&#;]{1,32};?)"#)
    static let cp1252: [Int: UInt32] = [0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
        0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022,
        0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178]

    static func unescape(_ s: String) -> String {
        if !s.contains("&") { return s }
        return rx.sub(s) { m in
            let whole = m.group(0)!
            let body = m.group(1)!
            if body.hasPrefix("#") {
                let hex = body.dropFirst().first == "x" || body.dropFirst().first == "X"
                let digits = body.dropFirst(hex ? 2 : 1).replacingOccurrences(of: ";", with: "")
                guard let n = Int(digits, radix: hex ? 16 : 10) else { return whole }
                if let r = cp1252[n] { return String(Unicode.Scalar(r)!) }
                if n == 0 || (0xD800...0xDFFF).contains(n) || n > 0x10FFFF { return "\u{FFFD}" }
                if (0x1...0x8).contains(n) || (0xE...0x1F).contains(n) || (0x7F...0x9F).contains(n) || n == 0xB { return "" }
                return Unicode.Scalar(n).map { String($0) } ?? "\u{FFFD}"
            }
            if body.hasSuffix(";"), let v = named[String(body.dropLast())] { return v }
            // entité historique sans « ; » : le plus long préfixe connu
            for len in stride(from: min(body.count, 6), through: 2, by: -1) {
                let p = String(body.prefix(len))
                if legacy.contains(p), let v = named[p] { return v + body.dropFirst(len) }
            }
            return whole
        }
    }
}
