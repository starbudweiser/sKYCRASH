---
title: Gestionnaires de mods (MO2, Vortex, Wabbajack) et mises à jour du jeu
keywords: mo2, mod organizer, usvfs, vortex, wabbajack, overwrite, deploy, hardlink, steam update, mise à jour steam, downgrade, loose files, fichiers loose, stock game, modlist, profil, profile, skyrim.ini, skyrimprefs.ini
---
- MO2 utilise un système de fichiers virtuel (USVFS) : les outils (xEdit, Nemesis, Synthesis, DynDOLOD) doivent être lancés DEPUIS MO2, sinon ils ne voient pas les mods. Les fichiers générés vont dans « Overwrite » : les ranger dans un mod dédié.
- Vortex déploie par liens/copie dans Data : une purge ou un déploiement interrompu laisse des fichiers orphelins ; purger puis redéployer en cas de doute.
- Mise à jour Steam du jeu = rupture classique : tous les plugins SKSE et Address Library doivent être compatibles avec la nouvelle version. Désactiver les mises à jour automatiques (Steam > Propriétés > Mises à jour) ou « figer » la version ; les listes Wabbajack ciblent une version précise (ne pas mettre le jeu à jour au-dessus d'elle).
- Wabbajack : ne pas modifier une modlist en cours de route sans connaître ses dépendances ; en cas de crash, utiliser le support/Discord de la liste avec son crash log plutôt que de retirer des mods.
- Garder SkyrimSE.exe hors du dossier Program Files (UAC) et désactiver les antivirus sur le dossier de jeu en cas de fichiers bloqués ; « débloquer » les DLL téléchargées si Windows les marque.
- Sauvegarder la configuration du profil (skyrim.ini, skyrimprefs.ini, plugins.txt, loadorder.txt) avant de changer de version majeure.
