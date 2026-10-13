---
title: Community Shaders, upscaling et pile graphique moderne
keywords: community shaders, communityshaders, shader, shaders, pbr, parallax, terrain, upscaling, dlss, fsr, frame generation, streamline, reshade, enb, d3d11, dxgi, shader cache, nvngx, sl.interposer, skylighting, screen space, ssgi, grass
---
- Community Shaders (CS) est un plugin SKSE qui remplace/étend les shaders du jeu par des « features » (éclairage, terrain parallax, herbe, ombres…). Il exige le bon Address Library et une version compatible avec votre exécutable : vérifier la branche/version sur sa page.
- Au premier lancement (ou après mise à jour), CS compile un cache de shaders : ne pas interrompre ; en cas de crash pendant cette phase, vider le cache (dossier Data/ShaderCache) et relancer. Un cache obsolète est une cause fréquente de crash graphique après mise à jour.
- Ne pas combiner CS et ENB : les deux modifient le rendu et sont généralement incompatibles. Désactiver une feature à la fois (menu CS) pour isoler un crash.
- Upscaling/Frame Generation (DLSS, FSR, Streamline) exige un GPU/driver compatibles ; sous Wine/Mac ou sans GPU NVIDIA RTX, ces DLL échouent à l'initialisation (voir fiche CrossOver).
- Les mods de textures PBR/parallax augmentent fortement la VRAM : une saturation VRAM + crash dans d3d11/nvwgf2um est un tableau classique (voir fiche mémoire).
- Mettre à jour les pilotes GPU est utile pour les crashs dans les DLL du pilote (nvwgf2um, atidxx64) ; sous Mac, changer de moteur D3DMetal/DXVK/DXMT.
