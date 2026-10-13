---
title: Triage d'un CTD selon la phase du crash
keywords: ctd, crash au lancement, logo, main menu, menu principal, écran de chargement, loading screen, fast travel, voyage rapide, charger une sauvegarde, load save, transition de cellule, cell transition, combat, aléatoire, random, bisect, dichotomie
---
- Phase = premier indice. Noter QUAND le crash survient avant d'ouvrir le log :
  - Avant/au logo Bethesda ou juste après : SKSE/Address Library/plugin SKSE incompatible, DLL manquante (VC++ redist), mauvaise version du jeu après mise à jour Steam.
  - Écran de chargement initial / menu principal : plugin SKSE qui lève une exception (voir skse64.log), master manquant, archive BSA corrompue, ENB/ReShade mal installé.
  - Chargement d'une sauvegarde : scripts orphelins, mod retiré en cours de partie, sauvegarde gonflée (ReSaver), plugin manquant ou ordre de chargement modifié.
  - Transition de cellule / voyage rapide : mémoire (VRAM/heap), navmesh/cellule en conflit, textures lourdes, mod de monde (DynDOLOD, villes).
  - Combat / animations : Havok/behavior (Nemesis/Pandora/FNIS), physique SMP/CBPC, mod d'animation récent.
  - Crash aléatoire après 1-2 h : fuite/pression mémoire, scripts qui s'accumulent, allocateur (tbbmalloc/Engine Fixes mal configuré).
- Méthode de la dichotomie : désactiver la moitié des mods suspects (plugins récents/DLL d'abord), tester, puis réduire. Changer UN élément à la fois et noter le résultat.
- Un crash reproductible au même endroit pointe vers un asset ou un script ; un crash non reproductible pointe vers la mémoire ou la concurrence (mods de physique, frameworks).
- Toujours comparer plusieurs crash logs : une même adresse/DLL répétée est un signal fort, des piles différentes suggèrent un problème d'environnement.
