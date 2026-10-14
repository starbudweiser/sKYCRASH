"""Recoupements entre sources, sans IA : chronologie du plantage, historique des crash logs,
sauvegarde comparée aux plugins actuels, domaine des objets en cause.

Ce sont les preuves qu'un humain trouve en croisant plusieurs fichiers ; le moteur d'audit les
ajoute au rapport (constats + scores) et les garde dans report.extras pour l'export.
"""
from __future__ import annotations

import glob
import os
import re
from datetime import datetime, timedelta

import compat
import savegame
from i18n import L, N_

BASE_MASTERS = ("skyrim.esm", "update.esm", "dawnguard.esm", "hearthfires.esm", "dragonborn.esm")
MAX_HISTORY = 12
MAX_SAVE_AGE_DAYS = 7  # au-delà, la sauvegarde la plus récente n'est sans doute pas celle qui a été chargée
ARCHIVE_DIR = "sKYCRASH-archive"  # crash logs mis de côté par « Purger les logs », lus par l'historique

CRASH_TIME_RE = re.compile(r"^CRASH TIME:\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})")
CRASH_NAME_RE = re.compile(r"crash-(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})", re.I)
UPTIME_RE = re.compile(r"Process Uptime:\s*(\d+):(\d{2}):(\d{2})")
AT_RE = re.compile(r"\bat 0x[0-9A-Fa-f]+\s+(.+)$")
OBJ_TYPE_RE = re.compile(r"\(([A-Za-z_][\w:]*)\*\)")
PLUGIN_LINE_RE = re.compile(r"^\s*\[[^\]]+\]\s+(.+?\.es[mpl])\s*$", re.I)
DLL_LINE_RE = re.compile(r"^\s+(\S.*?\.dll)\b", re.I)  # lignes indentées de la section SKSE PLUGINS
TS_RE = re.compile(r"\[(?:(\d{4}-\d{2}-\d{2})[ T])?(\d{2}):(\d{2}):(\d{2})(?:[.,]\d+)?")
WARN_RE = re.compile(r"\[(?:w|e|warn|warning|err|error)\]", re.I)

# (clé, libellé, motif d'événement) — repérés dans les journaux horodatés des plugins SKSE
EVENTS = [
    ("save", N_("chargement d'une sauvegarde"),
     re.compile(r"loading save|load(?:ing)? ?game|kPreLoadGame|kPostLoadGame|PostLoadGame|PreLoadGame", re.I)),
    ("newgame", N_("nouvelle partie"), re.compile(r"kNewGame|\bnew game\b", re.I)),
    ("menu", N_("menu principal"), re.compile(r"main ?menu", re.I)),
]

# domaine : (motif des types d'objets du crash log, motif des noms de DLL / plugins liés)
DOMAINS = {
    "audio": (re.compile(r"Sound|Music|Audio|Acoustic", re.I),
              re.compile(r"sound|music|audio|occlusion|acoustic|ambien|bird|flock", re.I)),
    "region": (re.compile(r"TESRegion|TESWeather|TESClimate|\bSky\b", re.I),
               re.compile(r"region|weather|storm|climate|cloud|rain|snow|fog|environs", re.I)),
    "anim": (re.compile(r"^hk|Havok|Behavior|Animation", re.I),
             re.compile(r"anim|behavior|havok|pandora|nemesis|\boar\b|\bdar\b", re.I)),
}
DOMAIN_LABELS = {"audio": N_("son et musique"), "region": N_("régions et météo"), "anim": N_("animations")}
CRASH_EVENT = N_("plantage")


# --------------------------------------------------------------- crash logs
def _crash_time(path: str, lines: list):
    for l in lines[:5]:
        m = CRASH_TIME_RE.match(l.strip())
        if m:
            return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
    m = CRASH_NAME_RE.search(os.path.basename(path))
    if m:
        return datetime(*map(int, m.groups()))
    try:
        return datetime.fromtimestamp(os.path.getmtime(path))
    except OSError:
        return None


def _section(lines: list, title: str) -> list:
    out, inside = [], False
    for l in lines:
        if not l[:1].isspace() and l.strip().endswith(":") and l.strip().upper() == l.strip():
            if inside:
                break
            inside = l.strip() == title
            continue
        if inside:
            out.append(l)
    return out


def summarize_crash(path: str, lines: list) -> dict:
    """Résumé d'un crash log Crash Logger SSE : date, lieu, durée, objets, DLL SKSE, plugins."""
    head = lines[:40]
    where = ""
    for l in head:
        if "unhandled" in l.lower():
            m = AT_RE.search(l.strip())
            where = (m.group(1) if m else l.strip()).split("\t")[0].strip()
            break
    up = next((UPTIME_RE.search(l) for l in lines[:80] if UPTIME_RE.search(l)), None)
    objs = []
    for l in _section(lines, "POSSIBLE RELEVANT OBJECTS:"):
        objs += OBJ_TYPE_RE.findall(l)
    skse = {m.group(1) for m in (DLL_LINE_RE.match(l) for l in _section(lines, "SKSE PLUGINS:")) if m}
    plugins = [m.group(1) for m in (PLUGIN_LINE_RE.match(l) for l in _section(lines, "PLUGINS:")) if m]
    return {
        "path": path, "time": _crash_time(path, lines), "where": where,
        "uptime": (int(up.group(1)) * 3600 + int(up.group(2)) * 60 + int(up.group(3))) if up else None,
        "objects": list(dict.fromkeys(objs)), "skse": skse, "plugins": plugins,
    }


def crash_history(folders: list, read_lines) -> list:
    """Tous les crash logs des dossiers donnés (les plus récents d'abord), résumés."""
    paths = set()
    for d in folders:
        paths.update(glob.glob(os.path.join(d, "crash-*.log")))
        paths.update(glob.glob(os.path.join(d, ARCHIVE_DIR, "crash-*.log")))
    items = []
    for p in paths:
        try:
            items.append((os.path.getmtime(p), p))
        except OSError:
            continue
    items.sort(reverse=True)
    return [summarize_crash(p, read_lines(p)) for _m, p in items[:MAX_HISTORY]]


# --------------------------------------------------------------- chronologie
def _events(entries: list, crash_at: datetime, window_s: int) -> list:
    """Derniers événements (sauvegarde, menu...) horodatés dans les journaux, avant le plantage."""
    start = crash_at - timedelta(seconds=window_s + 5)
    best = {}
    for _m, path, lines, kind in entries:
        if kind == "crash":
            continue
        for l in lines:
            ev = next(((k, lab) for k, lab, rx in EVENTS if rx.search(l)), None)
            if not ev:
                continue
            m = TS_RE.search(l)
            if not m:
                continue
            day = m.group(1) or crash_at.strftime("%Y-%m-%d")
            try:
                at = datetime.strptime(f"{day} {m.group(2)}:{m.group(3)}:{m.group(4)}", "%Y-%m-%d %H:%M:%S")
            except ValueError:
                continue
            if start <= at <= crash_at + timedelta(seconds=1):
                if ev[0] not in best or at > best[ev[0]][0]:
                    best[ev[0]] = (at, ev[1], os.path.basename(path))
    return sorted(best.values())


# --------------------------------------------------------------- plugins actifs
def active_plugins(game_dir: str) -> tuple:
    """(plugins actifs et installés, ensemble des fichiers de Data en minuscules, chemin du plugins.txt)."""
    data_dir = os.path.join(game_dir, "Data")
    try:
        data = {n.lower() for n in os.listdir(data_dir)}
    except OSError:
        return [], set(), None
    implicit = [m for m in BASE_MASTERS if m in data]
    ccc = os.path.join(game_dir, "Skyrim.ccc")
    try:
        with open(ccc, encoding="utf-8", errors="ignore") as f:
            implicit += [l.strip() for l in f if l.strip() and l.strip().lower() in data]
    except OSError:
        pass
    ptxt = compat.find_plugins_txt(game_dir)
    listed = []
    if ptxt:
        try:
            with open(ptxt, encoding="utf-8", errors="ignore") as f:
                listed = [l.strip()[1:] for l in f if l.startswith("*") and l.strip()[1:].lower() in data]
        except OSError:
            pass
    seen, out = set(), []
    for p in implicit + listed:
        if p.lower() not in seen:
            seen.add(p.lower())
            out.append(p)
    return out, data, ptxt


def _docs_dirs(folders: list) -> list:
    """Dossiers « My Games/Skyrim Special Edition » déduits des dossiers de logs (…/SKSE, …/Logs/Script)."""
    out = []
    for d in folders:
        cur = os.path.normpath(d)
        for _ in range(3):
            if os.path.isdir(os.path.join(cur, "Saves")):
                if cur not in out:
                    out.append(cur)
                break
            cur = os.path.dirname(cur)
    return out


def _warn_count(log_dir: str, stem: str) -> int:
    p = os.path.join(log_dir, stem + ".log")
    try:
        with open(p, encoding="utf-8", errors="ignore") as f:
            return sum(1 for l in f if WARN_RE.search(l))
    except OSError:
        return 0


def _fmt(dt: datetime) -> str:
    return dt.strftime("%d/%m %H:%M:%S")


# --------------------------------------------------------------- analyse
def analyse(report, scores: dict, entries: list, game_dir: str, read_lines, bump):
    """Ajoute au rapport les constats croisés ; remplit report.extras pour l'export."""
    from audit_engine import Finding, SEV_INFO, SEV_WARN
    folders = sorted({os.path.dirname(p) for _m, p, _l, _k in entries})
    extras = report.extras
    history = crash_history(folders, read_lines)
    extras["history"] = history
    # le dernier plantage « actif » : un crash log archivé par la purge ne sert qu'à l'historique
    latest = history[0] if history and ARCHIVE_DIR not in history[0]["path"].split(os.sep) else None

    # 1. chronologie du dernier plantage
    if latest and latest["time"]:
        evs = _events(entries, latest["time"], latest["uptime"] or 600)
        extras["timeline"] = [(at, lab, src) for at, lab, src in evs] + [(latest["time"], CRASH_EVENT, os.path.basename(latest["path"]))]
        save_ev = next((e for e in reversed(evs) if e[1] == EVENTS[0][1]), None)
        if save_ev:
            gap = int((latest["time"] - save_ev[0]).total_seconds())
            report.findings.append(Finding(
                SEV_WARN, "chronologie",
                L("Plantage {s} s après le chargement d'une sauvegarde", s=gap),
                L("Chargement repéré à {t} dans {src} ; plantage à {c}.", t=_fmt(save_ev[0]), src=save_ev[2],
                  c=_fmt(latest["time"])), L("chronologie"), [],
                L("Tester une partie neuve depuis le menu principal (console : coc <lieu>) : si elle tient, "
                  "la sauvegarde est en cause (plugins ajoutés ou retirés depuis).")))
        elif latest["uptime"] is not None and latest["uptime"] < 60:
            report.findings.append(Finding(
                SEV_WARN, "chronologie", L("Plantage {s} s après le lancement du jeu", s=latest["uptime"]),
                L("Avant ou pendant le menu principal : chargement des plugins et des données."),
                L("chronologie"), [], L("Vérifier les masters manquants et les plugins SKSE récents.")))

    # 2. historique : signatures répétées, DLL et plugins apparus depuis le plantage précédent
    if history:
        lines = [f"{_fmt(c['time'])} — {c['where'] or '?'}" for c in history if c["time"]]
        same = sum(1 for c in history if c["where"] and latest and c["where"] == latest["where"])
        report.findings.append(Finding(
            SEV_INFO, "historique", L("{n} crash log(s) dans l'historique", n=len(history)),
            L("Même point de plantage que le dernier : {k} fois.", k=same), L("historique"), lines[:6]))
        prev = next((c for c in history[1:] if c["skse"]), None)
        if latest and latest["skse"] and prev:
            added = sorted(latest["skse"] - prev["skse"])
            removed = sorted(prev["skse"] - latest["skse"])
            if added or removed:
                detail = []
                if added:
                    detail.append(L("Ajoutées : {l}", l=", ".join(added[:12])))
                if removed:
                    detail.append(L("Retirées : {l}", l=", ".join(removed[:12])))
                report.findings.append(Finding(
                    SEV_WARN if added else SEV_INFO, "historique",
                    L("DLL SKSE modifiées depuis le plantage du {d}", d=_fmt(prev["time"])),
                    " — ".join(detail), L("historique"), [],
                    L("Une DLL apparue juste avant un nouveau type de plantage est un suspect prioritaire.")))
                for d in added:
                    bump(scores, d, 2, L("DLL SKSE apparue depuis le plantage précédent"))
            extras["skse_diff"] = {"since": prev["time"], "added": added, "removed": removed}

    # 3. sauvegarde comparée aux plugins actuels
    act, data, ptxt = active_plugins(game_dir) if game_dir else ([], set(), None)
    added_since_save = []
    if act:
        before = latest["time"].timestamp() if latest and latest["time"] else None
        save = None
        for docs in _docs_dirs(folders):
            for p in savegame.latest_saves(os.path.join(docs, "Saves"), before, limit=1):
                try:
                    save = savegame.read_save(p)
                except (OSError, ValueError):
                    continue
                break
            if save:
                break
        if save and before and before - save.saved_at > MAX_SAVE_AGE_DAYS * 86400:
            save = None  # trop ancienne (ex. réenregistrée depuis) : comparaison non significative
        if save:
            active_low = {p.lower() for p in act}
            in_save = {p.lower() for p in save.all_plugins}
            missing = [p for p in save.all_plugins if p.lower() not in active_low]
            added_since_save = [p for p in act if p.lower() not in in_save]
            extras["save"] = {"path": save.path, "player": save.player, "location": save.location,
                              "saved_at": datetime.fromtimestamp(save.saved_at), "count": len(save.all_plugins),
                              "missing": missing, "added": added_since_save, "plugins_txt": ptxt}
            name = os.path.splitext(os.path.basename(save.path))[0]
            when = datetime.fromtimestamp(save.saved_at).strftime("%d/%m %H:%M")
            if missing:
                report.findings.append(Finding(
                    SEV_WARN, "sauvegarde",
                    L("{n} plugin(s) de la sauvegarde « {s} » ne sont plus actifs", n=len(missing), s=name),
                    L("Sauvegarde du {d} ({loc}).", d=when, loc=save.location), L("sauvegarde"), missing[:8],
                    L("Réactiver ces plugins pour charger la partie, ou nettoyer la sauvegarde (ReSaver) "
                      "après les avoir retirés proprement.")))
            if added_since_save:
                report.findings.append(Finding(
                    SEV_WARN if len(added_since_save) >= 10 else SEV_INFO, "sauvegarde",
                    L("{n} plugin(s) ajoutés depuis la sauvegarde « {s} »", n=len(added_since_save), s=name),
                    L("Sauvegarde du {d} ({loc}), {k} plugins à l'époque.", d=when, loc=save.location,
                      k=len(save.all_plugins)), L("sauvegarde"), added_since_save[:8],
                    L("Ajouter des plugins en cours de partie (régions, météo, sons, PNJ) peut faire planter au "
                      "chargement. Tester une partie neuve (coc) ; si elle tient, retirer les ajouts récents.")))

    # 4. domaine des objets en cause -> DLL et plugins ajoutés liés à ce domaine
    if latest and latest["objects"]:
        doms = [k for k, (obj_rx, _n) in DOMAINS.items() if any(obj_rx.search(o) for o in latest["objects"])]
        if doms:
            log_dir = os.path.dirname(latest["path"])
            dlls, plugs = [], []
            for k in doms:
                name_rx = DOMAINS[k][1]
                for d in sorted(latest["skse"]):
                    if name_rx.search(d) and d not in [x[0] for x in dlls]:
                        dlls.append((d, _warn_count(log_dir, os.path.splitext(d)[0])))
                plugs += [p for p in added_since_save if name_rx.search(p) and p not in plugs]
            labels = ", ".join(L(DOMAIN_LABELS[k]) for k in doms)
            parts = []
            if dlls:
                parts.append(L("DLL chargées : {l}", l=", ".join(
                    d + (L(" ({n} avertissements)", n=w) if w else "") for d, w in dlls[:10])))
            if plugs:
                parts.append(L("Plugins ajoutés depuis la sauvegarde : {l}", l=", ".join(plugs[:10])))
            extras["domains"] = {"labels": labels, "dlls": dlls, "plugins": plugs}
            report.findings.append(Finding(
                SEV_WARN, "domaine", L("Objets en cause : {d}", d=labels),
                " — ".join(parts) or L("Aucune DLL ni plugin récent lié à ce domaine."), L("recoupement"),
                [", ".join(latest["objects"][:6])],
                L("Tester en désactivant un par un ces DLL et plugins, en commençant par les plus récents.")))
            for d, w in dlls:
                bump(scores, d, 3 if w else 2, L("lié aux objets en cause ({d})", d=labels))
            for p in plugs:
                bump(scores, p, 2, L("ajouté depuis la sauvegarde, lié aux objets en cause"))
