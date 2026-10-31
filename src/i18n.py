"""Internationalisation : français (source), anglais, italien, espagnol.

Le texte français sert de clé : L("Texte {x}", x=1) renvoie la traduction de la langue
active, ou le français si elle manque. Les traductions vivent dans i18n_strings.TR
sous la forme {texte_fr: (en, it, es)}. Module sans dépendance Qt.
"""
from __future__ import annotations

import re
import subprocess

LANGS = {"fr": "Français", "en": "English", "it": "Italiano", "es": "Español"}
LANG_NAMES_FR = {"fr": "français", "en": "anglais", "it": "italien", "es": "espagnol"}
_INDEX = {"en": 0, "it": 1, "es": 2}
_lang = "fr"


def system_lang(default: str = "en") -> str:
    """Première langue préférée du système parmi celles de l'appli, sinon `default`."""
    try:
        out = subprocess.run(["defaults", "read", "-g", "AppleLanguages"], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return default
    return next((c for c in re.findall(r'"?([a-z]{2})[-_,"\s]', out) if c in LANGS), default)


def set_lang(code: str) -> str:
    global _lang
    _lang = code if code in LANGS else "fr"
    return _lang


def get_lang() -> str:
    return _lang


def N_(text: str) -> str:
    """Marque un texte à traduire sans le traduire (déclarations au niveau module)."""
    return text


def L(text: str, **kw) -> str:
    """Traduit `text` (clé française) et applique str.format(**kw) si des paramètres sont fournis."""
    out = text
    if _lang != "fr":
        try:
            from i18n_strings import TR
            tr = TR.get(text)
            if tr:
                out = tr[_INDEX[_lang]] or text
        except ImportError:
            pass
    if not kw:
        return out
    try:
        return out.format(**kw)
    except (KeyError, IndexError, ValueError):
        return text.format(**kw)
