#!/bin/bash
# Version de développement : « sKYCRASH Dev.app » dans ~/Applications/Skyrim Tools (identifiant ….dev, données et
# Trousseau séparés de la version installée, pas de mise à jour automatique). Pour les essais pendant les itérations.
set -euo pipefail
DEV=1 exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_app.sh" "$HOME/Applications/Skyrim Tools"
