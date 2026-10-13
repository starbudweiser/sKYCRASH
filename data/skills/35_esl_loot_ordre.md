---
title: Plugins ESP/ESM/ESL, LOOT et ordre de chargement
keywords: esl, esp, esm, esplugin, loot, masterlist, load order, ordre de chargement, missing master, master manquant, plugins.txt, loadorder.txt, 254, 4096, bees, light plugin, espfe, formid, xedit, tes5edit, sseedit
---
- Limite : 254 plugins complets (.esp/.esm) actifs ; les plugins légers (ESL ou flag ESL) en occupent un seul slot partagé pour 4096 chacun. Au-delà de la limite, les formIDs se corrompent et le jeu plante.
- Solutions : flaguer ESL les plugins éligibles (xEdit « Compact FormIDs » si nécessaire, sinon simple flag), fusionner des mods, retirer du contenu. BEES (Backported Extended ESL Support) permet les ESL « étendus » sur SE 1.5.97.
- « Missing master » : un plugin dépend d'un master absent/désactivé. Le jeu peut crasher au chargement ou à la lecture de la sauvegarde. Corriger avant tout autre diagnostic (LOOT, xEdit « Check for Errors »).
- LOOT trie selon une masterlist communautaire et signale conflits/incompatibilités ; un tri n'est pas une garantie de stabilité. Trier après chaque ajout de plugin, ne pas modifier l'ordre au milieu d'une partie.
- Les patchs générés (Synthesis, Bashed Patch, DynDOLOD, Nemesis, FNIS, Pandora) doivent être régénérés après un changement de mods ; un patch obsolète est une cause classique de crash.
- xEdit : n'utiliser que pour nettoyer (ITM/UDR) si la page du mod le recommande ; ne pas « nettoyer » les masters officiels sans raison.
