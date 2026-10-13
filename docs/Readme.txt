=== sKYCRASH (Skyrim Special Edition, macOS) ===

Prérequis : Python 3.10+ (macOS). Dépendances (PyQt6, keyring) installées dans .venv.

Lancer en développement :
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    python Skyrim_Crash_Analyzer.py

Tests du moteur d'audit :
    python -m unittest test_audit_engine -v

Construire l'application autonome (.app) :
    ./Build_App.sh        (chmod +x Build_App.sh si nécessaire)
    -> dist/sKYCRASH.app

Fonctions :
  - "Analyser les logs"   : scan rapide des dossiers configurés.
  - "Audit approfondi"    : moteur à règles (crash logs Crash Logger SSE / .NET Script
    Framework, logs SKSE, Papyrus) -> suspects classés (DLL, plugins, scripts,
    catégories : mémoire, graphique, mesh, animation...), preuves et pistes.
  - Assistant IA (panneau de droite) : pose des questions ; l'IA reçoit le rapport
    d'audit + extraits de logs. Bouton "IA…" pour choisir Gemini ou Ollama.
      * Gemini : clé API stockée dans le Trousseau macOS (ou variable GEMINI_API_KEY).
        Le rapport et des extraits de logs sont envoyés à Google.
      * Ollama : 100 % local (http://localhost:11434, `ollama pull llama3.1`).
  - "Répertoires…"        : dossiers surveillés (config :
    ~/Library/Application Support/SkyrimCrashAnalyzer/config.json).
  - "Fichier…"            : analyse rapide d'un .log/.txt isolé.
  - Clic sur une carte    : affiche le contenu du log.

Note : après un nouveau crash, relancer "Audit approfondi" pour actualiser le
contexte donné à l'IA.