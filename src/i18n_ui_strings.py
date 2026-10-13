"""Traductions : {texte français: (anglais, italien, espagnol)}.

Les placeholders {x} doivent rester identiques dans toutes les langues (vérifié par test_i18n).
"""

TR = {
    # ------------------------------------------------------------ interface
    "Analyser les logs": ("Analyze logs", "Analizza i log", "Analizar logs"),
    "Audit approfondi": ("Deep audit", "Audit approfondito", "Auditoría a fondo"),
    "Fichier…": ("File…", "File…", "Archivo…"),
    "Purger les logs": ("Purge logs", "Elimina i log", "Purgar logs"),
    "Supprime les .log / .log0 des répertoires configurés": (
        "Deletes the .log / .log0 files in the configured folders",
        "Elimina i file .log / .log0 nelle cartelle configurate",
        "Elimina los archivos .log / .log0 de las carpetas configuradas"),
    "Assistant IA": ("AI Assistant", "Assistente IA", "Asistente IA"),
    "Posez une question sur le dernier crash…": (
        "Ask a question about the last crash…",
        "Fai una domanda sull'ultimo crash…",
        "Haz una pregunta sobre el último crash…"),
    "Votre question…": ("Your question…", "La tua domanda…", "Tu pregunta…"),
    "Envoyer": ("Send", "Invia", "Enviar"),
    "Expliquer le crash": ("Explain the crash", "Spiega il crash", "Explicar el crash"),
    "Quelle est la cause la plus probable du dernier crash ? Que dois-je vérifier en premier ?": (
        "What is the most likely cause of the last crash? What should I check first?",
        "Qual è la causa più probabile dell'ultimo crash? Cosa devo controllare per primo?",
        "¿Cuál es la causa más probable del último crash? ¿Qué debo comprobar primero?"),
    "Vous": ("You", "Tu", "Tú"),
    "Assistant": ("Assistant", "Assistente", "Asistente"),
    "Erreur": ("Error", "Errore", "Error"),
    "Assistant réfléchit": ("Assistant is thinking", "L'assistente sta pensando", "El asistente está pensando"),
    "Nouveau crash détecté : {name}": (
        "New crash detected: {name}", "Nuovo crash rilevato: {name}", "Nuevo crash detectado: {name}"),
    "Audit en cours…": ("Audit in progress…", "Audit in corso…", "Auditoría en curso…"),
    "Échec de l'audit : {msg}": ("Audit failed: {msg}", "Audit non riuscito: {msg}", "Fallo de la auditoría: {msg}"),
    "AUDIT — {verdict}": ("AUDIT — {verdict}", "AUDIT — {verdict}", "AUDITORÍA — {verdict}"),
    "Installation : {dir}": ("Installation: {dir}", "Installazione: {dir}", "Instalación: {dir}"),
    "Suspects classés": ("Ranked suspects", "Sospetti in classifica", "Sospechosos clasificados"),
    "(score {score}) ": ("(score {score}) ", "(punteggio {score}) ", "(puntuación {score}) "),
    "Piste : {s}": ("Lead: {s}", "Pista: {s}", "Pista: {s}"),
    "    Piste : {tip}": ("    Lead: {tip}", "    Pista: {tip}", "    Pista: {tip}"),
    "Ouvrir Log": ("Open log", "Apri log", "Abrir log"),
    "Logs (*.log *.txt)": ("Logs (*.log *.txt)", "Log (*.log *.txt)", "Logs (*.log *.txt)"),
    "Fichier introuvable.": ("File not found.", "File non trovato.", "Archivo no encontrado."),
    "Aucun problème détecté dans {name}.": (
        "No problem detected in {name}.", "Nessun problema rilevato in {name}.", "Ningún problema detectado en {name}."),
    "Aucun problème détecté.": ("No problem detected.", "Nessun problema rilevato.", "Ningún problema detectado."),
    "Aucun fichier log à supprimer.": ("No log file to delete.", "Nessun file di log da eliminare.", "No hay archivos de log que eliminar."),
    "Supprimer définitivement {n} fichier(s) log ?": (
        "Permanently delete {n} log file(s)?", "Eliminare definitivamente {n} file di log?",
        "¿Eliminar definitivamente {n} archivo(s) de log?"),
    "Dossiers concernés :": ("Affected folders:", "Cartelle interessate:", "Carpetas afectadas:"),
    "Action irréversible.": ("This cannot be undone.", "Azione irreversibile.", "Acción irreversible."),
    "Supprimer": ("Delete", "Elimina", "Eliminar"),
    "Annuler": ("Cancel", "Annulla", "Cancelar"),
    "{n} fichier(s) supprimé(s).": ("{n} file(s) deleted.", "{n} file eliminato/i.", "{n} archivo(s) eliminado(s)."),
    "Échecs :": ("Failures:", "Errori:", "Fallos:"),
    "Lecture : {name}": ("Reading: {name}", "Lettura: {name}", "Lectura: {name}"),
    "Erreur inattendue : {e}": ("Unexpected error: {e}", "Errore imprevisto: {e}", "Error inesperado: {e}"),
    # dialogues
    "Sélectionner un dossier pour {game}": (
        "Select a folder for {game}", "Seleziona una cartella per {game}", "Selecciona una carpeta para {game}"),
    "(clé enregistrée)": ("(key saved)", "(chiave salvata)", "(clave guardada)"),
    "Coller la clé API": ("Paste the API key", "Incolla la chiave API", "Pega la clave API"),
    "Langue": ("Language", "Lingua", "Idioma"),
    "Fournisseur": ("Provider", "Provider", "Proveedor"),
    "Modèle Gemini": ("Gemini model", "Modello Gemini", "Modelo Gemini"),
    "Clé API Gemini": ("Gemini API key", "Chiave API Gemini", "Clave API de Gemini"),
    "URL Ollama": ("Ollama URL", "URL Ollama", "URL de Ollama"),
    "Modèle Ollama": ("Ollama model", "Modello Ollama", "Modelo Ollama"),
    "Utiliser les fiches de connaissances modding Skyrim (dossier skills/)": (
        "Use the Skyrim modding knowledge sheets (skills/ folder)",
        "Usa le schede di conoscenza sul modding di Skyrim (cartella skills/)",
        "Usar las fichas de conocimiento de modding de Skyrim (carpeta skills/)"),
    "Recherche web Google (Gemini uniquement, plus lent)": (
        "Google web search (Gemini only, slower)",
        "Ricerca web Google (solo Gemini, più lenta)",
        "Búsqueda web de Google (solo Gemini, más lenta)"),
    "Connaissances": ("Knowledge", "Conoscenze", "Conocimientos"),
    "Anonymiser les chemins et e-mails avant envoi à Gemini": (
        "Anonymize paths and e-mails before sending to Gemini",
        "Anonimizza percorsi ed e-mail prima dell'invio a Gemini",
        "Anonimizar rutas y correos antes de enviarlos a Gemini"),
    "Confidentialité": ("Privacy", "Privacy", "Privacidad"),
    "Surveiller les dossiers : nouveau crash = notification + audit automatique": (
        "Watch the folders: new crash = notification + automatic audit",
        "Monitora le cartelle: nuovo crash = notifica + audit automatico",
        "Vigilar las carpetas: nuevo crash = notificación + auditoría automática"),
    "Surveillance": ("Monitoring", "Monitoraggio", "Vigilancia"),
    "Auto (CrossOver) — ou dossier contenant SkyrimSE.exe": (
        "Auto (CrossOver) — or folder containing SkyrimSE.exe",
        "Auto (CrossOver) — o cartella contenente SkyrimSE.exe",
        "Auto (CrossOver) — o carpeta que contiene SkyrimSE.exe"),
    "Choisir…": ("Browse…", "Scegli…", "Elegir…"),
    "Dossier du jeu": ("Game folder", "Cartella del gioco", "Carpeta del juego"),
    "La clé est stockée dans le Trousseau macOS (jamais en clair dans la config). ": (
        "The key is stored in the macOS Keychain (never in plain text in the config). ",
        "La chiave è salvata nel Portachiavi di macOS (mai in chiaro nella configurazione). ",
        "La clave se guarda en el Llavero de macOS (nunca en texto plano en la configuración). "),
    "Avec Gemini, le rapport d'audit et des extraits de logs sont envoyés à Google. Ollama reste 100 % local.": (
        "With Gemini, the audit report and log excerpts are sent to Google. Ollama stays 100% local.",
        "Con Gemini, il rapporto di audit e alcuni estratti dei log vengono inviati a Google. Ollama resta 100% locale.",
        "Con Gemini, el informe de auditoría y fragmentos de logs se envían a Google. Ollama es 100 % local."),
    "Dossier de Skyrim Special Edition": (
        "Skyrim Special Edition folder", "Cartella di Skyrim Special Edition", "Carpeta de Skyrim Special Edition"),
    "Actualiser": ("Refresh", "Aggiorna", "Actualizar"),
    "Récupération des modèles {label}…": (
        "Fetching {label} models…", "Recupero dei modelli {label}…", "Obteniendo modelos de {label}…"),
    "{n} modèle(s) {label} disponible(s).": (
        "{n} {label} model(s) available.", "{n} modello/i {label} disponibile/i.", "{n} modelo(s) de {label} disponible(s)."),
    "Liste indisponible ({msg}). Vous pouvez saisir le nom du modèle.": (
        "List unavailable ({msg}). You can type the model name.",
        "Elenco non disponibile ({msg}). Puoi digitare il nome del modello.",
        "Lista no disponible ({msg}). Puedes escribir el nombre del modelo."),
    # ------------------------------------------------------------ client IA
    "Module 'keyring' indisponible : définissez GEMINI_API_KEY dans l'environnement.": (
        "Module 'keyring' unavailable: set GEMINI_API_KEY in the environment.",
        "Modulo 'keyring' non disponibile: definisci GEMINI_API_KEY nell'ambiente.",
        "Módulo 'keyring' no disponible: define GEMINI_API_KEY en el entorno."),
    "Trousseau inaccessible : {e}": ("Keychain inaccessible: {e}", "Portachiavi inaccessibile: {e}", "Llavero inaccesible: {e}"),
    " [clé utilisée : {src}, se termine par …{end}]": (
        " [key used: {src}, ends with …{end}]", " [chiave usata: {src}, termina con …{end}]",
        " [clave usada: {src}, termina en …{end}]"),
    "Requête refusée ({code}) — clé API invalide ou modèle inconnu. {msg}{hint}": (
        "Request refused ({code}) — invalid API key or unknown model. {msg}{hint}",
        "Richiesta rifiutata ({code}) — chiave API non valida o modello sconosciuto. {msg}{hint}",
        "Solicitud rechazada ({code}): clave API no válida o modelo desconocido. {msg}{hint}"),
    "Quota dépassé (429). Réessayez plus tard.": (
        "Quota exceeded (429). Try again later.", "Quota superata (429). Riprova più tardi.",
        "Cuota superada (429). Inténtalo más tarde."),
    "Erreur HTTP {code}. {msg}": ("HTTP error {code}. {msg}", "Errore HTTP {code}. {msg}", "Error HTTP {code}. {msg}"),
    "Connexion impossible : {reason}": (
        "Connection failed: {reason}", "Connessione impossibile: {reason}", "No se pudo conectar: {reason}"),
    "Délai dépassé ou erreur réseau : {e}": (
        "Timeout or network error: {e}", "Timeout o errore di rete: {e}", "Tiempo agotado o error de red: {e}"),
    "Réponse du serveur illisible.": (
        "Unreadable server response.", "Risposta del server illeggibile.", "Respuesta del servidor ilegible."),
    "Clé API Gemini absente : impossible de lister les modèles.": (
        "Gemini API key missing: cannot list models.",
        "Chiave API Gemini assente: impossibile elencare i modelli.",
        "Falta la clave API de Gemini: no se pueden listar los modelos."),
    "Aucun modèle texte renvoyé par l'API.": (
        "No text model returned by the API.", "Nessun modello di testo restituito dall'API.",
        "La API no devolvió ningún modelo de texto."),
    "URL Ollama invalide.": ("Invalid Ollama URL.", "URL Ollama non valido.", "URL de Ollama no válida."),
    "Aucun modèle Ollama installé (`ollama pull llama3.1`).": (
        "No Ollama model installed (`ollama pull llama3.1`).",
        "Nessun modello Ollama installato (`ollama pull llama3.1`).",
        "Ningún modelo de Ollama instalado (`ollama pull llama3.1`)."),
    "(réponse vide)": ("(empty response)", "(risposta vuota)", "(respuesta vacía)"),
    "réponse inattendue": ("unexpected response", "risposta inattesa", "respuesta inesperada"),
    "Gemini n'a pas renvoyé de texte ({reason}).": (
        "Gemini returned no text ({reason}).", "Gemini non ha restituito testo ({reason}).",
        "Gemini no devolvió texto ({reason})."),
    "Réponse Ollama inattendue (modèle installé ? `ollama pull <modèle>`).": (
        "Unexpected Ollama response (model installed? `ollama pull <model>`).",
        "Risposta Ollama inattesa (modello installato? `ollama pull <modello>`).",
        "Respuesta de Ollama inesperada (¿modelo instalado? `ollama pull <modelo>`)."),
    "Fournisseur inconnu : {provider}": (
        "Unknown provider: {provider}", "Provider sconosciuto: {provider}", "Proveedor desconocido: {provider}"),
    "trousseau": ("keychain", "portachiavi", "llavero"),
    "variable d'environnement GEMINI_API_KEY": (
        "GEMINI_API_KEY environment variable", "variabile d'ambiente GEMINI_API_KEY",
        "variable de entorno GEMINI_API_KEY"),
    "aucune": ("none", "nessuna", "ninguna"),
    # ------------------------------------------------------------ libellés IA
    "VERDICT": ("VERDICT", "VERDETTO", "VEREDICTO"),
    "CAUSE": ("CAUSE", "CAUSA", "CAUSA"),
    "CONFIANCE": ("CONFIDENCE", "AFFIDABILITÀ", "CONFIANZA"),
    "PREUVES": ("EVIDENCE", "PROVE", "PRUEBAS"),
    "ACTIONS": ("ACTIONS", "AZIONI", "ACCIONES"),
    "MANQUE": ("MISSING", "MANCANTE", "FALTA"),
    "CRITIQUE": ("CRITICAL", "CRITICO", "CRÍTICO"),
    "AVERTISSEMENT": ("WARNING", "AVVISO", "AVISO"),
    "INFO": ("INFO", "INFO", "INFO"),
    "Veille automatique : mettre à jour la base de connaissances (GitHub, Steam, Reddit, SKSE)": (
        "Auto-watch: update the knowledge base (GitHub, Steam, Reddit, SKSE)",
        "Veglia automatica: aggiorna la base di conoscenza (GitHub, Steam, Reddit, SKSE)",
        "Vigilancia automática: actualizar la base de conocimiento (GitHub, Steam, Reddit, SKSE)"),
    "Mettre à jour maintenant": ("Update now", "Aggiorna ora", "Actualizar ahora"),
    "Base de connaissances": ("Knowledge base", "Base di conoscenza", "Base de conocimiento"),
    "Dernière mise à jour de la base : {d}": (
        "Last knowledge base update: {d}",
        "Ultimo aggiornamento della base: {d}",
        "Última actualización de la base: {d}"),
    "jamais": ("never", "mai", "nunca"),
    "Mise à jour de la base de connaissances…": (
        "Updating the knowledge base…",
        "Aggiornamento della base di conoscenza…",
        "Actualizando la base de conocimiento…"),
    "Mise à jour déjà en cours.": (
        "Update already in progress.", "Aggiornamento già in corso.", "Actualización ya en curso."),
    "Base de connaissances : {u} source(s) mise(s) à jour, {f} en échec.": (
        "Knowledge base: {u} source(s) updated, {f} failed.",
        "Base di conoscenza: {u} fonte/i aggiornata/e, {f} non riuscita/e.",
        "Base de conocimiento: {u} fuente(s) actualizada(s), {f} con error."),
    "Mise à jour impossible : {msg}": (
        "Update impossible: {msg}", "Aggiornamento impossibile: {msg}", "Actualización imposible: {msg}"),
    # ------------------------------------------------------------ réglages (fenêtre unique)
    "Réglages…": ("Settings…", "Impostazioni…", "Ajustes…"),
    "Réglages": ("Settings", "Impostazioni", "Ajustes"),
    "Fichier": ("File", "File", "Archivo"),
    "Ouvrir un log…": ("Open a log…", "Apri un log…", "Abrir un log…"),
    "Langue, dossiers de logs, IA, base de connaissances (⌘,)": (
        "Language, log folders, AI, knowledge base (⌘,)",
        "Lingua, cartelle dei log, IA, base di conoscenza (⌘,)",
        "Idioma, carpetas de logs, IA, base de conocimientos (⌘,)"),
    "Général": ("General", "Generale", "General"),
    "Dossiers de logs": ("Log folders", "Cartelle dei log", "Carpetas de logs"),
    "IA": ("AI", "IA", "IA"),
    "Veille": ("Monitoring", "Monitoraggio", "Vigilancia"),
    "Ajouter…": ("Add…", "Aggiungi…", "Añadir…"),
    "Retirer": ("Remove", "Rimuovi", "Quitar"),
    "Dossiers où sKYCRASH cherche les logs de crash, SKSE et Papyrus.": (
        "Folders where sKYCRASH looks for crash, SKSE and Papyrus logs.",
        "Cartelle in cui sKYCRASH cerca i log di crash, SKSE e Papyrus.",
        "Carpetas donde sKYCRASH busca los logs de crash, SKSE y Papyrus."),
    "Aucun log à auditer. Configurez les dossiers dans Réglages… > Dossiers de logs.": (
        "No log to audit. Set up the folders in Settings… > Log folders.",
        "Nessun log da analizzare. Configura le cartelle in Impostazioni… > Cartelle dei log.",
        "Ningún log que auditar. Configura las carpetas en Ajustes… > Carpetas de logs."),
    "Aucun fichier .log trouvé. Configurez les dossiers dans Réglages… > Dossiers de logs.": (
        "No .log file found. Set up the folders in Settings… > Log folders.",
        "Nessun file .log trovato. Configura le cartelle in Impostazioni… > Cartelle dei log.",
        "No se encontró ningún archivo .log. Configura las carpetas en Ajustes… > Carpetas de logs."),
    "Installation non localisée — indiquez le dossier du jeu dans Réglages… > Général pour activer les contrôles de version.": (
        "Installation not found — set the game folder in Settings… > General to enable version checks.",
        "Installazione non individuata — indica la cartella del gioco in Impostazioni… > Generale per attivare i controlli di versione.",
        "Instalación no localizada: indica la carpeta del juego en Ajustes… > General para activar las comprobaciones de versión."),
    "Modèle introuvable (404) : choisissez-en un autre dans Réglages… > IA (bouton Actualiser). {msg}": (
        "Model not found (404): choose another one in Settings… > AI (Refresh button). {msg}",
        "Modello non trovato (404): sceglierne un altro in Impostazioni… > IA (pulsante Aggiorna). {msg}",
        "Modelo no encontrado (404): elige otro en Ajustes… > IA (botón Actualizar). {msg}"),
    "Clé API Gemini absente : renseignez-la dans Réglages… > IA.": (
        "Gemini API key missing: enter it in Settings… > AI.",
        "Chiave API Gemini assente: inseriscila in Impostazioni… > IA.",
        "Falta la clave API de Gemini: introdúcela en Ajustes… > IA."),
}
