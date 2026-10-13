---
title: Rendu, ENB, ReShade, DXVK/D3DMetal
keywords: d3d11, d3d10, dxgi, nvwgf2um, atidxx, amdxx, d3dcompiler, enbseries, reshade, dxvk, d3dmetal, bsshader, bsgraphics, graphique, shader, gpu, wine, crossover, gptk
---
- Crash avec d3d11.dll / dxgi.dll / pilote GPU (nvwgf2um, atidxx, amdxx) dans la pile : souvent shader, ENB/ReShade, pilote ou VRAM, pas un « mod de gameplay ».
- Tests : renommer/désactiver d3d11.dll (ENB), dxgi.dll (ReShade/ENB), enbseries.ini ; relancer. Si le crash disparaît, c'est le post-processing.
- ENB/ReShade doivent correspondre à la version du jeu ; réglages « VideoMemorySizeMb » trop élevés ou « ForceVideoMemorySize » peuvent crasher.
- Sur Mac (CrossOver/Wine/GPTK) : essayer D3DMetal vs DXVK, désactiver ENB, vérifier l'option de synchronisation (MSync/ESync) et la version de CrossOver ; les crashs dans wine.dll/winemac sont de la couche de compatibilité.
- Mettre à jour les pilotes GPU (Windows) ; en cas de crash dans BSShader, vérifier mods de météo/éclairage et shaders personnalisés.
