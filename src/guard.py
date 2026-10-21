"""Filet de sécurité sur les réponses de l'assistant IA, sans IA.

Retire les conseils qui contredisent la fiche d'installation vérifiée (inventory.py) :
installer un outil déjà présent, « télécharger » le Creation Club présent, vérifier une limite
de plugins déjà respectée… Corrige aussi le dossier inventé SKSE/Crashlogs.
Les motifs couvrent le français, l'anglais, l'italien et l'espagnol (langues de réponse).
Si une clé TypeSafe est présente, Jev juge en plus chaque conseil restant face aux faits
(`jev_judge`) : il attrape les contradictions que les motifs ne prévoient pas.
"""
from __future__ import annotations

import re

import inventory
import jev_client
from i18n import L, N_

_ACTION = r"(?:install|t[ée]l[ée]charg|download|scaric|descarg|ajout|add|aggiung|añad|met(?:tre|s) en place)"
_CHECK = r"(?:v[ée]rifi|check|controll|comprueb|verific|assur|ensure|make sure)"

# (fait à vérifier, motif d'une ligne de conseil à retirer, libellé)
RULES = [
    (lambda f: (f.get("tools") or {}).get("crashlogger"),
     re.compile(_ACTION + r".{0,60}crash ?logger|crash ?logger.{0,40}" + _ACTION, re.I), "Crash Logger SSE"),
    (lambda f: (f.get("tools") or {}).get("enginefixes"),
     re.compile(_ACTION + r".{0,60}engine ?fixes", re.I), "SSE Engine Fixes"),
    (lambda f: f.get("address_library"),
     re.compile(r"(?:" + _ACTION + "|" + _CHECK + r").{0,60}address ?library", re.I), "Address Library"),
    (lambda f: f.get("skse_installed"),
     re.compile(_ACTION + r".{0,40}\bskse(?:64)?\b(?!\s*plugin)", re.I), "SKSE"),
    (lambda f: (f.get("cc") or {}).get("listed") and f["cc"]["present"] >= f["cc"]["listed"],
     re.compile(r"creation ?club|\bcc\b.{0,30}(?:manquant|missing|mancant|falt)", re.I), "Creation Club"),
    (lambda f: (f.get("plugins") or {}).get("limit_ok"),
     re.compile(r"\b254\b|(?:limite?|limit)\b.{0,40}plugins?|plugins?.{0,40}(?:limite?|limit)\b", re.I),
     N_("limite de 254 plugins")),
]
_ITEM = re.compile(r"^\s*(?:\d+[.)]|[-•*])\s+")
_NUMBERED = re.compile(r"^(\s*)\d+([.)])(\s+)")
_CRASHLOGS_DIR = re.compile(r"SKSE[\\/]+Crash ?logs[\\/]?", re.I)
JEV_LABEL = N_("contradiction avec les faits (Jev)")
JEV_THRESHOLD = 0.8   # probabilité minimale de « contredit » pour retirer un conseil
JEV_MAX_ITEMS = 20


def apply(text: str, facts: dict, judge=None) -> tuple:
    """(réponse corrigée, libellés des conseils retirés).

    `judge(items, facts)` (ex. `jev_judge`) renvoie, pour chaque conseil, s'il faut le retirer ;
    en cas d'erreur du service, seuls les motifs s'appliquent.
    """
    if not text or not facts:
        return text, []
    active = [(rx, label) for check, rx, label in RULES if _safe(check, facts)]
    removed, lines, drop = [], text.splitlines(), set()
    for i, line in enumerate(lines):
        if _ITEM.match(line):
            hit = next((label for rx, label in active if rx.search(line)), None)
            if hit:
                drop.add(i)
                if hit not in removed:
                    removed.append(hit)
    if judge:
        todo = [i for i, line in enumerate(lines) if _ITEM.match(line) and i not in drop][:JEV_MAX_ITEMS]
        try:
            verdicts = judge([_ITEM.sub("", lines[i]).strip() for i in todo], facts) if todo else []
        except jev_client.JevError:
            verdicts = []
        for i, bad in zip(todo, verdicts):
            if bad:
                drop.add(i)
                if JEV_LABEL not in removed:
                    removed.append(JEV_LABEL)
    out = [line for i, line in enumerate(lines) if i not in drop]
    # renumérote les listes numérotées après suppression
    n, fixed = 0, []
    for line in out:
        m = _NUMBERED.match(line)
        if m:
            n += 1
            line = f"{m.group(1)}{n}{m.group(2)}{m.group(3)}" + line[m.end():]
        elif line.strip() and not _ITEM.match(line):
            n = 0
        fixed.append(line)
    result = "\n".join(fixed)
    if (facts.get("tools") or {}).get("crashlogger"):
        result = _CRASHLOGS_DIR.sub("SKSE/", result)
    if removed:
        result += "\n\n" + L("(sKYCRASH : {n} conseil(s) retiré(s), déjà en place ou vérifié : {l}.)",
                             n=len(removed), l=", ".join(L(x) for x in removed))
    return result, removed


def jev_judge(items: list, facts: dict) -> list:
    """Jev : chaque conseil contredit-il la fiche d'installation vérifiée ? (une Choice par conseil)"""
    criteria = {
        "contradicts": "The advice asks to install, download, enable, verify or fix something that "
                       "`installation_facts` shows is already installed, present or satisfied, or it states "
                       "something about this installation (a version, a folder, a file's role) that "
                       "`installation_facts` contradicts.",
        "consistent": "The advice agrees with `installation_facts` or builds on them.",
        "not_covered": "`installation_facts` says nothing about what this advice concerns.",
    }
    questions = {f"c{i}": {"type": "choice", "criteria": criteria, "instructions":
                           f"How does the troubleshooting advice `advice[{i}]` relate to the verified facts "
                           "about this Skyrim installation in `installation_facts`?"}
                 for i in range(len(items))}
    state = {"installation_facts": inventory.to_context(facts), "advice": items}
    answers = jev_client.system_one(state, questions)
    return [(answers.get(f"c{i}") or {}).get("choice") == "contradicts"
            and ((answers[f"c{i}"].get("probabilities") or {}).get("contradicts") or 0) >= JEV_THRESHOLD
            for i in range(len(items))]


def default_judge():
    """`jev_judge` si une clé TypeSafe est disponible, sinon None (motifs seuls)."""
    return jev_judge if jev_client.get_api_key() else None


def _safe(check, facts) -> bool:
    try:
        return bool(check(facts))
    except (KeyError, TypeError):
        return False
