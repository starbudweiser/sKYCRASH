---
title: Interface, Scaleform, SkyUI et mods de menus
keywords: skyui, scaleform, swf, ui, menu, interface, flash, compass, compassnavigationoverhaul, infinityui, ui extensions, imgui, dear imgui, inventory, hudmenu, custom skills, journalmenu, mcm, mod configuration menu, quickloot, ui_selection
---
- L'interface de Skyrim est du Scaleform (Flash/.swf). Les mods d'UI (SkyUI, InfinityUI, Compass Navigation Overhaul, QuickLoot, TrueHUD…) s'accrochent à ces menus par des plugins SKSE : un menu modifié par deux mods en conflit produit des crashs à l'ouverture d'un menu précis.
- Indices : noms de menus dans la pile (HUDMenu, JournalMenu, InventoryMenu, MapMenu), « scaleform » dans les fonctions, plantage reproductible à l'ouverture d'un écran.
- Un plugin d'UI qui plante au chargement (exception dans skse64.log) a souvent un prérequis d'interface manquant (ex. un mod UI de base absent ou d'une autre version). Vérifier la page du mod, ses prérequis et la version du jeu/SKSE.
- MCM (menus de configuration) et mods Papyrus-UI dépendent de SkyUI/SKSE ; des réglages MCM corrompus dans une sauvegarde peuvent nécessiter un reset du mod.
- Dear ImGui (menus pour mods, ex. frameworks de configuration) s'appuie sur le moteur de rendu : sous Wine/Mac ou avec ENB, les crashs d'overlay sont plus fréquents ; désactiver l'overlay pour tester.
- Ne pas installer deux mods qui remplacent le même .swf (journal, inventaire, carte) sans patch de compatibilité.
