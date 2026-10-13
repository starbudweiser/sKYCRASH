"""Mise en forme des réponses de l'IA : sections colorées, listes, sans icônes.

Le prompt système impose des sections en MAJUSCULES (VERDICT, CAUSE, CONFIANCE,
PREUVES, ACTIONS, MANQUE). Ce module les repère (avec tolérance sur les variantes
et le Markdown résiduel) et produit du HTML compatible QTextEdit.
"""
import html
import re
import unicodedata

from i18n import L, N_

TEXT = "#dddddd"
MUTED = "#8f8f8f"
PALETTE = {
    "verdict": "#f59e0b",
    "cause": "#f87171",
    "confiance": "#38bdf8",
    "preuves": "#38bdf8",
    "actions": "#4ade80",
    "manque": "#aaaaaa",
}
LEVEL_COLORS = {
    "elevee": "#4ade80", "moyenne": "#fbbf24", "faible": "#f87171",
    "high": "#4ade80", "medium": "#fbbf24", "low": "#f87171",
    "alta": "#4ade80", "media": "#fbbf24", "bassa": "#f87171", "baja": "#f87171",
}

# Libellés affichés (clés françaises, traduites à l'affichage)
TITLES = {
    "verdict": N_("VERDICT"), "cause": N_("CAUSE"), "confiance": N_("CONFIANCE"),
    "preuves": N_("PREUVES"), "actions": N_("ACTIONS"), "manque": N_("MANQUE"),
}

ALIASES = {
    "verdict": "verdict", "resume": "verdict", "conclusion": "verdict",
    "cause": "cause", "cause probable": "cause", "cause la plus probable": "cause",
    "cause probable du crash": "cause",
    "confiance": "confiance", "niveau de confiance": "confiance",
    "preuves": "preuves", "preuves tirees des logs": "preuves", "indices": "preuves",
    "actions": "actions", "etapes": "actions", "verifications": "actions",
    "etapes de verification": "actions", "etapes concretes": "actions",
    "manque": "manque", "informations manquantes": "manque", "limites": "manque",
    "ce qui manque": "manque",
    # en / it / es
    "summary": "verdict", "verdetto": "verdict", "veredicto": "verdict",
    "probable cause": "cause", "causa": "cause", "causa probable": "cause",
    "confidence": "confiance", "affidabilita": "confiance", "confianza": "confiance",
    "evidence": "preuves", "prove": "preuves", "pruebas": "preuves",
    "azioni": "actions", "acciones": "actions", "steps": "actions",
    "missing": "manque", "missing information": "manque", "mancante": "manque",
    "falta": "manque", "cosa manca": "manque", "lo que falta": "manque",
}
LABEL_RE = re.compile(r"^\s*(?:#{1,6}\s*)?(?:\d+[.)]\s*)?[*_]*([^:*_\n]{3,40}?)[*_]*\s*[:：]\s*[*_]*\s*(.*)$")
BARE_LABEL_RE = re.compile(r"^\s*(?:#{1,6}\s*)?[*_]*([A-Za-zÀ-ÿ' ]{3,40}?)[*_]*\s*$")
BULLET_RE = re.compile(r"^\s*[-*•–]\s+(.*)$")
NUM_RE = re.compile(r"^\s*(\d+)[.)]\s+(.*)$")
INLINE_RE = re.compile(r"\*\*(.+?)\*\*|`([^`]+)`")


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.strip().lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def _section_key(label: str):
    return ALIASES.get(_norm(label))


def _inline(text: str, base: str = TEXT) -> str:
    """Échappe le HTML ; **gras** -> blanc gras ; `code` -> monospace ambré."""
    out, pos = [], 0
    for m in INLINE_RE.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        if m.group(1) is not None:
            out.append(f'<span style="color:#ffffff;font-weight:700">{html.escape(m.group(1))}</span>')
        else:
            out.append(f'<span style="color:#fbbf24;font-family:Menlo,monospace">{html.escape(m.group(2))}</span>')
        pos = m.end()
    out.append(html.escape(text[pos:]))
    return f'<span style="color:{base}">{"".join(out)}</span>'


def _label(key: str, title: str, rest: str) -> str:
    color = PALETTE[key]
    head = f'<span style="color:{color};font-weight:800;letter-spacing:1px">{html.escape(L(TITLES[key]))}</span>'
    body = ""
    if rest:
        if key == "confiance":
            lvl = LEVEL_COLORS.get(_norm(rest).split(" ")[0].strip(".,;"), color)
            body = f' &nbsp;<span style="color:{lvl};font-weight:700">{html.escape(rest.strip("* "))}</span>'
        else:
            body = " &nbsp;" + _inline(rest)
    return f'<p style="margin:12px 0 3px 0">{head}{body}</p>'


def render_html(answer: str) -> str:
    """Convertit le texte brut de l'IA en HTML coloré structuré."""
    parts = []
    key = None
    for raw in answer.replace("\r\n", "\n").split("\n"):
        line = raw.rstrip()
        if not line.strip():
            continue
        if re.match(r"^\s*([-*_]\s*){3,}$", line):  # séparateurs Markdown
            continue
        m = LABEL_RE.match(line)
        if m and (k := _section_key(m.group(1))):
            key = k
            parts.append(_label(k, m.group(1), m.group(2).strip()))
            continue
        m = BARE_LABEL_RE.match(line)
        if m and (k := _section_key(m.group(1))) and not BULLET_RE.match(line):
            key = k
            parts.append(_label(k, m.group(1), ""))
            continue
        accent = PALETTE.get(key, MUTED)
        m = NUM_RE.match(line)
        if m:
            parts.append(
                f'<p style="margin:2px 0 2px 6px"><span style="color:{accent};font-weight:700">{m.group(1)}.</span>'
                f' {_inline(m.group(2))}</p>')
            continue
        m = BULLET_RE.match(line)
        if m:
            parts.append(
                f'<p style="margin:2px 0 2px 6px"><span style="color:{accent};font-weight:700">&ndash;</span>'
                f' {_inline(m.group(1))}</p>')
            continue
        text = re.sub(r"^\s*#{1,6}\s*", "", line)
        parts.append(f'<p style="margin:3px 0">{_inline(text.strip())}</p>')
    return "".join(parts) or f'<p style="margin:3px 0">{_inline(answer.strip())}</p>'
