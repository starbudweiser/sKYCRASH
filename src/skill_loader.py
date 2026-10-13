"""Fiches de connaissances (skills) modding Skyrim injectées dans le prompt de l'IA.

Chaque fiche est un fichier Markdown `skills/*.md`, avec un en-tête optionnel :

    ---
    title: Titre lisible
    keywords: mot1, mot2, d3d11
    always: true        (optionnel : toujours incluse)
    ---
    Contenu...

Dossiers lus : celui fourni avec l'application, la veille fournie (knowledge_seed/), la veille
mise à jour automatiquement (~/Library/Application Support/SkyrimCrashAnalyzer/knowledge), puis
~/Library/Application Support/SkyrimCrashAnalyzer/skills (fiches personnelles ;
une fiche du même nom remplace celle fournie).

Les notes « auto: true » (veille externe non fiable) ne sont injectées que si un de leurs
mots-clés apparaît dans le contexte, après les fiches manuelles et dans un budget réduit.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

MAX_SKILLS_CHARS = 15000
MAX_AUTO_CHARS = 4500
MAX_FILE_BYTES = 64 * 1024
USER_DIR = Path.home() / "Library" / "Application Support" / "SkyrimCrashAnalyzer" / "skills"
KNOWLEDGE_DIR = USER_DIR.parent / "knowledge"


def bundled_dir() -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
    return base / "data" / "skills"


def seed_dir() -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent.parent))
    return base / "data" / "knowledge_seed"


def _parse(text: str, fallback_title: str) -> dict:
    meta, body = {}, text
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            for line in text[3:end].splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip().lower()] = v.strip()
            body = text[end + 4:].lstrip("\n")
    keywords = [k.strip().lower() for k in meta.get("keywords", "").split(",") if k.strip()]
    return {
        "title": meta.get("title") or fallback_title,
        "keywords": keywords,
        "always": meta.get("always", "").lower() in ("1", "true", "oui", "yes"),
        "auto": meta.get("auto", "").lower() in ("1", "true", "oui", "yes"),
        "body": body.strip(),
    }


def load_skills(extra_dirs: list | None = None) -> dict:
    """Retourne {nom_de_fichier: fiche}. Les dossiers suivants écrasent les précédents."""
    skills = {}
    for d in [bundled_dir(), seed_dir(), KNOWLEDGE_DIR, USER_DIR, *(extra_dirs or [])]:
        try:
            files = sorted(Path(d).glob("*.md"))
        except OSError:
            continue
        for f in files:
            try:
                if f.stat().st_size > MAX_FILE_BYTES:
                    continue
                skills[f.name] = _parse(f.read_text(encoding="utf-8", errors="ignore"), f.stem)
            except OSError:
                continue
    return skills


def select_skills(context: str, question: str = "", skills: dict | None = None,
                  max_chars: int = MAX_SKILLS_CHARS, max_auto_chars: int = MAX_AUTO_CHARS) -> str:
    """Texte des fiches pertinentes (toujours-actives + mots-clés trouvés), borné en taille."""
    skills = load_skills() if skills is None else skills
    hay = (context + "\n" + question).lower()
    scored = []
    for name, s in skills.items():
        hits = sum(1 for k in s["keywords"] if k in hay)
        if s.get("auto"):
            if hits:
                scored.append((2, -hits, name, s))
        elif s["always"] or hits:
            scored.append((0 if s["always"] else 1, -hits, name, s))
    scored.sort(key=lambda t: t[:3])
    out, used, used_auto = [], 0, 0
    for _, _, _, s in scored:
        block = f"### {s['title']}\n{s['body']}"
        if used + len(block) > max_chars:
            continue
        if s.get("auto"):
            if used_auto + len(block) > min(max_auto_chars, max_chars // 3):
                continue
            used_auto += len(block)
        out.append(block)
        used += len(block)
    return "\n\n".join(out)
