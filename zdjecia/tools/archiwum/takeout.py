"""Eksport Google Takeout: lista zdjęć z ZIP-ów (albo rozpakowanych folderów) i ich daty z plików JSON.

Takeout dzieli bibliotekę na ZIP-y po 2-50 GB; zdjęcie i jego JSON mogą trafić do różnych ZIP-ów,
więc najpierw zbieramy wszystkie pliki, potem dopasowujemy JSON-y w obrębie tego samego folderu.
Nazwy JSON-ów Google skraca do 51 znaków, a duplikaty nazw dostają licznik „(1)” w różnych miejscach -
stąd kilka wariantów nazwy do sprawdzenia ([sidecar_names]) i zapas: pole „title” w JSON-ie.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import zipfile
from dataclasses import dataclass, field
from pathlib import PurePosixPath

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}

# Foldery bez wartości dla wspomnień (kosz, zablokowane)
SKIP_FOLDERS = re.compile(r"(^|/)(kosz|trash|bin|locked folder|folder zablokowany)(/|$)", re.I)

# Zrzuty ekranu, komunikatory, pobrane - po nazwie pliku
SKIP_NAMES = re.compile(
    r"(screenshot|zrzut|screen_shot|screenrecord|whatsapp|messenger|received_\d|"
    r"^img-\d{8}-wa\d+|-wa\d{4}|^fb_img|^snapchat|^signal-\d)",
    re.I,
)

# Wersja edytowana w Zdjęciach Google (nazwa zależy od języka konta)
EDITED = re.compile(r"-(edited|edytowane|bearbeitet|modifié|editado|modificato)$", re.I)

# Licznik duplikatu w nazwie: IMG_1234(1).jpg
COUNTER = re.compile(r"^(.*?)(\(\d+\))$")

JSON_LIMIT = 51


@dataclass
class Entry:
    """Plik w eksporcie: [container] = ścieżka ZIP-a albo '' (zwykły plik), [member] = ścieżka w środku."""

    container: str
    member: str
    size: int

    @property
    def folder(self) -> str:
        return str(PurePosixPath(self.member).parent)

    @property
    def name(self) -> str:
        return PurePosixPath(self.member).name


@dataclass
class Photo:
    entry: Entry
    title: str  # nazwa oryginału (z JSON-a albo z pliku)
    taken_ms: int | None  # z JSON-a; None = brak (wtedy EXIF w skanie)
    edited: bool = False
    favorite: bool = False
    people: list[str] = field(default_factory=list)
    lat: float | None = None
    lon: float | None = None

    @property
    def id(self) -> str:
        return photo_id(self.title, self.taken_ms or 0, self.entry.size, self.edited)


def photo_id(title: str, taken_ms: int, size: int, edited: bool) -> str:
    raw = f"{title.lower()}|{taken_ms}|{size}|{'e' if edited else 'o'}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:12]


def split_counter(name: str) -> tuple[str, str]:
    """IMG_1234(1).jpg -> ('IMG_1234.jpg', '(1)')"""
    stem, ext = os.path.splitext(name)
    m = COUNTER.match(stem)
    if not m:
        return name, ""
    return m.group(1) + ext, m.group(2)


def original_name(name: str) -> tuple[str, bool]:
    """Nazwa oryginału dla wersji edytowanej: IMG_1-edited.jpg -> ('IMG_1.jpg', True)"""
    stem, ext = os.path.splitext(name)
    m = EDITED.search(stem)
    if not m:
        return name, False
    return stem[: m.start()] + ext, True


def sidecar_names(image_name: str) -> list[str]:
    """Możliwe nazwy pliku JSON dla zdjęcia (od najbardziej prawdopodobnej)."""
    base, edited = original_name(image_name)
    plain, counter = split_counter(base)
    stem = os.path.splitext(plain)[0]
    out: list[str] = []

    def add(prefix: str, suffix: str = ".json") -> None:
        for limit in (JSON_LIMIT, JSON_LIMIT - 4, None):
            room = None if limit is None else limit - len(counter) - len(suffix)
            if room is not None and room <= 0:
                continue
            p = prefix if room is None else prefix[:room]
            for cand in (p + counter + suffix, p + suffix + counter if counter else None):
                if cand and cand not in out:
                    out.append(cand)

    add(plain + ".supplemental-metadata")
    add(plain)
    add(stem)
    # Stary zapis licznika: IMG_1234.jpg(1).json
    if counter:
        for cand in (f"{plain}{counter}.json", f"{plain}.supplemental-metadata{counter}.json"):
            if cand not in out:
                out.append(cand)
    return out


def is_image(name: str) -> bool:
    return os.path.splitext(name)[1].lower() in IMAGE_EXT


def skip_reason(entry: Entry) -> str | None:
    if SKIP_FOLDERS.search(entry.folder):
        return "kosz/zablokowane"
    if SKIP_NAMES.search(entry.name):
        return "zrzut/komunikator"
    return None


def list_entries(paths: list[str]) -> list[Entry]:
    """Wszystkie pliki z podanych ZIP-ów i folderów (foldery przeszukiwane rekurencyjnie, z ZIP-ami w środku)."""
    out: list[Entry] = []
    for root in paths:
        if os.path.isfile(root) and root.lower().endswith(".zip"):
            out.extend(_zip_entries(root))
            continue
        for dirpath, _dirs, files in os.walk(root):
            for f in files:
                full = os.path.join(dirpath, f)
                if f.lower().endswith(".zip"):
                    out.extend(_zip_entries(full))
                elif is_image(f) or f.lower().endswith(".json"):
                    rel = os.path.relpath(full, root).replace(os.sep, "/")
                    out.append(Entry(container="", member=os.path.join(root, rel).replace(os.sep, "/"), size=os.path.getsize(full)))
    return out


def _zip_entries(path: str) -> list[Entry]:
    with zipfile.ZipFile(path) as z:
        return [
            Entry(container=path, member=i.filename, size=i.file_size)
            for i in z.infolist()
            if not i.is_dir() and (is_image(i.filename) or i.filename.lower().endswith(".json"))
        ]


class Reader:
    """Czyta pliki z ZIP-ów (otwarte ZIP-y trzyma do zamknięcia)."""

    def __init__(self) -> None:
        self._zips: dict[str, zipfile.ZipFile] = {}

    def read(self, e: Entry) -> bytes:
        if not e.container:
            with open(e.member, "rb") as f:
                return f.read()
        z = self._zips.get(e.container)
        if z is None:
            z = self._zips[e.container] = zipfile.ZipFile(e.container)
        return z.read(e.member)

    def close(self) -> None:
        for z in self._zips.values():
            z.close()
        self._zips.clear()


def parse_sidecar(data: bytes) -> dict:
    try:
        j = json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {}
    return j if isinstance(j, dict) else {}


def sidecar_info(j: dict) -> dict:
    """Data zrobienia (ms), ulubione, osoby i miejsce z JSON-a Takeoutu."""
    out: dict = {"title": j.get("title") if isinstance(j.get("title"), str) else None}
    for key in ("photoTakenTime", "creationTime"):
        t = j.get(key)
        if isinstance(t, dict):
            try:
                ts = int(t.get("timestamp"))
            except (TypeError, ValueError):
                continue
            if ts > 0:
                out["taken_ms"] = ts * 1000
                out["taken_from"] = key
                break
    out["favorite"] = j.get("favorited") is True
    people = j.get("people")
    if isinstance(people, list):
        out["people"] = [p["name"] for p in people if isinstance(p, dict) and isinstance(p.get("name"), str) and p["name"]]
    geo = j.get("geoDataExif") or j.get("geoData")
    if isinstance(geo, dict):
        lat, lon = geo.get("latitude"), geo.get("longitude")
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)) and (lat or lon):
            out["lat"], out["lon"] = float(lat), float(lon)
    return out


def match_photos(entries: list[Entry], reader: Reader) -> tuple[list[Photo], dict[str, int]]:
    """Zdjęcia z danymi z JSON-ów. Zwraca też liczniki pominiętych (do raportu)."""
    stats: dict[str, int] = {}
    jsons: dict[str, dict[str, Entry]] = {}
    for e in entries:
        if e.name.lower().endswith(".json"):
            jsons.setdefault(e.folder, {})[e.name] = e
    title_cache: dict[str, dict[str, list[Entry]]] = {}

    def by_title(folder: str) -> dict[str, list[Entry]]:
        m = title_cache.get(folder)
        if m is None:
            m = {}
            for je in jsons.get(folder, {}).values():
                t = sidecar_info(parse_sidecar(reader.read(je))).get("title")
                if t:
                    m.setdefault(t, []).append(je)
            title_cache[folder] = m
        return m

    photos: list[Photo] = []
    for e in entries:
        if not is_image(e.name):
            continue
        reason = skip_reason(e)
        if reason:
            stats[reason] = stats.get(reason, 0) + 1
            continue
        folder_jsons = jsons.get(e.folder, {})
        side = next((folder_jsons[n] for n in sidecar_names(e.name) if n in folder_jsons), None)
        base, edited = original_name(e.name)
        plain, _counter = split_counter(base)
        if side is None:
            cands = by_title(e.folder).get(plain) or []
            side = cands[0] if len(cands) == 1 else None
        info = sidecar_info(parse_sidecar(reader.read(side))) if side is not None else {}
        if side is None:
            stats["bez JSON-a"] = stats.get("bez JSON-a", 0) + 1
        photos.append(
            Photo(
                entry=e,
                title=info.get("title") or plain,
                taken_ms=info.get("taken_ms"),
                edited=edited,
                favorite=bool(info.get("favorite")),
                people=info.get("people") or [],
                lat=info.get("lat"),
                lon=info.get("lon"),
            )
        )
    return dedupe(photos, stats), stats


def dedupe(photos: list[Photo], stats: dict[str, int]) -> list[Photo]:
    """To samo zdjęcie w „Photos from RRRR” i w albumach - jedno. Gdy jest wersja edytowana, oryginał odpada."""
    seen: dict[str, Photo] = {}
    for p in photos:
        key = p.id
        if key in seen:
            stats["duplikat (album)"] = stats.get("duplikat (album)", 0) + 1
            continue
        seen[key] = p
    edited_keys = {(p.entry.folder, original_name(p.entry.name)[0]) for p in seen.values() if p.edited}
    out = []
    for p in seen.values():
        if not p.edited and (p.entry.folder, p.entry.name) in edited_keys:
            stats["oryginał (jest edytowana)"] = stats.get("oryginał (jest edytowana)", 0) + 1
            continue
        out.append(p)
    return out
