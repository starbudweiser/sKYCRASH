"""Compatibilité jeu / SKSE / plugins et corrélation avec l'installation de Skyrim.

Deux niveaux :
- à partir des seuls logs (skse64.log) : runtime décodé, plugins vérifiés mais non chargés ;
- avec le dossier du jeu (détecté sous CrossOver ou choisi) : version de SkyrimSE.exe,
  Address Library correspondante, DLL SKSE présentes, plugins.txt, âge des DLL suspectes.
"""
import glob
import os
import re
import struct
from datetime import datetime

from i18n import L, N_

BOTTLES_GLOB = os.path.expanduser("~/Library/Application Support/CrossOver/Bottles/*")
MAX_EXE_BYTES = 80 * 1024 * 1024
MAX_PLUGINS_NON_ESL = 254
# DLL présentes dans Plugins/ mais qui ne sont pas des plugins SKSE (dépendances d'autres mods)
NON_PLUGIN_DLLS = {"msdia140.dll"}  # lue par Crash Logger SSE pour les symboles de débogage

CHECK_RE = re.compile(r"checking plugin (.+?\.dll)\s*$", re.I)
LOADED_RE = re.compile(r"plugin (.+?\.dll) \(([0-9A-Fa-f]{8}) (.+?) ([0-9A-Fa-f]{8})\) loaded correctly \(handle (\d+)\)", re.I)
PLUGIN_DIR_RE = re.compile(r"plugin directory = (.+?)\\?\s*$", re.I)

# DLL SKSE connues : nom de fichier (minuscules) -> (mod, rôle). Usage : contexte pour le diagnostic.
DLL_CATALOG = {
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
}

_RUNTIME_RE = re.compile(r"^[0-9A-Fa-f]{8}$")


def decode_runtime(hex8: str):
    """01050610 -> (1, 5, 97) ; format SKSE : major<<24 | minor<<16 | build<<4 | sub."""
    if not hex8 or not _RUNTIME_RE.match(hex8):
        return None
    v = int(hex8, 16)
    return (v >> 24, (v >> 16) & 0xFF, (v >> 4) & 0xFFF)


def runtime_label(hex8: str) -> str:
    t = decode_runtime(hex8)
    if not t:
        return hex8 or "inconnu"
    kind = "SE" if (t[0], t[1]) == (1, 5) else "AE" if (t[0], t[1]) >= (1, 6) else "?"
    return f"{t[0]}.{t[1]}.{t[2]} ({kind})"


def address_library_name(version: tuple) -> str:
    major, minor, build = version[:3]
    prefix = "version" if (major, minor) == (1, 5) else "versionlib"  # SE : version-*.bin ; AE : versionlib-*.bin
    return f"{prefix}-{major}-{minor}-{build}-0.bin"


def _base(win_path: str) -> str:
    return re.split(r"[\\/]+", win_path.strip())[-1]


def skse_plugins(lines: list) -> dict:
    """Retourne {'checked': [dll...], 'loaded': {dll_lower: (affichage, handle)}, 'plugin_dir': str|None}."""
    checked, loaded, pdir = [], {}, None
    for l in lines:
        m = PLUGIN_DIR_RE.search(l)
        if m and pdir is None:
            pdir = m.group(1).strip().rstrip("\\")
        m = CHECK_RE.search(l)
        if m:
            checked.append(_base(m.group(1)))
            continue
        m = LOADED_RE.search(l)
        if m:
            loaded[_base(m.group(1)).lower()] = (m.group(3), int(m.group(5)))
    return {"checked": checked, "loaded": loaded, "plugin_dir": pdir}


def not_loaded(info: dict) -> list:
    return [d for d in info["checked"]
            if d.lower() not in info["loaded"] and d.lower() not in NON_PLUGIN_DLLS]


# ------------------------------------------------------------ dossier du jeu
_extra_roots: list = []  # dossiers contenant d'autres bouteilles (ex. disque externe), déduits du réglage


def _bottle_root_of(path: str):
    parts = os.path.normpath(path or "").split(os.sep)
    if "drive_c" in parts and parts.index("drive_c") >= 2:
        return os.sep.join(parts[:parts.index("drive_c") - 1])
    return None


def _bottles() -> list:
    globs = [BOTTLES_GLOB] + [os.path.join(r, "*") for r in _extra_roots]
    out = []
    for g in globs:
        for b in sorted(glob.glob(g)):
            if os.path.isdir(os.path.join(b, "drive_c")) and b not in out:
                out.append(b)
    return out


def win_to_host(win_path: str) -> list:
    """Chemin Windows (C:\\Games\\...) -> chemins candidats dans les bouteilles CrossOver."""
    m = re.match(r"^([A-Za-z]):[\\/]+(.*)$", win_path.strip())
    if not m:
        return []
    rel = re.split(r"[\\/]+", m.group(2))
    return [os.path.join(b, "drive_c" if m.group(1).upper() == "C" else f"dosdevices/{m.group(1).lower()}:", *rel)
            for b in _bottles()]


def find_game_dir(plugin_dir_win: str = None, user_dir: str = "") -> str:
    """Dossier contenant SkyrimSE.exe : choix utilisateur, sinon déduit du log SKSE sous CrossOver.

    Les bouteilles voisines de celle du réglage (même dossier parent) sont aussi explorées :
    une bouteille renommée ou déplacée sur un disque externe reste trouvée.
    """
    root = _bottle_root_of(user_dir)
    if root and root not in _extra_roots:
        _extra_roots.append(root)
    cands = []
    if user_dir:
        cands.append(user_dir)
    if plugin_dir_win:
        for p in win_to_host(plugin_dir_win):  # .../Data/SKSE/Plugins -> racine du jeu
            cands.append(os.path.normpath(os.path.join(p, "..", "..", "..")))
    for b in _bottles():
        for sub in ("Games/Skyrim Special Edition", "Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition",
                    "GOG Games/Skyrim Special Edition", "Program Files (x86)/GOG Galaxy/Games/Skyrim Special Edition"):
            cands.append(os.path.join(b, "drive_c", *sub.split("/")))
    for c in cands:
        if os.path.isfile(os.path.join(c, "SkyrimSE.exe")):
            return c
    return ""


def read_exe_version(exe_path: str):
    """Version de fichier (major, minor, build, rev) lue dans la ressource VS_FIXEDFILEINFO."""
    try:
        with open(exe_path, "rb") as f:
            data = f.read(MAX_EXE_BYTES)
    except OSError:
        return None
    i = data.find(b"\xbd\x04\xef\xfe")  # signature 0xFEEF04BD
    if i < 0 or i + 16 > len(data):
        return None
    ms, ls = struct.unpack_from("<II", data, i + 8)
    return (ms >> 16, ms & 0xFFFF, ls >> 16, ls & 0xFFFF)


def _plugins_txt_in(drive_c: str):
    for d in glob.glob(os.path.join(drive_c, "users", "*", "AppData", "Local", "Skyrim Special Edition*")):
        try:
            for n in os.listdir(d):
                if n.lower() == "plugins.txt":
                    return os.path.join(d, n)
        except OSError:
            continue
    return None


def find_plugins_txt(game_dir: str):
    """plugins.txt de la bouteille qui contient le jeu, sinon de la première bouteille CrossOver qui en a un."""
    parts = os.path.normpath(game_dir or "").split(os.sep)
    if "drive_c" in parts:
        hit = _plugins_txt_in(os.sep.join(parts[:parts.index("drive_c") + 1]))
        if hit:
            return hit
    for b in _bottles():
        hit = _plugins_txt_in(os.path.join(b, "drive_c"))
        if hit:
            return hit
    return None


def is_light_plugin(path: str) -> bool:
    """Vrai pour un .esl ou un .esp/.esm marqué ESL (drapeau 0x200 de l'en-tête TES4)."""
    if path.lower().endswith(".esl"):
        return True
    try:
        with open(path, "rb") as f:
            head = f.read(12)
    except OSError:
        return False  # plugin listé mais absent : compté comme plein, par prudence
    return len(head) == 12 and head[:4] == b"TES4" and bool(struct.unpack_from("<I", head, 8)[0] & 0x200)


def _fmt_date(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%d/%m/%Y")


# ------------------------------------------------------------------- audits
def audit_log_compat(lines: list, src: str, report, scores, bump):
    """Constats issus du seul skse64.log : plugins vérifiés mais non chargés."""
    from audit_engine import Finding, SEV_CRIT, SEV_INFO
    info = skse_plugins(lines)
    report.skse_info = info
    plugins = [d for d in info["checked"] if d.lower() not in NON_PLUGIN_DLLS]
    if plugins:
        report.findings.append(Finding(
            SEV_INFO, "skse", L("{loaded} plugin(s) SKSE chargés sur {total} vérifiés",
                                loaded=len(info["loaded"]), total=len(plugins)), "", src))
    for dll in not_loaded(info):
        report.findings.append(Finding(
            SEV_CRIT, "skse", L("Plugin SKSE vérifié mais non chargé : {dll}", dll=dll),
            L("SKSE a examiné ce fichier sans le valider : version du jeu/SKSE incompatible, Address Library absente, "
              "DLL corrompue ou dépendance manquante. Il a pu aussi faire planter le chargement."), src, [],
            L("Mettre à jour la DLL pour la version du jeu, installer l'Address Library correspondante, ou la retirer.")))
        bump(scores, dll, 6, L("vérifié mais non chargé par SKSE ({src})", src=src))


def audit_install(game_dir: str, report, scores, bump):
    """Constats issus de l'installation : version de l'exe, Address Library, DLL, plugins.txt."""
    from audit_engine import Finding, SEV_CRIT, SEV_INFO, SEV_WARN
    report.game_dir = game_dir
    exe = os.path.join(game_dir, "SkyrimSE.exe")
    ver = read_exe_version(exe)
    plug_dir = os.path.join(game_dir, "Data", "SKSE", "Plugins")
    src = L("installation")
    if ver:
        report.findings.append(Finding(SEV_INFO, "version", f"SkyrimSE.exe {ver[0]}.{ver[1]}.{ver[2]}.{ver[3]}", game_dir, src))
        info = getattr(report, "skse_info", None)
        rt = None
        if info is not None and getattr(report, "skse_runtime", None):
            rt = decode_runtime(report.skse_runtime)
        if rt and rt[:3] != ver[:3]:
            report.findings.append(Finding(
                SEV_CRIT, "version", L("Version du jeu différente du runtime SKSE du log"),
                L("Jeu {gv} / SKSE compilé pour {sv}.", gv=f"{ver[0]}.{ver[1]}.{ver[2]}", sv=f"{rt[0]}.{rt[1]}.{rt[2]}"),
                src, [],
                L("Installer la build SKSE correspondant exactement au jeu (SE 1.5.97 ou AE 1.6.x).")))
            bump(scores, L("[version] jeu/SKSE incohérents"), 10, L("version de SkyrimSE.exe ≠ runtime SKSE"))
        al = address_library_name(ver)
        # builds AE 1.7.x : nommage des fichiers Address Library non vérifié -> pas de contrôle de fichier
        if (ver[0], ver[1]) <= (1, 6) and os.path.isdir(plug_dir) and not os.path.isfile(os.path.join(plug_dir, al)):
            report.findings.append(Finding(
                SEV_WARN, "version", L("Address Library introuvable ({al})", al=al),
                L("Les plugins SKSE modernes en dépendent : sans elle, ils ne se chargent pas ou plantent."), src, [],
                L("Installer l'Address Library correspondant à cette version du jeu (SE : « All in one 1.5.97 »).")))
            bump(scores, L("[version] Address Library absente"), 6, L("{al} absent de Data/SKSE/Plugins", al=al))
    elif os.path.isfile(exe):
        report.findings.append(Finding(SEV_INFO, "version", L("Version de SkyrimSE.exe illisible"), exe, src))

    if os.path.isdir(plug_dir):
        try:
            files = {n.lower(): n for n in os.listdir(plug_dir) if n.lower().endswith(".dll")}
        except OSError:
            files = {}
        info = getattr(report, "skse_info", None)
        if info and info["checked"]:
            known = {d.lower() for d in info["checked"]}
            extra = [files[k] for k in files if k not in known]
            if extra:
                report.findings.append(Finding(
                    SEV_INFO, "skse", L("{n} DLL présentes mais absentes du log SKSE", n=len(extra)),
                    ", ".join(sorted(extra)[:8]), src, [],
                    L("Log ancien (jeu lancé avant l'ajout ?) ou DLL ignorées par SKSE.")))
        # corrélation suspects -> fichiers réels
        shown = 0
        for name, _score, _reasons in sorted(((n, d["score"], d["reasons"]) for n, d in scores.items()),
                                              key=lambda x: -x[1]):
            low = name.lower()
            if low in files and shown < 5:
                p = os.path.join(plug_dir, files[low])
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                cat = DLL_CATALOG.get(low)
                detail = L("Fichier {f} — {kb} Ko, modifié le {d}", f=files[low], kb=st.st_size // 1024,
                           d=_fmt_date(st.st_mtime))
                if cat:
                    detail += f" — {cat[0]} : {L(cat[1])}"
                report.findings.append(Finding(
                    SEV_INFO, "mod", L("Suspect présent dans l'installation : {f}", f=files[low]), detail, src))
                shown += 1

    ptxt = find_plugins_txt(game_dir)
    if ptxt:
        try:
            with open(ptxt, encoding="utf-8", errors="ignore") as f:
                entries = [l.strip() for l in f if l.strip() and not l.startswith("#")]
        except OSError:
            entries = []
        active = [e.lstrip("*") for e in entries if e.startswith("*")]
        report.findings.append(Finding(
            SEV_INFO, "plugins", L("plugins.txt : {a} plugin(s) actifs sur {t}", a=len(active), t=len(entries)),
            ptxt, src))
        data_dir = os.path.join(game_dir, "Data")
        esl_unknown = [e for e in active if e.lower().endswith((".esp", ".esm"))
                       and not is_light_plugin(os.path.join(data_dir, e))]
        if len(esl_unknown) > MAX_PLUGINS_NON_ESL:
            report.findings.append(Finding(
                SEV_WARN, "plugins",
                L("{n} plugins .esp/.esm actifs (limite {max} hors ESL)", n=len(esl_unknown), max=MAX_PLUGINS_NON_ESL),
                L("Au-delà, les formIDs se corrompent ou le jeu plante."), src, [],
                L("Flaguer ESL les plugins éligibles (xEdit) ou retirer des mods.")))
            bump(scores, L("[plugins] limite 254 dépassée"), 8, L("trop de plugins actifs"))


def annotate_suspects(report):
    """Ajoute le rôle connu des DLL suspectes (catalogue) aux raisons du classement."""
    notes = []
    for name, score, reasons in report.suspects:
        cat = DLL_CATALOG.get(name.lower())
        if cat:
            notes.append((name, f"{cat[0]} : {L(cat[1])}"))
    return notes
