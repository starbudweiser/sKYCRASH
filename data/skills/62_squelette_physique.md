---
title: Squelette, physique (SMP/CBPC) et moteurs d'animation
keywords: hdt, hdt-smp, smp, cbpc, xpmsse, skeleton, squelette, physique, physics, bhk, ragdoll, cloth, nemesis, pandora, fnis, behavior, dar, oar, open animation replacer, dynamic animation replacer, animation, havok, hkb, hkbbehaviorgraph, nioverride, racemenu
---
- Les plugins de physique (HDT-SMP / Faster HDT-SMP, CBPC) simulent cheveux, tissus et corps ; ils s'exécutent en parallèle et sont une source fréquente de crashs aléatoires, surtout avec beaucoup de PNJ ou de pièces d'armure.
- Un squelette incompatible (XPMSSE / squelettes de corps) ou deux mods qui fournissent le même squelette provoquent des crashs d'animation ; garder UN squelette, installé en dernier côté fichiers.
- Moteurs d'animation : Nemesis/Pandora/FNIS génèrent des behaviors ; les relancer après CHAQUE changement de mods d'animation, vérifier l'absence d'erreur, et ne pas mélanger FNIS et Nemesis. DAR/OAR (remplacement d'animations par conditions) : un dossier mal nommé ou un JSON invalide peut provoquer une erreur de chargement.
- Indices dans le log : bhkCollisionObject, hkbBehaviorGraph, NiNode, ragdoll, hdt, cbp.
- Isolation : désactiver SMP/CBPC, puis les mods d'armures/cheveux avec physique, puis régénérer les behaviors ; réduire le nombre de PNJ (mods de population) pour tester.
- Sous Wine/Mac, les mods de physique multithreadés peuvent être moins stables : tester sans eux avant de conclure.
