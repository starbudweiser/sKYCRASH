# Export `crash_events.jsonl` (contrat v1)

sKYCRASH écrit, à la fin de chaque audit (manuel ou déclenché par la surveillance des nouveaux logs), un
événement par plantage analysé, pour mORTEX. Lecture seule côté mORTEX.

- Fichier : `~/Library/Application Support/SkyrimCrashAnalyzer/exports/crash_events.jsonl` (dossier créé si absent ;
  `SKYRIM_CA_EXPORT_DIR` impose un autre dossier).
- Format : JSON Lines, UTF-8, une ligne = un objet, ajout seul (une écriture `O_APPEND` + `fsync`, verrou `flock`).
- Clé d'unicité : `(log_name, crash_time)`. Un log ré-analysé n'ajoute rien (la première ligne est conservée).
- Réglage : Réglages… > Général > « Échange avec mORTEX » (activé par défaut ; clé `export_events` = `"1"`/`"0"`).

```json
{"schema":1,"crash_time":"2026-10-07T22:35:01","log_name":"crash-2026-10-07-22-35-01.log",
 "game_runtime":"1.5.97","skse_runtime":"1.5.97","verdict":"suspect principal : X.dll",
 "suspects":[{"name":"X.dll","kind":"dll","score":12,"reasons":["…"]}],
 "plugins_hash":"<sha256 ou null>","bottle":"<nom ou null>"}
```

| Champ | Contenu |
|---|---|
| `schema` | `1`. Tout changement incompatible incrémente ce nombre. |
| `crash_time` | `CRASH TIME` du log (sinon date du nom de fichier, sinon mtime), ISO 8601 local sans fuseau. |
| `log_name` | Nom du fichier, sans chemin. |
| `game_runtime` / `skse_runtime` | Versions `x.y.z` (en-tête du crash log / runtime lu dans `skse64.log`), `null` si inconnues. |
| `verdict` | Verdict de l'audit (texte libre, dans la langue de l'appli). |
| `suspects` | Triés par score décroissant, dont les entrées `env` en fin de liste. |
| `plugins_hash` | SHA-256 de la liste **ordonnée** des plugins actifs (`*` de `plugins.txt`), en minuscules ; `null` si introuvable. |
| `bottle` | Nom de la bouteille CrossOver (dossier avant `drive_c`), `null` sinon. |

`suspects[]` : `{name, kind, score, reasons[]}`.

- `kind` : `dll` (`.dll`), `plugin` (`.esp/.esm/.esl`), `object` (autre : script manquant, catégorie d'asset comme
  `mesh`, `texture`, `navmesh/cellule`), `env` (environnement), `mod` (réservé : lien vers un mod, rempli plus tard
  quand mORTEX fournira `install_facts.json`).
- `reasons` : 4 au plus, texte libre dans la langue de l'appli (à afficher, pas à interpréter).
- Entrées `env` : `name` stable, `reasons` en anglais :
  `wine_layer`, `renderer:D3DMetal|DXVK|DXMT`, `dlss_unavailable`, `unified_memory`, `memory_pressure`,
  `game_skse_mismatch`, `address_library_missing`, `plugin_limit`, `graphics_proxy`.

Confidentialité : aucun contenu brut de log, aucun chemin ; `/Users/…`, `C:\Users\…` et le nom d'utilisateur macOS
sont remplacés (`~`, `user`).
