"""Export structuré des analyses de plantage, lu par mORTEX (contrat v1, voir docs/export_crash_events.md).

Un fichier JSON Lines, une ligne par plantage analysé, en ajout seul :
~/Library/Application Support/SkyrimCrashAnalyzer/exports/crash_events.jsonl
Module sans dépendance Qt. Aucun contenu brut de log ni chemin personnel n'est écrit.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path

import audit_engine as ae
import compat
import insights

SCHEMA = 1
EXPORT_ENV = "SKYRIM_CA_EXPORT_DIR"          # dossier imposé (tests, aperçu)
FILENAME = "crash_events.jsonl"
MAX_REASONS = 4
PLUGIN_EXTS = (".esp", ".esm", ".esl")
# étiquettes de catégorie « [x] » du moteur qui décrivent l'environnement : reconstruites ici de façon stable
ENV_TAGS = {"mémoire", "graphique", "plateforme", "version", "plugins", "réglages"}
HEADER_VER_RE = re.compile(r"^Skyrim\s*\w*\s*v([\d.]+)", re.I)
TAG_RE = re.compile(r"^\[([^\]]+)\]")
_USER_PATH_RES = (re.compile(r"/Users/[^/\s\"']+"), re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"']+", re.I))


def export_dir() -> Path:
    override = os.environ.get(EXPORT_ENV)
    if override:
        return Path(override)
    return Path.home() / "Library" / "Application Support" / "SkyrimCrashAnalyzer" / "exports"


def export_path() -> Path:
    return export_dir() / FILENAME


# ----------------------------------------------------------------- anonymisation
def scrub(text: str) -> str:
    """Retire chemins personnels et nom d'utilisateur d'un texte libre."""
    for rx in _USER_PATH_RES:
        text = rx.sub("~", text)
    user = Path.home().name
    if len(user) >= 3:
        text = re.sub(re.escape(user), "user", text, flags=re.I)
    return text


def bottle_name(game_dir: str):
    parts = os.path.normpath(game_dir or "").split(os.sep)
    if "drive_c" not in parts or parts.index("drive_c") < 1:
        return None
    return scrub(parts[parts.index("drive_c") - 1]) or None


# ----------------------------------------------------------------- champs de l'événement
def _fr_tag(tag: str) -> str:
    """Étiquette de catégorie ramenée au français (clé stable), quelle que soit la langue de l'appli."""
    try:
        from i18n_strings import TR
    except ImportError:
        return tag
    if tag in TR:
        return tag
    for fr, tr in TR.items():
        if tag in tr:
            return fr
    return tag


def suspect_kind(name: str) -> str:
    low = name.lower()
    if low.endswith(".dll"):
        return "dll"
    if low.endswith(PLUGIN_EXTS):
        return "plugin"
    return "object"


def _suspects(report) -> list:
    out = []
    for name, score, reasons in report.suspects:
        m = TAG_RE.match(name)
        if m:
            tag = _fr_tag(m.group(1))
            if tag in ENV_TAGS:
                continue  # l'environnement est reconstruit par _env_suspects
            name, kind = tag, "object"
        else:
            kind = suspect_kind(name)
        out.append({"name": scrub(name), "kind": kind, "score": int(score),
                    "reasons": [scrub(r) for r in reasons[:MAX_REASONS]]})
    return out


def _env(name: str, score: int, reason: str) -> dict:
    return {"name": name, "kind": "env", "score": score, "reasons": [reason]}


def _env_suspects(lines: list, report, game_version) -> list:
    """Constats d'environnement Wine/CrossOver, avec des identifiants et raisons stables (anglais)."""
    out = []
    specs = {}
    for l in ae._section(lines, "SYSTEM SPECS:"):
        m = ae.SPEC_RE.match(l)
        if m:
            specs[m.group(1)] = m.group(2).strip()
    modules = [re.split(r"\s{2,}|\t", l.strip())[0] for l in ae._section(lines, "MODULES:") if l.strip()]
    is_wine = bool(ae.WINE_RE.search(" ".join(specs.values())) or any(m.lower().startswith("wine") for m in modules))
    if is_wine:
        out.append(_env("wine_layer", 3, "game running through CrossOver/Wine/GPTK"))
        renderer = ae.detect_renderer(lines)
        if renderer:
            out.append(_env("renderer:" + renderer, 1, "graphics translation layer: " + renderer))
        if any(h in m.lower() for m in modules for h in ae.DLSS_HINTS):
            out.append(_env("dlss_unavailable", 2, "DLSS/Streamline modules loaded but unavailable under Wine"))
    ram = ae.MEM_RE.search(specs.get("PHYSICAL MEMORY", ""))
    vram = ae.MEM_RE.search(specs.get("GPU MEMORY", ""))
    unified = bool(is_wine and ram and vram and float(vram.group(2)) >= float(ram.group(2)))
    if unified:
        out.append(_env("unified_memory", 1, "GPU memory is shared with system RAM"))
    for key, label in (("PHYSICAL MEMORY", "RAM"), ("GPU MEMORY", "VRAM")):
        if unified and key == "GPU MEMORY":
            continue
        m = ae.MEM_RE.search(specs.get(key, ""))
        if m and float(m.group(2)) > 0 and float(m.group(1)) / float(m.group(2)) >= 0.85:
            out.append(_env("memory_pressure", 5, f"{label} at {100 * float(m.group(1)) / float(m.group(2)):.0f}% at crash time"))
    # version du jeu vs runtime SKSE, Address Library
    rt = compat.decode_runtime(report.skse_runtime) if report.skse_runtime else None
    gv = tuple(int(x) for x in game_version.split(".")[:3]) if game_version and re.fullmatch(r"[\d.]+", game_version) else None
    if gv and rt and len(gv) == 3 and tuple(rt[:3]) != gv:
        out.append(_env("game_skse_mismatch", 10, f"game {game_version} vs SKSE runtime {'.'.join(map(str, rt[:3]))}"))
    inv = report.extras.get("inventory") or {}
    if inv.get("address_library") is False:
        out.append(_env("address_library_missing", 6, "Address Library file for this game version not found"))
    pl = inv.get("plugins") or {}
    if pl and not pl.get("limit_ok", True):
        out.append(_env("plugin_limit", 8, f"{pl.get('full')} full plugins active, limit is {compat.MAX_PLUGINS_NON_ESL}"))
    for proxy, role in (inv.get("proxies") or {}).items():
        out.append(_env("graphics_proxy", 1, f"{proxy} at game root: {role or 'unknown'}"))
    return out


def plugins_hash(game_dir: str):
    """SHA-256 de la liste ordonnée (ordre de chargement) des plugins actifs de plugins.txt, en minuscules."""
    if not game_dir:
        return None
    ptxt = compat.find_plugins_txt(game_dir)
    if not ptxt:
        return None
    try:
        with open(ptxt, encoding="utf-8", errors="ignore") as f:
            active = [l.strip()[1:].lower() for l in f if l.startswith("*") and l.strip()[1:]]
    except OSError:
        return None
    return hashlib.sha256("\n".join(active).encode("utf-8")).hexdigest() if active else None


def crash_key(event: dict) -> tuple:
    return (event["log_name"], event["crash_time"])


def build_event(crash_path: str, lines: list, report) -> dict:
    """Événement v1 d'un plantage. `report` : AuditReport dont les suspects portent sur ce crash."""
    when = insights._crash_time(crash_path, lines)
    game_version = next((m.group(1) for l in lines[:5] for m in [HEADER_VER_RE.match(l.strip())] if m), None)
    if not game_version:
        game_version = (report.extras.get("inventory") or {}).get("game_version")
    rt = compat.decode_runtime(report.skse_runtime) if report.skse_runtime else None
    return {
        "schema": SCHEMA,
        "crash_time": when.strftime("%Y-%m-%dT%H:%M:%S") if when else None,
        "log_name": os.path.basename(crash_path),
        "game_runtime": game_version,
        "skse_runtime": ".".join(map(str, rt[:3])) if rt else None,
        "verdict": scrub(report.verdict or ""),
        "suspects": _suspects(report) + _env_suspects(lines, report, game_version),
        "plugins_hash": plugins_hash(report.game_dir),
        "bottle": bottle_name(report.game_dir),
    }


# ----------------------------------------------------------------- fichier JSONL
def _existing_keys(path: Path) -> set:
    keys = set()
    try:
        with open(path, encoding="utf-8") as f:
            for l in f:
                try:
                    e = json.loads(l)
                    keys.add((e["log_name"], e["crash_time"]))
                except (ValueError, KeyError, TypeError):
                    continue  # ligne illisible : ignorée, jamais réécrite
    except OSError:
        pass
    return keys


def append_event(event: dict, path: Path = None) -> bool:
    """Ajoute la ligne si ce crash (nom du log + CRASH TIME) n'y est pas déjà. Retourne True si écrite."""
    path = Path(path) if path else export_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    line = (json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    fd = os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        try:
            import fcntl
            fcntl.flock(fd, fcntl.LOCK_EX)  # deux instances ne mélangent pas leurs lignes
        except ImportError:
            pass
        if crash_key(event) in _existing_keys(path):
            return False
        os.write(fd, line)  # une seule écriture O_APPEND : la ligne est complète ou absente
        os.fsync(fd)
        return True
    finally:
        os.close(fd)


def export_report(report, game_dir: str = "", path: Path = None) -> int:
    """Écrit un événement par crash log analysé ; retourne le nombre de lignes ajoutées.

    Avec plusieurs crashs, chacun est ré-audité seul (plus les logs non-crash) pour que ses suspects soient les siens.
    """
    crashes, others = [], []
    for p in report.analysed:
        lines = ae.read_lines(p)
        (crashes if ae.classify_log(p, lines) == "crash" else others).append((p, lines))
    added = 0
    for p, lines in crashes:
        rep = report if len(crashes) == 1 else ae.audit_paths([p] + [o for o, _l in others], game_dir)
        if append_event(build_event(p, lines, rep), path):
            added += 1
    return added


def audit_and_export(files: list, game_dir: str, enabled: bool = True):
    """Audit complet puis export (si activé). L'export n'échoue jamais l'audit."""
    report = ae.audit_paths(files, game_dir)
    if enabled:
        try:
            export_report(report, game_dir)
        except (OSError, ValueError):
            pass
    return report
