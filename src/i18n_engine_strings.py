"""Traductions du moteur d'audit et de la compatibilité : {français: (en, it, es)}."""

TR = {
    " (handle {h})": (" (handle {h})", " (handle {h})", " (handle {h})"),
    " (le plus récent)": (" (most recent)", " (il più recente)", " (el más reciente)"),
    "# Audit — verdict : {verdict}": ("# Audit — verdict: {verdict}", "# Audit — verdetto: {verdict}", "# Auditoría — veredicto: {verdict}"),
    "## Constats": ("## Findings", "## Risultati", "## Hallazgos"),
    "## Extraits de logs": ("## Log excerpts", "## Estratti dei log", "## Fragmentos de logs"),
    "## Suspects classés": ("## Ranked suspects", "## Sospetti in classifica", "## Sospechosos clasificados"),
    "(aucune erreur de chargement)": ("(no loading error)", "(nessun errore di caricamento)", "(sin errores de carga)"),
    "(aucune erreur)": ("(no error)", "(nessun errore)", "(sin errores)"),
    ", en train de s'enregistrer auprès de {related}": (
        ", while registering with {related}", ", mentre si registrava presso {related}",
        ", mientras se registraba con {related}"),
    "Address Library introuvable ({al})": (
        "Address Library not found ({al})", "Address Library non trovata ({al})", "Address Library no encontrada ({al})"),
    "Aligner les versions : exécutable du jeu, SKSE, Address Library et plugins SKSE (AE vs SE vs 1.5.97).": (
        "Align the versions: game executable, SKSE, Address Library and SKSE plugins (AE vs SE vs 1.5.97).",
        "Allinea le versioni: eseguibile del gioco, SKSE, Address Library e plugin SKSE (AE vs SE vs 1.5.97).",
        "Alinea las versiones: ejecutable del juego, SKSE, Address Library y plugins SKSE (AE vs SE vs 1.5.97)."),
    "Allocateur mémoire (tbbmalloc) présent dans le STACK": (
        "Memory allocator (tbbmalloc) present in the STACK", "Allocatore di memoria (tbbmalloc) presente nello STACK",
        "Asignador de memoria (tbbmalloc) presente en el STACK"),
    "Analyser le module fautif et la pile d'appels ci-dessous.": (
        "Analyze the faulty module and the call stack below.", "Analizza il modulo difettoso e lo stack delle chiamate qui sotto.",
        "Analiza el módulo defectuoso y la pila de llamadas de abajo."),
    "Animation, behavior ou physique Havok": ("Animation, behavior or Havok physics", "Animazione, behavior o fisica Havok", "Animación, behavior o física Havok"),
    "Archive BSA problématique": ("Problematic BSA archive", "Archivio BSA problematico", "Archivo BSA problemático"),
    "Au-delà, les formIDs se corrompent ou le jeu plante.": (
        "Beyond that, formIDs get corrupted or the game crashes.", "Oltre questo limite, i formID si corrompono o il gioco si blocca.",
        "Más allá, los formIDs se corrompen o el juego se cierra."),
    "Avant la v7, EngineFixes.toml doit contenir SaveGameMaxSize = true et MaxStdio = 8192 ; les DLL de la partie 2 (tbbmalloc.dll...) doivent être à la racine du jeu.": (
        "Before v7, EngineFixes.toml must contain SaveGameMaxSize = true and MaxStdio = 8192; the Part 2 DLLs (tbbmalloc.dll...) must be in the game root.",
        "Prima della v7, EngineFixes.toml deve contenere SaveGameMaxSize = true e MaxStdio = 8192; le DLL della parte 2 (tbbmalloc.dll...) devono trovarsi nella radice del gioco.",
        "Antes de la v7, EngineFixes.toml debe contener SaveGameMaxSize = true y MaxStdio = 8192; las DLL de la parte 2 (tbbmalloc.dll...) deben estar en la raíz del juego."),
    "Avec ENB/ReShade, vérifier que d3d11 est en override « native, builtin » ; en cas de crash graphique, tester le backend DXVK de la bouteille (un changement à la fois).": (
        "With ENB/ReShade, check that d3d11 is overridden as “native, builtin”; on a graphics crash, try the bottle's DXVK backend (one change at a time).",
        "Con ENB/ReShade, verifica che d3d11 sia in override «native, builtin»; in caso di crash grafico, prova il backend DXVK della bottiglia (una modifica alla volta).",
        "Con ENB/ReShade, comprueba que d3d11 esté en override «native, builtin»; ante un crash gráfico, prueba el backend DXVK de la botella (un cambio cada vez)."),
    "Comparer plusieurs crash logs ; vérifier l'environnement avant d'accuser un mod.": (
        "Compare several crash logs; check the environment before blaming a mod.",
        "Confronta più crash log; verifica l'ambiente prima di accusare una mod.",
        "Compara varios crash logs; revisa el entorno antes de culpar a un mod."),
    "Composants notables chargés : {list}": (
        "Notable components loaded: {list}", "Componenti rilevanti caricati: {list}", "Componentes relevantes cargados: {list}"),
    "Configuration enregistrée par Crash Logger": (
        "Configuration recorded by Crash Logger", "Configurazione registrata da Crash Logger", "Configuración registrada por Crash Logger"),
    "Conflit de mods modifiant la même cellule : vérifier avec xEdit et un patch de compatibilité, éviter le fast-travel dans la zone concernée.": (
        "Mod conflict editing the same cell: check with xEdit and a compatibility patch, avoid fast-travel in the affected area.",
        "Conflitto tra mod che modificano la stessa cella: verifica con xEdit e una patch di compatibilità, evita il fast travel nella zona interessata.",
        "Conflicto de mods que modifican la misma celda: comprueba con xEdit y un parche de compatibilidad, evita el viaje rápido en la zona afectada."),
    "Consulter ce log et la page du mod ; mettre à jour ou retirer le plugin.": (
        "Read this log and the mod page; update or remove the plugin.",
        "Consulta questo log e la pagina della mod; aggiorna o rimuovi il plugin.",
        "Consulta este log y la página del mod; actualiza o quita el plugin."),
    "Contenu Creation Club manquant ou incomplet": (
        "Creation Club content missing or incomplete", "Contenuto Creation Club mancante o incompleto",
        "Contenido de Creation Club ausente o incompleto"),
    "Crash dans le moteur sans DLL tierce visible": (
        "Crash in the engine with no visible third-party DLL", "Crash nel motore senza DLL di terze parti visibili",
        "Crash en el motor sin DLL de terceros visible"),
    "Crash détecté : {exc}{tag}": ("Crash detected: {exc}{tag}", "Crash rilevato: {exc}{tag}", "Crash detectado: {exc}{tag}"),
    "DLSS exige un GPU NVIDIA RTX et Windows natif : ces DLL échouent à s'initialiser sous Wine.": (
        "DLSS requires an NVIDIA RTX GPU and native Windows: these DLLs fail to initialize under Wine.",
        "DLSS richiede una GPU NVIDIA RTX e Windows nativo: queste DLL non si inizializzano sotto Wine.",
        "DLSS requiere una GPU NVIDIA RTX y Windows nativo: estas DLL no se inicializan bajo Wine."),
    "DLSS/Streamline chargés alors qu'ils sont indisponibles sous CrossOver": (
        "DLSS/Streamline loaded although unavailable under CrossOver", "DLSS/Streamline caricati pur non essendo disponibili sotto CrossOver",
        "DLSS/Streamline cargados aunque no están disponibles bajo CrossOver"),
    "DLSS/Streamline indisponible (normal sous CrossOver/Wine ou sans GPU NVIDIA RTX) : désactiver DLSS/Frame Generation dans ENB.": (
        "DLSS/Streamline unavailable (normal under CrossOver/Wine or without an NVIDIA RTX GPU): disable DLSS/Frame Generation in ENB.",
        "DLSS/Streamline non disponibile (normale sotto CrossOver/Wine o senza GPU NVIDIA RTX): disattiva DLSS/Frame Generation in ENB.",
        "DLSS/Streamline no disponible (normal bajo CrossOver/Wine o sin GPU NVIDIA RTX): desactiva DLSS/Frame Generation en ENB."),
    "DirectX 11/12 est traduit vers Metal par la couche d'Apple intégrée à CrossOver.": (
        "DirectX 11/12 is translated to Metal by Apple's layer built into CrossOver.",
        "DirectX 11/12 viene tradotto in Metal dal livello di Apple integrato in CrossOver.",
        "DirectX 11/12 se traduce a Metal mediante la capa de Apple integrada en CrossOver."),
    "DirectX est traduit vers Vulkan puis Metal, plus sensible à la pression mémoire.": (
        "DirectX is translated to Vulkan then Metal, more sensitive to memory pressure.",
        "DirectX viene tradotto in Vulkan e poi Metal, più sensibile alla pressione sulla memoria.",
        "DirectX se traduce a Vulkan y luego a Metal, más sensible a la presión de memoria."),
    "Désactiver DLSS/Frame Generation dans ENB, ou retirer sl.*.dll et nvngx.dll de la bouteille.": (
        "Disable DLSS/Frame Generation in ENB, or remove sl.*.dll and nvngx.dll from the bottle.",
        "Disattiva DLSS/Frame Generation in ENB, oppure rimuovi sl.*.dll e nvngx.dll dalla bottiglia.",
        "Desactiva DLSS/Frame Generation en ENB, o quita sl.*.dll y nvngx.dll de la botella."),
    "Désactiver ENB/ReShade/DXVK-D3DMetal en test, vérifier la couche de compatibilité (Wine/CrossOver/GPTK), baisser les réglages graphiques et les effets de particules.": (
        "Disable ENB/ReShade/DXVK-D3DMetal as a test, check the compatibility layer (Wine/CrossOver/GPTK), lower graphics settings and particle effects.",
        "Disattiva ENB/ReShade/DXVK-D3DMetal per prova, verifica il livello di compatibilità (Wine/CrossOver/GPTK), abbassa le impostazioni grafiche e gli effetti particellari.",
        "Desactiva ENB/ReShade/DXVK-D3DMetal como prueba, revisa la capa de compatibilidad (Wine/CrossOver/GPTK), baja los ajustes gráficos y los efectos de partículas."),
    "Désactiver ce plugin (et son dépendant) ; vérifier sa version vis-à-vis du jeu/SKSE et ses prérequis (ex. mod UI installé ?).": (
        "Disable this plugin (and its dependent); check its version against the game/SKSE and its prerequisites (e.g. UI mod installed?).",
        "Disattiva questo plugin (e il suo dipendente); verifica la sua versione rispetto a gioco/SKSE e i prerequisiti (es. mod UI installata?).",
        "Desactiva este plugin (y su dependiente); comprueba su versión respecto al juego/SKSE y sus requisitos (¿mod de UI instalado?)."),
    "Désactiver ces plugins un par un (ou dichotomie) pour confirmer.": (
        "Disable these plugins one by one (or by bisection) to confirm.", "Disattiva questi plugin uno alla volta (o per bisezione) per confermare.",
        "Desactiva estos plugins uno a uno (o por bisección) para confirmar."),
    "Désactiver les mods de PNJ/apparence/IA récents ; tester dans une zone sans PNJ.": (
        "Disable recent NPC/appearance/AI mods; test in an area without NPCs.",
        "Disattiva le mod recenti di PNG/aspetto/IA; prova in una zona senza PNG.",
        "Desactiva los mods recientes de PNJ/apariencia/IA; prueba en una zona sin PNJ."),
    "ENB/proxy d3d11": ("ENB/d3d11 proxy", "ENB/proxy d3d11", "ENB/proxy d3d11"),
    "En cas de crash graphique, comparer avec D3DMetal ou DXVK.": (
        "On a graphics crash, compare with D3DMetal or DXVK.", "In caso di crash grafico, confronta con D3DMetal o DXVK.",
        "Ante un crash gráfico, compara con D3DMetal o DXVK."),
    "En cas de crash graphique, tester le backend D3DMetal de la bouteille et réduire les textures.": (
        "On a graphics crash, try the bottle's D3DMetal backend and reduce textures.",
        "In caso di crash grafico, prova il backend D3DMetal della bottiglia e riduci le texture.",
        "Ante un crash gráfico, prueba el backend D3DMetal de la botella y reduce las texturas."),
    "Erreur critique dans le log de {stem}": ("Critical error in the {stem} log", "Errore critico nel log di {stem}", "Error crítico en el log de {stem}"),
    "Exception SKSE au chargement des plugins (suspect : {name})": (
        "SKSE exception while loading plugins (suspect: {name})", "Eccezione SKSE durante il caricamento dei plugin (sospetto: {name})",
        "Excepción de SKSE al cargar los plugins (sospechoso: {name})"),
    "Exécution via une couche de compatibilité (CrossOver/Wine/GPTK)": (
        "Running through a compatibility layer (CrossOver/Wine/GPTK)", "Esecuzione tramite un livello di compatibilità (CrossOver/Wine/GPTK)",
        "Ejecución mediante una capa de compatibilidad (CrossOver/Wine/GPTK)"),
    "Fichier {f} — {kb} Ko, modifié le {d}": (
        "File {f} — {kb} KB, modified {d}", "File {f} — {kb} KB, modificato il {d}", "Archivo {f} — {kb} KB, modificado el {d}"),
    "Fichier {src}": ("File {src}", "File {src}", "Archivo {src}"),
    "Flaguer ESL les plugins éligibles (xEdit) ou retirer des mods.": (
        "Flag eligible plugins as ESL (xEdit) or remove mods.", "Imposta il flag ESL sui plugin idonei (xEdit) o rimuovi delle mod.",
        "Marca como ESL los plugins elegibles (xEdit) o quita mods."),
    "Fonctions natives Papyrus non liées": ("Unbound Papyrus native functions", "Funzioni native Papyrus non collegate", "Funciones nativas de Papyrus sin enlazar"),
    "Fréquent sous Wine/Rosetta ou lors d'un crash dans du code généré ; l'analyse repose sur la section STACK brute.": (
        "Common under Wine/Rosetta or when crashing in generated code; the analysis relies on the raw STACK section.",
        "Frequente sotto Wine/Rosetta o in caso di crash in codice generato; l'analisi si basa sulla sezione STACK grezza.",
        "Frecuente bajo Wine/Rosetta o al fallar en código generado; el análisis se basa en la sección STACK en bruto."),
    "Identifier le dernier équipement/PNJ chargé ; vérifier les mods de corps (CBBE/BHUNP), armures et FaceGen ; relancer la génération FaceGen/BodySlide.": (
        "Identify the last equipment/NPC loaded; check body mods (CBBE/BHUNP), armors and FaceGen; re-run FaceGen/BodySlide generation.",
        "Individua l'ultimo equipaggiamento/PNG caricato; verifica le mod del corpo (CBBE/BHUNP), le armature e FaceGen; rilancia la generazione FaceGen/BodySlide.",
        "Identifica el último equipo/PNJ cargado; revisa los mods de cuerpo (CBBE/BHUNP), armaduras y FaceGen; vuelve a generar FaceGen/BodySlide."),
    "Incompatibilité de version (jeu / SKSE / Address Library)": (
        "Version mismatch (game / SKSE / Address Library)", "Incompatibilità di versione (gioco / SKSE / Address Library)",
        "Incompatibilidad de versión (juego / SKSE / Address Library)"),
    "Installer l'Address Library correspondant à cette version du jeu (SE : « All in one 1.5.97 »).": (
        "Install the Address Library matching this game version (SE: “All in one 1.5.97”).",
        "Installa l'Address Library corrispondente a questa versione del gioco (SE: «All in one 1.5.97»).",
        "Instala la Address Library que corresponda a esta versión del juego (SE: «All in one 1.5.97»)."),
    "Installer la build SKSE correspondant exactement au jeu (SE 1.5.97 ou AE 1.6.x).": (
        "Install the SKSE build matching the game exactly (SE 1.5.97 or AE 1.6.x).",
        "Installa la build SKSE che corrisponde esattamente al gioco (SE 1.5.97 o AE 1.6.x).",
        "Instala la build de SKSE que coincida exactamente con el juego (SE 1.5.97 o AE 1.6.x)."),
    "Jeu {gv} / SKSE compilé pour {sv}.": ("Game {gv} / SKSE built for {sv}.", "Gioco {gv} / SKSE compilato per {sv}.", "Juego {gv} / SKSE compilado para {sv}."),
    "Le GPU partage la RAM du Mac ({vram} Go annoncés pour {ram} Go de RAM) : seule la RAM compte.": (
        "The GPU shares the Mac's RAM ({vram} GB reported for {ram} GB of RAM): only the RAM matters.",
        "La GPU condivide la RAM del Mac ({vram} GB dichiarati per {ram} GB di RAM): conta solo la RAM.",
        "La GPU comparte la RAM del Mac ({vram} GB anunciados para {ram} GB de RAM): solo cuenta la RAM."),
    "Le jeu tourne en émulation sur Apple Silicon : accès mémoire et timings atypiques possibles.": (
        "The game runs under emulation on Apple Silicon: atypical memory accesses and timings are possible.",
        "Il gioco gira in emulazione su Apple Silicon: possibili accessi alla memoria e tempi atipici.",
        "El juego se ejecuta emulado en Apple Silicon: son posibles accesos a memoria y tiempos atípicos."),
    "Le script n'existe pas ou n'est pas chargé : mod incomplet, master manquant ou ancien save.": (
        "The script does not exist or is not loaded: incomplete mod, missing master or old save.",
        "Lo script non esiste o non è caricato: mod incompleta, master mancante o vecchio salvataggio.",
        "El script no existe o no está cargado: mod incompleto, master ausente o partida antigua."),
    "Les plugins SKSE modernes en dépendent : sans elle, ils ne se chargent pas ou plantent.": (
        "Modern SKSE plugins depend on it: without it, they fail to load or crash.",
        "I plugin SKSE moderni ne dipendono: senza di essa non si caricano o vanno in crash.",
        "Los plugins SKSE modernos dependen de ella: sin ella no se cargan o fallan."),
    "Log ancien (jeu lancé avant l'ajout ?) ou DLL ignorées par SKSE.": (
        "Old log (game launched before the addition?) or DLLs ignored by SKSE.",
        "Log vecchio (gioco avviato prima dell'aggiunta?) o DLL ignorate da SKSE.",
        "Log antiguo (¿juego iniciado antes de añadirlo?) o DLL ignoradas por SKSE."),
    "Mesh/NIF défectueux ou incompatible (corps, armure, visage)": (
        "Defective or incompatible mesh/NIF (body, armor, face)", "Mesh/NIF difettoso o incompatibile (corpo, armatura, viso)",
        "Mesh/NIF defectuoso o incompatible (cuerpo, armadura, rostro)"),
    "Messages d'échec dans le log de {stem}": ("Failure messages in the {stem} log", "Messaggi di errore nel log di {stem}", "Mensajes de fallo en el log de {stem}"),
    "Mettre à jour la DLL pour la version du jeu, installer l'Address Library correspondante, ou la retirer.": (
        "Update the DLL for the game version, install the matching Address Library, or remove it.",
        "Aggiorna la DLL per la versione del gioco, installa l'Address Library corrispondente, oppure rimuovila.",
        "Actualiza la DLL a la versión del juego, instala la Address Library correspondiente, o quítala."),
    "Mettre à jour le plugin pour la version du jeu/SKSE, ou le retirer.": (
        "Update the plugin for the game/SKSE version, or remove it.", "Aggiorna il plugin per la versione di gioco/SKSE, oppure rimuovilo.",
        "Actualiza el plugin a la versión del juego/SKSE, o quítalo."),
    "Moteur de script (Papyrus) impliqué": ("Script engine (Papyrus) involved", "Motore di script (Papyrus) coinvolto", "Motor de scripts (Papyrus) implicado"),
    "Moteur graphique sous Wine : D3DMetal (GPTK)": ("Graphics engine under Wine: D3DMetal (GPTK)", "Motore grafico sotto Wine: D3DMetal (GPTK)", "Motor gráfico bajo Wine: D3DMetal (GPTK)"),
    "Moteur graphique sous Wine : DXMT": ("Graphics engine under Wine: DXMT", "Motore grafico sotto Wine: DXMT", "Motor gráfico bajo Wine: DXMT"),
    "Moteur graphique sous Wine : DXVK / MoltenVK": ("Graphics engine under Wine: DXVK / MoltenVK", "Motore grafico sotto Wine: DXVK / MoltenVK", "Motor gráfico bajo Wine: DXVK / MoltenVK"),
    "Mémoire unifiée : la « VRAM » annoncée n'est pas dédiée": (
        "Unified memory: the reported “VRAM” is not dedicated", "Memoria unificata: la «VRAM» dichiarata non è dedicata",
        "Memoria unificada: la «VRAM» anunciada no es dedicada"),
    "Navmesh / cellule / pathfinding": ("Navmesh / cell / pathfinding", "Navmesh / cella / pathfinding", "Navmesh / celda / pathfinding"),
    "Pile d'appels vide : Crash Logger n'a pas pu la reconstruire": (
        "Empty call stack: Crash Logger could not rebuild it", "Stack delle chiamate vuoto: Crash Logger non è riuscito a ricostruirlo",
        "Pila de llamadas vacía: Crash Logger no pudo reconstruirla"),
    "Piles d'appels vides, adresses atypiques et échecs DLSS/Streamline sont fréquents dans ce contexte : ne pas les imputer à un mod sans autre preuve.": (
        "Empty call stacks, atypical addresses and DLSS/Streamline failures are common in this context: do not blame a mod without other evidence.",
        "Stack vuoti, indirizzi atipici e errori DLSS/Streamline sono frequenti in questo contesto: non attribuirli a una mod senza altre prove.",
        "Las pilas vacías, las direcciones atípicas y los fallos de DLSS/Streamline son frecuentes en este contexto: no los atribuyas a un mod sin otra prueba."),
    "Plugin SKSE en échec : {dll}": ("SKSE plugin failed: {dll}", "Plugin SKSE in errore: {dll}", "Plugin SKSE con error: {dll}"),
    "Plugin SKSE vérifié mais non chargé : {dll}": (
        "SKSE plugin checked but not loaded: {dll}", "Plugin SKSE verificato ma non caricato: {dll}", "Plugin SKSE verificado pero no cargado: {dll}"),
    "Plugins cités dans le crash log": ("Plugins cited in the crash log", "Plugin citati nel crash log", "Plugins citados en el crash log"),
    "Problème de rendu / shader / pilote graphique": ("Rendering / shader / graphics driver problem", "Problema di rendering / shader / driver grafico", "Problema de renderizado / shader / controlador gráfico"),
    "Processeur x86-64 émulé (Rosetta 2)": ("Emulated x86-64 processor (Rosetta 2)", "Processore x86-64 emulato (Rosetta 2)", "Procesador x86-64 emulado (Rosetta 2)"),
    "Provient de SSE Engine Fixes ; à rapprocher de la pression mémoire.": (
        "Comes from SSE Engine Fixes; relate it to memory pressure.", "Proviene da SSE Engine Fixes; da collegare alla pressione sulla memoria.",
        "Proviene de SSE Engine Fixes; relaciónalo con la presión de memoria."),
    "Regarder les objets/formulaires cités et les catégories signalées.": (
        "Look at the cited objects/forms and the flagged categories.", "Guarda gli oggetti/form citati e le categorie segnalate.",
        "Revisa los objetos/formularios citados y las categorías señaladas."),
    "Relancer Nemesis/Pandora/FNIS, désactiver les mods d'animation récents ou de physique (CBPC, HDT-SMP) pour isoler.": (
        "Re-run Nemesis/Pandora/FNIS, disable recent animation or physics mods (CBPC, HDT-SMP) to isolate.",
        "Rilancia Nemesis/Pandora/FNIS, disattiva le mod di animazione o fisica recenti (CBPC, HDT-SMP) per isolare.",
        "Vuelve a ejecutar Nemesis/Pandora/FNIS, desactiva los mods recientes de animación o física (CBPC, HDT-SMP) para aislar."),
    "Repérer le script le plus bavard ci-dessous ; désactiver le mod ou nettoyer la sauvegarde.": (
        "Spot the chattiest script below; disable the mod or clean the save.", "Individua lo script più prolisso qui sotto; disattiva la mod o pulisci il salvataggio.",
        "Localiza el script más charlatán de abajo; desactiva el mod o limpia la partida."),
    "Réduire les textures 2K/4K, désactiver les mods gourmands (ENB, grands overhauls), installer un patch mémoire (SSE Engine Fixes / Part 2).": (
        "Reduce 2K/4K textures, disable heavy mods (ENB, big overhauls), install a memory patch (SSE Engine Fixes / Part 2).",
        "Riduci le texture 2K/4K, disattiva le mod pesanti (ENB, grandi overhaul), installa una patch per la memoria (SSE Engine Fixes / Part 2).",
        "Reduce las texturas 2K/4K, desactiva los mods pesados (ENB, grandes overhauls), instala un parche de memoria (SSE Engine Fixes / Part 2)."),
    "Réduire textures/mods gourmands, fermer les applications, pagefile.": (
        "Reduce textures/heavy mods, close applications, pagefile.", "Riduci texture/mod pesanti, chiudi le applicazioni, pagefile.",
        "Reduce texturas/mods pesados, cierra aplicaciones, pagefile."),
    "Réinstaller le mod ou nettoyer la sauvegarde (ReSaver).": (
        "Reinstall the mod or clean the save (ReSaver).", "Reinstalla la mod o pulisci il salvataggio (ReSaver).", "Reinstala el mod o limpia la partida (ReSaver)."),
    "Résoudre ces offsets via Address Library (même version de jeu) pour identifier la fonction du moteur concernée.": (
        "Resolve these offsets through Address Library (same game version) to identify the engine function involved.",
        "Risolvi questi offset tramite Address Library (stessa versione del gioco) per identificare la funzione del motore coinvolta.",
        "Resuelve estos offsets con Address Library (misma versión del juego) para identificar la función del motor implicada."),
    "SKSE a examiné ce fichier sans le valider : version du jeu/SKSE incompatible, Address Library absente, DLL corrompue ou dépendance manquante. Il a pu aussi faire planter le chargement.": (
        "SKSE examined this file without accepting it: incompatible game/SKSE version, missing Address Library, corrupt DLL or missing dependency. It may also have crashed the loading.",
        "SKSE ha esaminato questo file senza convalidarlo: versione gioco/SKSE incompatibile, Address Library assente, DLL corrotta o dipendenza mancante. Potrebbe anche aver causato il crash del caricamento.",
        "SKSE examinó este archivo sin validarlo: versión de juego/SKSE incompatible, Address Library ausente, DLL corrupta o dependencia faltante. También pudo provocar el fallo de la carga."),
    "SKSE {v} — runtime {rt}": ("SKSE {v} — runtime {rt}", "SKSE {v} — runtime {rt}", "SKSE {v} — runtime {rt}"),
    "SSE Engine Fixes v{v} (ancienne branche, avant v7)": (
        "SSE Engine Fixes v{v} (old branch, before v7)", "SSE Engine Fixes v{v} (vecchio ramo, prima della v7)", "SSE Engine Fixes v{v} (rama antigua, antes de la v7)"),
    "STACK : fonctions du moteur (SkyrimSE.exe) les plus citées": (
        "STACK: most cited engine functions (SkyrimSE.exe)", "STACK: funzioni del motore (SkyrimSE.exe) più citate",
        "STACK: funciones del motor (SkyrimSE.exe) más citadas"),
    "Scripts introuvables (mod retiré en cours de partie ou fichiers manquants)": (
        "Scripts not found (mod removed mid-playthrough or missing files)", "Script non trovati (mod rimossa a partita in corso o file mancanti)",
        "Scripts no encontrados (mod quitado durante la partida o archivos ausentes)"),
    "Scripts non liés à leur quest/objet": ("Scripts not bound to their quest/object", "Script non collegati alla loro quest/oggetto", "Scripts no enlazados a su misión/objeto"),
    "Scripts surchargés ou mods retirés en cours de partie : consulter Papyrus.0.log, nettoyer la sauvegarde (ReSaver).": (
        "Overloaded scripts or mods removed mid-playthrough: check Papyrus.0.log, clean the save (ReSaver).",
        "Script sovraccarichi o mod rimosse a partita in corso: consulta Papyrus.0.log, pulisci il salvataggio (ReSaver).",
        "Scripts sobrecargados o mods quitados durante la partida: consulta Papyrus.0.log, limpia la partida (ReSaver)."),
    "Surcharge Papyrus (piles de scripts en vidange)": ("Papyrus overload (script stacks being dumped)", "Sovraccarico Papyrus (stack di script in svuotamento)", "Sobrecarga de Papyrus (pilas de scripts volcándose)"),
    "Surveiller la pression mémoire de macOS ; fermer les applications gourmandes.": (
        "Monitor macOS memory pressure; close heavy applications.", "Monitora la pressione sulla memoria di macOS; chiudi le applicazioni pesanti.",
        "Vigila la presión de memoria de macOS; cierra las aplicaciones pesadas."),
    "Suspect présent dans l'installation : {f}": (
        "Suspect present in the installation: {f}", "Sospetto presente nell'installazione: {f}", "Sospechoso presente en la instalación: {f}"),
    "Tester sans ENB/DLSS pour isoler un problème de rendu.": (
        "Test without ENB/DLSS to isolate a rendering problem.", "Prova senza ENB/DLSS per isolare un problema di rendering.",
        "Prueba sin ENB/DLSS para aislar un problema de renderizado."),
    "Tester sans ENB/DLSS, essayer D3DMetal vs DXVK, mettre à jour CrossOver, surveiller la mémoire unifiée.": (
        "Test without ENB/DLSS, try D3DMetal vs DXVK, update CrossOver, monitor unified memory.",
        "Prova senza ENB/DLSS, confronta D3DMetal e DXVK, aggiorna CrossOver, monitora la memoria unificata.",
        "Prueba sin ENB/DLSS, compara D3DMetal y DXVK, actualiza CrossOver, vigila la memoria unificada."),
    "Texture ou ressource corrompue / format non supporté": (
        "Corrupt texture or resource / unsupported format", "Texture o risorsa corrotta / formato non supportato", "Textura o recurso corrupto / formato no compatible"),
    "Tous les plugins SKSE se sont chargés": ("All SKSE plugins loaded", "Tutti i plugin SKSE sono stati caricati", "Todos los plugins SKSE se cargaron"),
    "Traduction DirectX vers Metal récente, encore peu éprouvée avec ENB.": (
        "Recent DirectX-to-Metal translation, still little proven with ENB.", "Traduzione DirectX verso Metal recente, ancora poco collaudata con ENB.",
        "Traducción de DirectX a Metal reciente, aún poco probada con ENB."),
    "Typique d'un asset défectueux (mesh, texture, navmesh, script) ou d'un conflit de données plutôt que d'un plugin SKSE.": (
        "Typical of a defective asset (mesh, texture, navmesh, script) or a data conflict rather than an SKSE plugin.",
        "Tipico di un asset difettoso (mesh, texture, navmesh, script) o di un conflitto di dati piuttosto che di un plugin SKSE.",
        "Típico de un asset defectuoso (mesh, textura, navmesh, script) o de un conflicto de datos más que de un plugin SKSE."),
    "Typiquement un plugin SKSE absent/incompatible ou des .pex d'un mod qui attendent une fonction native qui n'existe pas dans cette version.": (
        "Typically a missing/incompatible SKSE plugin or a mod's .pex files expecting a native function that does not exist in this version.",
        "Tipicamente un plugin SKSE assente/incompatibile o dei .pex di una mod che attendono una funzione nativa inesistente in questa versione.",
        "Normalmente un plugin SKSE ausente/incompatible o .pex de un mod que esperan una función nativa que no existe en esta versión."),
    "Télécharger/réinstaller le contenu Creation Club via le jeu (Créations) ou retirer les mods qui le requièrent ; ne pas utiliser le menu Créations avec MO2/Vortex.": (
        "Download/reinstall the Creation Club content through the game (Creations) or remove the mods requiring it; do not use the Creations menu with MO2/Vortex.",
        "Scarica/reinstalla il contenuto Creation Club dal gioco (Creazioni) o rimuovi le mod che lo richiedono; non usare il menu Creazioni con MO2/Vortex.",
        "Descarga/reinstala el contenido de Creation Club desde el juego (Creaciones) o quita los mods que lo requieren; no uses el menú Creaciones con MO2/Vortex."),
    "Un acteur / PNJ est impliqué": ("An actor / NPC is involved", "Un attore / PNG è coinvolto", "Un actor / PNJ está implicado"),
    "Un plugin a levé une exception pendant la phase de chargement/PostLoad. Dernier plugin actif : {name}": (
        "A plugin raised an exception during the load/PostLoad phase. Last active plugin: {name}",
        "Un plugin ha sollevato un'eccezione durante la fase di caricamento/PostLoad. Ultimo plugin attivo: {name}",
        "Un plugin lanzó una excepción durante la fase de carga/PostLoad. Último plugin activo: {name}"),
    "Un script très bavard est un suspect fréquent de lenteurs/instabilité.": (
        "A very chatty script is a frequent suspect for slowdowns/instability.", "Uno script molto prolisso è un sospetto frequente di rallentamenti/instabilità.",
        "Un script muy charlatán es un sospechoso frecuente de lentitud/inestabilidad."),
    "Version de SkyrimSE.exe illisible": ("SkyrimSE.exe version unreadable", "Versione di SkyrimSE.exe illeggibile", "Versión de SkyrimSE.exe ilegible"),
    "Version du jeu différente du runtime SKSE du log": (
        "Game version differs from the SKSE runtime in the log", "Versione del gioco diversa dal runtime SKSE del log",
        "Versión del juego distinta del runtime SKSE del log"),
    "Vérifier ces réglages ou passer à la v7 recommandée par la communauté.": (
        "Check these settings or move to v7 recommended by the community.", "Verifica queste impostazioni o passa alla v7 consigliata dalla community.",
        "Revisa estos ajustes o pasa a la v7 recomendada por la comunidad."),
    "Vérifier l'ordre de chargement et l'intégrité des BSA ; limite d'archives atteinte ?": (
        "Check the load order and BSA integrity; archive limit reached?", "Verifica l'ordine di caricamento e l'integrità dei BSA; limite di archivi raggiunto?",
        "Revisa el orden de carga y la integridad de los BSA; ¿límite de archivos alcanzado?"),
    "Vérifier les textures récentes (format BC7/BC1, mipmaps), réinstaller le mod incriminé.": (
        "Check recent textures (BC7/BC1 format, mipmaps), reinstall the offending mod.",
        "Verifica le texture recenti (formato BC7/BC1, mipmap), reinstalla la mod incriminata.",
        "Revisa las texturas recientes (formato BC7/BC1, mipmaps), reinstala el mod sospechoso."),
    "[creation club] contenu manquant": ("[creation club] missing content", "[creation club] contenuto mancante", "[creation club] contenido ausente"),
    "[graphique]": ("[graphics]", "[grafica]", "[gráficos]"),
    "[mémoire]": ("[memory]", "[memoria]", "[memoria]"),
    "[plateforme] CrossOver/Wine": ("[platform] CrossOver/Wine", "[piattaforma] CrossOver/Wine", "[plataforma] CrossOver/Wine"),
    "[plugins] limite 254 dépassée": ("[plugins] 254 limit exceeded", "[plugins] limite di 254 superato", "[plugins] límite de 254 superado"),
    "[script] fonctions natives non liées": ("[script] unbound native functions", "[script] funzioni native non collegate", "[script] funciones nativas sin enlazar"),
    "[script] surcharge Papyrus": ("[script] Papyrus overload", "[script] sovraccarico Papyrus", "[script] sobrecarga de Papyrus"),
    "[version] Address Library absente": ("[version] Address Library missing", "[version] Address Library assente", "[version] Address Library ausente"),
    "[version] jeu/SKSE incohérents": ("[version] game/SKSE mismatch", "[version] gioco/SKSE incoerenti", "[version] juego/SKSE incoherentes"),
    "affichage, VSync, framerate": ("display, VSync, framerate", "schermo, VSync, framerate", "pantalla, VSync, framerate"),
    "aide ENB (profondeur, météo)": ("ENB helper (depth, weather)", "supporto ENB (profondità, meteo)", "ayuda de ENB (profundidad, clima)"),
    "allocateur tbbmalloc dans le STACK ({src})": ("tbbmalloc allocator in the STACK ({src})", "allocatore tbbmalloc nello STACK ({src})", "asignador tbbmalloc en el STACK ({src})"),
    "aucun crash log trouvé": ("no crash log found", "nessun crash log trovato", "ningún crash log encontrado"),
    "barres de vie et HUD (API pour d'autres mods)": ("health bars and HUD (API for other mods)", "barre della salute e HUD (API per altre mod)", "barras de vida y HUD (API para otros mods)"),
    "caméra à la 3e personne": ("third-person camera", "telecamera in terza persona", "cámara en tercera persona"),
    "cité {n}× dans {src}": ("cited {n}× in {src}", "citato {n}× in {src}", "citado {n}× en {src}"),
    "composants chargés ({src})": ("components loaded ({src})", "componenti caricati ({src})", "componentes cargados ({src})"),
    "correctifs et ajustements divers": ("assorted fixes and tweaks", "correzioni e modifiche varie", "correcciones y ajustes varios"),
    "correctifs moteur et allocateur mémoire (framework)": ("engine fixes and memory allocator (framework)", "correzioni del motore e allocatore di memoria (framework)", "correcciones del motor y asignador de memoria (framework)"),
    "couche de compatibilité détectée ({src})": ("compatibility layer detected ({src})", "livello di compatibilità rilevato ({src})", "capa de compatibilidad detectada ({src})"),
    "crash détecté, source indéterminée": ("crash detected, source undetermined", "crash rilevato, origine indeterminata", "crash detectado, origen indeterminado"),
    "distribution de mots-clés (framework)": ("keyword distribution (framework)", "distribuzione di parole chiave (framework)", "distribución de palabras clave (framework)"),
    "distribution de sorts/perks/objets (framework)": ("spell/perk/item distribution (framework)", "distribuzione di incantesimi/vantaggi/oggetti (framework)", "distribución de hechizos/ventajas/objetos (framework)"),
    "déplacements et verrouillage de cible": ("movement and target lock", "movimenti e blocco del bersaglio", "movimiento y fijación de objetivo"),
    "exception SKSE au chargement ({src})": ("SKSE exception on load ({src})", "eccezione SKSE al caricamento ({src})", "excepción de SKSE al cargar ({src})"),
    "exception inconnue": ("unknown exception", "eccezione sconosciuta", "excepción desconocida"),
    "fonction native non liée : {k}": ("unbound native function: {k}", "funzione nativa non collegata: {k}", "función nativa sin enlazar: {k}"),
    "fonctions Papyrus natives (framework très répandu)": ("native Papyrus functions (very common framework)", "funzioni native Papyrus (framework molto diffuso)", "funciones nativas de Papyrus (framework muy extendido)"),
    "fonctions utilitaires Papyrus (framework)": ("Papyrus utility functions (framework)", "funzioni di utilità Papyrus (framework)", "funciones de utilidad de Papyrus (framework)"),
    "génère les crash logs analysés ici": ("generates the crash logs analyzed here", "genera i crash log analizzati qui", "genera los crash logs analizados aquí"),
    "installation": ("installation", "installazione", "instalación"),
    "interface boussole/marqueurs ; s'appuie sur le Scaleform du jeu": ("compass/markers interface; relies on the game's Scaleform", "interfaccia bussola/marcatori; si appoggia allo Scaleform del gioco", "interfaz de brújula/marcadores; se apoya en el Scaleform del juego"),
    "menus ImGui pour les mods": ("ImGui menus for mods", "menu ImGui per le mod", "menús ImGui para mods"),
    "modules GPU en pile ({src})": ("GPU modules on the stack ({src})", "moduli GPU nello stack ({src})", "módulos de GPU en la pila ({src})"),
    "morphs et overlays du personnage": ("character morphs and overlays", "morph e overlay del personaggio", "morphs y overlays del personaje"),
    "pas de crash log, anomalies secondaires uniquement": ("no crash log, secondary anomalies only", "nessun crash log, solo anomalie secondarie", "sin crash log, solo anomalías secundarias"),
    "patch dynamique des enregistrements au chargement": ("dynamic record patching at load time", "patch dinamica dei record al caricamento", "parcheo dinámico de registros al cargar"),
    "plugin inconnu": ("unknown plugin", "plugin sconosciuto", "plugin desconocido"),
    "plugin lié à l'exception SKSE ({src})": ("plugin tied to the SKSE exception ({src})", "plugin legato all'eccezione SKSE ({src})", "plugin vinculado a la excepción de SKSE ({src})"),
    "plugins.txt : {a} plugin(s) actifs sur {t}": ("plugins.txt: {a} active plugin(s) out of {t}", "plugins.txt: {a} plugin attivi su {t}", "plugins.txt: {a} plugin(s) activos de {t}"),
    "point de crash dans {src}": ("crash point in {src}", "punto di crash in {src}", "punto de fallo en {src}"),
    "refusé/en erreur au chargement SKSE ({src})": ("refused/errored at SKSE load ({src})", "rifiutato/in errore al caricamento SKSE ({src})", "rechazado/con error en la carga de SKSE ({src})"),
    "rôle connu : {role}": ("known role: {role}", "ruolo noto: {role}", "función conocida: {role}"),
    "script introuvable : {k} ({v}×)": ("script not found: {k} ({v}×)", "script non trovato: {k} ({v}×)", "script no encontrado: {k} ({v}×)"),
    "script manquant dans {src}": ("missing script in {src}", "script mancante in {src}", "script ausente en {src}"),
    "script non lié : {k} ({v}×)": ("unbound script: {k} ({v}×)", "script non collegato: {k} ({v}×)", "script sin enlazar: {k} ({v}×)"),
    "script non lié dans {src}": ("unbound script in {src}", "script non collegato in {src}", "script sin enlazar en {src}"),
    "structures de données pour scripts Papyrus (framework)": ("data structures for Papyrus scripts (framework)", "strutture dati per script Papyrus (framework)", "estructuras de datos para scripts Papyrus (framework)"),
    "suspect principal : {name}": ("main suspect: {name}", "sospetto principale: {name}", "sospechoso principal: {name}"),
    "traductions/chaînes dynamiques (framework)": ("dynamic translations/strings (framework)", "traduzioni/stringhe dinamiche (framework)", "traducciones/cadenas dinámicas (framework)"),
    "trop de plugins actifs": ("too many active plugins", "troppi plugin attivi", "demasiados plugins activos"),
    "version ancienne v{v} ({src})": ("old version v{v} ({src})", "versione vecchia v{v} ({src})", "versión antigua v{v} ({src})"),
    "version de SkyrimSE.exe ≠ runtime SKSE": ("SkyrimSE.exe version ≠ SKSE runtime", "versione di SkyrimSE.exe ≠ runtime SKSE", "versión de SkyrimSE.exe ≠ runtime SKSE"),
    "vérifié mais non chargé par SKSE ({src})": ("checked but not loaded by SKSE ({src})", "verificato ma non caricato da SKSE ({src})", "verificado pero no cargado por SKSE ({src})"),
    "{al} absent de Data/SKSE/Plugins": ("{al} missing from Data/SKSE/Plugins", "{al} assente da Data/SKSE/Plugins", "{al} ausente de Data/SKSE/Plugins"),
    "{label} presque saturée au moment du crash ({pct} %)": ("{label} nearly saturated at crash time ({pct} %)", "{label} quasi satura al momento del crash ({pct} %)", "{label} casi saturada en el momento del fallo ({pct} %)"),
    "{label} à {pct} % au moment du crash ({src})": ("{label} at {pct} % at crash time ({src})", "{label} al {pct} % al momento del crash ({src})", "{label} al {pct} % en el momento del fallo ({src})"),
    "{loaded} plugin(s) SKSE chargés sur {total} vérifiés": ("{loaded} SKSE plugin(s) loaded out of {total} checked", "{loaded} plugin SKSE caricati su {total} verificati", "{loaded} plugin(s) SKSE cargados de {total} verificados"),
    "{n} DLL présentes mais absentes du log SKSE": ("{n} DLL(s) present but absent from the SKSE log", "{n} DLL presenti ma assenti dal log SKSE", "{n} DLL presentes pero ausentes del log de SKSE"),
    "{n} erreur(s) critique(s) dans {src}": ("{n} critical error(s) in {src}", "{n} errore/i critico/i in {src}", "{n} error(es) crítico(s) en {src}"),
    "{n} fonction(s) : ": ("{n} function(s): ", "{n} funzione/i: ", "{n} función(es): "),
    "{n} fonction(s) native(s) dans {src}": ("{n} native function(s) in {src}", "{n} funzione/i nativa/e in {src}", "{n} función(es) nativa(s) en {src}"),
    "{n} ligne(s)": ("{n} line(s)", "{n} riga/e", "{n} línea(s)"),
    "{n} ligne(s) '{cat}' dans {src}": ("{n} '{cat}' line(s) in {src}", "{n} riga/e '{cat}' in {src}", "{n} línea(s) '{cat}' en {src}"),
    "{n} ligne(s) critique(s)": ("{n} critical line(s)", "{n} riga/e critica/che", "{n} línea(s) crítica(s)"),
    "{n} modules chargés (dont ~{p} plugins .dllplugin).": ("{n} modules loaded (including ~{p} .dllplugin plugins).", "{n} moduli caricati (di cui ~{p} plugin .dllplugin).", "{n} módulos cargados (de ellos ~{p} plugins .dllplugin)."),
    "{n} occurrence(s)": ("{n} occurrence(s)", "{n} occorrenza/e", "{n} aparición(es)"),
    "{n} occurrence(s) — scripts trop nombreux ou en boucle.": ("{n} occurrence(s) — too many scripts or looping.", "{n} occorrenza/e — troppi script o in loop.", "{n} aparición(es): demasiados scripts o en bucle."),
    "{n} plugins .esp/.esm actifs (limite {max} hors ESL)": ("{n} active .esp/.esm plugins (limit {max} excluding ESL)", "{n} plugin .esp/.esm attivi (limite {max} esclusi ESL)", "{n} plugins .esp/.esm activos (límite {max} sin contar ESL)"),
    "{n} script(s) CC introuvable(s) dans {src}": ("{n} CC script(s) not found in {src}", "{n} script CC non trovato/i in {src}", "{n} script(s) de CC no encontrado(s) en {src}"),
    "{n} vidange(s) de piles dans {src}": ("{n} stack dump(s) in {src}", "{n} svuotamento/i di stack in {src}", "{n} volcado(s) de pila en {src}"),
    "{n}× dans la pile d'appels ({src})": ("{n}× in the call stack ({src})", "{n}× nello stack delle chiamate ({src})", "{n}× en la pila de llamadas ({src})"),
    "{n}× dans le STACK ({src})": ("{n}× in the STACK ({src})", "{n}× nello STACK ({src})", "{n}× en el STACK ({src})"),
    "{total} erreurs Papyrus ; scripts les plus fautifs": ("{total} Papyrus errors; most faulty scripts", "{total} errori Papyrus; script più problematici", "{total} errores de Papyrus; scripts más defectuosos"),
    "{v} erreurs Papyrus ({src})": ("{v} Papyrus errors ({src})", "{v} errori Papyrus ({src})", "{v} errores de Papyrus ({src})"),
    "Épuisement de mémoire (RAM/VRAM/heap)": ("Memory exhaustion (RAM/VRAM/heap)", "Esaurimento della memoria (RAM/VRAM/heap)", "Agotamiento de memoria (RAM/VRAM/heap)"),
}
