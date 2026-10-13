---
title: CrossOver / Wine / GPTK sur Mac (Apple Silicon)
keywords: crossover, wine, d3dmetal, gptk, apple_gptk, dxmt, dxvk, moltenvk, rosetta, virtualapple, winemac, winecoreaudio, macos, mac, bouteille, bottle, msync, esync, apple silicon, unified memory, mémoire unifiée
---
- Skyrim tourne en émulation : Rosetta 2 (CPU VirtualApple) + Wine + traduction DirectX→Metal. Piles d'appels vides, adresses atypiques et crashs graphiques y sont plus fréquents : ne pas accuser un mod sans autre preuve.
- Moteurs graphiques : D3DMetal (Apple GPTK, intégré à CrossOver, le plus rapide), DXMT (traduction D3D11→Metal directe, récente), DXVK + MoltenVK (D3D→Vulkan→Metal, plus gourmand en mémoire). En cas de crash graphique : changer UN moteur à la fois et retester.
- Mémoire unifiée : le GPU partage la RAM du Mac. Un « GPU MEMORY » supérieur à la RAM (ex. 103 Go pour 64 Go) n'est pas une VRAM dédiée ; seule la RAM disponible compte. Surveiller la pression mémoire (Moniteur d'activité) et fermer les autres applications.
- DLSS / Streamline (sl.interposer.dll, sl.dlss.dll, nvngx.dll) ne fonctionnent pas sous Wine/Mac : retirer les DLL ou désactiver DLSS/Frame Generation dans ENB ; les erreurs Streamline dans les logs sont attendues.
- ENB/ReShade : d3d11.dll/dxgi.dll proxy doivent être en override « native, builtin » dans la bouteille ; ENB est moins éprouvé avec D3DMetal.
- Les chemins Windows sont dans la bouteille (…/drive_c/users/crossover/Documents/My Games/Skyrim Special Edition/). Ajouter ces dossiers dans « Répertoires… ». Respecter la casse des fichiers pour les mods copiés manuellement.
- Après une mise à jour de CrossOver ou de macOS, retester sans mods avant de conclure ; un changement de version de Wine peut casser des plugins qui fonctionnaient.
