---
title: SKSE, Address Library et versions du jeu
keywords: skse, address library, versionlib, no version data, incompatible, disabled, version mismatch, 1.6., 1.5.97, ae, se, f4se
---
- Skyrim SE (1.5.97) et AE (1.6.x) ont des exécutables différents ; la plupart des plugins SKSE récents exigent Address Library (all-in-one ou version spécifique) correspondant exactement à la version du jeu.
- Dans skse64.log : « disabled, no version data » = plugin ancien sans support de la version actuelle ; « reported as incompatible with current version » = plugin non compilé pour cette version ; « couldn't load plugin » (code d'erreur) = DLL manquante (VC++ redist) ou dépendance.
- Solutions : mettre à jour le plugin vers la version AE/« NG » adéquate, installer le bon Address Library, ou retirer le plugin. Après une mise à jour du jeu, tous les plugins SKSE doivent être revérifiés.
- Un crash au lancement juste après la mise à jour de Steam est quasi toujours un mismatch SKSE/Address Library/plugins.
- Vérifier que le lanceur utilisé est skse64_loader.exe (pas SkyrimSE.exe) si les mods SKSE ne se chargent pas.
- Bibliothèques courantes : SSE Engine Fixes (nécessite ses propres DLL tbbmalloc), Crash Logger SSE (génère les crash logs), PapyrusUtil, powerofthree's Tweaks, Scrambled Bugs.
- « exception occurred while loading plugins » dans skse64.log : un plugin a levé une exception pendant le chargement/PostLoad. Les lignes « sending message type 0 to plugin N » (N = handle indiqué dans « loaded correctly (handle N) ») précèdent l'erreur : le dernier handle actif est le premier suspect, « registering plugin listener for X » indique le plugin avec lequel il interagissait (souvent un framework UI comme InfinityUI/SkyUI). Mettre à jour ou désactiver ce plugin et vérifier ses prérequis.
- Runtime SKSE 01050610 = Skyrim SE 1.5.97 ; les plugins « AE/NG » (Address Library 1.6.x) ne se chargent pas sur 1.5.97 et inversement.
- Builds courantes d'après la page officielle SKSE (relevé du 2026-10-09, à revérifier via la veille automatique) : SE 1.5.97 → SKSE 2.0.20 ; AE GOG 1.6.1179 → SKSE 2.2.6 ; AE Steam 1.7.x (ex. 1.7.104) → SKSE 2.3.1. La branche 1.7.x change de format d'Address Library : un plugin compilé pour 1.6.x ne fonctionne pas dessus sans mise à jour.
