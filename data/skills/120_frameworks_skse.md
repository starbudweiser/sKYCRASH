---
title: Frameworks SKSE courants (ne pas confondre bibliothèque et coupable)
keywords: powerofthree, po3, papyrusextender, papyrusutil, base object swapper, baseobjectswapper, keyword item distributor, kid, spid, spell perk item distributor, dynamic string distributor, dsd, commonlib, commonlibsse, mfg fix, scrambled bugs, tweaks, engine fixes, enginefixes, skse64, framework, nioverride, jcontainers, dyndolod, dllplugin
---
- Les frameworks (PapyrusExtender, powerOfThree's Tweaks, Base Object Swapper, SPID/KID, DSD, JContainers, PapyrusUtil, NiOverride) fournissent des fonctions ou injectent des données pour d'autres mods. Ils apparaissent dans les piles parce qu'ils interceptent des fonctions du moteur : être CITÉ ne veut pas dire être FAUTIF.
- Règle : si un framework est en haut de la pile, chercher quel mod lui fournit des données (fichiers _DISTR.ini, _SWAP.ini, .json) ou quel script l'appelle ; vérifier la version du framework vs le jeu/Address Library, puis les données d'un mod récent.
- « Native function … could find no matching function » : un framework (souvent PapyrusExtender) est absent, trop ancien ou non chargé par SKSE ; vérifier skse64.log.
- Un fichier de distribution mal formé (ligne invalide dans un _DISTR.ini) peut faire planter SPID/KID/BOS : le log du framework (Documents/My Games/…/SKSE/<Framework>.log) nomme la ligne.
- Garder les frameworks à jour avec la version du jeu ; les plugins « NG » fonctionnent sur plusieurs versions via Address Library, les plugins anciens non.
- DynDOLOD/TexGen sont des outils de génération : leurs sorties sont à régénérer après tout changement de mods du monde.
