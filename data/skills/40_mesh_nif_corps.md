---
title: Meshes NIF, armures, corps et visages
keywords: .nif, niskininstance, bstrishape, nitrishape, bsdismember, facegen, bsfadenode, mesh, armor, armure, cbbe, bhunp, 3ba, outfit, skeleton, xpmsse, facegeom
---
- Les crashs avec NiSkinInstance/BSTriShape/BSDismember et un .nif cité dans « POSSIBLE RELEVANT OBJECTS » indiquent presque toujours un mesh mal exporté (skin partitions manquants, os absents du squelette, mauvais format SSE vs LE).
- Causes : armure/vêtement non converti LE→SSE, corps (CBBE/BHUNP/3BA) non reconstruit via BodySlide après changement de preset, squelette XPMSSE absent/obsolète, FaceGen manquant pour un PNJ ajouté par un mod.
- Pistes : identifier le mod propriétaire du .nif (MO2 : onglet Conflits/Data), le rouvrir dans NifSkope/Outfit Studio, reconstruire avec BodySlide, vérifier XPMSSE, régénérer FaceGen via Creation Kit (« Ctrl+F4 ») si le crash est lié à un visage de PNJ.
- Si le fichier cité est dans un mod de cheveux/visage (racemenu, kalilies), tester en désactivant le mod de présets.
