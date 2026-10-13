---
title: Indicateurs et diagnostics éprouvés (inspiré de l'analyseur communautaire de Phostwood)
keywords: nvwgf2um, nvlddmkm, nvapi64, amdxx64, amdxc64, atidxx64, atikmdag, msvcp140, vcruntime140, ucrtbase, msvcp100, enginefixes, tbbmalloc, d3dx9_42, quest_journal, journalmenu, journal_systemtab, bsimagespace, nicamera, worldroot, hudmenu, dragon's eye, dragons eye, minimap, bswin32gamepaddevice, bspcgamepaddevicehandler, bswin32keyboarddevice, bloodhiteffect, bloodspray, fpsfixplugin, 132bef, 12fdd00, 12f5590, bhkcollisionobject, bhkcompressedmeshshape, bsdynamictrishape, ninode, object reference: none, basefrom: null, baseform: null, physical memory, gpu memory, missing master, 254, esl, creations, bees, navmesh, pathing, bspathing, isran, celann, dawnguard horse, dyndolod, pagefile
---
Source d'inspiration : analyseur de crash de Phostwood (phostwood.github.io/crash-analyzer). Ces règles sont des heuristiques : un indicateur isolé ne prouve rien, plusieurs indicateurs concordants augmentent la confiance. Mentionne toujours le niveau de confiance.

**Pilotes GPU** : nvwgf2um(x).dll, nvlddmkm.sys, nvapi64.dll, nvgpucomp64.dll (NVIDIA) ; amdxx64.dll, amdxc64.dll, atidxx64.dll, atikmdag.sys (AMD). Leur présence dans la pile = problème de pilote/shader/VRAM : mise à jour/réinstallation propre du pilote (DDU), vérification ENB/ReShade, baisse des textures.

**Runtime Visual C++** : msvcp140.dll, vcruntime140.dll, msvcp100/110.dll, ucrtbase.dll en tête de pile = redistribuables VC++ manquants ou corrompus (installer les VC++ 2015-2022 x64, ainsi que les anciennes versions). Sur Mac/Wine, vérifier qu'ils sont présents dans la bouteille.

**SSE Engine Fixes** : EngineFixes.dll, tbbmalloc.dll, tbb.dll, d3dx9_42.dll. Très souvent mal installé : il faut les DEUX parties (plugin SKSE adapté à la version du jeu + DLL à la racine du jeu). Avant la v7, EngineFixes.toml doit contenir SaveGameMaxSize = true et MaxStdio = 8192. Préférer la v7 récente.

**Interface** : Quest_Journal.swf / JournalMenu / Journal_SystemTab = journal SkyUI. Dragon's Eye Minimap : BSImagespace, NiCamera, "WorldRoot Camera/Node", « Block ( », HUDMenu. Manette/clavier : BSWin32GamepadDevice, BSPCGamepadDeviceHandler (indicateur peu fiable), bswin32keyboarddevice.

**SSE Fixes (FpsFixPlugin.dll)** : effets d'impact BloodHitEffectBlunt/Cut, BloodSpray*, ImpactArrowDirt01/Dust01, PierceBone, FistBlood* dans le log = problème lié aux effets d'impact ; vérifier SSE Fixes/mods de sang.

**Meshes** : codes hex en première ligne 132BEF (mesh de tête, souvent PNJ/FaceGen), 12FDD00 (NIF corrompu), 12F5590 (chargement/rendu de mesh, FaceGen). Termes : bhkCollisionObject, bhkCompressedMeshShape, BSDynamicTriShape, BSEffectShaderProperty, BSFadeNode, NiNode (squelette). Marche à suivre : repérer les .nif cités dans « POSSIBLE RELEVANT OBJECTS »/pile, retrouver le mod source, réinstaller, scanner avec NifScan ou SNIFF, corriger avec SSE NIF Optimizer ou Cathedral Assets Optimizer, régénérer FaceGen (Creation Kit) pour un PNJ, vérifier le squelette.

**Mémoire** : seuils d'alerte ~85 % RAM ou VRAM. Pistes : fermer les applications, pagefile Windows fixe d'environ 40 Go (surtout ≤ 16 Go de RAM ; avis divergents, un pagefile géré par le système reste acceptable avec 64 Go+), textures 1K/2K, VRAMr pour optimiser automatiquement, limiter la densité d'objets (arbres/végétation), suivre l'usage avec Intel PresentMon. Contournement en jeu : console `pcb` (Purge Cell Buffer), surtout en intérieur. Une forte consommation peut être la conséquence d'un autre problème.

**Masters manquants / dépendances** : signes : première ligne avec offset 0198090 (AE) ou 5E1F22 (SE), présence de « SettingT<INISettingCollection>* », ou aucun plugin listé. Causes : master manquant ou chargé après son dépendant (Trier avec LOOT/Sort), mod retiré en cours de partie, mod nécessitant les Creation Club non téléchargés, mod avec ESL « récent » sur un jeu < 1.6.1130 (installer BEES), mauvais usage du menu Créations avec MO2/Vortex (ne jamais l'utiliser avec un gestionnaire externe), mauvaise version SE/AE. Identifier avec MO2 (triangle jaune) ou SSEEdit.

**Limite de plugins** : maximum 254 plugins non-ESL (ceux flaggés ESL apparaissent avec formID [FE xxx] et ne comptent pas). Au-delà : instabilité grave ; solutions : ESLifier, flagger en ESL les plugins éligibles.

**« Object Reference: None » / « BaseForm: null »** (Crash Logger / NetScriptFramework) : une référence pointe vers un objet inexistant. Le fichier le plus probable est le plugin de la référence elle-même (fichier du registre/« Modified by ») ; les fichiers de la cellule parente sont secondaires. Ignorer Skyrim.esm, Update.esm, Dawnguard.esm, HearthFires.esm, Dragonborn.esm. Pistes : désactiver le mod et ses dépendances, vérifier version, patch manquant, ordre de chargement.

**Navmesh / pathing** : indicateurs BSPathing/navmesh dans le haut de la pile = PNJ ou créature bloqué (obstacle ajouté par un mod, mod d'IA/pathing incompatible). Pistes : charger une sauvegarde plus ancienne, laisser les suiveurs/montures en attente avant un voyage rapide, mod Navigator (Navmesh Fixes), tester `tai`/`tcai` en console pour confirmer, désactiver les mods d'IA/déplacement. Cas connu : cheval Dawnguard de « Skyrim Immersive Creatures » avec Isran/Celann : supprimer le form SIC_WERoad07 dans SSEEdit.

**DynDOLOD 3.0.34** : version connue pour causer des crashs ; vérifier la version et régénérer/mettre à jour.
