---
title: Lire un crash log (Crash Logger SSE / .NET Script Framework)
keywords: crash logger, call stack, probable call stack, unhandled exception, exception_access_violation, exception_, rsp, rax, registers, possible relevant objects, netscriptframework, .net script
---
- EXCEPTION_ACCESS_VIOLATION : lecture/écriture d'une adresse invalide (pointeur nul ou corrompu) ; cas le plus fréquent. EXCEPTION_STACK_OVERFLOW : récursion infinie (souvent script ou animation). EXCEPTION_INT_DIVIDE_BY_ZERO : division par zéro dans un plugin.
- « PROBABLE CALL STACK » : lire de haut en bas ; ignorer les modules système (ntdll, kernel32, KERNELBASE) ; le premier module tiers est le premier suspect, SkyrimSE.exe+offset seul nécessite la résolution Address Library.
- « POSSIBLE RELEVANT OBJECTS » liste des formes/objets rencontrés (NIF, TESObject*, plugins) : très utile pour identifier le mod fautif (asset ou record).
- « Registers » (RAX/RCX…) pointant vers 0 indique un pointeur nul ; vers des objets valides indique plutôt un asset.
- Si l'AV a lieu dans une DLL Crash Logger elle-même, c'est souvent un symptôme d'un autre plugin.
- Toujours citer les lignes précises du log comme preuves et préciser quand une conclusion est incertaine.
