#!/bin/bash
# Construit "sKYCRASH.app" à la racine du projet.
# Utilise le venv local .venv ; supprime tous les fichiers/dossiers temporaires en sortie.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="sKYCRASH"
ENTRY="src/Skyrim_Crash_Analyzer.py"
WORK_DIR="$ROOT/.build_tmp"

command -v python3 >/dev/null || { echo "python3 introuvable" >&2; exit 1; }
[ -f "$ENTRY" ] || { echo "Point d'entrée absent : $ENTRY" >&2; exit 1; }
[ -f docs/requirements.txt ] || { echo "docs/requirements.txt absent" >&2; exit 1; }

cleanup() {
    rm -rf "$WORK_DIR" "$ROOT/build" "$ROOT/dist_app" "$ROOT/$APP_NAME.spec"
    find "$ROOT" -path "$ROOT/.venv" -prune -o -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$ROOT" -name ".DS_Store" -not -path "$ROOT/.venv/*" -delete 2>/dev/null || true
}
trap cleanup EXIT

# Python de référence : celui de python.org s'il existe (le PATH d'Automator est minimal).
PY_SYS="/Library/Frameworks/Python.framework/Versions/3.12/bin/python3"
[ -x "$PY_SYS" ] || PY_SYS="$(command -v python3)"

# Venv recréé s'il est absent ou inutilisable (ex. copié depuis un autre dossier).
PY="$ROOT/.venv/bin/python"
if ! "$PY" -c "import sys" >/dev/null 2>&1; then
    rm -rf .venv
    "$PY_SYS" -m venv .venv
fi
"$PY" -m pip install --quiet --upgrade pip
"$PY" -m pip install --quiet -r docs/requirements.txt

rm -rf "$WORK_DIR" "$ROOT/$APP_NAME.app"
mkdir -p "$WORK_DIR"

"$PY" -m PyInstaller --windowed --noconfirm --clean \
    --distpath "$WORK_DIR/dist" \
    --workpath "$WORK_DIR/work" \
    --specpath "$WORK_DIR" \
    --name "$APP_NAME" \
    --paths "$ROOT/src" \
    --hidden-import keyring.backends.macOS \
    --hidden-import skill_loader --hidden-import ai_format --hidden-import compat \
    --hidden-import knowledge_updater --hidden-import i18n --hidden-import i18n_strings \
    --hidden-import i18n_ui_strings --hidden-import i18n_engine_strings \
    --add-data "$ROOT/data/skills:data/skills" \
    --add-data "$ROOT/data/knowledge_seed:data/knowledge_seed" \
    --osx-bundle-identifier "local.stephan.skyrimcrashanalyzer" \
    --icon "$ROOT/assets/icon.icns" \
    "$ROOT/$ENTRY"

mv "$WORK_DIR/dist/$APP_NAME.app" "$ROOT/$APP_NAME.app"

# Signature stable avec _tools/sign_app.sh (certificat local) ; sans lui (compilation depuis
# le dépôt GitHub seul), signature ad hoc pour que l'appli se lance quand même.
SIGN_APP="$(cd "$ROOT/.." && pwd)/_tools/sign_app.sh"
if [ -x "$SIGN_APP" ]; then
    "$SIGN_APP" "$ROOT/$APP_NAME.app" 1.0.1
else
    echo "_tools/sign_app.sh absent : signature ad hoc."
    codesign --force --deep --sign - "$ROOT/$APP_NAME.app"
fi

echo "OK -> $ROOT/$APP_NAME.app"
[ -n "${NO_OPEN:-}" ] || open "$ROOT/$APP_NAME.app"