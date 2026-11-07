// Compatibilité jeu / SKSE / plugins et corrélation avec l'installation de Skyrim : traduction de src/compat.py.

import Foundation

public enum Compat {
    public static let BOTTLES_GLOB = PyFS.expanduser("~/Library/Application Support/CrossOver/Bottles/*")
    public static let MAX_EXE_BYTES = 80 * 1024 * 1024
    public static let MAX_PLUGINS_NON_ESL = 254
    static let NON_PLUGIN_DLLS: Set<String> = ["msdia140.dll"]

    static let CHECK_RE = Rx(#"checking plugin (.+?\.dll)\s*$"#, i: true)
    static let LOADED_RE = Rx(#"plugin (.+?\.dll) \(([0-9A-Fa-f]{8}) (.+?) ([0-9A-Fa-f]{8})\) loaded correctly \(handle (\d+)\)"#, i: true)
    static let PLUGIN_DIR_RE = Rx(#"plugin directory = (.+?)\\?\s*$"#, i: true)

    public static let DLL_CATALOG: [String: (String, String)] = [
        "enginefixes.dll": ("SSE Engine Fixes", N_("correctifs moteur et allocateur mémoire (framework)")),
        "crashlogger.dll": ("Crash Logger SSE", N_("génère les crash logs analysés ici")),
        "po3_tweaks.dll": ("powerOfThree's Tweaks", N_("correctifs et ajustements divers")),
        "po3_papyrusextender.dll": ("powerOfThree's Papyrus Extender", N_("fonctions Papyrus natives (framework très répandu)")),
        "po3_spellperkitemdistributor.dll": ("Spell Perk Item Distributor", N_("distribution de sorts/perks/objets (framework)")),
        "keyworditemdistributor.dll": ("Keyword Item Distributor", N_("distribution de mots-clés (framework)")),
        "skypatcher.dll": ("SkyPatcher", N_("patch dynamique des enregistrements au chargement")),
        "ssedisplaytweaks.dll": ("SSE Display Tweaks", N_("affichage, VSync, framerate")),
        "skee64.dll": ("RaceMenu (SKEE)", N_("morphs et overlays du personnage")),
        "jcontainers64.dll": ("JContainers", N_("structures de données pour scripts Papyrus (framework)")),
        "papyrusutil.dll": ("PapyrusUtil", N_("fonctions utilitaires Papyrus (framework)")),
        "smoothcam.dll": ("SmoothCam", N_("caméra à la 3e personne")),
        "truehud.dll": ("TrueHUD", N_("barres de vie et HUD (API pour d'autres mods)")),
        "truedirectionalmovement.dll": ("True Directional Movement", N_("déplacements et verrouillage de cible")),
        "sksemenuframework.dll": ("SKSE Menu Framework", N_("menus ImGui pour les mods")),
        "enbhelperse.dll": ("ENBHelperSE", N_("aide ENB (profondeur, météo)")),
        "compassnavigationoverhaul.dll": ("Compass Navigation Overhaul", N_("interface boussole/marqueurs ; s'appuie sur le Scaleform du jeu")),
        "dynamicstringdistributor.dll": ("Dynamic String Distributor", N_("traductions/chaînes dynamiques (framework)")),
    ]

    static let RUNTIME_RE = Rx(#"^[0-9A-Fa-f]{8}$"#)

    public static func decodeRuntime(_ hex8: String) -> (Int, Int, Int)? {
        guard !hex8.isEmpty, RUNTIME_RE.test(hex8), let v = Int(hex8, radix: 16) else { return nil }
        return (v >> 24, (v >> 16) & 0xFF, (v >> 4) & 0xFFF)
    }

    public static func runtimeLabel(_ hex8: String) -> String {
        guard let t = decodeRuntime(hex8) else { return hex8.isEmpty ? "inconnu" : hex8 }
        let kind = (t.0 == 1 && t.1 == 5) ? "SE" : ((t.0, t.1) >= (1, 6) ? "AE" : "?")
        return "\(t.0).\(t.1).\(t.2) (\(kind))"
    }

    public static func addressLibraryName(_ v: (Int, Int, Int, Int)) -> String {
        let prefix = (v.0 == 1 && v.1 == 5) ? "version" : "versionlib"
        return "\(prefix)-\(v.0)-\(v.1)-\(v.2)-0.bin"
    }

    static let SEP_RE = Rx(#"[\\/]+"#)
    static func base(_ winPath: String) -> String { SEP_RE.split(winPath.pyStrip).last ?? "" }

    public static func sksePlugins(_ lines: [String]) -> SkseInfo {
        var info = SkseInfo()
        for l in lines {
            if let m = PLUGIN_DIR_RE.search(l), info.pluginDir == nil {
                info.pluginDir = m.group(1)!.pyStrip.pyRStrip("\\")
            }
            if let m = CHECK_RE.search(l) { info.checked.append(base(m.group(1)!)); continue }
            if let m = LOADED_RE.search(l) { info.loaded[base(m.group(1)!).lowercased()] = (m.group(3)!, Int(m.group(5)!)!) }
        }
        return info
    }

    public static func notLoaded(_ info: SkseInfo) -> [String] {
        info.checked.filter { info.loaded[$0.lowercased()] == nil && !NON_PLUGIN_DLLS.contains($0.lowercased()) }
    }

    // MARK: dossier du jeu

    nonisolated(unsafe) static var _extraRoots: [String] = []
    static let rootsLock = NSLock()
    static var extraRoots: [String] {
        get { rootsLock.lock(); defer { rootsLock.unlock() }; return _extraRoots }
        set { rootsLock.lock(); defer { rootsLock.unlock() }; _extraRoots = newValue }
    }

    static func bottleRootOf(_ path: String) -> String? {
        let parts = PyFS.normpath(path).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let i = parts.firstIndex(of: "drive_c"), i >= 2 { return parts[0..<(i - 1)].joined(separator: "/") }
        return nil
    }

    static func bottles() -> [String] {
        var out: [String] = []
        for g in [BOTTLES_GLOB] + extraRoots.map({ PyFS.join($0, "*") }) {
            for b in pySorted(PyFS.glob(g)) where PyFS.isDir(PyFS.join(b, "drive_c")) && !out.contains(b) { out.append(b) }
        }
        return out
    }

    static let WIN_RE = Rx(#"^([A-Za-z]):[\\/]+(.*)$"#)

    public static func winToHost(_ winPath: String) -> [String] {
        guard let m = WIN_RE.match(winPath.pyStrip) else { return [] }
        let rel = SEP_RE.split(m.group(2)!)
        let drive = m.group(1)!
        return bottles().map { PyFS.joinList([$0, drive.uppercased() == "C" ? "drive_c" : "dosdevices/\(drive.lowercased()):"] + rel) }
    }

    public static func findGameDir(pluginDirWin: String? = nil, userDir: String = "") -> String {
        if let root = bottleRootOf(userDir) { rootsLock.lock(); if !_extraRoots.contains(root) { _extraRoots.append(root) }; rootsLock.unlock() }
        var cands: [String] = []
        if !userDir.isEmpty { cands.append(userDir) }
        if let pd = pluginDirWin, !pd.isEmpty {
            for p in winToHost(pd) { cands.append(PyFS.normpath(PyFS.join(p, "..", "..", ".."))) }
        }
        for b in bottles() {
            for sub in ["Games/Skyrim Special Edition", "Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition",
                        "GOG Games/Skyrim Special Edition", "Program Files (x86)/GOG Galaxy/Games/Skyrim Special Edition"] {
                cands.append(PyFS.joinList([b, "drive_c"] + sub.components(separatedBy: "/")))
            }
        }
        for c in cands where PyFS.isFile(PyFS.join(c, "SkyrimSE.exe")) { return c }
        return ""
    }

    /// Version de fichier (major, minor, build, rev) lue dans la ressource VS_FIXEDFILEINFO.
    public static func readExeVersion(_ exePath: String) -> (Int, Int, Int, Int)? {
        guard let fh = FileHandle(forReadingAtPath: exePath) else { return nil }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: MAX_EXE_BYTES) else { return nil }
        guard let r = data.range(of: Data([0xBD, 0x04, 0xEF, 0xFE])) else { return nil }
        let i = r.lowerBound
        if i + 16 > data.count { return nil }
        func u32(_ p: Int) -> Int {
            Int(data[data.startIndex + p]) | Int(data[data.startIndex + p + 1]) << 8 | Int(data[data.startIndex + p + 2]) << 16 | Int(data[data.startIndex + p + 3]) << 24
        }
        let off = i - data.startIndex
        let ms = u32(off + 8), ls = u32(off + 12)
        return (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF)
    }

    static func pluginsTxtIn(_ driveC: String) -> String? {
        for d in pySorted(PyFS.glob(PyFS.join(driveC, "users", "*", "AppData", "Local", "Skyrim Special Edition*"))) {
            guard let names = PyFS.listdir(d) else { continue }
            for n in names where n.lowercased() == "plugins.txt" { return PyFS.join(d, n) }
        }
        return nil
    }

    public static func findPluginsTxt(_ gameDir: String) -> String? {
        let parts = PyFS.normpath(gameDir).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let i = parts.firstIndex(of: "drive_c"), let hit = pluginsTxtIn(parts[0...i].joined(separator: "/")) { return hit }
        for b in bottles() { if let hit = pluginsTxtIn(PyFS.join(b, "drive_c")) { return hit } }
        return nil
    }

    /// Vrai pour un .esl ou un .esp/.esm marqué ESL (drapeau 0x200 de l'en-tête TES4).
    public static func isLightPlugin(_ path: String) -> Bool {
        if path.lowercased().hasSuffix(".esl") { return true }
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 12), head.count == 12 else { return false }
        let b = [UInt8](head)
        guard b[0..<4].elementsEqual([0x54, 0x45, 0x53, 0x34]) else { return false }
        let flags = UInt32(b[8]) | UInt32(b[9]) << 8 | UInt32(b[10]) << 16 | UInt32(b[11]) << 24
        return flags & 0x200 != 0
    }

    static func fmtDate(_ ts: Double) -> String { Wall(timestamp: ts).format("%d/%m/%Y") }

    // MARK: audits

    static func auditLogCompat(_ lines: [String], _ src: String, _ report: AuditReport, _ scores: Scores) {
        let info = sksePlugins(lines)
        report.skseInfo = info
        let plugins = info.checked.filter { !NON_PLUGIN_DLLS.contains($0.lowercased()) }
        if !plugins.isEmpty {
            report.findings.append(Finding(SEV_INFO, "skse", L("{loaded} plugin(s) SKSE chargés sur {total} vérifiés",
                                                              ["loaded": info.loaded.count, "total": plugins.count]), "", src))
        }
        for dll in notLoaded(info) {
            report.findings.append(Finding(
                SEV_CRIT, "skse", L("Plugin SKSE vérifié mais non chargé : {dll}", ["dll": dll]),
                L("SKSE a examiné ce fichier sans le valider : version du jeu/SKSE incompatible, Address Library absente, DLL corrompue ou dépendance manquante. Il a pu aussi faire planter le chargement."),
                src, [], L("Mettre à jour la DLL pour la version du jeu, installer l'Address Library correspondante, ou la retirer.")))
            scores.bump(dll, 6, L("vérifié mais non chargé par SKSE ({src})", ["src": src]))
        }
    }

    static func auditInstall(_ gameDir: String, _ report: AuditReport, _ scores: Scores) {
        report.gameDir = gameDir
        let exe = PyFS.join(gameDir, "SkyrimSE.exe")
        let ver = readExeVersion(exe)
        let plugDir = PyFS.join(gameDir, "Data", "SKSE", "Plugins")
        let src = L("installation")
        if let ver {
            report.findings.append(Finding(SEV_INFO, "version", "SkyrimSE.exe \(ver.0).\(ver.1).\(ver.2).\(ver.3)", gameDir, src))
            var rt: (Int, Int, Int)?
            if report.skseInfo != nil && !report.skseRuntime.isEmpty { rt = decodeRuntime(report.skseRuntime) }
            if let rt, !(rt.0 == ver.0 && rt.1 == ver.1 && rt.2 == ver.2) {
                report.findings.append(Finding(
                    SEV_CRIT, "version", L("Version du jeu différente du runtime SKSE du log"),
                    L("Jeu {gv} / SKSE compilé pour {sv}.", ["gv": "\(ver.0).\(ver.1).\(ver.2)", "sv": "\(rt.0).\(rt.1).\(rt.2)"]),
                    src, [], L("Installer la build SKSE correspondant exactement au jeu (SE 1.5.97 ou AE 1.6.x).")))
                scores.bump(L("[version] jeu/SKSE incohérents"), 10, L("version de SkyrimSE.exe ≠ runtime SKSE"))
            }
            let al = addressLibraryName(ver)
            if (ver.0, ver.1) <= (1, 6) && PyFS.isDir(plugDir) && !PyFS.isFile(PyFS.join(plugDir, al)) {
                report.findings.append(Finding(
                    SEV_WARN, "version", L("Address Library introuvable ({al})", ["al": al]),
                    L("Les plugins SKSE modernes en dépendent : sans elle, ils ne se chargent pas ou plantent."), src, [],
                    L("Installer l'Address Library correspondant à cette version du jeu (SE : « All in one 1.5.97 »).")))
                scores.bump(L("[version] Address Library absente"), 6, L("{al} absent de Data/SKSE/Plugins", ["al": al]))
            }
        } else if PyFS.isFile(exe) {
            report.findings.append(Finding(SEV_INFO, "version", L("Version de SkyrimSE.exe illisible"), exe, src))
        }

        if PyFS.isDir(plugDir) {
            var files = ODict<String>()
            for n in PyFS.listdir(plugDir) ?? [] where n.lowercased().hasSuffix(".dll") { files[n.lowercased()] = n }
            if let info = report.skseInfo, !info.checked.isEmpty {
                let known = Set(info.checked.map { $0.lowercased() })
                let extra = files.keys.filter { !known.contains($0) }.map { files[$0]! }
                if !extra.isEmpty {
                    report.findings.append(Finding(
                        SEV_INFO, "skse", L("{n} DLL présentes mais absentes du log SKSE", ["n": extra.count]),
                        pySorted(extra).prefix(8).joined(separator: ", "), src, [],
                        L("Log ancien (jeu lancé avant l'ajout ?) ou DLL ignorées par SKSE.")))
                }
            }
            var shown = 0
            for (name, _, _) in scores.sortedItems {
                let low = name.lowercased()
                guard let file = files[low], shown < 5 else { continue }
                let p = PyFS.join(plugDir, file)
                guard let size = PyFS.size(p), let mt = PyFS.mtime(p) else { continue }
                var detail = L("Fichier {f} — {kb} Ko, modifié le {d}", ["f": file, "kb": size / 1024, "d": fmtDate(mt)])
                if let cat = DLL_CATALOG[low] { detail += " — \(cat.0) : \(L(cat.1))" }
                report.findings.append(Finding(SEV_INFO, "mod", L("Suspect présent dans l'installation : {f}", ["f": file]), detail, src))
                shown += 1
            }
        }

        if let ptxt = findPluginsTxt(gameDir) {
            var entries: [String] = []
            if let text = PyFS.readText(ptxt) {
                entries = text.pyFileLines.filter { !$0.pyIsBlank && !$0.hasPrefix("#") }.map { $0.pyStrip }
            }
            let active = entries.filter { $0.hasPrefix("*") }.map { $0.pyLStrip("*") }
            report.findings.append(Finding(
                SEV_INFO, "plugins", L("plugins.txt : {a} plugin(s) actifs sur {t}", ["a": active.count, "t": entries.count]), ptxt, src))
            let dataDir = PyFS.join(gameDir, "Data")
            let eslUnknown = active.filter { e in
                let l = e.lowercased()
                return (l.hasSuffix(".esp") || l.hasSuffix(".esm")) && !isLightPlugin(PyFS.join(dataDir, e))
            }
            if eslUnknown.count > MAX_PLUGINS_NON_ESL {
                report.findings.append(Finding(
                    SEV_WARN, "plugins",
                    L("{n} plugins .esp/.esm actifs (limite {max} hors ESL)", ["n": eslUnknown.count, "max": MAX_PLUGINS_NON_ESL]),
                    L("Au-delà, les formIDs se corrompent ou le jeu plante."), src, [],
                    L("Flaguer ESL les plugins éligibles (xEdit) ou retirer des mods.")))
                scores.bump(L("[plugins] limite 254 dépassée"), 8, L("trop de plugins actifs"))
            }
        }
    }

    static func annotateSuspects(_ report: AuditReport) -> [(String, String)] {
        var notes: [(String, String)] = []
        for s in report.suspects {
            if let cat = DLL_CATALOG[s.name.lowercased()] { notes.append((s.name, "\(cat.0) : \(L(cat.1))")) }
        }
        return notes
    }
}
