---
title: Papyrus, scripts et sauvegardes
keywords: papyrus, virtualmachine, bsscript, skyrimvm, .psc, dumping stack, stack overflow, suspended stack, cannot open store, none object, script, resaver, save, sauvegarde
---
- « Cannot open store for class X » : le mod fournissant le script a été retiré alors que la sauvegarde l'appelle encore ; le script devient « orphelin ».
- « Dumping stack » / « Suspended stack » en grand nombre : surcharge Papyrus, souvent due à un script qui tourne en boucle (OnUpdate) ou à des mods lourds ; cela précède souvent des ralentissements puis un crash.
- Scripts bavards dans Papyrus.0.log : lister les plus fréquents (classe .psc) ; un mod unique qui spamme est un excellent suspect.
- Pistes : réinstaller le mod manquant, nettoyer la sauvegarde avec ReSaver (scripts orphelins, instances inactives), éviter de désinstaller des mods à scripts en cours de partie, activer le logging Papyrus dans Skyrim.ini (bEnableLogging=1) pour diagnostiquer.
- Un seul message d'erreur Papyrus n'est pas un crash : privilégier les motifs répétés et corrélés avec le moment du crash.
- « Cannot open store for class "ccXXX…", missing file? » (scripts ccBGS_*, CCHorseArmor… ) : contenu Creation Club absent ou incomplet (téléchargement CC oublié, fichiers retirés, ou usage du menu Créations avec un gestionnaire externe). Corriger via le jeu (Créations) ou retirer les mods qui en dépendent.
- « Script X cannot be bound to Y » : le script n'existe pas ou n'est pas chargé (mod incomplet, master manquant, ancienne sauvegarde).
- « Native function F in empty state could find no matching function on linked type … Function will not be bound » : le .pex attend une fonction native absente (plugin SKSE manquant/incompatible, ou mauvaise version du mod).
