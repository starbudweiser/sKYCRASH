---
title: Épuisement mémoire (RAM, VRAM, heap)
keywords: bad_alloc, out of memory, failed to allocate, virtualalloc, tbbmalloc, mémoire, memory, vram, 4k, 2k, enb, ctd
---
- Skyrim SE est un processus 64 bits mais son allocateur et ses pools internes saturent avec de très gros packs de textures/meshes ; EXCEPTION_ACCESS_VIOLATION après de longues sessions ou dans des zones denses (Whiterun, Solitude, Markarth) est un signe classique.
- Causes fréquentes : textures 4K/8K non nécessaires, trop de mods de végétation/éclairage, ENB avec réglages VRAM élevés, ShadowBoost mal réglé.
- Pistes : installer SSE Engine Fixes (correctif mémoire/allocateur) et vérifier tbbmalloc.dll ; réduire les textures (optimiser avec Cathedral Assets Optimizer / BC7→BC1 pour les grandes), réduire distance d'affichage, limiter ENB (MemoryAllocation), vérifier la VRAM disponible.
- Sur Mac via CrossOver/GPTK la VRAM unifiée est partagée avec la RAM : garder de la marge.
- Un crash survenant systématiquement au même endroit suggère un asset ou un mod local ; un crash aléatoire après longtemps suggère plutôt la mémoire.
