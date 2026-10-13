---
title: Où trouver et comment activer les logs utiles
keywords: log, logs, papyrus.0.log, skse64.log, crashlogs, crashlogger, crash logger, benablelogging, benabletrace, bloaddebuginformation, skyrimcustom.ini, my games, documents, dotnet script framework, netscriptframework, journal
---
- Dossier : Documents/My Games/Skyrim Special Edition/ (ou « Skyrim Special Edition GOG »). Sous CrossOver : dans la bouteille, drive_c/users/crossover/Documents/My Games/…
- SKSE/skse64.log : chargement des plugins (versions, refus, exceptions). SKSE/Crashlogs/crash-*.log : crash logs de Crash Logger SSE. Logs/Script/Papyrus.0.log : erreurs et traces Papyrus. Autres logs : un fichier .log par plugin dans SKSE/.
- Activer Papyrus : dans SkyrimCustom.ini (pas Skyrim.ini), section [Papyrus] : bEnableLogging=1, bEnableTrace=1, bLoadDebugInformation=1. À désactiver une fois le diagnostic terminé (ralentit le jeu).
- Crash Logger SSE (alandtse) : écrit un rapport à chaque crash (pile, registres, modules, SYSTEM SPECS). Sa configuration (.toml/.ini dans Data/SKSE/Plugins) permet de choisir le niveau de détail et d'activer le journal des modules.
- Un log vieux ne correspond pas forcément au dernier lancement : comparer les dates avant d'interpréter. Purger les logs avant un test (bouton « Purger les logs ») pour obtenir une base propre.
- Partager un log : joindre le crash log COMPLET, skse64.log, la liste des plugins et les versions (jeu, SKSE, Address Library). Masquer les noms d'utilisateur dans les chemins.
