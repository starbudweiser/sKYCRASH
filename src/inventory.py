"""Fiche d'installation vérifiée : ce qui est réellement présent dans le jeu, lu sur le disque.

Envoyée à l'assistant IA comme FAITS (à ne pas remettre en cause), et utilisée par guard.py
pour retirer les conseils qui les contredisent (« installer Crash Logger » alors qu'il est là).
"""
from __future__ import annotations

import glob
import os
import re

import compat
import insights
from i18n import L

# clé -> (nom affiché, fichiers DLL dans Data/SKSE/Plugins, en minuscules)
TOOLS = {
    "crashlogger": ("Crash Logger SSE", ("crashlogger.dll",)),
    "trainwreck": ("Trainwreck", ("trainwreck.dll",)),
    "enginefixes": ("SSE Engine Fixes", ("enginefixes.dll",)),
    "bugfixes": ("Bug Fixes SSE", ("bugfixessse.dll",)),
    "scrambledbugs": ("Scrambled Bugs", ("scrambledbugs.dll",)),
    "papyrustweaks": ("Papyrus Tweaks NG", ("papyrustweaks.dll",)),
    "displaytweaks": ("SSE Display Tweaks", ("ssedisplaytweaks.dll",)),
    "spid": ("Spell Perk Item Distributor", ("po3_spellperkitemdistributor.dll",)),
    "kid": ("Keyword Item Distributor", ("po3_keyworditemdistributor.dll",)),
    "bos": ("Base Object Swapper", ("po3_baseobjectswapper.dll",)),
    "papyrusextender": ("powerofthree's Papyrus Extender", ("po3_papyrusextender.dll",)),
    "tweaks": ("powerofthree's Tweaks", ("po3_tweaks.dll",)),
    "jcontainers": ("JContainers", ("jcontainers64.dll",)),
    "racemenu": ("RaceMenu (skee64)", ("skee64.dll",)),
    "mcmhelper": ("MCM Helper", ("mcmhelper.dll",)),
    "communityshaders": ("Community Shaders", ("communityshaders.dll",)),
}
PROXY_DLLS = ("d3d11.dll", "dxgi.dll", "d3d12.dll")
# (marqueur binaire, rôle) : le premier trouvé l'emporte (le pont mDLSS contient aussi « enbseries »)
PROXY_MARKERS = ((b"mDLSS", "pont mDLSS (DLSS vers MetalFX)"), (b"crosire's ReShade", "ReShade"),
                 (b"ReShade", "ReShade"), (b"ENBSeries", "ENB"), (b"enbseries", "ENB"),
                 (b"DXVK", "DXVK"), (b"dxmt", "DXMT"), (b"Community Shaders", "Community Shaders"))
SKSE_VERSION_RE = re.compile(r"SKSE64 runtime: initialize \(version = ([\d.]+)")
CRASHLOGGER_VER_RE = re.compile(r"CrashLoggerSSE v([\d-]+)")


def build(game_dir: str, entries: list, history: list) -> dict:
    """Faits vérifiés. `entries` : logs lus par le moteur ; `history` : crash logs (actifs et archivés)."""
    facts = {"game_dir": game_dir or ""}
    if game_dir:
        ver = compat.read_exe_version(os.path.join(game_dir, "SkyrimSE.exe"))
        facts["game_version"] = ".".join(map(str, ver)) if ver else None
        plug_dir = os.path.join(game_dir, "Data", "SKSE", "Plugins")
        try:
            dlls = {n.lower() for n in os.listdir(plug_dir)}
        except OSError:
            dlls = set()
        facts["tools"] = {k: any(f in dlls for f in files) for k, (_label, files) in TOOLS.items()}
        facts["skse_installed"] = bool(glob.glob(os.path.join(game_dir, "skse64_*.dll")))
        if ver:
            facts["address_library"] = compat.address_library_name(ver).lower() in dlls
        root = {n.lower() for n in os.listdir(game_dir)} if os.path.isdir(game_dir) else set()
        facts["enb"] = "enbseries.ini" in root
        facts["reshade"] = "reshade.ini" in root
        facts["proxies"] = {n: _proxy_role(os.path.join(game_dir, n)) for n in PROXY_DLLS if n in root}

        ccc = []
        try:
            with open(os.path.join(game_dir, "Skyrim.ccc"), encoding="utf-8", errors="ignore") as f:
                ccc = [l.strip() for l in f if l.strip()]
        except OSError:
            pass
        data_dir = os.path.join(game_dir, "Data")
        try:
            data = {n.lower() for n in os.listdir(data_dir)}
        except OSError:
            data = set()
        facts["cc"] = {"listed": len(ccc), "present": sum(1 for c in ccc if c.lower() in data)}

        act, _data, ptxt = insights.active_plugins(game_dir)
        light = sum(1 for p in act if compat.is_light_plugin(os.path.join(data_dir, p)))
        full = len(act) - light
        facts["plugins"] = {"active": len(act), "full": full, "light": light,
                            "limit_ok": full <= compat.MAX_PLUGINS_NON_ESL, "plugins_txt": ptxt}
        parts = os.path.normpath(game_dir).split(os.sep)
        if "drive_c" in parts and parts.index("drive_c") >= 1:
            facts["bottle"] = parts[parts.index("drive_c") - 1]

    for _m, path, lines, kind in entries:
        if kind == "skse":
            m = next((SKSE_VERSION_RE.search(l) for l in lines[:5] if SKSE_VERSION_RE.search(l)), None)
            if m:
                facts["skse_version"] = m.group(1)
                break
    active = [c for c in history if insights.ARCHIVE_DIR not in c["path"].split(os.sep)]
    archived = [c for c in history if c not in active]
    folders = sorted({os.path.dirname(p) for _m, p, _l, _k in entries})
    skse_dir = next((os.path.join(d, "SKSE") for d in insights._docs_dirs(folders)
                     if os.path.isdir(os.path.join(d, "SKSE"))),
                    next((os.path.dirname(p) for _m, p, _l, kind in entries if kind == "skse"), ""))
    facts["crash_logs"] = {
        "active": len(active), "archived": len(archived),
        "dir": (os.path.dirname(history[0]["path"]).replace(os.sep + insights.ARCHIVE_DIR, "") if history
                else skse_dir),  # Crash Logger écrit à côté de skse64.log
        "last": (history[0]["time"].strftime("%d/%m/%Y %H:%M"), history[0]["where"]) if history and history[0]["time"] else None,
    }
    for c in history:
        try:
            with open(c["path"], encoding="utf-8", errors="ignore") as f:
                head = f.read(400)
        except OSError:
            continue
        m = CRASHLOGGER_VER_RE.search(head)
        if m:
            facts["crashlogger_version"] = m.group(1).replace("-", ".")
            break
    return facts


def _proxy_role(path: str) -> str:
    """Rôle d'une DLL graphique posée à la racine du jeu, d'après des marqueurs dans le binaire."""
    try:
        with open(path, "rb") as f:
            blob = f.read(8 * 1024 * 1024)
    except OSError:
        return ""
    return next((role for marker, role in PROXY_MARKERS if marker in blob), "inconnu")


def _yes(b) -> str:
    return L("oui") if b else L("non")


def to_context(facts: dict) -> str:
    """Bloc « faits vérifiés » pour l'assistant IA (en français, comme le reste du contexte)."""
    if not facts:
        return ""
    out = [L("## Faits vérifiés sur l'installation (lus sur le disque : ne pas les remettre en cause)")]
    if facts.get("game_version"):
        out.append(L("- Jeu : SkyrimSE.exe {v}", v=facts["game_version"]))
    if "skse_installed" in facts:
        out.append(L("- SKSE installé : {b}", b=_yes(facts["skse_installed"]))
                   + (f" (v{facts['skse_version']})" if facts.get("skse_version") else ""))
    if "address_library" in facts:
        out.append(L("- Address Library pour cette version : {b}", b=_yes(facts["address_library"])))
    tools = facts.get("tools") or {}
    present = [TOOLS[k][0] for k, v in tools.items() if v]
    absent = [TOOLS[k][0] for k, v in tools.items() if not v]
    if present:
        cl = facts.get("crashlogger_version")
        out.append(L("- Outils installés : {l}", l=", ".join(
            p + (f" v{cl}" if p == "Crash Logger SSE" and cl else "") for p in present)))
    if absent:
        out.append(L("- Outils absents : {l}", l=", ".join(absent)))
    cc = facts.get("cc")
    if cc:
        out.append(L("- Creation Club : {p} fichier(s) présents sur {n} listés dans Skyrim.ccc (chargés automatiquement)",
                     p=cc["present"], n=cc["listed"]))
    pl = facts.get("plugins")
    if pl:
        out.append(L("- Plugins actifs : {a} ({f} pleins, {l} légers ESL) — limite de 254 pleins : {ok}",
                     a=pl["active"], f=pl["full"], l=pl["light"],
                     ok=L("respectée") if pl["limit_ok"] else L("DÉPASSÉE")))
    if facts.get("bottle"):
        out.append(L("- Jeu lancé sous CrossOver (bouteille « {b} »)", b=facts["bottle"]))
    if facts.get("enb") or facts.get("reshade"):
        out.append(L("- Post-traitement : ENB {e}, ReShade {r}", e=_yes(facts.get("enb")), r=_yes(facts.get("reshade"))))
    for name, role in (facts.get("proxies") or {}).items():
        out.append(L("- {f} à la racine du jeu : {r} (ne pas le renommer ni le supprimer sans en tenir compte)",
                     f=name, r=role or "?"))
    cr = facts.get("crash_logs") or {}
    if cr:
        line = L("- Crash logs : {a} actif(s), {k} archivé(s) par la purge", a=cr["active"], k=cr["archived"])
        if cr.get("dir"):
            line += " — " + L("Crash Logger écrit dans {d}", d=cr["dir"])
        if cr.get("last"):
            line += " — " + L("dernier : {d} ({w})", d=cr["last"][0], w=cr["last"][1] or "?")
        out.append(line)
    return "\n".join(out)
