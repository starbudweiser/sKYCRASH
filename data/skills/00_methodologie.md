---
title: Méthodologie de diagnostic Skyrim SE/AE
keywords: crash
always: true
---
- Le module en tête de la pile d'appels n'est pas forcément coupable : un plugin peut crasher dans le moteur (SkyrimSE.exe) ou un pilote parce qu'il a passé une donnée corrompue. Cherche le premier module tiers (non Windows, non SkyrimSE.exe) et les objets « POSSIBLE RELEVANT OBJECTS ».
- Un crash dans SkyrimSE.exe seul, sans DLL tierce, pointe souvent vers un asset (NIF, texture, navmesh, animation) ou un form/record corrompu.
- Vérifier d'abord la cohérence des versions : exécutable du jeu, SKSE, Address Library, plugins SKSE (.dll). Un mismatch cause des crashs au lancement ou au menu.
- Dichotomie : désactiver la moitié des mods suspects, tester, recommencer. Toujours tester sur une sauvegarde ou une nouvelle partie.
- Un seul log ne prouve rien : croiser crash log, skse64.log et Papyrus.0.log. Indique ton niveau de confiance.
- Ne conseille jamais de supprimer des fichiers du jeu sans sauvegarde ; privilégie la désactivation réversible dans le gestionnaire de mods (MO2/Vortex).
- Plateforme : sur Mac, Skyrim tourne via CrossOver/Wine/GPTK ; les problèmes graphiques (d3d11/dxvk/d3dmetal) peuvent venir de la couche de compatibilité, pas du mod.
- Sous CrossOver (CPU « VirtualApple », GPU « Compatibility Mode »), Crash Logger produit souvent une PROBABLE CALL STACK vide et une adresse d'exception atypique (ex. 0x0002D51C2FA4) : analyser la section STACK brute (références « -> module+offset »), compter les modules tiers, et ne pas accuser un mod sans preuve concordante. Un STACK dont presque toutes les références sont SkyrimSE.exe indique un crash dans le moteur.
- Un crash log compare/corrèle les offsets SkyrimSE.exe+XXXX avec Address Library de la même version du jeu pour identifier la fonction du moteur.
- Le fichier CrashLogger.log (sans horodatage) n'est PAS un crash log : c'est le journal de chargement du plugin.
- Ordre de lecture recommandé : 1) skse64.log (exception au chargement ? plugin refusé ?), 2) crash-*.log (STACK, MODULES, SYSTEM SPECS), 3) Papyrus.0.log, 4) logs des plugins (EngineFixes, ENB...).
