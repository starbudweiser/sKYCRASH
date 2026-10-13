---
title: Animations, behaviors et physique Havok
keywords: hkb, hkp, bhk, havok, behavior, .hkx, nemesis, pandora, animation, dar, oar, ccor, mco, bfco, fnis, physics
---
- Les crashs dans hkb*/hkp*/bhk* ou liés à un behavior/.hkx viennent de behaviors non régénérés ou conflictuels, d'animations incompatibles avec le squelette, ou de physique (collision) corrompue.
- Après tout ajout/retrait de mod d'animation (FNIS, Nemesis, Pandora, DAR/OAR), il faut relancer le générateur ; oublier cette étape est la cause n°1.
- Ne pas mélanger FNIS et Nemesis/Pandora sans suivre leur guide ; éviter deux frameworks de combat concurrents (MCO/BFCO/Valhalla) ensemble.
- Tester : désactiver les mods d'animation récents, régénérer, vérifier que le squelette (XPMSSE) est unique et à jour. Les mods de physique (CBPC, HDT-SMP) peuvent crasher si la version ne correspond pas à celle du jeu.
