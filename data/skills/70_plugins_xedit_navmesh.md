---
title: Plugins ESP/ESM/ESL, conflits, navmesh, ordre de chargement
keywords: .esp, .esm, .esl, navmesh, tesobjectcell, bspathing, tesobjectarmo, form, record, xedit, sseedit, loot, load order, masters, master, plugins, patch, conflit
---
- Un plugin cité dans le crash log (« POSSIBLE RELEVANT OBJECTS ») est un suspect, pas une preuve : il peut être simplement l'objet en cours de traitement.
- Outils : LOOT (ordre de chargement), SSEEdit/xEdit (conflits, masters manquants, « Quick Auto Clean » uniquement sur plugins recommandés), Synthesis/patchers.
- Masters manquants ou désactivés = crash au chargement de sauvegarde ou de cellule. Vérifier qu'aucun plugin n'a un master absent.
- Navmesh : mods modifiant la même cellule (TESObjectCELL, BSPathing) ont besoin d'un patch de compatibilité ; plusieurs mods de navmesh sur la même zone provoquent des crashs de pathfinding.
- Limite des plugins : 254 plugins complets + ESL (4096 formIDs/ESL) ; dépasser ou mal flaguer en ESL corrompt les formIDs.
- Stratégie : isoler par moitié dans MO2 en gardant les masters ; vérifier les patchs de compatibilité (Requiem, Obsidian, Ordinator, etc.).
