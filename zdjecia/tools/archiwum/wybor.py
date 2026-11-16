"""Czysta logika wyboru (testy w test_archiwum.py):
1. odsiew techniczny (za małe, rozmazane, ciemne, grafiki, bez daty),
2. wydarzenia (przerwa > 3 h) i serie (te same ujęcia w ciągu 90 s) - z serii zostaje najlepsze,
3. kandydaci do przeglądu: kilka najlepszych z wydarzenia, lata wyrównane (rzadkie lata dostają więcej),
4. wybór końcowy z ocen przeglądu: najlepsze, z limitem na wydarzenie, dzień i rok.
Wpis = słownik z katalogu (katalog.jsonl): id, taken, w, h, sharp, sharp_cell, mean, color, dhash, faces, ...
"""
from __future__ import annotations

import bisect
import math
from collections import defaultdict
from datetime import datetime

EVENT_GAP_MS = 3 * 3600 * 1000
BURST_MS = 90 * 1000
BURST_HAMMING = 14
DUPLICATE_HAMMING = 4

MIN_SIDE = 480
MAX_ASPECT = 2.4
MIN_SHARP_PCT = 0.08
MIN_SHARP = 8.0

PICK_SCORE = 6  # od tej oceny przeglądu zdjęcie może trafić do archiwum
PER_EVENT = 3
PER_DAY = 4


def taken_ms(e: dict) -> int | None:
    return e.get("taken") or None


def reject_reason(e: dict, sharp_pct: float) -> str | None:
    if e.get("error"):
        return "nieczytelne"
    if not taken_ms(e):
        return "bez daty"
    w, h = e.get("w") or 0, e.get("h") or 0
    if min(w, h) < MIN_SIDE:
        return "za małe"
    if max(w, h) / max(1, min(w, h)) > MAX_ASPECT:
        return "panorama/pasek"
    if e.get("fmt") == "PNG" and not e.get("camera"):
        return "grafika"
    # Najpierw naświetlenie: ciemne zdjęcie ma też mało szczegółów, ale to nie rozmycie
    if e.get("mean", 0.5) < 0.07:
        return "ciemne"
    if e.get("mean", 0.5) > 0.93:
        return "prześwietlone"
    if e.get("sharp_cell", 0) < MIN_SHARP or sharp_pct < MIN_SHARP_PCT:
        return "rozmazane"
    return None


class Percentiles:
    def __init__(self, values: list[float]) -> None:
        self.sorted = sorted(values)

    def __call__(self, v: float) -> float:
        if not self.sorted:
            return 0.5
        return bisect.bisect_left(self.sorted, v) / len(self.sorted)


def largest_face(e: dict) -> float:
    return max((f[2] * f[3] for f in e.get("faces") or []), default=0.0)


def tech_score(e: dict, sharp_cell_pct: float, sharp_pct: float, color_pct: float) -> float:
    exposure = 1 - min(1.0, abs(e.get("mean", 0.47) - 0.47) / 0.35)
    if e.get("dark", 0) > 0.4:
        exposure -= 0.3
    if e.get("bright", 0) > 0.25:
        exposure -= 0.3
    face = largest_face(e)
    faces = 0.25 if face >= 0.04 else 0.15 if face >= 0.01 else 0.05 if face > 0 else 0.0
    return round(
        0.35 * sharp_cell_pct
        + 0.15 * sharp_pct
        + 0.15 * color_pct
        + 0.2 * exposure
        + faces
        + (0.5 if e.get("favorite") else 0.0)
        + (0.1 if e.get("people") else 0.0),
        4,
    )


def score_all(entries: list[dict]) -> tuple[list[dict], dict[str, int]]:
    """Wpisy przyjęte (z polem 'score') i liczniki odrzuconych wg powodu."""
    usable = [e for e in entries if not e.get("error")]
    sharp_cell = Percentiles([math.log1p(e.get("sharp_cell", 0)) for e in usable])
    sharp = Percentiles([math.log1p(e.get("sharp", 0)) for e in usable])
    color = Percentiles([e.get("color", 0) for e in usable])
    kept, rejected = [], defaultdict(int)
    for e in entries:
        sc = sharp_cell(math.log1p(e.get("sharp_cell", 0)))
        reason = reject_reason(e, sc)
        if reason:
            rejected[reason] += 1
            continue
        kept.append({**e, "score": tech_score(e, sc, sharp(math.log1p(e.get("sharp", 0))), color(e.get("color", 0)))})
    return kept, dict(rejected)


def events(entries: list[dict], gap_ms: int = EVENT_GAP_MS) -> list[list[dict]]:
    out: list[list[dict]] = []
    last = None
    for e in sorted(entries, key=lambda x: (taken_ms(x), x["id"])):
        t = taken_ms(e)
        if last is None or t - last > gap_ms:
            out.append([])
        out[-1].append(e)
        last = t
    return out


def bursts(event: list[dict]) -> list[list[dict]]:
    """Serie i powtórki w wydarzeniu: podobny odcisk w ciągu 90 s albo prawie identyczny w ogóle."""
    groups: list[list[dict]] = []
    for e in event:
        home = None
        for g in groups:
            for o in g:
                d = bin(int(e.get("dhash", 0)) ^ int(o.get("dhash", 0))).count("1")
                near = abs(taken_ms(e) - taken_ms(o)) <= BURST_MS
                if d <= DUPLICATE_HAMMING or (near and d <= BURST_HAMMING):
                    home = g
                    break
            if home:
                break
        if home is None:
            groups.append([e])
        else:
            home.append(e)
    return groups


def event_quota(groups: int) -> int:
    return min(groups, 10, 1 + round(1.6 * math.log2(max(1, groups))))


def year_of(e: dict) -> int:
    return datetime.fromtimestamp(taken_ms(e) / 1000).year


def day_of(e: dict) -> str:
    return datetime.fromtimestamp(taken_ms(e) / 1000).strftime("%Y-%m-%d")


def allocate(counts: dict[int, int], total: int) -> dict[int, int]:
    """Miejsca na lata proporcjonalnie do pierwiastka z liczby zdjęć (rzadkie lata zyskują), najwyżej tyle, ile jest."""
    alloc = {y: 0 for y in counts}
    left = total
    open_years = {y for y, c in counts.items() if c > 0}
    while left > 0 and open_years:
        weight = sum(math.sqrt(counts[y]) for y in open_years)
        given = 0
        for y in sorted(open_years):
            share = max(1, int(left * math.sqrt(counts[y]) / weight))
            take = min(share, counts[y] - alloc[y], left - given)
            alloc[y] += take
            given += take
            if given >= left:
                break
        left -= given
        open_years = {y for y in open_years if alloc[y] < counts[y]}
        if given == 0:
            break
    return alloc


def candidates(entries: list[dict], target: int) -> list[dict]:
    """Najlepsze z każdego wydarzenia (bez serii), potem lata wyrównane do [target]. Chronologicznie."""
    pool: list[dict] = []
    for ev in events(entries):
        groups = [max(g, key=lambda x: x["score"]) for g in bursts(ev)]
        groups.sort(key=lambda x: -x["score"])
        pool.extend(groups[: event_quota(len(groups))])
    if len(pool) > target:
        by_year: dict[int, list[dict]] = defaultdict(list)
        for e in pool:
            by_year[year_of(e)].append(e)
        alloc = allocate({y: len(v) for y, v in by_year.items()}, target)
        pool = [e for y, v in by_year.items() for e in sorted(v, key=lambda x: -x["score"])[: alloc[y]]]
    return sorted(pool, key=lambda x: (taken_ms(x), x["id"]))


def final_choice(cands: list[dict], reviews: dict[str, dict], count: int) -> list[dict]:
    """Z ocen przeglądu: ocena ≥ [PICK_SCORE], najlepsze najpierw, limity na wydarzenie / dzień / rok
    (limity luzują się, gdy brakuje zdjęć do [count]). Zwraca wpisy z polami przeglądu, chronologicznie."""
    picked = []
    for e in cands:
        r = reviews.get(e["id"])
        if r and r.get("s", 0) >= PICK_SCORE:
            picked.append({**e, "review": r})
    if not picked:
        return []
    ev_of = {}
    for i, ev in enumerate(events(picked)):
        for e in ev:
            ev_of[e["id"]] = i
    years = {year_of(e) for e in picked}
    order = sorted(picked, key=lambda x: (-x["review"]["s"], -x["score"], x["id"]))
    chosen: dict[str, dict] = {}
    for relax in (1, 2, 4, 1000):
        per_year_cap = max(25, math.ceil(2.0 * count / len(years))) * relax
        ev_n, day_n, year_n = defaultdict(int), defaultdict(int), defaultdict(int)
        for e in chosen.values():
            ev_n[ev_of[e["id"]]] += 1
            day_n[day_of(e)] += 1
            year_n[year_of(e)] += 1
        for e in order:
            if len(chosen) >= count:
                break
            if e["id"] in chosen:
                continue
            ev, day, year = ev_of[e["id"]], day_of(e), year_of(e)
            if ev_n[ev] >= PER_EVENT * relax or day_n[day] >= PER_DAY * relax or year_n[year] >= per_year_cap:
                continue
            chosen[e["id"]] = e
            ev_n[ev] += 1
            day_n[day] += 1
            year_n[year] += 1
        if len(chosen) >= count:
            break
    return sorted(chosen.values(), key=lambda x: (taken_ms(x), x["id"]))


def export_size(w: int, h: int, max_long: int = 800, max_short: int = 600) -> tuple[int, int]:
    """Rozmiar po zmniejszeniu: dłuższy bok ≤ 800, krótszy ≤ 600, bez powiększania."""
    long_, short = max(w, h), min(w, h)
    scale = min(1.0, max_long / long_, max_short / short)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    return nw, nh


def clean_caption(text: str, limit: int = 28) -> str:
    t = " ".join(str(text or "").split())
    if len(t) <= limit:
        return t
    cut = t[: limit + 1].rsplit(" ", 1)[0]
    return (cut if len(cut) >= limit // 2 else t[:limit]).rstrip(" ,.;:-")


def clean_box(box) -> list[float] | None:
    """left, top, width, height w ułamkach; przycięte do zdjęcia; None = brak / nieprawidłowe"""
    if not isinstance(box, (list, tuple)) or len(box) != 4:
        return None
    try:
        l, t, w, h = (float(v) for v in box)
    except (TypeError, ValueError):
        return None
    l, t = min(max(l, 0.0), 1.0), min(max(t, 0.0), 1.0)
    w, h = min(max(w, 0.0), 1.0 - l), min(max(h, 0.0), 1.0 - t)
    if w < 0.05 or h < 0.05:
        return None
    return [round(l, 3), round(t, 3), round(w, 3), round(h, 3)]


def index_entry(e: dict, w: int, h: int) -> dict:
    """Wpis spisu w Firestore (ARCHIWUM.md)."""
    r = e.get("review") or {}
    out = {"id": e["id"], "t": int(taken_ms(e)), "c": clean_caption(r.get("c", "")), "s": int(r.get("s", 0)), "w": w, "h": h}
    f, m = clean_box(r.get("f")), clean_box(r.get("m"))
    if f:
        out["f"] = f
    if m:
        out["m"] = m
    if e.get("title"):
        out["n"] = e["title"]  # nazwa pliku - telefon nie doda drugi raz tego samego zdjęcia
    return out


# Zdjęcia dodane z telefonu (src "tel", ARCHIWUM.md) - to samo ujęcie co w Takeoucie: ta sama nazwa pliku
# i czas do 14 h różnicy (Zdjęcia Google i telefon potrafią inaczej liczyć strefę czasową)
PHONE_SOURCE = "tel"
SAME_SHOT_MS = 14 * 3600 * 1000


def same_shot(a: dict, b: dict) -> bool:
    na, nb = str(a.get("n") or "").casefold(), str(b.get("n") or "").casefold()
    if not na or na != nb:
        return False
    try:
        return abs(int(a["t"]) - int(b["t"])) <= SAME_SHOT_MS
    except (KeyError, TypeError, ValueError):
        return False


def merge_spis(new: list[dict], old: list[dict]) -> tuple[list[dict], list[str]]:
    """Spis z PC ([new]) + zdjęcia dodane z telefonu, które już są w bazie ([old] z src "tel").
    Zdjęcie z telefonu, które jest też w Takeoucie, ustępuje wersji z przeglądu (jego id - do usunięcia).
    Zwraca (spis chronologicznie, id zdjęć z telefonu do usunięcia z bazy)."""
    ids = {x["id"] for x in new}
    merged = list(new)
    dropped = []
    for x in old:
        if not isinstance(x, dict) or x.get("src") != PHONE_SOURCE or not x.get("id") or x["id"] in ids:
            continue
        if any(same_shot(x, y) for y in new):
            dropped.append(x["id"])
            continue
        ids.add(x["id"])
        merged.append(x)
    merged.sort(key=lambda x: (int(x.get("t", 0)), x["id"]))
    return merged, dropped
