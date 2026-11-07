# Changelog — sKYCRASH

Notes de version / release notes (EN + FR). Translations in IT and ES: see the Nexus Mods page.

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
