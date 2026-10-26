"""Auto-alimentation de la base de connaissances (veille crashs Skyrim moddé).

Sources (liste blanche de domaines, HTTPS uniquement, aucune clé requise) :
  - GitHub : releases + issues « crash » des dépôts clés (Crash Logger SSE, Community Shaders...)
  - Steam : annonces de mises à jour du jeu (ISteamNews)
  - Reddit : fils r/skyrimmods et r/macgaming parlant de crash/CTD (flux RSS)
  - SKSE : page officielle des versions
  - CrossOver : journal des versions (CodeWeavers), pour les joueurs sur Mac

Chaque source produit une note Markdown `auto_<id>.md` (même format que skills/) dans
~/Library/Application Support/SkyrimCrashAnalyzer/knowledge. Les notes sont des DONNÉES
externes non fiables : texte nettoyé, lignes de type « prompt injection » retirées, taille bornée.
Les mots-clés (noms de DLL cités, versions) permettent de ne les injecter que si le crash
analysé les concerne.

CLI : python knowledge_updater.py [--out DIR] [--force]
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

APP_DIR = Path.home() / "Library" / "Application Support" / "SkyrimCrashAnalyzer"
KNOWLEDGE_DIR = APP_DIR / "knowledge"
STATE_NAME = "_state.json"
UA = "SkyrimCrashAnalyzer/1.0 (+local knowledge updater)"
ALLOWED_HOSTS = {"api.github.com", "api.steampowered.com", "www.reddit.com", "skse.silverlock.org",
                 "www.codeweavers.com"}
TIMEOUT_S = 15
MAX_BYTES = 1_500_000
MAX_NOTE_CHARS = 6000
DEFAULT_INTERVAL_H = 24
LAUNCH_INTERVAL_H = 1     # au lancement de l'app : mise à jour si la dernière date de plus d'une heure
PERIODIC_INTERVAL_H = 6   # app restée ouverte : vérification toutes les 6 h
SLOW_HOSTS = {"www.reddit.com": 6.0}  # secondes entre deux requêtes vers ces hôtes (sinon 429)
STEAM_APPID = 489830  # Skyrim Special Edition / Anniversary Edition

_LOCK = threading.Lock()


class UpdateError(Exception):
    """Erreur de récupération d'une source (réseau, quota, format)."""


class RateLimited(UpdateError):
    """Quota de l'API atteint : inutile d'insister sur le même hôte."""


@dataclass
class Source:
    id: str
    kind: str          # github_releases | github_issues | steam_news | reddit_rss | skse_site | crossover_changelog
    target: str        # dépôt "owner/name", appid, requête ou URL
    title: str
    keywords: tuple = ()


SOURCES = (
    Source("gh_crashlogger_releases", "github_releases", "alandtse/CrashLoggerSSE",
           "Crash Logger SSE — versions récentes", ("crash logger", "crashlogger", "crash-")),
    Source("gh_crashlogger_issues", "github_issues", "alandtse/CrashLoggerSSE",
           "Crash Logger SSE — problèmes signalés", ("crash logger", "crashlogger")),
    Source("gh_cs_releases", "github_releases", "community-shaders/skyrim-community-shaders",
           "Community Shaders — versions récentes", ("community shaders", "communityshaders", "shadercache")),
    Source("gh_cs_issues", "github_issues", "community-shaders/skyrim-community-shaders",
           "Community Shaders — crashs signalés", ("community shaders", "communityshaders", "shadercache")),
    Source("gh_papyrusextender", "github_releases", "powerof3/PapyrusExtenderSSE",
           "PapyrusExtender — versions récentes", ("papyrusextender", "papyrus extender", "po3_papyrusextender")),
    Source("gh_baseobjectswapper", "github_releases", "powerof3/BaseObjectSwapper",
           "Base Object Swapper — versions récentes", ("baseobjectswapper", "base object swapper")),
    Source("gh_skse", "github_releases", "ianpatt/skse64",
           "SKSE64 — versions publiées", ("skse64", "skse", "address library")),
    Source("gh_loot", "github_releases", "loot/loot",
           "LOOT — versions récentes", ("loot", "masterlist", "load order")),
    Source("gh_mo2", "github_releases", "ModOrganizer2/modorganizer",
           "Mod Organizer 2 — versions récentes", ("mo2", "mod organizer", "usvfs")),
    Source("gh_mo2_issues", "github_issues", "ModOrganizer2/modorganizer",
           "Mod Organizer 2 — crashs signalés", ("mo2", "mod organizer", "usvfs")),
    Source("gh_wabbajack", "github_releases", "wabbajack-tools/wabbajack",
           "Wabbajack — versions récentes", ("wabbajack",)),
    Source("gh_enginefixes", "github_releases", "aers/EngineFixesSkyrim64",
           "SSE Engine Fixes — versions récentes", ("enginefixes", "engine fixes", "tbbmalloc", "enginefixes.toml")),
    Source("gh_enginefixes_issues", "github_issues", "aers/EngineFixesSkyrim64",
           "SSE Engine Fixes — crashs signalés", ("enginefixes", "engine fixes", "tbbmalloc")),
    Source("gh_spid", "github_releases", "powerof3/Spell-Perk-Item-Distributor",
           "Spell Perk Item Distributor (SPID) — versions récentes", ("po3_spellperkitemdistributor", "spid", "_distr.ini")),
    Source("gh_kid", "github_releases", "powerof3/Keyword-Item-Distributor",
           "Keyword Item Distributor (KID) — versions récentes", ("po3_keyworditemdistributor", "_kid.ini")),
    Source("gh_dxmt", "github_releases", "3Shain/dxmt",
           "DXMT (Direct3D 11 sur Metal, CrossOver) — versions récentes", ("dxmt", "d3d11.dll", "metal", "crossover")),
    Source("gh_dxvk", "github_releases", "doitsujin/dxvk",
           "DXVK (Direct3D sur Vulkan) — versions récentes", ("dxvk", "d3d11.dll", "dxgi.dll", "vulkan")),
    Source("steam_skyrim", "steam_news", str(STEAM_APPID),
           "Skyrim SE/AE — annonces de mises à jour (Steam)", ("skyrimse.exe", "address library", "versionlib")),
    Source("reddit_crash", "reddit_rss", "CTD OR crash",
           "r/skyrimmods — fils récents sur les crashs", ()),
    Source("reddit_mac", "reddit_rss", "macgaming:skyrim",
           "r/macgaming — Skyrim sur Mac (CrossOver, GPTK)", ("crossover", "wine", "virtualapple", "d3dmetal", "dxmt")),
    Source("crossover_changelog", "crossover_changelog", "https://www.codeweavers.com/crossover/changelog",
           "CrossOver — journal des versions (CodeWeavers)", ("crossover", "wine", "virtualapple", "d3dmetal", "dxmt", "moltenvk")),
    Source("skse_site", "skse_site", "https://skse.silverlock.org/",
           "SKSE — page officielle des versions", ("skse", "skse64", "runtime", "address library")),
)

# ------------------------------------------------------------------ nettoyage
_INJECTION = re.compile(
    r"(ignore|disregard|forget)\s+(all\s+|any\s+)?(previous|prior|above|earlier)\s+(instructions?|prompts?)"
    r"|system\s+prompt|you\s+are\s+now\b|nouvelle?s?\s+instructions?\s*:|ignore\s+les\s+instructions", re.I)
_TAG = re.compile(r"<[^>]+>")
_MDLINK = re.compile(r"\[([^\]]*)\]\((?:[^)]*)\)")
_URL = re.compile(r"https?://\S+")
_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
_DLL = re.compile(r"\b([A-Za-z0-9_+\-]{4,60})\.dll\b", re.I)
_VER = re.compile(r"\b1\.[56]\.\d{2,4}\b")


def clean(text: str, limit: int = 400) -> str:
    """Texte brut sûr et court : sans HTML/URL/Markdown lourd, sans lignes d'injection."""
    t = html.unescape(str(text or ""))
    t = _TAG.sub(" ", t)
    t = _MDLINK.sub(r"\1", t)
    t = _URL.sub("", t)
    t = _CTRL.sub(" ", t)
    t = t.replace("`", "'").replace("---", "—")
    lines = []
    for ln in t.splitlines():
        ln = re.sub(r"[#>*_|]+", " ", ln)
        ln = re.sub(r"\s+", " ", ln).strip()
        if not ln:
            continue
        if _INJECTION.search(ln):
            ln = "[ligne retirée]"
        lines.append(ln)
    out = " ".join(lines)
    return out[:limit].rstrip() + ("…" if len(out) > limit else "")


def extract_keywords(*texts: str) -> list:
    """Noms de DLL (avec et sans extension) et versions du jeu cités dans les textes."""
    kws = []
    for t in texts:
        for m in _DLL.finditer(t):
            stem = m.group(1).lower()
            kws.append(stem + ".dll")
            if len(stem) >= 6:
                kws.append(stem)
        kws.extend(v for v in _VER.findall(t))
    seen, out = set(), []
    for k in kws:
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out[:40]


# --------------------------------------------------------------------- HTTP
def _check_url(url: str) -> None:
    p = urllib.parse.urlparse(url)
    if p.scheme != "https" or p.hostname not in ALLOWED_HOSTS:
        raise UpdateError(f"URL non autorisée : {p.hostname}")


def http_get(url: str, etag: str | None = None, accept: str = "application/json") -> tuple:
    """GET borné. Retourne (status, corps, etag). 304 → corps vide."""
    _check_url(url)
    headers = {"User-Agent": UA, "Accept": accept}
    if etag:
        headers["If-None-Match"] = etag
    token = os.environ.get("GITHUB_TOKEN")
    if token and urllib.parse.urlparse(url).hostname == "api.github.com":
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            _check_url(resp.geturl())
            body = resp.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                raise UpdateError("réponse trop volumineuse")
            return resp.status, body, resp.headers.get("ETag")
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return 304, b"", etag
        if e.code in (403, 429):
            raise RateLimited(f"quota ou accès refusé ({e.code})")
        raise UpdateError(f"HTTP {e.code}")
    except urllib.error.URLError as e:
        raise UpdateError(f"réseau : {e.reason}")
    except (TimeoutError, OSError) as e:
        raise UpdateError(f"réseau : {e}")


def _json(body: bytes):
    try:
        return json.loads(body.decode("utf-8", errors="replace"))
    except ValueError:
        raise UpdateError("JSON illisible")


def _date(s: str) -> str:
    return str(s or "")[:10]


# -------------------------------------------------------------------- parseurs
def parse_github_releases(body: bytes, repo: str) -> list:
    items = []
    for r in _json(body)[:12]:
        tag = clean(r.get("tag_name", ""), 40)
        if not tag or re.search(r"(?i)(?:^|[-_.])pr\d+|nightly|dev\b", tag):
            continue  # builds de PR/nightly : bruit
        items.append(f"{tag} ({_date(r.get('published_at'))})"
                     f"{' [préversion]' if r.get('prerelease') else ''} : "
                     f"{clean(r.get('body') or r.get('name') or '', 380)}")
        if len(items) >= 4:
            break
    return items


def parse_github_issues(body: bytes, repo: str) -> list:
    data = _json(body)
    items = []
    for it in (data.get("items") if isinstance(data, dict) else data) or []:
        if "pull_request" in it:
            continue
        labels = ",".join(clean(lb.get("name", ""), 20) for lb in it.get("labels", [])[:4])
        items.append(f"#{it.get('number')} [{it.get('state')}] {clean(it.get('title', ''), 140)} "
                     f"({_date(it.get('updated_at'))}{', ' + labels if labels else ''}) : "
                     f"{clean(it.get('body') or '', 220)}")
        if len(items) >= 8:
            break
    return items


_STEAM_RELEVANT = re.compile(r"(?i)update|patch|hotfix|fix|crash|version|\b1\.[56]\.\d+")


def parse_steam_news(body: bytes, _target: str) -> list:
    items = []
    for n in (_json(body).get("appnews", {}).get("newsitems", []) or [])[:25]:
        text = f"{n.get('title', '')} {n.get('contents', '')}"
        if not _STEAM_RELEVANT.search(text):
            continue
        d = datetime.fromtimestamp(int(n.get("date", 0)), timezone.utc).strftime("%Y-%m-%d") if n.get("date") else ""
        items.append(f"{d} {clean(n.get('title', ''), 140)} : {clean(n.get('contents', ''), 300)}")
        if len(items) >= 6:
            break
    return items


_REDDIT_RELEVANT = re.compile(r"(?i)crash|ctd|freez|won'?t (launch|start)|black screen|access violation|\.dll")


def parse_reddit_rss(body: bytes, _target: str) -> list:
    raw = body.decode("utf-8", errors="replace")
    if re.search(r"<!(DOCTYPE|ENTITY)", raw, re.I):
        raise UpdateError("flux XML refusé (DTD)")
    try:
        root = ET.fromstring(raw)
    except ET.ParseError:
        raise UpdateError("flux RSS illisible")
    ns = {"a": "http://www.w3.org/2005/Atom"}
    items = []
    for e in root.findall("a:entry", ns)[:25]:
        title = e.findtext("a:title", "", ns)
        content = e.findtext("a:content", "", ns)
        if not _REDDIT_RELEVANT.search(title + " " + content):
            continue
        items.append(f"{_date(e.findtext('a:updated', '', ns))} {clean(title, 150)} : {clean(content, 260)}")
        if len(items) >= 8:
            break
    return items


_CX_VERSION = re.compile(r'<a name="([\d.]+)"></a>\s*<span[^>]*>(.*?)</span>(.*?)(?=<a name="|$)', re.S)
_CX_ITEM = re.compile(r"<li>(?!\s*<span)(.*?)</li>", re.S)
_CX_RELEVANT = re.compile(r"skyrim|bethesda|direct3d|d3d1[01]|dxmt|d3dmetal|metal|crash|freeze|hang", re.I)


def parse_crossover_changelog(body: bytes, _target: str) -> list:
    """Les 6 dernières versions de CrossOver, avec en priorité les correctifs utiles (D3D, Metal, crash, Skyrim)."""
    raw = body.decode("utf-8", errors="replace")
    items = []
    for m in list(_CX_VERSION.finditer(raw))[:6]:
        head = clean(m.group(2), 80)
        fixes = [clean(x, 160) for x in _CX_ITEM.findall(m.group(3))]
        fixes = [f for f in fixes if f]
        useful = [f for f in fixes if _CX_RELEVANT.search(f)] or fixes[:2]
        items.append(f"{head} : " + " ; ".join(useful[:4]))
    return items


def parse_skse_site(body: bytes, _target: str) -> list:
    text = _TAG.sub("\n", body.decode("utf-8", errors="replace"))
    out = []
    for ln in text.splitlines():
        ln = clean(ln, 200)
        if ln and re.search(r"(?i)(skyrim|runtime|build|skse).*\d+\.\d+\.\d+|\d+\.\d+\.\d+.*(skyrim|runtime|build)", ln):
            if ln not in out:
                out.append(ln)
        if len(out) >= 12:
            break
    return out


# ---------------------------------------------------------------------- sources
def _request_for(src: Source) -> tuple:
    """(url, accept, parseur)."""
    if src.kind == "github_releases":
        return (f"https://api.github.com/repos/{src.target}/releases?per_page=8",
                "application/vnd.github+json", parse_github_releases)
    if src.kind == "github_issues":
        q = f"repo:{src.target} is:issue (crash OR CTD OR freeze) in:title"
        return ("https://api.github.com/search/issues?sort=updated&per_page=10&q=" + urllib.parse.quote(q),
                "application/vnd.github+json", parse_github_issues)
    if src.kind == "steam_news":
        return (f"https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid={int(src.target)}"
                "&count=25&maxlength=500", "application/json", parse_steam_news)
    if src.kind == "reddit_rss":
        sub, _, query = src.target.rpartition(":")  # "sous:requête", sinon r/skyrimmods
        return (f"https://www.reddit.com/r/{sub or 'skyrimmods'}/search.rss?restrict_sr=1&sort=new&q="
                + urllib.parse.quote(query), "application/atom+xml", parse_reddit_rss)
    if src.kind == "crossover_changelog":
        return (src.target, "text/html", parse_crossover_changelog)
    if src.kind == "skse_site":
        return (src.target, "text/html", parse_skse_site)
    raise UpdateError(f"type de source inconnu : {src.kind}")


def render_note(src: Source, items: list, fetched: str) -> str:
    kws = list(dict.fromkeys([*src.keywords, *extract_keywords(*items)]))
    body = "\n".join(f"- {it}" for it in items)
    note = (f"---\ntitle: Veille — {src.title}\nkeywords: {', '.join(kws)}\nauto: true\n"
            f"updated: {fetched}\n---\n"
            f"Source externe automatique ({fetched}), NON vérifiée : indice à recouper avec les logs.\n{body}\n")
    return note[:MAX_NOTE_CHARS]


# ------------------------------------------------------------------------ état
def _state_path(out_dir: Path) -> Path:
    return Path(out_dir) / STATE_NAME


def load_state(out_dir: Path | None = None) -> dict:
    try:
        d = json.loads(_state_path(out_dir or KNOWLEDGE_DIR).read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_state(out_dir: Path, state: dict) -> None:
    try:
        Path(out_dir).mkdir(parents=True, exist_ok=True)
        _state_path(out_dir).write_text(json.dumps(state, indent=1), encoding="utf-8")
    except OSError:
        pass


def due(interval_h: float = DEFAULT_INTERVAL_H, out_dir: Path | None = None, now: float | None = None) -> bool:
    last = load_state(out_dir).get("last_run", 0)
    return ((now if now is not None else time.time()) - float(last or 0)) >= interval_h * 3600


def status(out_dir: Path | None = None) -> dict:
    d = Path(out_dir or KNOWLEDGE_DIR)
    st = load_state(d)
    try:
        n = len(list(d.glob("auto_*.md")))
    except OSError:
        n = 0
    return {"last_run": st.get("last_run"), "files": n, "dir": str(d)}


@dataclass
class Report:
    updated: list = field(default_factory=list)
    unchanged: list = field(default_factory=list)
    failed: dict = field(default_factory=dict)
    skipped: bool = False


def update_all(out_dir: Path | None = None, force: bool = False, sources=None, fetch=http_get,
               progress=None, sleep=time.sleep) -> Report:
    """Récupère les sources et réécrit les notes. Tolérant : une source en échec n'arrête pas les autres."""
    out = Path(out_dir or KNOWLEDGE_DIR)
    rep = Report()
    if not _LOCK.acquire(blocking=False):
        rep.skipped = True
        return rep
    try:
        state = load_state(out)
        etags = state.setdefault("etags", {})
        srcs = state.setdefault("sources", {})
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        blocked_hosts = set()
        last_call = {}
        try:
            out.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            rep.failed["*"] = f"dossier inaccessible : {e}"
            return rep
        for src in (sources or SOURCES):
            if progress:
                progress(src.title)
            try:
                url, accept, parser = _request_for(src)
                host = urllib.parse.urlparse(url).hostname
                if host in blocked_hosts:
                    raise RateLimited("hôte ignoré (quota atteint)")
                if host in SLOW_HOSTS and host in last_call:
                    sleep(max(0.0, SLOW_HOSTS[host] - (time.time() - last_call[host])))
                last_call[host] = time.time()
                path = out / f"auto_{src.id}.md"
                status_code, body, etag = fetch(url, None if (force or not path.exists()) else etags.get(url), accept)
                if status_code == 304:
                    rep.unchanged.append(src.id)
                    srcs[src.id] = {"ok": True, "fetched": time.time(), "count": srcs.get(src.id, {}).get("count", 0)}
                    continue
                items = parser(body, src.target)
                if not items:
                    rep.unchanged.append(src.id)  # rien de pertinent : on garde l'ancienne note
                    srcs[src.id] = {"ok": True, "fetched": time.time(), "count": 0}
                    continue
                tmp = path.with_suffix(".tmp")
                tmp.write_text(render_note(src, items, now), encoding="utf-8")
                os.replace(tmp, path)
                if etag:
                    etags[url] = etag
                rep.updated.append(src.id)
                srcs[src.id] = {"ok": True, "fetched": time.time(), "count": len(items)}
            except RateLimited as e:
                blocked_hosts.add(urllib.parse.urlparse(_request_for(src)[0]).hostname)
                rep.failed[src.id] = str(e)
                srcs[src.id] = {"ok": False, "error": str(e), "fetched": time.time()}
            except (UpdateError, OSError) as e:
                rep.failed[src.id] = str(e)
                srcs[src.id] = {"ok": False, "error": str(e), "fetched": time.time()}
            sleep(0.15)  # courtoisie envers les API
        if len(rep.failed) < len(sources or SOURCES):  # au moins une source a répondu
            state["last_run"] = time.time()
        _save_state(out, state)
        return rep
    finally:
        _LOCK.release()


def main(argv: list) -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", help="dossier de sortie (défaut : dossier utilisateur)")
    ap.add_argument("--force", action="store_true", help="ignorer les ETag et le délai")
    a = ap.parse_args(argv)
    out = Path(a.out) if a.out else KNOWLEDGE_DIR
    if not a.force and not due(out_dir=out):
        print("À jour (dernière exécution < 24 h). Utilisez --force.")
        return 0
    rep = update_all(out, force=a.force, progress=lambda t: print(" •", t))
    print(f"mises à jour : {len(rep.updated)} | inchangées : {len(rep.unchanged)} | échecs : {len(rep.failed)}")
    for k, v in rep.failed.items():
        print(f"   ! {k}: {v}")
    return 0 if len(rep.failed) < len(SOURCES) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
