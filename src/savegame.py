"""Lecture de l'en-tête d'une sauvegarde Skyrim SE (.ess) : joueur, lieu, date, liste des plugins.

Lecture seule, sans dépendance : la partie compressée (LZ4 bloc ou zlib) n'est décompressée
que sur les premiers kilo-octets, là où se trouve la liste des plugins.
"""
from __future__ import annotations

import os
import struct
import zlib
from dataclasses import dataclass, field
from datetime import datetime, timezone

MAGIC = b"TESV_SAVEGAME"
_NEEDED = 256 * 1024  # la liste des plugins tient largement dans les premiers Ko décompressés


@dataclass
class SaveInfo:
    path: str
    player: str = ""
    level: int = 0
    location: str = ""
    saved_at: float = 0.0                       # horodatage POSIX (FILETIME de l'en-tête, sinon mtime)
    plugins: list = field(default_factory=list)  # plugins pleins, dans l'ordre de la sauvegarde
    light: list = field(default_factory=list)    # plugins légers (ESL)

    @property
    def all_plugins(self) -> list:
        return self.plugins + self.light


class _Reader:
    def __init__(self, data: bytes, pos: int = 0):
        self.d, self.p = data, pos

    def take(self, n: int) -> bytes:
        if self.p + n > len(self.d):
            raise ValueError("sauvegarde tronquée")
        out = self.d[self.p:self.p + n]
        self.p += n
        return out

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack("<H", self.take(2))[0]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.take(8))[0]

    def f32(self):
        return struct.unpack("<f", self.take(4))[0]

    def wstr(self) -> str:
        raw = self.take(self.u16())
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return raw.decode("cp1252", errors="replace")


def lz4_block_prefix(src: bytes, want: int) -> bytes:
    """Décompresse un bloc LZ4 jusqu'à obtenir au moins `want` octets (ou la fin du bloc)."""
    out = bytearray()
    i, n = 0, len(src)
    while i < n and len(out) < want:
        token = src[i]
        i += 1
        lit = token >> 4
        if lit == 15:
            while True:
                b = src[i]
                i += 1
                lit += b
                if b != 255:
                    break
        out += src[i:i + lit]
        i += lit
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        mlen = token & 15
        if mlen == 15:
            while True:
                b = src[i]
                i += 1
                mlen += b
                if b != 255:
                    break
        mlen += 4
        if offset == 0 or offset > len(out):
            raise ValueError("bloc LZ4 invalide")
        start = len(out) - offset
        for k in range(mlen):  # copie octet par octet : les recouvrements sont permis
            out.append(out[start + k])
    return bytes(out)


def read_save(path: str) -> SaveInfo:
    """Lit l'en-tête et la liste des plugins d'un .ess. Lève ValueError si le format est inconnu."""
    with open(path, "rb") as f:
        data = f.read()
    r = _Reader(data)
    if r.take(len(MAGIC)) != MAGIC:
        raise ValueError("pas une sauvegarde Skyrim")
    r.u32()  # taille de l'en-tête
    version = r.u32()
    r.u32()  # numéro de sauvegarde
    info = SaveInfo(path)
    info.player = r.wstr()
    info.level = r.u32()
    info.location = r.wstr()
    r.wstr()  # date en jeu
    r.wstr()  # race
    r.u16()   # sexe
    r.f32(), r.f32()
    filetime = r.u64()
    width, height = r.u32(), r.u32()
    compression = r.u16() if version >= 12 else 0
    r.take(width * height * (4 if version >= 12 else 3))
    try:
        info.saved_at = datetime(1601, 1, 1, tzinfo=timezone.utc).timestamp() + filetime / 1e7
    except (OverflowError, ValueError):
        info.saved_at = os.path.getmtime(path)
    if not 946684800 < info.saved_at < 4102444800:  # FILETIME incohérente : on garde la date du fichier
        info.saved_at = os.path.getmtime(path)

    if compression:
        r.u32()  # taille décompressée
        size = r.u32()
        packed = r.take(min(size, len(data) - r.p))
        if compression == 2:
            body = lz4_block_prefix(packed, _NEEDED)
        elif compression == 1:
            body = zlib.decompressobj().decompress(packed, _NEEDED)
        else:
            raise ValueError(f"compression inconnue ({compression})")
        b = _Reader(body)
    else:
        b = r
    form_version = b.u8()
    b.u32()  # taille du bloc plugins
    info.plugins = [b.wstr() for _ in range(b.u8())]
    if form_version >= 78:
        info.light = [b.wstr() for _ in range(b.u16())]
    return info


def saves_dir_for(game_docs: str) -> str:
    return os.path.join(game_docs, "Saves")


def latest_saves(saves_dir: str, before: float = None, limit: int = 5) -> list:
    """Chemins des .ess les plus récents (éventuellement antérieurs à `before`), du plus récent au plus ancien."""
    try:
        names = [n for n in os.listdir(saves_dir) if n.lower().endswith(".ess")]
    except OSError:
        return []
    items = []
    for n in names:
        p = os.path.join(saves_dir, n)
        try:
            m = os.path.getmtime(p)
        except OSError:
            continue
        if before is None or m <= before:
            items.append((m, p))
    items.sort(reverse=True)
    return [p for _m, p in items[:limit]]
