"""Dossier de diagnostic : un seul fichier Markdown avec tout le contexte d'un plantage.

Il rassemble le rapport d'audit, les recoupements (chronologie, historique, sauvegarde),
les DLL SKSE récentes, les avertissements des journaux de plugins et l'extrait utile du
dernier crash log, pour le transmettre à un humain ou à n'importe quel assistant IA.
"""
from __future__ import annotations

import os
from datetime import datetime

import ai_client
import insights
import inventory
from audit_engine import SECTION_RE
from i18n import L

CRASH_SECTIONS = ("POSSIBLE RELEVANT OBJECTS:", "CALL STACK ([P]robable / [S]tack scan):", "PROBABLE CALL STACK:",
                  "REGISTERS:")
MAX_SECTION_LINES = 60


def _fmt(dt) -> str:
    return dt.strftime("%d/%m/%Y %H:%M:%S") if dt else "?"


def _crash_excerpt(path: str, read_lines) -> list:
    lines = read_lines(path)
    out = ["```text", *[l.rstrip() for l in lines[:12]]]
    for title in CRASH_SECTIONS:
        start = next((i for i, l in enumerate(lines) if l.strip() == title), None)
        if start is None:
            continue
        out.append("")
        out.append(title)
        for l in lines[start + 1:start + 1 + MAX_SECTION_LINES]:
            if not l[:1].isspace() and SECTION_RE.match(l.strip()):
                break
            out.append(l.rstrip())
    out.append("```")
    return out


def _recent_dlls(game_dir: str, limit: int = 25) -> list:
    plug = os.path.join(game_dir, "Data", "SKSE", "Plugins")
    items = []
    try:
        for n in os.listdir(plug):
            if n.lower().endswith(".dll"):
                p = os.path.join(plug, n)
                items.append((os.path.getmtime(p), n, os.path.getsize(p)))
    except OSError:
        return []
    items.sort(reverse=True)
    return items[:limit]


def _log_warnings(folder: str, limit: int = 20) -> list:
    out = []
    try:
        names = [n for n in os.listdir(folder) if n.lower().endswith(".log") and not n.lower().startswith("crash-")]
    except OSError:
        return []
    for n in names:
        try:
            with open(os.path.join(folder, n), encoding="utf-8", errors="ignore") as f:
                lines = [l.rstrip() for l in f if insights.WARN_RE.search(l)]
        except OSError:
            continue
        if lines:
            out.append((len(lines), n, lines[:2]))
    out.sort(reverse=True)
    return out[:limit]


def build(report, read_lines, anonymize: bool = True, app_name: str = "sKYCRASH") -> str:
    ex = report.extras
    history = ex.get("history") or []
    latest = history[0] if history else None
    md = [L("# Dossier de diagnostic {app}", app=app_name), "",
          L("Généré le {d}.", d=_fmt(datetime.now()))]
    if report.game_dir:
        md.append(L("Installation : `{dir}`", dir=report.game_dir))
    audit = report.to_markdown().replace("\n## ", "\n### ")
    facts = inventory.to_context(ex.get("inventory") or {})
    if facts:
        md += ["", facts]
    md += ["", "#" + audit if audit.startswith("# ") else audit, ""]  # titres décalés d'un niveau

    md += [L("## Chronologie du dernier plantage"), ""]
    if ex.get("timeline"):
        md += [f"- {_fmt(at)} — {L(label)} ({src})" for at, label, src in ex["timeline"]]
    else:
        md.append(L("Aucun événement horodaté trouvé dans les journaux."))
    md.append("")

    md += [L("## Historique des plantages"), ""]
    if history:
        md += [L("| Date | Point de plantage | Durée de jeu | Objets en cause |"), "|---|---|---|---|"]
        for c in history:
            up = f"{c['uptime'] // 60} min {c['uptime'] % 60:02d} s" if c["uptime"] is not None else "?"
            md.append(f"| {_fmt(c['time'])} | `{c['where'] or '?'}` | {up} | {', '.join(c['objects'][:4])} |")
        diff = ex.get("skse_diff")
        if diff:
            md += ["", L("DLL SKSE depuis le plantage du {d} : ajoutées {a} ; retirées {r}.", d=_fmt(diff["since"]),
                         a=", ".join(diff["added"]) or "-", r=", ".join(diff["removed"]) or "-")]
    else:
        md.append(L("Aucun crash log Crash Logger SSE trouvé."))
    md.append("")

    save = ex.get("save")
    md += [L("## Sauvegarde et plugins actuels"), ""]
    if save:
        md += [L("Sauvegarde : `{name}` — {player}, {loc}, enregistrée le {d}, {n} plugins.",
                 name=os.path.basename(save["path"]), player=save["player"], loc=save["location"],
                 d=_fmt(save["saved_at"]), n=save["count"]),
               L("Liste des plugins actuels : `{p}`", p=save["plugins_txt"] or "?"), "",
               L("Plugins de la sauvegarde qui ne sont plus actifs ({n}) :", n=len(save["missing"]))]
        md += [f"- {p}" for p in save["missing"]] or ["- " + L("aucun")]
        md += ["", L("Plugins ajoutés depuis la sauvegarde ({n}) :", n=len(save["added"]))]
        md += [f"- {p}" for p in save["added"]] or ["- " + L("aucun")]
    else:
        md.append(L("Sauvegarde ou liste des plugins introuvable (dossier du jeu inconnu ?)."))
    md.append("")

    if report.game_dir:
        md += [L("## DLL SKSE les plus récentes"), ""]
        md += [f"- {datetime.fromtimestamp(t).strftime('%d/%m/%Y %H:%M')} — {n} ({s // 1024} Ko)"
               for t, n, s in _recent_dlls(report.game_dir)]
        md.append("")

    if latest:
        folder = os.path.dirname(latest["path"])
        md += [L("## Avertissements des journaux de plugins"), ""]
        warns = _log_warnings(folder)
        for n, name, sample in warns:
            md.append(L("- **{name}** : {n} ligne(s)", name=name, n=n))
            md += [f"  - `{s[:200]}`" for s in sample]
        if not warns:
            md.append(L("Aucun avertissement repéré."))
        md += ["", L("## Extrait du dernier crash log ({name})", name=os.path.basename(latest["path"])), ""]
        md += _crash_excerpt(latest["path"], read_lines)

    text = "\n".join(md) + "\n"
    return ai_client.anonymize(text) if anonymize else text


def default_filename() -> str:
    return datetime.now().strftime("sKYCRASH-diagnostic-%Y-%m-%d-%H%M.md")
