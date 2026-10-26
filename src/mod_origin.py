"""Mod d'origine des fichiers suspects (DLL SKSE, plugins) : relie un nom de fichier au mod qui l'installe.

Sources, dans l'ordre :
- installation mABBAJACK : manifeste de la liste dans <jeu>/.mabbajack/installation.json.gz (chemins
  « mods/<mod>/… » du .wabbajack) ;
- instance Mod Organizer 2 : dossier mods/ à côté de ModOrganizer.ini, dans le dossier du jeu
  (STOCK GAME) ou son parent.
"""
import gzip
import json
import os

EXTS = (".dll", ".esp", ".esm", ".esl")
SNAPSHOT = os.path.join(".mabbajack", "installation.json.gz")
MAX_FILES = 400_000  # garde-fou pour une instance MO2 géante


def _add(index: dict, name: str, mod: str) -> None:
    mods = index.setdefault(name.lower(), [])
    if mod not in mods:
        mods.append(mod)


def _from_mabbajack(game_dir: str, index: dict) -> bool:
    path = os.path.join(game_dir, SNAPSHOT)
    if not os.path.isfile(path):
        return False
    with gzip.open(path, "rt", encoding="utf-8") as f:
        snap = json.load(f)
    for entry in snap.get("manifest") or []:
        parts = str(entry[0] if entry else "").replace("\\", "/").split("/")
        if len(parts) >= 3 and parts[0].lower() == "mods" and parts[-1].lower().endswith(EXTS):
            _add(index, parts[-1], parts[1])
    return True


def _mo2_mods_dir(game_dir: str) -> str:
    for base in (game_dir, os.path.dirname(game_dir)):
        if os.path.isfile(os.path.join(base, "ModOrganizer.ini")) and os.path.isdir(os.path.join(base, "mods")):
            return os.path.join(base, "mods")
    return ""


def _from_mo2(game_dir: str, index: dict) -> bool:
    mods_dir = _mo2_mods_dir(game_dir)
    if not mods_dir:
        return False
    seen = 0
    for mod in sorted(os.listdir(mods_dir)):
        root_dir = os.path.join(mods_dir, mod)
        if not os.path.isdir(root_dir) or mod.endswith("_separator"):
            continue
        for root, dirs, files in os.walk(root_dir):
            dirs[:] = [d for d in dirs if d.lower() not in ("meshes", "textures", "sound", "music", "interface")]
            for name in files:
                seen += 1
                if name.lower().endswith(EXTS):
                    _add(index, name, mod)
            if seen > MAX_FILES:
                return True
    return True


def build_index(game_dir: str) -> dict:
    """{nom de fichier en minuscules: [mods]} ; vide si aucune source n'est trouvée."""
    index: dict = {}
    if not game_dir:
        return index
    for source in (_from_mabbajack, _from_mo2):
        try:
            if source(game_dir, index):
                break
        except (OSError, ValueError, TypeError):
            continue
    return index


def origin_of(name: str, index: dict) -> list:
    return index.get(os.path.basename(str(name)).lower(), [])
