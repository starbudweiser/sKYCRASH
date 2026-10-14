"""Filet de sécurité sur les réponses de l'assistant IA, sans IA.

Retire les conseils qui contredisent la fiche d'installation vérifiée (inventory.py) :
installer un outil déjà présent, « télécharger » le Creation Club présent, vérifier une limite
de plugins déjà respectée… Corrige aussi le dossier inventé SKSE/Crashlogs.
Les motifs couvrent le français, l'anglais, l'italien et l'espagnol (langues de réponse).
"""
from __future__ import annotations

import re

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


def apply(text: str, facts: dict) -> tuple:
    """(réponse corrigée, libellés des conseils retirés)."""
    if not text or not facts:
        return text, []
    active = [(rx, label) for check, rx, label in RULES if _safe(check, facts)]
    removed, out = [], []
    for line in text.splitlines():
        if _ITEM.match(line):
            hit = next((label for rx, label in active if rx.search(line)), None)
            if hit:
                if hit not in removed:
                    removed.append(hit)
                continue
        out.append(line)
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


def _safe(check, facts) -> bool:
    try:
        return bool(check(facts))
    except (KeyError, TypeError):
        return False
