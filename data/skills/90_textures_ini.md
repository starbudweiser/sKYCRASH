---
title: Textures, BSA/archives et réglages INI
keywords: bstexturedb, .dds, bsresource, bstextureset, texture, bsa, ba2, ini, skyrim.ini, skyrimprefs, skyrimcustom, archive, bc7, bc1, mipmap, resourcedatadirlist, sresourcearchivelist
---
- Texture corrompue ou mal formatée (BC7 non supportée sur anciens GPU, mipmaps manquants, dimensions non multiples de 4) : crash en chargeant une cellule ou un objet.
- Skyrim.ini : éviter sResourceArchiveList trop longue ; le chargement des BSA suit l'ordre des plugins ; vérifier bInvalidateOlderFiles=1 pour utiliser les fichiers lâches.
- Pistes : identifier la texture dans le crash log, vérifier le mod fournisseur, reconvertir en BC7/BC1 avec Cathedral Assets Optimizer ou texconv, regénérer les mipmaps.
- Un fichier INI personnalisé (Skyrim.ini/SkyrimPrefs.ini) hérité d'une ancienne installation peut causer des crashs : tester avec des INI par défaut.
