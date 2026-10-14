// Recoupements de la preview (miroir de src/insights.py, src/savegame.py et src/diagnostic.py) :
// chronologie, historique des crash logs, sauvegarde .ess comparée aux plugins du dernier plantage,
// domaine des objets en cause, et export du dossier de diagnostic en Markdown.
// Sans accès aux fichiers du jeu, la liste « actuelle » est celle du dernier crash log (section PLUGINS).
// Les textes restent en français : la traduction de la page les reconnaît (mêmes gabarits que l'app).

const SEV = { CRIT: 3, WARN: 2, INFO: 1 };
const SEV_LABEL = { 3: "CRITIQUE", 2: "AVERTISSEMENT", 1: "INFO" };
const MAX_HISTORY = 12;
const MAGIC = "TESV_SAVEGAME";

const CRASH_TIME_RE = /^CRASH TIME:\s*(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
const CRASH_NAME_RE = /crash-(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})/i;
const UPTIME_RE = /Process Uptime:\s*(\d+):(\d{2}):(\d{2})/;
const AT_RE = /\bat 0x[0-9A-Fa-f]+\s+(.+)$/;
const OBJ_TYPE_RE = /\(([A-Za-z_][\w:]*)\*\)/g;
const PLUGIN_LINE_RE = /^\s*\[[^\]]+\]\s+(.+?\.es[mpl])\s*$/i;
const DLL_LINE_RE = /^\s+(\S.*?\.dll)\b/i;
const TS_RE = /\[(?:(\d{4}-\d{2}-\d{2})[ T])?(\d{2}):(\d{2}):(\d{2})(?:[.,]\d+)?/;
export const WARN_RE = /\[(?:w|e|warn|warning|err|error)\]/i;

const EVENTS = [
  ["save", "chargement d'une sauvegarde", /loading save|load(?:ing)? ?game|kPreLoadGame|kPostLoadGame|PostLoadGame|PreLoadGame/i],
  ["newgame", "nouvelle partie", /kNewGame|\bnew game\b/i],
  ["menu", "menu principal", /main ?menu/i],
];
const DOMAINS = {
  audio: [/Sound|Music|Audio|Acoustic/i, /sound|music|audio|occlusion|acoustic|ambien|bird|flock/i, "son et musique"],
  region: [/TESRegion|TESWeather|TESClimate|\bSky\b/i, /region|weather|storm|climate|cloud|rain|snow|fog|environs/i, "régions et météo"],
  anim: [/^hk|Havok|Behavior|Animation/i, /anim|behavior|havok|pandora|nemesis|\boar\b|\bdar\b/i, "animations"],
};

const pad = (n) => String(n).padStart(2, "0");
const fmt = (d) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const fmtLong = (d) => (d ? `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}` : "?");
const baseName = (n) => n.replace(/\.[^.]+$/, "");

// ------------------------------------------------------------------ sauvegarde .ess
function lz4BlockPrefix(src, want) {
  const out = [];
  let i = 0;
  while (i < src.length && out.length < want) {
    const token = src[i++];
    let lit = token >> 4;
    if (lit === 15) { let b; do { b = src[i++]; lit += b; } while (b === 255); }
    for (let k = 0; k < lit; k++) out.push(src[i + k]);
    i += lit;
    if (i >= src.length) break;
    const offset = src[i] | (src[i + 1] << 8);
    i += 2;
    let mlen = token & 15;
    if (mlen === 15) { let b; do { b = src[i++]; mlen += b; } while (b === 255); }
    mlen += 4;
    if (!offset || offset > out.length) throw new Error("bloc LZ4 invalide");
    const start = out.length - offset;
    for (let k = 0; k < mlen; k++) out.push(out[start + k]);
  }
  return Uint8Array.from(out);
}

class Reader {
  constructor(bytes, pos = 0) { this.b = bytes; this.v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength); this.p = pos; }
  need(n) { if (this.p + n > this.b.length) throw new Error("sauvegarde tronquée"); }
  u8() { this.need(1); return this.b[this.p++]; }
  u16() { this.need(2); const x = this.v.getUint16(this.p, true); this.p += 2; return x; }
  u32() { this.need(4); const x = this.v.getUint32(this.p, true); this.p += 4; return x; }
  f32() { this.need(4); this.p += 4; }
  u64() { this.need(8); const lo = this.v.getUint32(this.p, true), hi = this.v.getUint32(this.p + 4, true); this.p += 8; return hi * 4294967296 + lo; }
  take(n) { this.need(n); const x = this.b.subarray(this.p, this.p + n); this.p += n; return x; }
  wstr() {
    const raw = this.take(this.u16());
    try { return new TextDecoder("utf-8", { fatal: true }).decode(raw); } catch { return new TextDecoder("windows-1252").decode(raw); }
  }
}

export async function readSave(name, arrayBuffer, mtime) {
  const bytes = new Uint8Array(arrayBuffer);
  const r = new Reader(bytes);
  if (new TextDecoder().decode(r.take(MAGIC.length)) !== MAGIC) throw new Error("pas une sauvegarde Skyrim");
  r.u32();
  const version = r.u32();
  r.u32();
  const info = { name, player: r.wstr(), level: r.u32(), location: r.wstr(), plugins: [], light: [] };
  r.wstr(); r.wstr(); r.u16(); r.f32(); r.f32();
  const filetime = r.u64();
  const w = r.u32(), h = r.u32();
  const compression = version >= 12 ? r.u16() : 0;
  r.take(w * h * (version >= 12 ? 4 : 3));
  let at = new Date(filetime / 1e4 - 11644473600000);
  if (!(at.getFullYear() > 2000 && at.getFullYear() < 2100)) at = new Date(mtime);
  info.savedAt = at;
  let b = r;
  if (compression) {
    r.u32();
    const size = r.u32();
    const packed = r.take(Math.min(size, bytes.length - r.p));
    let body;
    if (compression === 2) body = lz4BlockPrefix(packed, 256 * 1024);
    else if (compression === 1) {
      const ds = new Response(new Blob([packed]).stream().pipeThrough(new DecompressionStream("deflate")));
      body = new Uint8Array(await ds.arrayBuffer());
    } else throw new Error(`compression inconnue (${compression})`);
    b = new Reader(body);
  }
  const formVersion = b.u8();
  b.u32();
  for (let n = b.u8(); n > 0; n--) info.plugins.push(b.wstr());
  if (formVersion >= 78) for (let n = b.u16(); n > 0; n--) info.light.push(b.wstr());
  info.all = [...info.plugins, ...info.light];
  return info;
}

// ------------------------------------------------------------------ crash logs
function section(lines, title) {
  const out = [];
  let inside = false;
  for (const l of lines) {
    const s = l.trim();
    if (!/^\s/.test(l) && s.endsWith(":") && s.toUpperCase() === s) {
      if (inside) break;
      inside = s === title;
      continue;
    }
    if (inside) out.push(l);
  }
  return out;
}

function crashTime(f) {
  for (const l of f.lines.slice(0, 5)) {
    const m = CRASH_TIME_RE.exec(l.trim());
    if (m) return new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  }
  const m = CRASH_NAME_RE.exec(f.name);
  return m ? new Date(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6]) : new Date(f.mtime);
}

export function summarizeCrash(f) {
  let where = "";
  for (const l of f.lines.slice(0, 40)) {
    if (/unhandled/i.test(l)) {
      const m = AT_RE.exec(l.trim());
      where = (m ? m[1] : l.trim()).split("\t")[0].trim();
      break;
    }
  }
  const upLine = f.lines.slice(0, 80).map((l) => UPTIME_RE.exec(l)).find(Boolean);
  const objects = [...new Set(section(f.lines, "POSSIBLE RELEVANT OBJECTS:").flatMap((l) => [...l.matchAll(OBJ_TYPE_RE)].map((m) => m[1])))];
  const skse = new Set(section(f.lines, "SKSE PLUGINS:").map((l) => DLL_LINE_RE.exec(l)?.[1]).filter(Boolean));
  const plugins = section(f.lines, "PLUGINS:").map((l) => PLUGIN_LINE_RE.exec(l)?.[1]).filter(Boolean);
  return {
    file: f, name: f.name, time: crashTime(f), where,
    uptime: upLine ? +upLine[1] * 3600 + +upLine[2] * 60 + +upLine[3] : null,
    objects, skse, plugins,
  };
}

function events(files, crashAt, windowS) {
  const start = crashAt.getTime() - (windowS + 5) * 1000;
  const best = {};
  for (const f of files) {
    if (f.kind === "crash") continue;
    for (const l of f.lines) {
      const ev = EVENTS.find(([, , rx]) => rx.test(l));
      if (!ev) continue;
      const m = TS_RE.exec(l);
      if (!m) continue;
      const day = m[1] ? m[1].split("-").map(Number) : [crashAt.getFullYear(), crashAt.getMonth() + 1, crashAt.getDate()];
      const at = new Date(day[0], day[1] - 1, day[2], +m[2], +m[3], +m[4]);
      if (at.getTime() >= start && at.getTime() <= crashAt.getTime() + 1000 && (!best[ev[0]] || at > best[ev[0]][0])) {
        best[ev[0]] = [at, ev[1], f.name];
      }
    }
  }
  return Object.values(best).sort((a, b) => a[0] - b[0]);
}

const warnCount = (files, stem) => {
  const f = files.find((x) => baseName(x.name).toLowerCase() === stem.toLowerCase() && x.kind !== "crash");
  return f ? f.lines.filter((l) => WARN_RE.test(l)).length : 0;
};

// ------------------------------------------------------------------ analyse
// files : [{name, mtime, text, lines, kind}] ; report : {findings, extras} ; scores/bump : ceux du moteur
export function analyse(files, report, scores, bump, saves = []) {
  const ex = (report.extras = report.extras || {});
  const push = (sev, cat, title, detail, source, evidence, tip) =>
    report.findings.push({ sev, cat, title, detail, source, evidence: evidence || [], tip: tip || "" });

  const history = files.filter((f) => f.kind === "crash").map(summarizeCrash).sort((a, b) => b.time - a.time).slice(0, MAX_HISTORY);
  ex.history = history;
  const latest = history[0];

  if (latest) {
    const evs = events(files, latest.time, latest.uptime ?? 600);
    ex.timeline = [...evs, [latest.time, "plantage", latest.name]];
    const saveEv = [...evs].reverse().find((e) => e[1] === EVENTS[0][1]);
    if (saveEv) {
      const gap = Math.round((latest.time - saveEv[0]) / 1000);
      push(SEV.WARN, "chronologie", `Plantage ${gap} s après le chargement d'une sauvegarde`,
        `Chargement repéré à ${fmt(saveEv[0])} dans ${saveEv[2]} ; plantage à ${fmt(latest.time)}.`, "chronologie", [],
        "Tester une partie neuve depuis le menu principal (console : coc <lieu>) : si elle tient, la sauvegarde est en cause (plugins ajoutés ou retirés depuis).");
    } else if (latest.uptime != null && latest.uptime < 60) {
      push(SEV.WARN, "chronologie", `Plantage ${latest.uptime} s après le lancement du jeu`,
        "Avant ou pendant le menu principal : chargement des plugins et des données.", "chronologie", [],
        "Vérifier les masters manquants et les plugins SKSE récents.");
    }
  }

  if (history.length) {
    const same = history.filter((c) => c.where && latest && c.where === latest.where).length;
    push(SEV.INFO, "historique", `${history.length} crash log(s) dans l'historique`,
      `Même point de plantage que le dernier : ${same} fois.`, "historique", history.slice(0, 6).map((c) => `${fmt(c.time)} — ${c.where || "?"}`));
    const prev = history.slice(1).find((c) => c.skse.size);
    if (latest && latest.skse.size && prev) {
      const added = [...latest.skse].filter((d) => !prev.skse.has(d)).sort();
      const removed = [...prev.skse].filter((d) => !latest.skse.has(d)).sort();
      if (added.length || removed.length) {
        const detail = [];
        if (added.length) detail.push(`Ajoutées : ${added.slice(0, 12).join(", ")}`);
        if (removed.length) detail.push(`Retirées : ${removed.slice(0, 12).join(", ")}`);
        push(added.length ? SEV.WARN : SEV.INFO, "historique", `DLL SKSE modifiées depuis le plantage du ${fmt(prev.time)}`,
          detail.join(" — "), "historique", [], "Une DLL apparue juste avant un nouveau type de plantage est un suspect prioritaire.");
        added.forEach((d) => bump(scores, d, 2, "DLL SKSE apparue depuis le plantage précédent"));
      }
      ex.skseDiff = { since: prev.time, added, removed };
    }
  }

  // sauvegarde : la plus récente antérieure au dernier plantage, comparée aux plugins de ce plantage
  let addedSinceSave = [];
  const save = [...saves].filter((s) => !latest || s.savedAt <= latest.time).sort((a, b) => b.savedAt - a.savedAt)[0] || saves[0];
  if (save) {
    const current = latest?.plugins?.length ? latest.plugins : null;
    const when = `${pad(save.savedAt.getDate())}/${pad(save.savedAt.getMonth() + 1)} ${pad(save.savedAt.getHours())}:${pad(save.savedAt.getMinutes())}`;
    const sname = baseName(save.name);
    ex.save = { ...save, missing: [], added: [], current: !!current };
    if (current) {
      const cur = new Set(current.map((p) => p.toLowerCase()));
      const inSave = new Set(save.all.map((p) => p.toLowerCase()));
      const missing = save.all.filter((p) => !cur.has(p.toLowerCase()));
      addedSinceSave = current.filter((p) => !inSave.has(p.toLowerCase()));
      Object.assign(ex.save, { missing, added: addedSinceSave });
      if (missing.length) push(SEV.WARN, "sauvegarde", `${missing.length} plugin(s) de la sauvegarde « ${sname} » ne sont plus actifs`,
        `Sauvegarde du ${when} (${save.location}).`, "sauvegarde", missing.slice(0, 8),
        "Réactiver ces plugins pour charger la partie, ou nettoyer la sauvegarde (ReSaver) après les avoir retirés proprement.");
      if (addedSinceSave.length) push(addedSinceSave.length >= 10 ? SEV.WARN : SEV.INFO, "sauvegarde",
        `${addedSinceSave.length} plugin(s) ajoutés depuis la sauvegarde « ${sname} »`,
        `Sauvegarde du ${when} (${save.location}), ${save.all.length} plugins à l'époque.`, "sauvegarde", addedSinceSave.slice(0, 8),
        "Ajouter des plugins en cours de partie (régions, météo, sons, PNJ) peut faire planter au chargement. Tester une partie neuve (coc) ; si elle tient, retirer les ajouts récents.");
    } else {
      push(SEV.INFO, "sauvegarde", `Sauvegarde « ${sname} » : ${save.all.length} plugins`,
        `Sauvegarde du ${when} (${save.location}). Ajoutez un crash log récent pour la comparer aux plugins chargés.`, "sauvegarde");
    }
  }

  if (latest && latest.objects.length) {
    const doms = Object.entries(DOMAINS).filter(([, [objRx]]) => latest.objects.some((o) => objRx.test(o))).map(([k]) => k);
    if (doms.length) {
      const dlls = [], plugs = [];
      for (const k of doms) {
        const nameRx = DOMAINS[k][1];
        [...latest.skse].sort().forEach((d) => {
          if (nameRx.test(d) && !dlls.some(([x]) => x === d)) dlls.push([d, warnCount(files, baseName(d))]);
        });
        addedSinceSave.forEach((p) => nameRx.test(p) && !plugs.includes(p) && plugs.push(p));
      }
      const labels = doms.map((k) => DOMAINS[k][2]).join(", ");
      const parts = [];
      if (dlls.length) parts.push(`DLL chargées : ${dlls.slice(0, 10).map(([d, w]) => d + (w ? ` (${w} avertissements)` : "")).join(", ")}`);
      if (plugs.length) parts.push(`Plugins ajoutés depuis la sauvegarde : ${plugs.slice(0, 10).join(", ")}`);
      ex.domains = { labels, dlls, plugins: plugs };
      push(SEV.WARN, "domaine", `Objets en cause : ${labels}`,
        parts.join(" — ") || "Aucune DLL ni plugin récent lié à ce domaine.", "recoupement", [latest.objects.slice(0, 6).join(", ")],
        "Tester en désactivant un par un ces DLL et plugins, en commençant par les plus récents.");
      dlls.forEach(([d, w]) => bump(scores, d, w ? 3 : 2, `lié aux objets en cause (${labels})`));
      plugs.forEach((p) => bump(scores, p, 2, "ajouté depuis la sauvegarde, lié aux objets en cause"));
    }
  }
}

// ------------------------------------------------------------------ export
const CRASH_SECTIONS = ["POSSIBLE RELEVANT OBJECTS:", "CALL STACK ([P]robable / [S]tack scan):", "PROBABLE CALL STACK:", "REGISTERS:"];

export function buildDiagnostic(report, files, anonymize = (t) => t) {
  const ex = report.extras || {};
  const md = ["# Dossier de diagnostic sKYCRASH", "", `Généré le ${fmtLong(new Date())}.`, "",
    `## Audit — verdict : ${report.verdict}`, "", "### Suspects classés"];
  report.suspects.forEach(([n, s, r], i) => md.push(`${i + 1}. **${n}** (score ${s}) — ${r.slice(0, 3).join("; ")}`));
  md.push("", "### Constats");
  [...report.findings].sort((a, b) => b.sev - a.sev).forEach((f) => {
    md.push(`- [${SEV_LABEL[f.sev]}] (${f.cat}) ${f.title} — ${f.source}`);
    if (f.detail) md.push(`    ${f.detail}`);
    f.evidence.slice(0, 3).forEach((e) => md.push(`    > ${e}`));
    if (f.tip) md.push(`    Piste : ${f.tip}`);
  });
  md.push("", "## Chronologie du dernier plantage", "");
  md.push(...(ex.timeline?.length ? ex.timeline.map(([at, lab, src]) => `- ${fmtLong(at)} — ${lab} (${src})`) : ["Aucun événement horodaté trouvé dans les journaux."]));
  md.push("", "## Historique des plantages", "");
  if (ex.history?.length) {
    md.push("| Date | Point de plantage | Durée de jeu | Objets en cause |", "|---|---|---|---|");
    ex.history.forEach((c) => {
      const up = c.uptime != null ? `${Math.floor(c.uptime / 60)} min ${pad(c.uptime % 60)} s` : "?";
      md.push(`| ${fmtLong(c.time)} | \`${c.where || "?"}\` | ${up} | ${c.objects.slice(0, 4).join(", ")} |`);
    });
    if (ex.skseDiff) md.push("", `DLL SKSE depuis le plantage du ${fmtLong(ex.skseDiff.since)} : ajoutées ${ex.skseDiff.added.join(", ") || "-"} ; retirées ${ex.skseDiff.removed.join(", ") || "-"}.`);
  } else md.push("Aucun crash log Crash Logger SSE trouvé.");
  md.push("", "## Sauvegarde et plugins actuels", "");
  const s = ex.save;
  if (s) {
    md.push(`Sauvegarde : \`${s.name}\` — ${s.player}, ${s.location}, enregistrée le ${fmtLong(s.savedAt)}, ${s.all.length} plugins.`, "");
    if (s.current) {
      md.push(`Plugins de la sauvegarde qui ne sont plus actifs (${s.missing.length}) :`, ...(s.missing.length ? s.missing.map((p) => `- ${p}`) : ["- aucun"]));
      md.push("", `Plugins ajoutés depuis la sauvegarde (${s.added.length}) :`, ...(s.added.length ? s.added.map((p) => `- ${p}`) : ["- aucun"]));
    }
  } else md.push("Sauvegarde ou liste des plugins introuvable (dossier du jeu inconnu ?).");
  const warns = files.filter((f) => f.kind !== "crash").map((f) => [f.lines.filter((l) => WARN_RE.test(l)), f.name]).filter(([w]) => w.length)
    .sort((a, b) => b[0].length - a[0].length).slice(0, 20);
  md.push("", "## Avertissements des journaux de plugins", "");
  warns.forEach(([w, n]) => md.push(`- **${n}** : ${w.length} ligne(s)`, ...w.slice(0, 2).map((x) => `  - \`${x.trim().slice(0, 200)}\``)));
  if (!warns.length) md.push("Aucun avertissement repéré.");
  const latest = ex.history?.[0];
  if (latest) {
    const lines = latest.file.lines;
    md.push("", `## Extrait du dernier crash log (${latest.name})`, "", "```text", ...lines.slice(0, 12));
    for (const title of CRASH_SECTIONS) {
      const i = lines.findIndex((l) => l.trim() === title);
      if (i < 0) continue;
      md.push("", title);
      for (const l of lines.slice(i + 1, i + 61)) {
        if (!/^\s/.test(l) && /^[A-Z][A-Z #0-9/()\[\]]+:\s*$/.test(l.trim())) break;
        md.push(l.trimEnd());
      }
    }
    md.push("```");
  }
  return anonymize(md.join("\n") + "\n");
}

export function downloadText(text, filename) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type: "text/markdown;charset=utf-8" }));
  a.download = filename;
  document.body.append(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

export function defaultFilename(d = new Date()) {
  return `sKYCRASH-diagnostic-${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}.md`;
}
