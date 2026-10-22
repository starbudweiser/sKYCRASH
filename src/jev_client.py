"""Client Jev (TypeSafe System One) : jugements typés (Choice, Noul, Score) sur un état donné.

Sans SDK : uniquement urllib, comme ai_client. La clé est lue dans le Trousseau macOS
(via `keyring`) ou la variable d'environnement TYPESAFE_API_KEY ; jamais écrite dans la config.
"""
from __future__ import annotations

import datetime
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

from i18n import L, N_

try:
    import keyring  # type: ignore
except Exception:  # keyring absent ou backend indisponible
    keyring = None

ENDPOINT = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
KEYRING_SERVICE = "SkyrimCrashAnalyzer"
KEYRING_USER = "typesafe_api_key"
TIMEOUT_S = 30
CONSOLE_URL = "https://console.typesafe.ai/"
# Consommation comptée par l'appli : l'API ne donne pas le solde de crédits, seulement les jetons de chaque réponse.
USAGE_FILE = Path.home() / "Library" / "Application Support" / "SkyrimCrashAnalyzer" / "jev_usage.json"


def _month() -> str:
    return datetime.date.today().strftime("%Y-%m")


def month_usage() -> dict:
    """Requêtes et jetons Jev du mois en cours (zéro au changement de mois)."""
    try:
        u = json.loads(USAGE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        u = {}
    if u.get("month") != _month():
        u = {}
    return {"month": _month(), "requests": int(u.get("requests", 0)),
            "input_tokens": int(u.get("input_tokens", 0)), "output_tokens": int(u.get("output_tokens", 0))}


def record_usage(input_tokens: int, output_tokens: int) -> None:
    u = month_usage()
    u["requests"] += 1
    u["input_tokens"] += int(input_tokens or 0)
    u["output_tokens"] += int(output_tokens or 0)
    try:
        USAGE_FILE.parent.mkdir(parents=True, exist_ok=True)
        USAGE_FILE.write_text(json.dumps(u), encoding="utf-8")
    except OSError:
        pass


class JevError(Exception):
    pass


def get_api_key_source() -> tuple:
    """(clé, source). Le trousseau prime sur l'environnement."""
    if keyring:
        try:
            k = keyring.get_password(KEYRING_SERVICE, KEYRING_USER)
            if k and k.strip():
                return k.strip(), N_("trousseau")
        except Exception:
            pass
    env = os.environ.get("TYPESAFE_API_KEY")
    if env and env.strip():
        return env.strip(), N_("variable d'environnement TYPESAFE_API_KEY")
    return None, N_("aucune")


def get_api_key():
    return get_api_key_source()[0]


def set_api_key(key: str) -> None:
    if not keyring:
        raise JevError(L("Module 'keyring' indisponible : définissez TYPESAFE_API_KEY dans l'environnement."))
    try:
        if key:
            keyring.set_password(KEYRING_SERVICE, KEYRING_USER, key.strip())
        else:
            keyring.delete_password(KEYRING_SERVICE, KEYRING_USER)
    except Exception as e:
        raise JevError(L("Trousseau inaccessible : {e}", e=e))


def system_one(state, questions: dict, model: str = MODEL, key: str | None = None) -> dict:
    """Pose `questions` sur `state` ; renvoie le dict `answers` (mêmes ids que les questions)."""
    key = key or get_api_key()
    if not key:
        raise JevError(L("Aucune clé TypeSafe (Jev)."))
    req = urllib.request.Request(
        ENDPOINT, data=json.dumps({"model": model, "state": state, "questions": questions}).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        usage = body.get("usage") or {}
        record_usage(usage.get("input_tokens", 0), usage.get("output_tokens", 0))
        return body.get("answers") or {}
    except urllib.error.HTTPError as e:
        raise JevError(L("Jev : erreur HTTP {code}.", code=e.code))
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise JevError(L("Jev : connexion impossible ({e}).", e=e))
    except ValueError:
        raise JevError(L("Jev : réponse illisible."))
