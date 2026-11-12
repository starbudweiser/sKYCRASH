#!/bin/zsh
# Publie une version de sKYCRASH (compilation, signature Developer ID, notarisation, release GitHub) via l'outil commun.
# Usage : ./release.sh [--notes "texte"] [--replace]   — la version vient de macos/build_app.sh (VERSION).
exec "$(cd "$(dirname "$0")/.." && pwd)/_tools/release_app.sh" sKYCRASH "$@"
