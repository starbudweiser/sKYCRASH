# Changelog — sKYCRASH

Notes de version / release notes (EN + FR). Translations in IT and ES: see the Nexus Mods page.

## 2.2.0

**English**

- Script origins: with Vortex or mORTEX, the mod that provides each script is now named (read from the deployment manifest) instead of "game (Data)".
- Mod names no longer carry the Nexus download suffix (for example "Abyss-83329-3-1-6-1708252797" becomes "Abyss").
- A suspect script with no known mod now shows the BSA archive that provides it.
- Identical findings from Papyrus.0.log and Papyrus.1.log are merged into one, listing both logs.
- Progress bar with percentage while the knowledge base updates, in the assistant header and under the "Update now" button, where the result is now shown.

**Français**

- Provenance des scripts : avec Vortex ou mORTEX, le mod qui fournit chaque script est maintenant nommé (lu dans le manifeste de déploiement) au lieu de « jeu (Data) ».
- Les noms de mods n'ont plus le suffixe de téléchargement Nexus (par exemple « Abyss-83329-3-1-6-1708252797 » devient « Abyss »).
- Un script suspect sans mod connu indique l'archive BSA qui le fournit.
- Les constats identiques de Papyrus.0.log et Papyrus.1.log sont fusionnés en un seul, qui cite les deux journaux.
- Barre de progression avec pourcentage pendant la mise à jour de la base de connaissances, dans l'en-tête de l'assistant et sous le bouton « Mettre à jour maintenant », où s'affiche désormais le résultat.

## 2.1.0

**English**

- New "Script origins" finding: for each Papyrus script named in the logs (missing, unbound, very chatty, or with unbound native functions), sKYCRASH tells which mod or BSA archive provides it, or that it is found nowhere.
- Warns when several mods provide the same script (possible conflict) and when a mod overrides a game script whose native functions are not bound.
- Script suspects now show the mod that provides them, like SKSE DLLs.

**Français**

- Nouveau constat « Provenance des scripts » : pour chaque script Papyrus cité dans les journaux (introuvable, non lié, très bavard ou aux fonctions natives non liées), sKYCRASH indique le mod ou l'archive BSA qui le fournit, ou qu'il n'est fourni nulle part.
- Signale quand plusieurs mods fournissent le même script (conflit possible) et quand un mod remplace un script du jeu dont les fonctions natives ne sont pas liées.
- Les scripts suspects indiquent désormais le mod qui les fournit, comme les DLL SKSE.

## 2.0.0

**English**

- Version number aligned across the Skyrim Mac Toolkit: every app of the kit is now a native Swift app, at version 2.0.0.

**Français**

- Numéro de version commun à tout le Skyrim Mac Toolkit : toutes les applis du kit sont désormais des applis Swift natives, en version 2.0.0.

## 1.3.1

**English**

- The standard buttons of dialogs (Cancel in Settings, Yes/No) now follow the app's language instead of staying in English.
- Rebuilt as a **native Swift app** (no more Python or PyInstaller): same analysis and same results (checked line by line against the previous version on the sample logs, on real crash logs and on saves; the mORTEX export file is byte-identical), faster to start, and not flagged by antivirus scanners. Your settings, knowledge base and export file are picked up as they are. API keys stay in the macOS Keychain (macOS may ask once to allow the new build to read them: choose "Always Allow").
- Automatic updates from inside the app: the app checks GitHub once a day, shows the release notes in your language, then downloads and installs the new version itself ("Install and relaunch"), after checking its checksum, Developer ID signature and Apple notarization, and never during an analysis. Also available from the "Check for updates…" menu item. Install this version by hand once: from then on, updates install from inside the app.
- New "Language" menu in the menu bar (Automatic, Français, English, Español, Italiano). Drag-and-drop of a log file onto the window.

**Français**

- Les boutons standard des dialogues (Annuler dans les Réglages, Oui/Non) suivent maintenant la langue de l'appli au lieu de rester en anglais.
- Reconstruite en **appli Swift native** (plus de Python ni de PyInstaller) : même analyse et mêmes résultats (vérifiés ligne à ligne avec la version précédente sur les logs d'exemple, sur de vrais crash logs et sur des sauvegardes ; le fichier d'export pour mORTEX est identique à l'octet près), démarrage plus rapide, et plus de fausses alertes antivirus. Vos réglages, la base de connaissances et le fichier d'export sont repris tels quels. Les clés API restent dans le Trousseau macOS (macOS peut demander une fois d'autoriser la nouvelle version à les lire : choisissez « Toujours autoriser »).
- Mise à jour automatique depuis l'appli : elle consulte GitHub une fois par jour, affiche les notes de version dans votre langue, puis télécharge et installe elle-même la nouvelle version (« Installer et relancer »), après avoir vérifié son empreinte, sa signature Developer ID et sa notarisation Apple, et jamais pendant une analyse. Disponible aussi par le menu « Rechercher les mises à jour… ». Installez cette version à la main une fois : ensuite, les mises à jour s'installent depuis l'appli.
- Nouveau menu « Langue » dans la barre de menus (Automatique, Français, English, Español, Italiano). Glisser-déposer d'un fichier log sur la fenêtre.

## 1.3.0

**English**

- Signed with a Developer ID and notarized by Apple: macOS now opens the app without a security warning.
- The app's launcher is now compiled from source when the app is built, instead of using PyInstaller's generic prebuilt launcher, which antivirus scanners tend to flag. No change in features.
- New animated splash screen at launch.
- The first letter of the app's name now uses the colour of its logo everywhere it appears.
- Version number aligned across the Skyrim Mac Toolkit.

**Français**

- Signée avec un certificat Developer ID et notarisée par Apple : macOS ouvre désormais l'appli sans avertissement de sécurité.
- Le lanceur de l'appli est maintenant compilé depuis les sources à la construction de l'appli, au lieu du lanceur générique précompilé de PyInstaller, souvent signalé par les antivirus. Aucun changement de fonctionnalités.
- Nouvel écran de lancement animé.
- La première lettre du nom de l'appli prend la couleur de son logo partout où il est écrit.
- Numéro de version commun à tout le Skyrim Mac Toolkit.

<!-- gen_changelogs : entrées ci-dessous conservées -->

## 1.0.0

First public release. / Première version publique.
