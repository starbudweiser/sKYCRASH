// Moteur d'audit des logs Skyrim SE (crash logs, SKSE, Papyrus) : traduction de src/audit_engine.py.
// Produit une liste de constats et un classement de suspects (mods / DLL / catégories).

import Foundation

public enum Audit {
    public static let MAX_LOG_BYTES = 20 * 1024 * 1024
    public static let CRASH_HEAD_LINES = 400
    public static let MAX_CRASH_LOGS = 3
    public static let MAX_PAPYRUS_LOGS = 2

    static let SYSTEM_MODULES: Set<String> = [
        "skyrimse.exe", "skyrimselauncher.exe", "ntdll.dll", "kernel32.dll", "kernelbase.dll",
        "user32.dll", "gdi32.dll", "win32u.dll", "msvcrt.dll", "ucrtbase.dll", "msvcp140.dll",
        "vcruntime140.dll", "vcruntime140_1.dll", "msvcp140_1.dll", "combase.dll", "rpcrt4.dll",
        "ole32.dll", "advapi32.dll", "shell32.dll", "sechost.dll", "wine.dll", "winex11.drv",
    ]
    static let GPU_MODULE_RE = Rx(#"^(d3d1[01]|d3d12|dxgi|nvwgf2um\w*|nvd3dum\w*|atidxx\w*|amdxx\w*|d3dcompiler_\d+|dxvk\w*|winemetal|d3dmetal)\.dll$"#, i: true)
    static let MODULE_RE = Rx(#"\b([A-Za-z0-9_\-.]+\.(?:dll|exe))\b"#, i: true)
    static let PLUGIN_RE = Rx(#"\b([A-Za-z0-9_\-. ']+?\.(?:esp|esm|esl))\b"#, i: true)
    static let EXC_RE = Rx(#"\b(EXCEPTION_[A-Z_]+)\b"#)

    struct Signature { let rx: Rx; let cat: String; let title: String; let advice: String; let weight: Int }
    static let SIGNATURES: [Signature] = [
        Signature(rx: Rx(#"bad_alloc|out of memory|failed to allocate|VirtualAlloc|tbbmalloc|memory manager"#, i: true),
                  cat: "mémoire", title: N_("Épuisement de mémoire (RAM/VRAM/heap)"),
                  advice: N_("Réduire les textures 2K/4K, désactiver les mods gourmands (ENB, grands overhauls), installer un patch mémoire (SSE Engine Fixes / Part 2)."), weight: 6),
        Signature(rx: Rx(#"d3d1[01]|dxgi|nvwgf2um|atidxx|amdxx|d3dcompiler|enbseries|enbhelper|reshade|dxvk|d3dmetal|BSGraphics|BSShader|BSBatchRenderer|ShaderParticle"#, i: true),
                  cat: "graphique", title: N_("Problème de rendu / shader / pilote graphique"),
                  advice: N_("Désactiver ENB/ReShade/DXVK-D3DMetal en test, vérifier la couche de compatibilité (Wine/CrossOver/GPTK), baisser les réglages graphiques et les effets de particules."), weight: 5),
        Signature(rx: Rx(#"\.nif\b|NiSkinInstance|NiSkinData|BSTriShape|NiTriShape|BSDismember|BSFaceGen|facegen|NiAVObject|BSGeometry|BSFadeNode"#, i: true),
                  cat: "mesh", title: N_("Mesh/NIF défectueux ou incompatible (corps, armure, visage)"),
                  advice: N_("Identifier le dernier équipement/PNJ chargé ; vérifier les mods de corps (CBBE/BHUNP), armures et FaceGen ; relancer la génération FaceGen/BodySlide."), weight: 4),
        Signature(rx: Rx(#"hkb\w*|hkp\w*|bhk\w*|havok|behavior|\.hkx\b|animation|nemesis|pandora"#, i: true),
                  cat: "animation/physique", title: N_("Animation, behavior ou physique Havok"),
                  advice: N_("Relancer Nemesis/Pandora/FNIS, désactiver les mods d'animation récents ou de physique (CBPC, HDT-SMP) pour isoler."), weight: 4),
        Signature(rx: Rx(#"BSTextureDB|TextureDB|\.dds\b|BSResource|BSTextureSet"#, i: true),
                  cat: "texture", title: N_("Texture ou ressource corrompue / format non supporté"),
                  advice: N_("Vérifier les textures récentes (format BC7/BC1, mipmaps), réinstaller le mod incriminé."), weight: 3),
        Signature(rx: Rx(#"\.bsa\b|BSArchive|archive"#, i: true),
                  cat: "archive", title: N_("Archive BSA problématique"),
                  advice: N_("Vérifier l'ordre de chargement et l'intégrité des BSA ; limite d'archives atteinte ?"), weight: 3),
        Signature(rx: Rx(#"navmesh|BSNavmesh|TESObjectCELL|pathing|BSPathing"#, i: true),
                  cat: "navmesh/cellule", title: N_("Navmesh / cellule / pathfinding"),
                  advice: N_("Conflit de mods modifiant la même cellule : vérifier avec xEdit et un patch de compatibilité, éviter le fast-travel dans la zone concernée."), weight: 4),
        Signature(rx: Rx(#"papyrus|VirtualMachine|BSScript|SkyrimVM|Papyrus::"#, i: true),
                  cat: "script", title: N_("Moteur de script (Papyrus) impliqué"),
                  advice: N_("Scripts surchargés ou mods retirés en cours de partie : consulter Papyrus.0.log, nettoyer la sauvegarde (ReSaver)."), weight: 4),
        Signature(rx: Rx(#"address ?library|versionlib|version mismatch|incompatible|unsupported (?:game )?version|wrong version"#, i: true),
                  cat: "version", title: N_("Incompatibilité de version (jeu / SKSE / Address Library)"),
                  advice: N_("Aligner les versions : exécutable du jeu, SKSE, Address Library et plugins SKSE (AE vs SE vs 1.5.97)."), weight: 6),
        Signature(rx: Rx(#"TESNPC|\bActor\b|Character|MagicTarget|ActorProcess"#, i: true),
                  cat: "PNJ/acteur", title: N_("Un acteur / PNJ est impliqué"),
                  advice: N_("Désactiver les mods de PNJ/apparence/IA récents ; tester dans une zone sans PNJ."), weight: 2),
    ]

    static let HRESULT_HINTS: [(String, String)] = [
        ("0x80004002", N_("Interface DirectX introuvable (E_NOINTERFACE) : sous CrossOver, DirectX 12 et certaines fonctions DXGI ne sont pas fournies. Désactiver la génération d'images et l'upscaler DX12 (Community Shaders, Frame Generation), ou essayer D3DMetal.")),
        ("0x887a0005", N_("Carte graphique perdue (DXGI_ERROR_DEVICE_REMOVED) : surcharge ou plantage du pilote. Réduire les réglages graphiques, retirer les overlays, vérifier la mémoire.")),
        ("0x8007000e", N_("Mémoire insuffisante (E_OUTOFMEMORY) : réduire textures et mods gourmands.")),
        ("0x80070057", N_("Paramètre refusé par DirectX (E_INVALIDARG) : souvent un réglage ou un preset incompatible avec la couche de compatibilité.")),
    ]

    static let STACK_REF_RE = Rx(#"->\s*(\S+?\.(?:dll|exe))\+([0-9A-Fa-f]+)"#, i: true)
    static let SPEC_RE = Rx(#"^\s*(OS|CPU|GPU #\d+|PHYSICAL MEMORY|GPU MEMORY):\s*(.+)$"#)
    static let SECTION_RE = Rx(#"^[A-Z][A-Z #0-9/+()\[\]]+:\s*$"#)
    static let MEM_RE = Rx(#"([\d.]+)\s*(?:GB)?\s*/\s*([\d.]+)\s*GB"#)
    static let WINE_RE = Rx(#"virtualapple|compatibility mode|crossover|wine|rosetta|d3dmetal|dxvk|apple"#, i: true)
    static let ENB_HINTS = ["d3dcompiler_46e", "enbhelper", "enbseries", "enblocal", "kiloadersatelliteenb"]
    public static let DLSS_HINTS = ["sl.dlss", "nvngx", "sl.common", "sl.interposer"]
    static let ALLOCATOR_MODULES: Set<String> = ["tbbmalloc.dll", "tbb.dll"]
    static let RENDERERS: [(Rx, String)] = [
        (Rx(#"D3DMetal|apple_gptk"#, i: true), "D3DMetal"),
        (Rx(#"dxmt"#, i: true), "DXMT"),
        (Rx(#"moltenvk|dxvk"#, i: true), "DXVK"),
    ]

    // MARK: lecture

    /// Lignes non vides d'un log (utf-8, sinon utf-16 avec marque d'ordre). Les fichiers énormes sont lus par la fin.
    public static func readLines(_ path: String) -> [String] {
        guard let size = PyFS.size(path), let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        var raw: Data
        do {
            if size > MAX_LOG_BYTES { try fh.seek(toOffset: UInt64(size - MAX_LOG_BYTES)) }
            raw = try fh.readToEnd() ?? Data()
        } catch { return [] }
        let bytes = [UInt8](raw)
        let text: String
        if bytes.count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            text = decodeUTF16Ignore(bytes[...])
        } else {
            text = decodeUTF8Ignore(bytes[...])
        }
        return text.pyLines.filter { !$0.pyIsBlank }
    }

    public static func classifyLog(_ path: String, _ lines: [String]) -> String {
        let name = PyFS.basename(path).lowercased()
        let head = lines.prefix(60).joined(separator: "\n").lowercased()
        if head.contains("this is not a crashlog") || name == "crashlogger.log" { return "other" }
        if head.contains("unhandled") && head.contains("exception") { return "crash" }
        if name.hasPrefix("crash-") || name.hasPrefix("crash_") || name.contains("netscriptframework") { return "crash" }
        if name.hasPrefix("papyrus") { return "papyrus" }
        if Rx(#"^skse(?:64|vr)?(?:_\w+)?\.log$"#).match(name) != nil { return "skse" }
        return "other"
    }

    static func isIgnoredModule(_ mod: String) -> Bool {
        let m = mod.lowercased()
        return SYSTEM_MODULES.contains(m) || GPU_MODULE_RE.test(m)
    }

    // MARK: crash

    static let UNHANDLED_RE = Rx(#"unhandled"#, i: true)
    static let CALLSTACK_RE = Rx(#"call ?stack|stack trace|backtrace"#, i: true)
    static let QUOTED_RE = Rx(#"unhandled exception "([^"]+)""#, i: true)

    static func auditCrash(_ path: String, _ lines: [String], _ report: AuditReport, _ scores: Scores, isLatest: Bool) {
        let src = PyFS.basename(path)
        let zone = Array(lines.prefix(CRASH_HEAD_LINES))
        let text = zone.joined(separator: "\n")
        let tag = isLatest ? L(" (le plus récent)") : ""

        let exc = EXC_RE.search(text)
        let header = zone.first { UNHANDLED_RE.test($0) } ?? ""
        let headerMods = MODULE_RE.findall(header)
        let quoted = QUOTED_RE.search(header)
        let excName = exc?.group(1) ?? quoted?.group(1) ?? L("exception inconnue")
        report.findings.append(Finding(
            SEV_CRIT, "crash", L("Crash détecté : {exc}{tag}", ["exc": excName, "tag": tag]),
            L("Fichier {src}", ["src": src]), src, header.isEmpty ? [] : [header.pyStrip],
            L("Analyser le module fautif et la pile d'appels ci-dessous.")))

        var stackMods: [String] = []
        var stackStart: Int?
        for (i, l) in zone.enumerated() where CALLSTACK_RE.test(l) { stackStart = i; break }
        let stackLines: [String]
        if let s = stackStart { stackLines = Array(zone[min(s + 1, zone.count)..<min(s + 90, zone.count)]) } else { stackLines = zone }
        for l in stackLines { stackMods.append(contentsOf: MODULE_RE.findall(l)) }

        let weight = isLatest ? 3 : 1
        for mod in headerMods where !isIgnoredModule(mod) {
            scores.bump(mod, 6 * weight, L("point de crash dans {src}", ["src": src]))
        }
        let counts = Counter(stackMods.filter { !isIgnoredModule($0) })
        for (mod, n) in counts.mostCommon(5) {
            scores.bump(mod, min(n, 4) * weight, L("{n}× dans la pile d'appels ({src})", ["n": n, "src": src]))
        }

        let gpu = Counter((headerMods + stackMods).filter { GPU_MODULE_RE.test($0) })
        if !gpu.isEmpty {
            scores.bump(L("[graphique]") + " " + pySorted(gpu.keys).joined(separator: ", "), 4 * weight,
                        L("modules GPU en pile ({src})", ["src": src]))
        }

        let plugs = Counter(PLUGIN_RE.findall(text).map { $0.pyStrip })
        for (p, n) in plugs.mostCommon(5) {
            scores.bump(p, min(n, 3) * weight, L("cité {n}× dans {src}", ["n": n, "src": src]))
        }
        if !plugs.isEmpty {
            report.findings.append(Finding(
                SEV_WARN, "plugins", L("Plugins cités dans le crash log"),
                plugs.mostCommon(5).map { "\($0.0) (\($0.1)×)" }.joined(separator: ", "), src, [],
                L("Désactiver ces plugins un par un (ou dichotomie) pour confirmer.")))
        }

        if !headerMods.isEmpty && headerMods.allSatisfy(isIgnoredModule) && counts.isEmpty {
            report.findings.append(Finding(
                SEV_WARN, "moteur", L("Crash dans le moteur sans DLL tierce visible"),
                L("Typique d'un asset défectueux (mesh, texture, navmesh, script) ou d'un conflit de données plutôt que d'un plugin SKSE."),
                src, [header.pyStrip], L("Regarder les objets/formulaires cités et les catégories signalées.")))
        }

        for sig in SIGNATURES {
            let hits = zone.filter { sig.rx.test($0) }.map { $0.pyStrip }
            if !hits.isEmpty {
                scores.bump("[\(L(sig.cat))]", sig.weight * weight,
                            L("{n} ligne(s) '{cat}' dans {src}", ["n": hits.count, "cat": L(sig.cat), "src": src]))
                report.findings.append(Finding(SEV_WARN, sig.cat, L(sig.title),
                                               L("{n} occurrence(s)", ["n": hits.count]), src, Array(hits.prefix(3)), L(sig.advice)))
            }
        }

        auditCppException(lines, report, scores, weight, src)
        let extra = auditCrashloggerExtras(lines, report, scores, weight, src)
        report.excerpts[path] = ((extra?.isEmpty == false ? extra! : zone.prefix(150).joined(separator: "\n"))).pyPrefix(12000)
    }

    static let CPP_FIELD_RE = Rx(#"^\s*(Type|Info|Throw Location):\s*(.+)$"#)

    static func auditCppException(_ lines: [String], _ report: AuditReport, _ scores: Scores, _ weight: Int, _ src: String) {
        var fields = ODict<String>()
        for l in section(lines, "C++ EXCEPTION:") {
            if let m = CPP_FIELD_RE.match(l) { fields[m.group(1)!] = m.group(2)!.pyStrip }
        }
        if fields.isEmpty { return }
        let kindRaw = (fields["Type"] ?? "").pyStrip("()* ")
        let kind = kindRaw.isEmpty ? L("type inconnu") : kindRaw
        let info = fields["Info"] ?? ""
        let whereAt = fields["Throw Location"] ?? ""
        let hint = HRESULT_HINTS.first { info.lowercased().contains($0.0) }.map { L($0.1) } ?? ""
        let detail = [info, whereAt.isEmpty ? "" : L("levée dans {where}", ["where": whereAt])].filter { !$0.isEmpty }.joined(separator: "; ")
        report.findings.append(Finding(
            SEV_WARN, "crash", L("Exception C++ : {kind}", ["kind": kind]), detail, src,
            fields.items.map { "\($0.0): \($0.1)" },
            hint.isEmpty ? L("Le plugin qui a levé l'exception est en général le premier module tiers de la pile d'appels.") : hint))
        if let mod = MODULE_RE.search(whereAt), !isIgnoredModule(mod.group(1)!) {
            scores.bump(mod.group(1)!, 4 * weight, L("a levé l'exception C++ ({src})", ["src": src]))
        }
    }

    // MARK: sections Crash Logger SSE

    public static func detectRenderer(_ lines: [String]) -> String? {
        let blob = lines.joined(separator: "\n")
        for (rx, name) in RENDERERS where rx.test(blob) { return name }
        return nil
    }

    /// Lignes d'une section non indentée « TITRE: » jusqu'à la section suivante.
    public static func section(_ lines: [String], _ title: String) -> [String] {
        guard let start = lines.firstIndex(where: { $0.pyStrip == title && !$0.firstIsSpace }) else { return [] }
        var out: [String] = []
        for l in lines[(start + 1)...] {
            if !l.firstIsSpace && SECTION_RE.test(l.pyStrip) { break }
            out.append(l)
        }
        return out
    }

    static let SPLIT_MODULE_RE = Rx(#"\s{2,}|\t"#)

    /// Spécifications « SYSTEM SPECS: » (ordre d'insertion).
    static func readSpecs(_ lines: [String]) -> ODict<String> {
        var specs = ODict<String>()
        for l in section(lines, "SYSTEM SPECS:") {
            if let m = SPEC_RE.match(l) { specs[m.group(1)!] = m.group(2)!.pyStrip }
        }
        return specs
    }

    public static func readModules(_ lines: [String]) -> [String] {
        section(lines, "MODULES:").filter { !$0.pyIsBlank }.map { SPLIT_MODULE_RE.split($0.pyStrip)[0] }
    }

    static func wineFindings(_ lines: [String], _ specs: ODict<String>, _ modules: [String], _ report: AuditReport, _ src: String) {
        let renderer = detectRenderer(lines)
        if renderer == "D3DMetal" {
            report.findings.append(Finding(
                SEV_INFO, "plateforme", L("Moteur graphique sous Wine : D3DMetal (GPTK)"),
                L("DirectX 11/12 est traduit vers Metal par la couche d'Apple intégrée à CrossOver."), src, [],
                L("Avec ENB/ReShade, vérifier que d3d11 est en override « native, builtin » ; en cas de crash graphique, tester le backend DXVK de la bouteille (un changement à la fois).")))
        } else if renderer == "DXVK" {
            report.findings.append(Finding(
                SEV_INFO, "plateforme", L("Moteur graphique sous Wine : DXVK / MoltenVK"),
                L("DirectX est traduit vers Vulkan puis Metal, plus sensible à la pression mémoire."), src, [],
                L("En cas de crash graphique, tester le backend D3DMetal de la bouteille et réduire les textures.")))
        } else if renderer == "DXMT" {
            report.findings.append(Finding(
                SEV_INFO, "plateforme", L("Moteur graphique sous Wine : DXMT"),
                L("Traduction DirectX vers Metal récente, encore peu éprouvée avec ENB."), src, [],
                L("En cas de crash graphique, comparer avec D3DMetal ou DXVK.")))
        }
        if (specs["CPU"] ?? "").lowercased().contains("virtualapple") || specs.values.joined(separator: " ").lowercased().contains("rosetta") {
            report.findings.append(Finding(
                SEV_INFO, "plateforme", L("Processeur x86-64 émulé (Rosetta 2)"),
                L("Le jeu tourne en émulation sur Apple Silicon : accès mémoire et timings atypiques possibles."), src, [], ""))
        }
        let low = modules.map { $0.lowercased() }
        if low.contains(where: { n in DLSS_HINTS.contains { n.contains($0) } }) {
            report.findings.append(Finding(
                SEV_WARN, "plateforme", L("DLSS/Streamline chargés alors qu'ils sont indisponibles sous CrossOver"),
                L("DLSS exige un GPU NVIDIA RTX et Windows natif : ces DLL échouent à s'initialiser sous Wine."), src, [],
                L("Désactiver DLSS/Frame Generation dans ENB, ou retirer sl.*.dll et nvngx.dll de la bouteille.")))
        }
    }

    static func fmt0(_ x: Double) -> String { String(format: "%.0f", x) }

    static func auditCrashloggerExtras(_ lines: [String], _ report: AuditReport, _ scores: Scores, _ weight: Int, _ src: String) -> String? {
        let specs = readSpecs(lines)
        var callStack = section(lines, "PROBABLE CALL STACK:")
        if callStack.isEmpty { callStack = section(lines, "CALL STACK ([P]robable / [S]tack scan):") }
        callStack = callStack.filter { !$0.pyIsBlank }
        let stackLines = section(lines, "STACK:")
        var refs: [(String, String)] = []
        for l in stackLines { for m in STACK_REF_RE.finditer(l) { refs.append((m.group(1)!, m.group(2)!.uppercased())) } }
        let modules = readModules(lines)
        if specs.isEmpty && refs.isEmpty && modules.isEmpty { return nil }

        if !specs.isEmpty {
            report.findings.append(Finding(
                SEV_INFO, "système", L("Configuration enregistrée par Crash Logger"),
                specs.items.map { "\($0.0): \($0.1)" }.joined(separator: "; "), src))
            let isWine = WINE_RE.test(specs.values.joined(separator: " ")) || modules.contains { $0.lowercased().hasPrefix("wine") }
            if isWine {
                scores.bump(L("[plateforme] CrossOver/Wine"), 3 * weight, L("couche de compatibilité détectée ({src})", ["src": src]))
                report.findings.append(Finding(
                    SEV_WARN, "plateforme", L("Exécution via une couche de compatibilité (CrossOver/Wine/GPTK)"),
                    L("Piles d'appels vides, adresses atypiques et échecs DLSS/Streamline sont fréquents dans ce contexte : ne pas les imputer à un mod sans autre preuve."),
                    src, [], L("Tester sans ENB/DLSS, essayer D3DMetal vs DXVK, mettre à jour CrossOver, surveiller la mémoire unifiée.")))
                wineFindings(lines, specs, modules, report, src)
            }
            let ram = MEM_RE.search(specs["PHYSICAL MEMORY"] ?? "")
            let vram = MEM_RE.search(specs["GPU MEMORY"] ?? "")
            let unified = isWine && ram != nil && vram != nil && num(vram!.group(2)!) >= num(ram!.group(2)!)
            if unified {
                report.findings.append(Finding(
                    SEV_INFO, "mémoire", L("Mémoire unifiée : la « VRAM » annoncée n'est pas dédiée"),
                    L("Le GPU partage la RAM du Mac ({vram} Go annoncés pour {ram} Go de RAM) : seule la RAM compte.",
                      ["vram": vram!.group(2)!, "ram": ram!.group(2)!]), src, [],
                    L("Surveiller la pression mémoire de macOS ; fermer les applications gourmandes.")))
            }
            for (key, label) in [("PHYSICAL MEMORY", "RAM"), ("GPU MEMORY", "VRAM")] {
                if unified && key == "GPU MEMORY" { continue }
                if let m = MEM_RE.search(specs[key] ?? ""), num(m.group(2)!) > 0, num(m.group(1)!) / num(m.group(2)!) >= 0.85 {
                    let pct = 100 * num(m.group(1)!) / num(m.group(2)!)
                    scores.bump(L("[mémoire]"), 5 * weight, L("{label} à {pct} % au moment du crash ({src})", ["label": label, "pct": fmt0(pct), "src": src]))
                    report.findings.append(Finding(
                        SEV_WARN, "mémoire", L("{label} presque saturée au moment du crash ({pct} %)", ["label": label, "pct": fmt0(pct)]),
                        specs[key]!, src, [], L("Réduire textures/mods gourmands, fermer les applications, pagefile.")))
                }
            }
        }

        if callStack.isEmpty {
            report.findings.append(Finding(
                SEV_WARN, "pile", L("Pile d'appels vide : Crash Logger n'a pas pu la reconstruire"),
                L("Fréquent sous Wine/Rosetta ou lors d'un crash dans du code généré ; l'analyse repose sur la section STACK brute."), src, [],
                L("Comparer plusieurs crash logs ; vérifier l'environnement avant d'accuser un mod.")))
        }

        if !refs.isEmpty {
            let counts = Counter(refs.map { $0.0 })
            var third = Counter()
            for (m, n) in counts.items where !isIgnoredModule(m) { third[m] = n }
            for (mod, n) in third.mostCommon(5) {
                scores.bump(mod, min(n, 4) * weight, L("{n}× dans le STACK ({src})", ["n": n, "src": src]))
            }
            let engine = Counter(refs.filter { $0.0.lowercased() == "skyrimse.exe" }.map { $0.1 })
            if !engine.isEmpty {
                report.findings.append(Finding(
                    SEV_INFO, "moteur", L("STACK : fonctions du moteur (SkyrimSE.exe) les plus citées"),
                    engine.mostCommon(5).map { "+\($0.0) (\($0.1)×)" }.joined(separator: ", "), src, [],
                    L("Résoudre ces offsets via Address Library (même version de jeu) pour identifier la fonction du moteur concernée.")))
            }
            if counts.keys.contains(where: { ALLOCATOR_MODULES.contains($0.lowercased()) }) {
                scores.bump(L("[mémoire]"), 2 * weight, L("allocateur tbbmalloc dans le STACK ({src})", ["src": src]))
                report.findings.append(Finding(
                    SEV_INFO, "mémoire", L("Allocateur mémoire (tbbmalloc) présent dans le STACK"),
                    L("Provient de SSE Engine Fixes ; à rapprocher de la pression mémoire."), src))
            }
        }

        if !modules.isEmpty {
            let low = modules.map { $0.lowercased() }
            let dupD3d11 = low.filter { $0 == "d3d11.dll" }.count >= 2
            var notable: [String] = []
            if dupD3d11 || low.contains(where: { n in ENB_HINTS.contains { n.contains($0) } }) { notable.append(L("ENB/proxy d3d11")) }
            if low.contains(where: { n in DLSS_HINTS.contains { n.contains($0) } }) { notable.append("DLSS/Streamline") }
            if low.contains(where: { $0.contains("netscriptframework") }) { notable.append("NetScriptFramework") }
            let plugins = low.filter { $0.hasSuffix(".dllplugin") }.count
            if !notable.isEmpty {
                scores.bump(L("[graphique]") + " " + notable.joined(separator: ", "), 2 * weight, L("composants chargés ({src})", ["src": src]))
                report.findings.append(Finding(
                    SEV_INFO, "graphique", L("Composants notables chargés : {list}", ["list": notable.joined(separator: ", ")]),
                    L("{n} modules chargés (dont ~{p} plugins .dllplugin).", ["n": modules.count, "p": plugins]), src, [],
                    L("Tester sans ENB/DLSS pour isoler un problème de rendu.")))
            }
        }

        var head: [String] = []
        for l in lines { if l.pyStrip == "REGISTERS:" { break }; head.append(l) }
        let resolved = Array(stackLines.filter { $0.contains("->") }.map { $0.pyStrip }.prefix(60))
        var parts = Array(head.prefix(40)) + ["", "STACK (références résolues) :"] + resolved
        if !modules.isEmpty { parts += ["", "MODULES : " + modules.joined(separator: ", ").pyPrefix(3500)] }
        return parts.joined(separator: "\n")
    }

    /// `float()` d'un nombre lu par MEM_RE (`[\d.]+`).
    static func num(_ s: String) -> Double { Double(s) ?? 0 }

    // MARK: skse

    static let SKSE_BAD_RE = Rx(#"(couldn'?t load|could not load|disabled|fatal error|no version data|incompatible|not a plugin|failed|error|0x[0-9a-f]{4,})"#, i: true)
    static let SKSE_VERSION_RE = Rx(#"version = ([\d.]+) ([0-9A-Fa-f]{8})"#)
    static let SKSE_LOADED_RE = Rx(#"\(([0-9A-Fa-f]{8}) (.+?) ([0-9A-Fa-f]{8})\) loaded correctly \(handle (\d+)\)"#)
    static let SKSE_SEND_RE = Rx(#"sending message type \d+ to plugin (\d+)"#)
    static let SKSE_LISTENER_RE = Rx(#"registering plugin listener for (\S+) at \d+ of \d+"#)
    static let SKSE_EXC_RE = Rx(#"exception occurred while loading plugins"#, i: true)
    static let SKSE_CRIT_RE = Rx(#"incompatible|no version data|couldn'?t load|fatal"#, i: true)

    static func auditSkse(_ path: String, _ lines: [String], _ report: AuditReport, _ scores: Scores) {
        let src = PyFS.basename(path)
        let bad = lines.filter { $0.lowercased().contains(".dll") && SKSE_BAD_RE.test($0) && !$0.lowercased().contains("loaded correctly") }.map { $0.pyStrip }
        var excerptLines = bad
        let ver = lines.first.flatMap { SKSE_VERSION_RE.search($0) }
        if let ver {
            let rt = ver.group(2)!
            report.skseRuntime = rt
            report.findings.append(Finding(SEV_INFO, "skse", L("SKSE {v} — runtime {rt}", ["v": ver.group(1)!, "rt": Compat.runtimeLabel(rt)]), "", src))
            excerptLines.insert(lines[0].pyStrip, at: 0)
        }
        var handles: [Int: String] = [:]
        for l in lines { if let m = SKSE_LOADED_RE.search(l) { handles[Int(m.group(4)!)!] = m.group(2)! } }
        var excFound = false
        for (i, l) in lines.enumerated() where SKSE_EXC_RE.test(l) {
            excFound = true
            let before = Array(lines[0..<i].reversed())
            let lastMsg = before.lazy.compactMap { SKSE_SEND_RE.search($0) }.first
            let lastReg = before.lazy.compactMap { SKSE_LISTENER_RE.search($0) }.first
            let culprit = lastMsg.flatMap { handles[Int($0.group(1)!)!] }
            let related = lastReg?.group(1)
            let name = culprit ?? related ?? L("plugin inconnu")
            var detail = L("Un plugin a levé une exception pendant la phase de chargement/PostLoad. Dernier plugin actif : {name}", ["name": name])
            if let lastMsg { detail += L(" (handle {h})", ["h": lastMsg.group(1)!]) }
            if let related { detail += L(", en train de s'enregistrer auprès de {related}", ["related": related]) }
            detail += "."
            let ctx = lines[max(0, i - 3)...i].map { $0.pyStrip }
            report.findings.append(Finding(
                SEV_CRIT, "skse", L("Exception SKSE au chargement des plugins (suspect : {name})", ["name": name]),
                detail, src, Array(ctx),
                L("Désactiver ce plugin (et son dépendant) ; vérifier sa version vis-à-vis du jeu/SKSE et ses prérequis (ex. mod UI installé ?).")))
            scores.bump(culprit != nil ? name + ".dll" : name, 12, L("exception SKSE au chargement ({src})", ["src": src]))
            if let related, related != name {
                scores.bump(related, 3, L("plugin lié à l'exception SKSE ({src})", ["src": src]))
            }
            excerptLines = Array(ctx) + excerptLines
            break
        }
        for l in bad {
            let dll = MODULE_RE.search(l)?.group(1) ?? L("plugin inconnu")
            let sev = SKSE_CRIT_RE.test(l) ? SEV_CRIT : SEV_WARN
            scores.bump(dll, sev == SEV_CRIT ? 5 : 2, L("refusé/en erreur au chargement SKSE ({src})", ["src": src]))
            report.findings.append(Finding(sev, "skse", L("Plugin SKSE en échec : {dll}", ["dll": dll]), "", src, [l],
                                           L("Mettre à jour le plugin pour la version du jeu/SKSE, ou le retirer.")))
        }
        Compat.auditLogCompat(lines, src, report, scores)
        if bad.isEmpty && !excFound && Compat.notLoaded(report.skseInfo ?? SkseInfo()).isEmpty {
            report.findings.append(Finding(SEV_INFO, "skse", L("Tous les plugins SKSE se sont chargés"), "", src))
        }
        let ex = excerptLines.prefix(60).joined(separator: "\n").pyPrefix(6000)
        report.excerpts[path] = ex.isEmpty ? L("(aucune erreur de chargement)") : ex
    }

    // MARK: papyrus

    static let PAPY_ERR_RE = Rx(#"\berror:\s*(.*)"#, i: true)
    static let PSC_RE = Rx(#"([A-Za-z0-9_]+)\.psc"#, i: true)
    static let STORE_RE = Rx(#"Cannot open store for class "([^"]+)""#, i: true)
    static let BIND_RE = Rx(#"Script (\S+) cannot be bound to"#, i: true)
    static let NATIVE_RE = Rx(#"Native function (\S+) in (?:empty )?state could find no matching function"#, i: true)
    static let PAPY_NUM_RE = Rx(#"0x[0-9a-f]+|\d+"#)
    static let PAPY_STACK_RE = Rx(#"dumping stack|stack overflow|suspended stack"#, i: true)

    static func auditPapyrus(_ path: String, _ lines: [String], _ report: AuditReport, _ scores: Scores) {
        let src = PyFS.basename(path)
        var msgs = Counter(), scripts = Counter(), missing = Counter()
        var unbound = Counter(), nativeUnbound = Counter()
        for (i, l) in lines.enumerated() {
            if let mc = STORE_RE.search(l) { missing[mc.group(1)!] += 1 }
            if let mb = BIND_RE.search(l) { unbound[mb.group(1)!] += 1 }
            if let mn = NATIVE_RE.search(l) { nativeUnbound[mn.group(1)!] += 1 }
            guard let m = PAPY_ERR_RE.search(l) else { continue }
            let msg = PAPY_NUM_RE.sub("#", m.group(1)!).pyStrip.pyPrefix(140)
            msgs[msg] += 1
            for nxt in lines[min(i + 1, lines.count)..<min(i + 8, lines.count)] {
                if let ms = PSC_RE.search(nxt) { scripts[ms.group(1)!] += 1; break }
            }
        }
        var ccMissing = Counter(), otherMissing = Counter()
        for (k, v) in missing.items { if k.lowercased().hasPrefix("cc") { ccMissing[k] = v } }
        for (k, v) in missing.items where !ccMissing.contains(k) { otherMissing[k] = v }
        func listOf(_ pairs: [(String, Int)]) -> String { pairs.map { "\($0.0) (\($0.1)×)" }.joined(separator: ", ") }
        if !ccMissing.isEmpty {
            let sorted = ccMissing.items.sorted { pyLess($0.0, $1.0) }
            report.findings.append(Finding(
                SEV_WARN, "script", L("Contenu Creation Club manquant ou incomplet"), listOf(Array(sorted.prefix(8))), src, [],
                L("Télécharger/réinstaller le contenu Creation Club via le jeu (Créations) ou retirer les mods qui le requièrent ; ne pas utiliser le menu Créations avec MO2/Vortex.")))
            scores.bump(L("[creation club] contenu manquant"), 2, L("{n} script(s) CC introuvable(s) dans {src}", ["n": ccMissing.keys.count, "src": src]))
        }
        if !otherMissing.isEmpty {
            let byCount = otherMissing.items.stableSorted { $0.1 > $1.1 }
            report.findings.append(Finding(
                SEV_WARN, "script", L("Scripts introuvables (mod retiré en cours de partie ou fichiers manquants)"),
                listOf(Array(byCount.prefix(8))), src, [], L("Réinstaller le mod ou nettoyer la sauvegarde (ReSaver).")))
            for (k, v) in byCount.prefix(3) {
                scores.bump(k + ".psc", min(v, 4) + 1, L("script manquant dans {src}", ["src": src]))
            }
        }
        if !unbound.isEmpty {
            report.findings.append(Finding(
                SEV_WARN, "script", L("Scripts non liés à leur quest/objet"), listOf(unbound.mostCommon(5)), src, [],
                L("Le script n'existe pas ou n'est pas chargé : mod incomplet, master manquant ou ancien save.")))
            for (k, _) in unbound.mostCommon(3) { scores.bump(k + ".psc", 2, L("script non lié dans {src}", ["src": src])) }
        }
        if !nativeUnbound.isEmpty {
            report.findings.append(Finding(
                SEV_WARN, "script", L("Fonctions natives Papyrus non liées"),
                L("{n} fonction(s) : ", ["n": nativeUnbound.total]) + nativeUnbound.keys.prefix(5).joined(separator: ", "), src, [],
                L("Typiquement un plugin SKSE absent/incompatible ou des .pex d'un mod qui attendent une fonction native qui n'existe pas dans cette version.")))
            scores.bump(L("[script] fonctions natives non liées"), 2, L("{n} fonction(s) native(s) dans {src}", ["n": nativeUnbound.total, "src": src]))
        }
        let total = msgs.total
        let stacks = lines.filter { PAPY_STACK_RE.test($0) }.count
        if stacks > 0 {
            report.findings.append(Finding(
                SEV_CRIT, "script", L("Surcharge Papyrus (piles de scripts en vidange)"),
                L("{n} occurrence(s) — scripts trop nombreux ou en boucle.", ["n": stacks]), src, [],
                L("Repérer le script le plus bavard ci-dessous ; désactiver le mod ou nettoyer la sauvegarde.")))
            scores.bump(L("[script] surcharge Papyrus"), 5, L("{n} vidange(s) de piles dans {src}", ["n": stacks, "src": src]))
        }
        if total > 0 {
            let top = scripts.mostCommon(5)
            if let first = top.first {
                report.findings.append(Finding(
                    first.1 >= 20 ? SEV_WARN : SEV_INFO, "script",
                    L("{total} erreurs Papyrus ; scripts les plus fautifs", ["total": total]),
                    listOf(top), src, msgs.mostCommon(3).map { "\($0.1)× \($0.0)" },
                    L("Un script très bavard est un suspect fréquent de lenteurs/instabilité.")))
                for (k, v) in top.prefix(3) where v >= 5 {
                    scores.bump(k, min(v / 5, 5), L("{v} erreurs Papyrus ({src})", ["v": v, "src": src]))
                }
            }
        }
        var extra = missing.items.prefix(15).map { L("script introuvable : {k} ({v}×)", ["k": $0.0, "v": $0.1]) }
        extra += unbound.items.prefix(10).map { L("script non lié : {k} ({v}×)", ["k": $0.0, "v": $0.1]) }
        extra += nativeUnbound.keys.prefix(10).map { L("fonction native non liée : {k}", ["k": $0]) }
        let ex = (msgs.mostCommon(15).map { "\($0.1)× \($0.0)" } + extra).joined(separator: "\n").pyPrefix(6000)
        report.excerpts[path] = ex.isEmpty ? L("(aucune erreur)") : ex
    }

    // MARK: logs de plugins

    static let PLUGIN_STRONG_RE = Rx(#"\[(?:critical|error|fatal)\]|\bfatal\b"#, i: true)
    static let PLUGIN_WEAK_RE = Rx(#"exception|failed to"#, i: true)
    static let ENGINEFIXES_VER_RE = Rx(#"Engine Fixes v(\d+)\.(\d+)\.(\d+)"#)
    static let STREAMLINE_RE = Rx(#"streamline"#, i: true)

    static func auditOther(_ path: String, _ lines: [String], _ report: AuditReport, _ scores: Scores) {
        let src = PyFS.basename(path)
        let stem = PyFS.splitext(src).0
        if let ver = ENGINEFIXES_VER_RE.search(lines.prefix(20).joined(separator: "\n")), Int(ver.group(1)!)! < 7 {
            let v = ver.groups.map { $0! }.joined(separator: ".")
            report.findings.append(Finding(
                SEV_WARN, "version", L("SSE Engine Fixes v{v} (ancienne branche, avant v7)", ["v": v]),
                L("Avant la v7, EngineFixes.toml doit contenir SaveGameMaxSize = true et MaxStdio = 8192 ; les DLL de la partie 2 (tbbmalloc.dll...) doivent être à la racine du jeu."),
                src, [], L("Vérifier ces réglages ou passer à la v7 recommandée par la communauté.")))
            scores.bump("EngineFixes.dll", 1, L("version ancienne v{v} ({src})", ["v": v, "src": src]))
        }
        let strong = lines.filter { PLUGIN_STRONG_RE.test($0) }.map { $0.pyStrip }
        let weak = lines.filter { PLUGIN_WEAK_RE.test($0) && !strong.contains($0.pyStrip) }.map { $0.pyStrip }
        if !strong.isEmpty {
            let streamline = strong.contains { STREAMLINE_RE.test($0) }
            let tip = streamline
                ? L("DLSS/Streamline indisponible (normal sous CrossOver/Wine ou sans GPU NVIDIA RTX) : désactiver DLSS/Frame Generation dans ENB.")
                : L("Consulter ce log et la page du mod ; mettre à jour ou retirer le plugin.")
            report.findings.append(Finding(
                SEV_WARN, "plugin", L("Erreur critique dans le log de {stem}", ["stem": stem]),
                L("{n} ligne(s) critique(s)", ["n": strong.count]), src, Array(strong.prefix(3)), tip))
            scores.bump(stem, min(strong.count, 3) + (streamline ? 0 : 1), L("{n} erreur(s) critique(s) dans {src}", ["n": strong.count, "src": src]))
        } else if !weak.isEmpty {
            report.findings.append(Finding(
                SEV_INFO, "plugin", L("Messages d'échec dans le log de {stem}", ["stem": stem]),
                L("{n} ligne(s)", ["n": weak.count]), src, Array(weak.prefix(2)), ""))
        }
        if !strong.isEmpty || !weak.isEmpty {
            report.excerpts[path] = (strong + weak).prefix(30).joined(separator: "\n").pyPrefix(3000)
        }
    }

    // MARK: général

    struct Entry { let mtime: Double; let path: String; let lines: [String]; let kind: String }

    public static func auditPaths(_ paths: [String], gameDir: String = "") -> AuditReport {
        let report = AuditReport()
        let scores = Scores()
        var entries: [Entry] = []
        for p in paths {
            guard let mtime = PyFS.mtime(p) else { continue }
            let lines = readLines(p)
            if !lines.isEmpty { entries.append(Entry(mtime: mtime, path: p, lines: lines, kind: classifyLog(p, lines))) }
        }
        entries = entries.stableSorted { $0.mtime > $1.mtime }

        let crashes = Array(entries.filter { $0.kind == "crash" }.prefix(MAX_CRASH_LOGS))
        for (idx, e) in crashes.enumerated() {
            auditCrash(e.path, e.lines, report, scores, isLatest: idx == 0)
            report.analysed.append(e.path)
        }
        var seen = Set<String>(), papyCount = 0
        for e in entries {
            if ["skse", "papyrus", "other"].contains(e.kind) {
                let key = e.kind + "\u{0}" + e.lines.joined(separator: "\n")
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            if e.kind == "papyrus" {
                papyCount += 1
                if papyCount > MAX_PAPYRUS_LOGS { continue }
            }
            switch e.kind {
            case "skse": auditSkse(e.path, e.lines, report, scores); report.analysed.append(e.path)
            case "papyrus": auditPapyrus(e.path, e.lines, report, scores); report.analysed.append(e.path)
            case "other": auditOther(e.path, e.lines, report, scores); report.analysed.append(e.path)
            default: break
            }
        }

        let gdir = Compat.findGameDir(pluginDirWin: report.skseInfo?.pluginDir, userDir: gameDir)
        if !gameDir.isEmpty && !PyFS.isFile(PyFS.join(gameDir, "SkyrimSE.exe")) {
            report.findings.append(Finding(
                SEV_WARN, "réglages", L("Le dossier du jeu des réglages n'existe plus"),
                L("Réglage : {old} — utilisé à la place : {new}", ["old": gameDir, "new": gdir.isEmpty ? L("aucun") : gdir]),
                L("réglages"), [], L("Mettre à jour le dossier du jeu dans Réglages… > Général.")))
            if !gdir.isEmpty { report.extras.gameDirFound = gdir }
        }
        if !gdir.isEmpty { Compat.auditInstall(gdir, report, scores) }

        do {
            try Insights.analyse(report, scores, entries, gdir)
        } catch {
            report.findings.append(Finding(SEV_INFO, "recoupement", L("Recoupements incomplets : {e}", ["e": "\(error)"]), "", ""))
        }
        report.extras.inventory = Inventory.build(gdir, entries, report.extras.history ?? [])

        report.suspects = scores.sortedItems.prefix(8).map { Suspect(name: $0.0, score: $0.1, reasons: $0.2) }
        let origins = ModOrigin.buildIndex(gdir)
        for i in report.suspects.indices {
            let name = report.suspects[i].name
            let mods = name.lowercased().hasSuffixAny(ModOrigin.EXTS) ? ModOrigin.originOf(name, origins) : []
            if !mods.isEmpty {
                report.suspects[i].reasons.append(L("fourni par le mod « {mod} »", ["mod": mods.prefix(3).joined(separator: ", ")]))
            }
        }
        for (name, role) in Compat.annotateSuspects(report) {
            for i in report.suspects.indices where report.suspects[i].name == name {
                report.suspects[i].reasons.append(L("rôle connu : {role}", ["role": role]))
            }
        }
        if crashes.isEmpty && report.findings.isEmpty {
            report.verdict = L("aucun crash log trouvé")
        } else if crashes.isEmpty {
            report.verdict = L("pas de crash log, anomalies secondaires uniquement")
        } else if let first = report.suspects.first {
            report.verdict = L("suspect principal : {name}", ["name": first.name])
        } else {
            report.verdict = L("crash détecté, source indéterminée")
        }
        return report
    }
}
