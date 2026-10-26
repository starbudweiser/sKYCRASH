"""Moteur d'audit des logs Skyrim SE (crash logs, SKSE, Papyrus).

Module sans dépendance Qt : testable et réutilisable. Il produit une liste de
constats (Finding) et un classement de suspects (mods / DLL / catégories).
Les textes affichés passent par i18n.L() (clé = texte français).
"""
from __future__ import annotations

import os
import re
from collections import Counter
from dataclasses import dataclass, field

import compat
import insights
import inventory
import mod_origin
from i18n import L, N_

MAX_LOG_BYTES = 20 * 1024 * 1024
CRASH_HEAD_LINES = 400       # zone analysée pour un crash log
MAX_CRASH_LOGS = 3           # nombre de crash logs récents analysés
MAX_PAPYRUS_LOGS = 2         # nombre de logs Papyrus distincts analysés
SEV_CRIT, SEV_WARN, SEV_INFO = 3, 2, 1


def sev_label(sev: int) -> str:
    return {SEV_CRIT: L("CRITIQUE"), SEV_WARN: L("AVERTISSEMENT"), SEV_INFO: L("INFO")}[sev]


# Modules système / moteur : jamais désignés comme coupables.
SYSTEM_MODULES = {
    "skyrimse.exe", "skyrimselauncher.exe", "ntdll.dll", "kernel32.dll", "kernelbase.dll",
    "user32.dll", "gdi32.dll", "win32u.dll", "msvcrt.dll", "ucrtbase.dll", "msvcp140.dll",
    "vcruntime140.dll", "vcruntime140_1.dll", "msvcp140_1.dll", "combase.dll", "rpcrt4.dll",
    "ole32.dll", "advapi32.dll", "shell32.dll", "sechost.dll", "wine.dll", "winex11.drv",
}
GPU_MODULE_RE = re.compile(r"^(d3d1[01]|d3d12|dxgi|nvwgf2um\w*|nvd3dum\w*|atidxx\w*|amdxx\w*|"
                           r"d3dcompiler_\d+|dxvk\w*|winemetal|d3dmetal)\.dll$", re.I)
MODULE_RE = re.compile(r"\b([A-Za-z0-9_\-.]+\.(?:dll|exe))\b", re.I)
PLUGIN_RE = re.compile(r"\b([A-Za-z0-9_\-. ']+?\.(?:esp|esm|esl))\b", re.I)
EXC_RE = re.compile(r"\b(EXCEPTION_[A-Z_]+)\b")

# (regex, catégorie, titre, conseil, poids)
SIGNATURES = [
    (re.compile(r"bad_alloc|out of memory|failed to allocate|VirtualAlloc|tbbmalloc|"
                r"memory manager", re.I),
     "mémoire", N_("Épuisement de mémoire (RAM/VRAM/heap)"),
     N_("Réduire les textures 2K/4K, désactiver les mods gourmands (ENB, grands overhauls), "
        "installer un patch mémoire (SSE Engine Fixes / Part 2)."), 6),
    (re.compile(r"d3d1[01]|dxgi|nvwgf2um|atidxx|amdxx|d3dcompiler|enbseries|enbhelper|"
                r"reshade|dxvk|d3dmetal|BSGraphics|BSShader|BSBatchRenderer|ShaderParticle", re.I),
     "graphique", N_("Problème de rendu / shader / pilote graphique"),
     N_("Désactiver ENB/ReShade/DXVK-D3DMetal en test, vérifier la couche de compatibilité "
        "(Wine/CrossOver/GPTK), baisser les réglages graphiques et les effets de particules."), 5),
    (re.compile(r"\.nif\b|NiSkinInstance|NiSkinData|BSTriShape|NiTriShape|BSDismember|"
                r"BSFaceGen|facegen|NiAVObject|BSGeometry|BSFadeNode", re.I),
     "mesh", N_("Mesh/NIF défectueux ou incompatible (corps, armure, visage)"),
     N_("Identifier le dernier équipement/PNJ chargé ; vérifier les mods de corps (CBBE/BHUNP), "
        "armures et FaceGen ; relancer la génération FaceGen/BodySlide."), 4),
    (re.compile(r"hkb\w*|hkp\w*|bhk\w*|havok|behavior|\.hkx\b|animation|nemesis|pandora", re.I),
     "animation/physique", N_("Animation, behavior ou physique Havok"),
     N_("Relancer Nemesis/Pandora/FNIS, désactiver les mods d'animation récents ou de physique "
        "(CBPC, HDT-SMP) pour isoler."), 4),
    (re.compile(r"BSTextureDB|TextureDB|\.dds\b|BSResource|BSTextureSet", re.I),
     "texture", N_("Texture ou ressource corrompue / format non supporté"),
     N_("Vérifier les textures récentes (format BC7/BC1, mipmaps), réinstaller le mod "
        "incriminé."), 3),
    (re.compile(r"\.bsa\b|BSArchive|archive", re.I),
     "archive", N_("Archive BSA problématique"),
     N_("Vérifier l'ordre de chargement et l'intégrité des BSA ; limite d'archives atteinte ?"), 3),
    (re.compile(r"navmesh|BSNavmesh|TESObjectCELL|pathing|BSPathing", re.I),
     "navmesh/cellule", N_("Navmesh / cellule / pathfinding"),
     N_("Conflit de mods modifiant la même cellule : vérifier avec xEdit et un patch de "
        "compatibilité, éviter le fast-travel dans la zone concernée."), 4),
    (re.compile(r"papyrus|VirtualMachine|BSScript|SkyrimVM|Papyrus::", re.I),
     "script", N_("Moteur de script (Papyrus) impliqué"),
     N_("Scripts surchargés ou mods retirés en cours de partie : consulter Papyrus.0.log, "
        "nettoyer la sauvegarde (ReSaver)."), 4),
    (re.compile(r"address ?library|versionlib|version mismatch|incompatible|"
                r"unsupported (?:game )?version|wrong version", re.I),
     "version", N_("Incompatibilité de version (jeu / SKSE / Address Library)"),
     N_("Aligner les versions : exécutable du jeu, SKSE, Address Library et plugins SKSE "
        "(AE vs SE vs 1.5.97)."), 6),
    (re.compile(r"TESNPC|\bActor\b|Character|MagicTarget|ActorProcess", re.I),
     "PNJ/acteur", N_("Un acteur / PNJ est impliqué"),
     N_("Désactiver les mods de PNJ/apparence/IA récents ; tester dans une zone sans PNJ."), 2),
]


@dataclass
class Finding:
    severity: int
    category: str
    title: str
    detail: str = ""
    source: str = ""
    evidence: list = field(default_factory=list)
    suggestion: str = ""


@dataclass
class AuditReport:
    findings: list = field(default_factory=list)
    suspects: list = field(default_factory=list)   # [(nom, score, [raisons])]
    analysed: list = field(default_factory=list)   # chemins analysés
    excerpts: dict = field(default_factory=dict)   # chemin -> extrait utile pour l'IA
    verdict: str = ""
    game_dir: str = ""                            # dossier du jeu détecté/choisi (vide si inconnu)
    skse_info: dict = None                         # plugins vérifiés/chargés lus dans skse64.log
    skse_runtime: str = ""                         # runtime SKSE (hex) lu dans skse64.log
    extras: dict = field(default_factory=dict)     # recoupements (chronologie, historique, sauvegarde) pour l'export

    def to_markdown(self) -> str:
        out = [L("# Audit — verdict : {verdict}", verdict=self.verdict), ""]
        if self.suspects:
            out.append(L("## Suspects classés"))
            for i, (name, score, reasons) in enumerate(self.suspects, 1):
                out.append(f"{i}. **{name}** (score {score}) — " + "; ".join(reasons[:3]))
            out.append("")
        out.append(L("## Constats"))
        for f in sorted(self.findings, key=lambda x: -x.severity):
            out.append(f"- [{sev_label(f.severity)}] ({f.category}) {f.title} — {f.source}")
            if f.detail:
                out.append(f"    {f.detail}")
            for e in f.evidence[:3]:
                out.append(f"    > {e}")
            if f.suggestion:
                out.append(L("    Piste : {tip}", tip=f.suggestion))
        return "\n".join(out)

    def to_context(self, max_chars: int = 60000) -> str:
        facts = inventory.to_context(self.extras.get("inventory") or {})
        parts = ([facts, ""] if facts else []) + [self.to_markdown(), "", L("## Extraits de logs")]
        for path, text in self.excerpts.items():
            parts.append(f"### {os.path.basename(path)}\n{text}")
        return "\n".join(parts)[:max_chars]


# ----------------------------------------------------------------- lecture
def read_lines(path: str) -> list:
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > MAX_LOG_BYTES:
                f.seek(-MAX_LOG_BYTES, os.SEEK_END)
            raw = f.read()
    except OSError:
        return []
    enc = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8"
    # lignes vides supprimées (certains logs Windows/Wine finissent en \r\r\n)
    return [l for l in raw.decode(enc, errors="ignore").splitlines() if l.strip()]


def classify_log(path: str, lines: list) -> str:
    name = os.path.basename(path).lower()
    head = "\n".join(lines[:60]).lower()
    if "this is not a crashlog" in head or name == "crashlogger.log":
        return "other"   # journal interne de Crash Logger, pas un rapport de crash
    if "unhandled" in head and "exception" in head:
        return "crash"
    if name.startswith(("crash-", "crash_")) or "netscriptframework" in name:
        return "crash"
    if name.startswith("papyrus"):
        return "papyrus"
    if re.match(r"^skse(?:64|vr)?(?:_\w+)?\.log$", name):  # skse64.log, skse64_loader.log ; pas les .txt de mods
        return "skse"
    return "other"


def _is_ignored_module(mod: str) -> bool:
    m = mod.lower()
    return m in SYSTEM_MODULES or bool(GPU_MODULE_RE.match(m))


# ------------------------------------------------------------------- crash
def audit_crash(path: str, lines: list, report: AuditReport, scores: dict, is_latest: bool):
    src = os.path.basename(path)
    zone = lines[:CRASH_HEAD_LINES]
    text = "\n".join(zone)
    tag = L(" (le plus récent)") if is_latest else ""

    exc = EXC_RE.search(text)
    header = next((l for l in zone if re.search(r"unhandled", l, re.I)), "")
    header_mods = [m for m in MODULE_RE.findall(header)]
    quoted = re.search(r'unhandled exception "([^"]+)"', header, re.I)
    exc_name = exc.group(1) if exc else (quoted.group(1) if quoted else L("exception inconnue"))
    report.findings.append(Finding(
        SEV_CRIT, "crash", L("Crash détecté : {exc}{tag}", exc=exc_name, tag=tag),
        L("Fichier {src}", src=src), src, [header.strip()] if header else [],
        L("Analyser le module fautif et la pile d'appels ci-dessous.")))

    # pile d'appels : lignes contenant "call stack"/"callstack" puis modules
    stack_mods, stack_start = [], None
    for i, l in enumerate(zone):
        if re.search(r"call ?stack|stack trace|backtrace", l, re.I):
            stack_start = i
            break
    stack_lines = zone[stack_start + 1: stack_start + 90] if stack_start is not None else zone
    for l in stack_lines:
        stack_mods.extend(MODULE_RE.findall(l))

    weight = 3 if is_latest else 1
    # module du point de crash (en-tête), prioritaire
    for mod in header_mods:
        if not _is_ignored_module(mod):
            _bump(scores, mod, 6 * weight, L("point de crash dans {src}", src=src))
    counts = Counter(m for m in stack_mods if not _is_ignored_module(m))
    for mod, n in counts.most_common(5):
        _bump(scores, mod, min(n, 4) * weight, L("{n}× dans la pile d'appels ({src})", n=n, src=src))

    gpu = Counter(m for m in header_mods + stack_mods if GPU_MODULE_RE.match(m))
    if gpu:
        _bump(scores, L("[graphique]") + " " + ", ".join(sorted(gpu)), 4 * weight,
              L("modules GPU en pile ({src})", src=src))

    # plugins .esp/.esm/.esl cités (objets pertinents)
    plugs = Counter(p.strip() for p in PLUGIN_RE.findall(text))
    for p, n in plugs.most_common(5):
        _bump(scores, p, min(n, 3) * weight, L("cité {n}× dans {src}", n=n, src=src))
    if plugs:
        report.findings.append(Finding(
            SEV_WARN, "plugins", L("Plugins cités dans le crash log"),
            ", ".join(f"{p} ({n}×)" for p, n in plugs.most_common(5)), src, [],
            L("Désactiver ces plugins un par un (ou dichotomie) pour confirmer.")))

    if header_mods and all(_is_ignored_module(m) for m in header_mods) and not counts:
        report.findings.append(Finding(
            SEV_WARN, "moteur", L("Crash dans le moteur sans DLL tierce visible"),
            L("Typique d'un asset défectueux (mesh, texture, navmesh, script) ou d'un conflit "
              "de données plutôt que d'un plugin SKSE."), src, [header.strip()],
            L("Regarder les objets/formulaires cités et les catégories signalées.")))

    for rx, cat, title, advice, w in SIGNATURES:
        hits = [l.strip() for l in zone if rx.search(l)]
        if hits:
            _bump(scores, f"[{L(cat)}]", w * weight,
                  L("{n} ligne(s) '{cat}' dans {src}", n=len(hits), cat=L(cat), src=src))
            report.findings.append(Finding(SEV_WARN, cat, L(title),
                                           L("{n} occurrence(s)", n=len(hits)),
                                           src, hits[:3], L(advice)))

    audit_cpp_exception(lines, report, scores, weight, src)
    extra = audit_crashlogger_extras(lines, report, scores, weight, src)
    report.excerpts[path] = (extra or "\n".join(zone[:150]))[:12000]


# Crash Logger 1.25+ : exception C++ levée par un plugin (Type, Info avec le HRESULT, Throw Location)
HRESULT_HINTS = (
    ("0x80004002", N_("Interface DirectX introuvable (E_NOINTERFACE) : sous CrossOver, DirectX 12 et certaines "
                      "fonctions DXGI ne sont pas fournies. Désactiver la génération d'images et l'upscaler DX12 "
                      "(Community Shaders, Frame Generation), ou essayer D3DMetal.")),
    ("0x887a0005", N_("Carte graphique perdue (DXGI_ERROR_DEVICE_REMOVED) : surcharge ou plantage du pilote. "
                      "Réduire les réglages graphiques, retirer les overlays, vérifier la mémoire.")),
    ("0x8007000e", N_("Mémoire insuffisante (E_OUTOFMEMORY) : réduire textures et mods gourmands.")),
    ("0x80070057", N_("Paramètre refusé par DirectX (E_INVALIDARG) : souvent un réglage ou un preset incompatible "
                      "avec la couche de compatibilité.")),
)


def audit_cpp_exception(lines: list, report: AuditReport, scores: dict, weight: int, src: str):
    fields = {}
    for l in _section(lines, "C++ EXCEPTION:"):
        m = re.match(r"\s*(Type|Info|Throw Location):\s*(.+)$", l)
        if m:
            fields[m.group(1)] = m.group(2).strip()
    if not fields:
        return
    kind = fields.get("Type", "").strip("()* ") or L("type inconnu")
    info = fields.get("Info", "")
    where = fields.get("Throw Location", "")
    hint = next((L(text) for code, text in HRESULT_HINTS if code in info.lower()), "")
    report.findings.append(Finding(
        SEV_WARN, "crash", L("Exception C++ : {kind}", kind=kind),
        "; ".join(x for x in (info, L("levée dans {where}", where=where) if where else "") if x), src,
        [f"{k}: {v}" for k, v in fields.items()],
        hint or L("Le plugin qui a levé l'exception est en général le premier module tiers de la pile d'appels.")))
    mod = MODULE_RE.search(where)
    if mod and not _is_ignored_module(mod.group(1)):
        _bump(scores, mod.group(1), 4 * weight, L("a levé l'exception C++ ({src})", src=src))


# ------------------------------------------- sections Crash Logger SSE (STACK, MODULES...)
STACK_REF_RE = re.compile(r"->\s*(\S+?\.(?:dll|exe))\+([0-9A-Fa-f]+)", re.I)
SPEC_RE = re.compile(r"^\s*(OS|CPU|GPU #\d+|PHYSICAL MEMORY|GPU MEMORY):\s*(.+)$")
SECTION_RE = re.compile(r"^[A-Z][A-Z #0-9/+()\[\]]+:\s*$")  # inclut « C++ EXCEPTION: » et « CALL STACK ([P]robable / [S]tack scan): »
MEM_RE = re.compile(r"([\d.]+)\s*(?:GB)?\s*/\s*([\d.]+)\s*GB")
WINE_RE = re.compile(r"virtualapple|compatibility mode|crossover|wine|rosetta|d3dmetal|dxvk|apple", re.I)
ENB_HINTS = ("d3dcompiler_46e", "enbhelper", "enbseries", "enblocal", "kiloadersatelliteenb")
DLSS_HINTS = ("sl.dlss", "nvngx", "sl.common", "sl.interposer")
ALLOCATOR_MODULES = {"tbbmalloc.dll", "tbb.dll"}
# moteur graphique de la couche de compatibilité, déduit des chemins/chaînes présents dans le log
RENDERERS = (
    (re.compile(r"D3DMetal|apple_gptk", re.I), "D3DMetal"),
    (re.compile(r"dxmt", re.I), "DXMT"),
    (re.compile(r"moltenvk|dxvk", re.I), "DXVK"),
)


def detect_renderer(lines: list):
    blob = "\n".join(lines)
    for rx, name in RENDERERS:
        if rx.search(blob):
            return name
    return None


def _section(lines: list, title: str) -> list:
    """Lignes d'une section non indentée 'TITRE:' jusqu'à la section suivante."""
    start = next((i for i, l in enumerate(lines) if l.strip() == title and not l[:1].isspace()), None)
    if start is None:
        return []
    out = []
    for l in lines[start + 1:]:
        if not l[:1].isspace() and SECTION_RE.match(l.strip()):
            break
        out.append(l)
    return out


def _wine_findings(lines, specs, modules, report, scores, weight, src, ram_pct_note):
    """Diagnostics propres à CrossOver / Wine / GPTK (Mac)."""
    renderer = detect_renderer(lines)
    if renderer == "D3DMetal":
        report.findings.append(Finding(
            SEV_INFO, "plateforme", L("Moteur graphique sous Wine : D3DMetal (GPTK)"),
            L("DirectX 11/12 est traduit vers Metal par la couche d'Apple intégrée à CrossOver."), src, [],
            L("Avec ENB/ReShade, vérifier que d3d11 est en override « native, builtin » ; en cas de crash "
              "graphique, tester le backend DXVK de la bouteille (un changement à la fois).")))
    elif renderer == "DXVK":
        report.findings.append(Finding(
            SEV_INFO, "plateforme", L("Moteur graphique sous Wine : DXVK / MoltenVK"),
            L("DirectX est traduit vers Vulkan puis Metal, plus sensible à la pression mémoire."), src, [],
            L("En cas de crash graphique, tester le backend D3DMetal de la bouteille et réduire les textures.")))
    elif renderer == "DXMT":
        report.findings.append(Finding(
            SEV_INFO, "plateforme", L("Moteur graphique sous Wine : DXMT"),
            L("Traduction DirectX vers Metal récente, encore peu éprouvée avec ENB."), src, [],
            L("En cas de crash graphique, comparer avec D3DMetal ou DXVK.")))
    if "virtualapple" in specs.get("CPU", "").lower() or "rosetta" in " ".join(specs.values()).lower():
        report.findings.append(Finding(
            SEV_INFO, "plateforme", L("Processeur x86-64 émulé (Rosetta 2)"),
            L("Le jeu tourne en émulation sur Apple Silicon : accès mémoire et timings atypiques possibles."),
            src, [], ""))
    low = [m.lower() for m in modules]
    if any(h in n for n in low for h in DLSS_HINTS):
        report.findings.append(Finding(
            SEV_WARN, "plateforme", L("DLSS/Streamline chargés alors qu'ils sont indisponibles sous CrossOver"),
            L("DLSS exige un GPU NVIDIA RTX et Windows natif : ces DLL échouent à s'initialiser sous Wine."),
            src, [],
            L("Désactiver DLSS/Frame Generation dans ENB, ou retirer sl.*.dll et nvngx.dll de la bouteille.")))


def audit_crashlogger_extras(lines: list, report: AuditReport, scores: dict, weight: int, src: str):
    """Exploite SYSTEM SPECS / PROBABLE CALL STACK / STACK / MODULES. Retourne un extrait pour l'IA."""
    specs = {}
    for l in _section(lines, "SYSTEM SPECS:"):
        m = SPEC_RE.match(l)
        if m:
            specs[m.group(1)] = m.group(2).strip()
    call_stack = [l for l in (_section(lines, "PROBABLE CALL STACK:")
                              or _section(lines, "CALL STACK ([P]robable / [S]tack scan):")) if l.strip()]
    stack_lines = _section(lines, "STACK:")
    refs = [(m.group(1), m.group(2).upper()) for l in stack_lines for m in STACK_REF_RE.finditer(l)]
    modules = [re.split(r"\s{2,}|\t", l.strip())[0] for l in _section(lines, "MODULES:") if l.strip()]
    if not (specs or refs or modules):
        return None

    if specs:
        report.findings.append(Finding(
            SEV_INFO, "système", L("Configuration enregistrée par Crash Logger"),
            "; ".join(f"{k}: {v}" for k, v in specs.items()), src))
        is_wine = bool(WINE_RE.search(" ".join(specs.values())) or any(m.lower().startswith("wine") for m in modules))
        if is_wine:
            _bump(scores, L("[plateforme] CrossOver/Wine"), 3 * weight,
                  L("couche de compatibilité détectée ({src})", src=src))
            report.findings.append(Finding(
                SEV_WARN, "plateforme", L("Exécution via une couche de compatibilité (CrossOver/Wine/GPTK)"),
                L("Piles d'appels vides, adresses atypiques et échecs DLSS/Streamline sont fréquents dans "
                  "ce contexte : ne pas les imputer à un mod sans autre preuve."), src, [],
                L("Tester sans ENB/DLSS, essayer D3DMetal vs DXVK, mettre à jour CrossOver, "
                  "surveiller la mémoire unifiée.")))
            _wine_findings(lines, specs, modules, report, scores, weight, src, None)
        ram = MEM_RE.search(specs.get("PHYSICAL MEMORY", ""))
        vram = MEM_RE.search(specs.get("GPU MEMORY", ""))
        unified = bool(is_wine and ram and vram and float(vram.group(2)) >= float(ram.group(2)))
        if unified:
            report.findings.append(Finding(
                SEV_INFO, "mémoire", L("Mémoire unifiée : la « VRAM » annoncée n'est pas dédiée"),
                L("Le GPU partage la RAM du Mac ({vram} Go annoncés pour {ram} Go de RAM) : seule la RAM compte.",
                  vram=vram.group(2), ram=ram.group(2)), src, [],
                L("Surveiller la pression mémoire de macOS ; fermer les applications gourmandes.")))
        for key, label in (("PHYSICAL MEMORY", "RAM"), ("GPU MEMORY", "VRAM")):
            if unified and key == "GPU MEMORY":
                continue  # ratio sans signification en mémoire unifiée
            m = MEM_RE.search(specs.get(key, ""))
            if m and float(m.group(2)) > 0 and float(m.group(1)) / float(m.group(2)) >= 0.85:
                pct = 100 * float(m.group(1)) / float(m.group(2))
                _bump(scores, L("[mémoire]"), 5 * weight,
                      L("{label} à {pct} % au moment du crash ({src})", label=label, pct=f"{pct:.0f}", src=src))
                report.findings.append(Finding(
                    SEV_WARN, "mémoire", L("{label} presque saturée au moment du crash ({pct} %)",
                                           label=label, pct=f"{pct:.0f}"),
                    specs[key], src, [], L("Réduire textures/mods gourmands, fermer les applications, pagefile.")))

    if not call_stack:
        report.findings.append(Finding(
            SEV_WARN, "pile", L("Pile d'appels vide : Crash Logger n'a pas pu la reconstruire"),
            L("Fréquent sous Wine/Rosetta ou lors d'un crash dans du code généré ; l'analyse repose "
              "sur la section STACK brute."), src, [],
            L("Comparer plusieurs crash logs ; vérifier l'environnement avant d'accuser un mod.")))

    if refs:
        counts = Counter(m for m, _ in refs)
        third = Counter({m: n for m, n in counts.items() if not _is_ignored_module(m)})
        for mod, n in third.most_common(5):
            _bump(scores, mod, min(n, 4) * weight, L("{n}× dans le STACK ({src})", n=n, src=src))
        engine = Counter(off for m, off in refs if m.lower() == "skyrimse.exe")
        if engine:
            report.findings.append(Finding(
                SEV_INFO, "moteur", L("STACK : fonctions du moteur (SkyrimSE.exe) les plus citées"),
                ", ".join(f"+{o} ({n}×)" for o, n in engine.most_common(5)), src, [],
                L("Résoudre ces offsets via Address Library (même version de jeu) pour identifier la "
                  "fonction du moteur concernée.")))
        if any(m.lower() in ALLOCATOR_MODULES for m in counts):
            _bump(scores, L("[mémoire]"), 2 * weight, L("allocateur tbbmalloc dans le STACK ({src})", src=src))
            report.findings.append(Finding(
                SEV_INFO, "mémoire", L("Allocateur mémoire (tbbmalloc) présent dans le STACK"),
                L("Provient de SSE Engine Fixes ; à rapprocher de la pression mémoire."), src))

    if modules:
        low = [m.lower() for m in modules]
        dup_d3d11 = low.count("d3d11.dll") >= 2
        notable = []
        if dup_d3d11 or any(h in n for n in low for h in ENB_HINTS):
            notable.append(L("ENB/proxy d3d11"))
        if any(h in n for n in low for h in DLSS_HINTS):
            notable.append("DLSS/Streamline")
        if any("netscriptframework" in n for n in low):
            notable.append("NetScriptFramework")
        plugins = sum(1 for n in low if n.endswith(".dllplugin"))
        if notable:
            _bump(scores, L("[graphique]") + " " + ", ".join(notable), 2 * weight,
                  L("composants chargés ({src})", src=src))
            report.findings.append(Finding(
                SEV_INFO, "graphique", L("Composants notables chargés : {list}", list=", ".join(notable)),
                L("{n} modules chargés (dont ~{p} plugins .dllplugin).", n=len(modules), p=plugins), src, [],
                L("Tester sans ENB/DLSS pour isoler un problème de rendu.")))

    head = []
    for l in lines:
        if l.strip() == "REGISTERS:":
            break
        head.append(l)
    resolved = [l.strip() for l in stack_lines if "->" in l][:60]
    parts = head[:40] + ["", "STACK (références résolues) :"] + resolved
    if modules:
        parts += ["", "MODULES : " + ", ".join(modules)[:3500]]
    return "\n".join(parts)


# -------------------------------------------------------------------- skse
SKSE_BAD_RE = re.compile(r"(couldn'?t load|could not load|disabled|fatal error|no version data|"
                         r"incompatible|not a plugin|failed|error|0x[0-9a-f]{4,})", re.I)
SKSE_VERSION_RE = re.compile(r"version = ([\d.]+) ([0-9A-Fa-f]{8})")
SKSE_LOADED_RE = re.compile(r"\(([0-9A-Fa-f]{8}) (.+?) ([0-9A-Fa-f]{8})\) loaded correctly \(handle (\d+)\)")
SKSE_SEND_RE = re.compile(r"sending message type \d+ to plugin (\d+)")
SKSE_LISTENER_RE = re.compile(r"registering plugin listener for (\S+) at \d+ of \d+")


def audit_skse(path: str, lines: list, report: AuditReport, scores: dict):
    src = os.path.basename(path)
    bad = [l.strip() for l in lines if ".dll" in l.lower() and SKSE_BAD_RE.search(l)
           and "loaded correctly" not in l.lower()]
    excerpt_lines = list(bad)
    ver = SKSE_VERSION_RE.search(lines[0]) if lines else None
    if ver:
        rt = ver.group(2)
        report.skse_runtime = rt
        report.findings.append(Finding(
            SEV_INFO, "skse", L("SKSE {v} — runtime {rt}", v=ver.group(1), rt=compat.runtime_label(rt)), "", src))
        excerpt_lines.insert(0, lines[0].strip())
    handles = {}
    for l in lines:
        m = SKSE_LOADED_RE.search(l)
        if m:
            handles[int(m.group(4))] = m.group(2)
    exc_found = False
    for i, l in enumerate(lines):
        if not re.search(r"exception occurred while loading plugins", l, re.I):
            continue
        exc_found = True
        last_msg = next((SKSE_SEND_RE.search(p) for p in reversed(lines[:i]) if SKSE_SEND_RE.search(p)), None)
        last_reg = next((SKSE_LISTENER_RE.search(p) for p in reversed(lines[:i]) if SKSE_LISTENER_RE.search(p)), None)
        culprit = handles.get(int(last_msg.group(1))) if last_msg else None
        related = last_reg.group(1) if last_reg else None
        name = culprit or related or L("plugin inconnu")
        detail = (L("Un plugin a levé une exception pendant la phase de chargement/PostLoad. "
                    "Dernier plugin actif : {name}", name=name)
                  + (L(" (handle {h})", h=last_msg.group(1)) if last_msg else "")
                  + (L(", en train de s'enregistrer auprès de {related}", related=related) if related else "") + ".")
        ctx = [x.strip() for x in lines[max(0, i - 3): i + 1]]
        report.findings.append(Finding(
            SEV_CRIT, "skse", L("Exception SKSE au chargement des plugins (suspect : {name})", name=name),
            detail, src, ctx,
            L("Désactiver ce plugin (et son dépendant) ; vérifier sa version vis-à-vis du jeu/SKSE et ses "
              "prérequis (ex. mod UI installé ?).")))
        _bump(scores, name + ".dll" if culprit else name, 12, L("exception SKSE au chargement ({src})", src=src))
        if related and related != name:
            _bump(scores, related, 3, L("plugin lié à l'exception SKSE ({src})", src=src))
        excerpt_lines = ctx + excerpt_lines
        break
    for l in bad:
        m = MODULE_RE.search(l)
        dll = m.group(1) if m else L("plugin inconnu")
        sev = SEV_CRIT if re.search(r"incompatible|no version data|couldn'?t load|fatal", l, re.I) else SEV_WARN
        _bump(scores, dll, 5 if sev == SEV_CRIT else 2, L("refusé/en erreur au chargement SKSE ({src})", src=src))
        report.findings.append(Finding(
            sev, "skse", L("Plugin SKSE en échec : {dll}", dll=dll), "", src, [l],
            L("Mettre à jour le plugin pour la version du jeu/SKSE, ou le retirer.")))
    compat.audit_log_compat(lines, src, report, scores, _bump)
    if not bad and not exc_found and not compat.not_loaded(report.skse_info or {"checked": [], "loaded": {}}):
        report.findings.append(Finding(SEV_INFO, "skse", L("Tous les plugins SKSE se sont chargés"), "", src))
    report.excerpts[path] = "\n".join(excerpt_lines[:60])[:6000] or L("(aucune erreur de chargement)")


# ----------------------------------------------------------------- papyrus
PAPY_ERR_RE = re.compile(r"\berror:\s*(.*)", re.I)
PSC_RE = re.compile(r"([A-Za-z0-9_]+)\.psc", re.I)
STORE_RE = re.compile(r'Cannot open store for class "([^"]+)"', re.I)
BIND_RE = re.compile(r"Script (\S+) cannot be bound to", re.I)
NATIVE_RE = re.compile(r"Native function (\S+) in (?:empty )?state could find no matching function", re.I)


def audit_papyrus(path: str, lines: list, report: AuditReport, scores: dict):
    src = os.path.basename(path)
    msgs, scripts, missing = Counter(), Counter(), Counter()
    unbound, native_unbound = Counter(), Counter()
    for i, l in enumerate(lines):
        mc = STORE_RE.search(l)
        if mc:
            missing[mc.group(1)] += 1
        mb = BIND_RE.search(l)
        if mb:
            unbound[mb.group(1)] += 1
        mn = NATIVE_RE.search(l)
        if mn:
            native_unbound[mn.group(1)] += 1
        m = PAPY_ERR_RE.search(l)
        if not m:
            continue
        msg = re.sub(r"0x[0-9a-f]+|\d+", "#", m.group(1)).strip()[:140]
        msgs[msg] += 1
        for nxt in lines[i + 1: i + 8]:
            ms = PSC_RE.search(nxt)
            if ms:
                scripts[ms.group(1)] += 1
                break
    cc_missing = {k: v for k, v in missing.items() if k.lower().startswith("cc")}
    other_missing = {k: v for k, v in missing.items() if k not in cc_missing}
    if cc_missing:
        report.findings.append(Finding(
            SEV_WARN, "script", L("Contenu Creation Club manquant ou incomplet"),
            ", ".join(f"{k} ({v}×)" for k, v in sorted(cc_missing.items())[:8]), src, [],
            L("Télécharger/réinstaller le contenu Creation Club via le jeu (Créations) ou retirer les mods qui "
              "le requièrent ; ne pas utiliser le menu Créations avec MO2/Vortex.")))
        _bump(scores, L("[creation club] contenu manquant"), 2,
              L("{n} script(s) CC introuvable(s) dans {src}", n=len(cc_missing), src=src))
    if other_missing:
        report.findings.append(Finding(
            SEV_WARN, "script", L("Scripts introuvables (mod retiré en cours de partie ou fichiers manquants)"),
            ", ".join(f"{k} ({v}×)" for k, v in sorted(other_missing.items(), key=lambda x: -x[1])[:8]),
            src, [], L("Réinstaller le mod ou nettoyer la sauvegarde (ReSaver).")))
        for k, v in sorted(other_missing.items(), key=lambda x: -x[1])[:3]:
            _bump(scores, k + ".psc", min(v, 4) + 1, L("script manquant dans {src}", src=src))
    if unbound:
        report.findings.append(Finding(
            SEV_WARN, "script", L("Scripts non liés à leur quest/objet"),
            ", ".join(f"{k} ({v}×)" for k, v in unbound.most_common(5)), src, [],
            L("Le script n'existe pas ou n'est pas chargé : mod incomplet, master manquant ou ancien save.")))
        for k, v in unbound.most_common(3):
            _bump(scores, k + ".psc", 2, L("script non lié dans {src}", src=src))
    if native_unbound:
        report.findings.append(Finding(
            SEV_WARN, "script", L("Fonctions natives Papyrus non liées"),
            L("{n} fonction(s) : ", n=sum(native_unbound.values())) + ", ".join(list(native_unbound)[:5]), src, [],
            L("Typiquement un plugin SKSE absent/incompatible ou des .pex d'un mod qui attendent une "
              "fonction native qui n'existe pas dans cette version.")))
        _bump(scores, L("[script] fonctions natives non liées"), 2,
              L("{n} fonction(s) native(s) dans {src}", n=sum(native_unbound.values()), src=src))
    total = sum(msgs.values())
    stacks = sum(1 for l in lines if re.search(r"dumping stack|stack overflow|suspended stack", l, re.I))
    if stacks:
        report.findings.append(Finding(
            SEV_CRIT, "script", L("Surcharge Papyrus (piles de scripts en vidange)"),
            L("{n} occurrence(s) — scripts trop nombreux ou en boucle.", n=stacks), src, [],
            L("Repérer le script le plus bavard ci-dessous ; désactiver le mod ou nettoyer la sauvegarde.")))
        _bump(scores, L("[script] surcharge Papyrus"), 5, L("{n} vidange(s) de piles dans {src}", n=stacks, src=src))
    if total:
        top = scripts.most_common(5)
        if top:
            report.findings.append(Finding(
                SEV_WARN if top[0][1] >= 20 else SEV_INFO, "script",
                L("{total} erreurs Papyrus ; scripts les plus fautifs", total=total),
                ", ".join(f"{k} ({v}×)" for k, v in top), src,
                [f"{n}× {m}" for m, n in msgs.most_common(3)],
                L("Un script très bavard est un suspect fréquent de lenteurs/instabilité.")))
            for k, v in top[:3]:
                if v >= 5:
                    _bump(scores, k, min(v // 5, 5), L("{v} erreurs Papyrus ({src})", v=v, src=src))
    extra_lines = [L("script introuvable : {k} ({v}×)", k=k, v=v) for k, v in list(missing.items())[:15]]
    extra_lines += [L("script non lié : {k} ({v}×)", k=k, v=v) for k, v in list(unbound.items())[:10]]
    extra_lines += [L("fonction native non liée : {k}", k=k) for k in list(native_unbound)[:10]]
    report.excerpts[path] = "\n".join(
        [f"{n}× {m}" for m, n in msgs.most_common(15)] + extra_lines)[:6000] or L("(aucune erreur)")


# ------------------------------------------------------- logs de plugins (autres)
PLUGIN_STRONG_RE = re.compile(r"\[(?:critical|error|fatal)\]|\bfatal\b", re.I)
PLUGIN_WEAK_RE = re.compile(r"exception|failed to", re.I)
ENGINEFIXES_VER_RE = re.compile(r"Engine Fixes v(\d+)\.(\d+)\.(\d+)")


def audit_other(path: str, lines: list, report: AuditReport, scores: dict):
    """Logs de plugins (Engine Fixes, ENB, JContainers...) : erreurs critiques et versions connues."""
    src = os.path.basename(path)
    stem = os.path.splitext(src)[0]
    ver = ENGINEFIXES_VER_RE.search("\n".join(lines[:20]))
    if ver and int(ver.group(1)) < 7:
        v = ".".join(ver.groups())
        report.findings.append(Finding(
            SEV_WARN, "version", L("SSE Engine Fixes v{v} (ancienne branche, avant v7)", v=v),
            L("Avant la v7, EngineFixes.toml doit contenir SaveGameMaxSize = true et MaxStdio = 8192 ; "
              "les DLL de la partie 2 (tbbmalloc.dll...) doivent être à la racine du jeu."), src, [],
            L("Vérifier ces réglages ou passer à la v7 recommandée par la communauté.")))
        _bump(scores, "EngineFixes.dll", 1, L("version ancienne v{v} ({src})", v=v, src=src))
    strong = [l.strip() for l in lines if PLUGIN_STRONG_RE.search(l)]
    weak = [l.strip() for l in lines if PLUGIN_WEAK_RE.search(l) and l.strip() not in strong]
    if strong:
        streamline = any(re.search(r"streamline", l, re.I) for l in strong)
        tip = (L("DLSS/Streamline indisponible (normal sous CrossOver/Wine ou sans GPU NVIDIA RTX) : "
                 "désactiver DLSS/Frame Generation dans ENB.") if streamline
               else L("Consulter ce log et la page du mod ; mettre à jour ou retirer le plugin."))
        report.findings.append(Finding(
            SEV_WARN, "plugin", L("Erreur critique dans le log de {stem}", stem=stem),
            L("{n} ligne(s) critique(s)", n=len(strong)), src, strong[:3], tip))
        _bump(scores, stem, min(len(strong), 3) + (0 if streamline else 1),
              L("{n} erreur(s) critique(s) dans {src}", n=len(strong), src=src))
    elif weak:
        report.findings.append(Finding(
            SEV_INFO, "plugin", L("Messages d'échec dans le log de {stem}", stem=stem),
            L("{n} ligne(s)", n=len(weak)), src, weak[:2], ""))
    if strong or weak:
        report.excerpts[path] = "\n".join((strong + weak)[:30])[:3000]


# ----------------------------------------------------------------- général
def _bump(scores: dict, name: str, pts: int, reason: str):
    entry = scores.setdefault(name, {"score": 0, "reasons": []})
    entry["score"] += pts
    if reason not in entry["reasons"]:
        entry["reasons"].append(reason)


def audit_paths(paths: list, game_dir: str = "") -> AuditReport:
    """Analyse une liste de fichiers logs ; game_dir (optionnel) active la corrélation avec l'installation."""
    report = AuditReport()
    scores: dict = {}
    entries = []
    for p in paths:
        try:
            mtime = os.path.getmtime(p)
        except OSError:
            continue
        lines = read_lines(p)
        if lines:
            entries.append((mtime, p, lines, classify_log(p, lines)))
    entries.sort(key=lambda e: e[0], reverse=True)

    crashes = [e for e in entries if e[3] == "crash"][:MAX_CRASH_LOGS]
    for idx, (_m, p, lines, _k) in enumerate(crashes):
        audit_crash(p, lines, report, scores, is_latest=(idx == 0))
        report.analysed.append(p)
    seen, papy_count = set(), 0
    for _m, p, lines, kind in entries:
        if kind in ("skse", "papyrus", "other"):
            key = (kind, hash("\n".join(lines)))
            if key in seen:      # logs identiques (rotation Papyrus.0..3, copies) : analysés une fois
                continue
            seen.add(key)
        if kind == "papyrus":
            papy_count += 1
            if papy_count > MAX_PAPYRUS_LOGS:
                continue
        if kind == "skse":
            audit_skse(p, lines, report, scores)
            report.analysed.append(p)
        elif kind == "papyrus":
            audit_papyrus(p, lines, report, scores)
            report.analysed.append(p)
        elif kind == "other":
            audit_other(p, lines, report, scores)
            report.analysed.append(p)

    gdir = compat.find_game_dir((report.skse_info or {}).get("plugin_dir"), game_dir)
    if game_dir and not os.path.isfile(os.path.join(game_dir, "SkyrimSE.exe")):
        report.findings.append(Finding(
            SEV_WARN, "réglages", L("Le dossier du jeu des réglages n'existe plus"),
            L("Réglage : {old} — utilisé à la place : {new}", old=game_dir, new=gdir or L("aucun")),
            L("réglages"), [], L("Mettre à jour le dossier du jeu dans Réglages… > Général.")))
        if gdir:
            report.extras["game_dir_found"] = gdir  # proposé à l'utilisateur pour corriger le réglage
    if gdir:
        try:
            compat.audit_install(gdir, report, scores, _bump)
        except OSError:
            pass  # installation illisible : on garde l'audit basé sur les logs

    try:
        insights.analyse(report, scores, entries, gdir, read_lines, _bump)
    except (OSError, ValueError) as e:  # recoupements facultatifs : jamais bloquants
        report.findings.append(Finding(SEV_INFO, "recoupement", L("Recoupements incomplets : {e}", e=e), "", ""))
    try:
        report.extras["inventory"] = inventory.build(gdir, entries, report.extras.get("history") or [])
    except OSError:
        pass  # fiche facultative : l'audit reste valable sans elle

    report.suspects = sorted(
        ((n, d["score"], d["reasons"]) for n, d in scores.items()), key=lambda x: -x[1])[:8]
    try:
        origins = mod_origin.build_index(gdir)
    except OSError:
        origins = {}
    for name, _s, reasons in report.suspects:
        mods = mod_origin.origin_of(name, origins) if name.lower().endswith(mod_origin.EXTS) else []
        if mods:
            reasons.append(L("fourni par le mod « {mod} »", mod=", ".join(mods[:3])))
    for name, role in compat.annotate_suspects(report):
        for n, _s, reasons in report.suspects:
            if n == name:
                reasons.append(L("rôle connu : {role}", role=role))
    if not crashes and not report.findings:
        report.verdict = L("aucun crash log trouvé")
    elif not crashes:
        report.verdict = L("pas de crash log, anomalies secondaires uniquement")
    elif report.suspects:
        report.verdict = L("suspect principal : {name}", name=report.suspects[0][0])
    else:
        report.verdict = L("crash détecté, source indéterminée")
    return report
