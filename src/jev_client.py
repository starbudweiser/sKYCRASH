"""Client Jev (TypeSafe System One) : jugements typés (Choice, Noul, Score) sur un état donné.

Sans SDK : uniquement urllib, comme ai_client. La clé est lue dans le Trousseau macOS
(via `keyring`) ou la variable d'environnement TYPESAFE_API_KEY ; jamais écrite dans la config.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

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
            return json.loads(resp.read().decode("utf-8")).get("answers") or {}
    except urllib.error.HTTPError as e:
        raise JevError(L("Jev : erreur HTTP {code}.", code=e.code))
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise JevError(L("Jev : connexion impossible ({e}).", e=e))
    except ValueError:
        raise JevError(L("Jev : réponse illisible."))
