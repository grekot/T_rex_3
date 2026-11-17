"""Kolaże 2-3 zdjęć z jednego wydarzenia dla zegarów biurkowych (płótno 800×450, 16:9).

Zdjęcia biorą się z eksportu (to, co już jest w archiwum). Układy są różne (obok siebie, duże z wstawką,
duże i małe zachodzące na siebie, trójka, polaroidy w wachlarzu, okno na rozmytym tle), tła też: rozmyte
zdjęcie, papier, a okazjonalnie motyw (zima / święta, urodziny, wiosna, lato, jesień).

Ważna treść mieści się w środkowym pasie 4:3 (x 100-700), bo zegar 320×240 obetnie boki - wpis spisu
dostaje f = ten pas. Tło może sięgać krawędzi.
"""
from __future__ import annotations

import hashlib
import io
import math
import random
import re
from datetime import datetime

from PIL import Image, ImageDraw, ImageFilter, ImageOps

import wybor

W, H = 800, 450
SAFE_X0, SAFE_X1 = 100, 700
SAFE_BOX = [round(SAFE_X0 / W, 3), 0.0, round((SAFE_X1 - SAFE_X0) / W, 3), 1.0]
MAX_JPEG = 300 * 1024


# ------------------------------------------------------------------ dobór grup


def collage_id(ids: list[str]) -> str:
    return hashlib.sha1(("kolaz:" + "|".join(ids)).encode()).hexdigest()[:12]


def groups(chosen: list[dict], count: int) -> list[list[dict]]:
    """Grupy 2-3 zdjęć z jednego wydarzenia (każde zdjęcie najwyżej w jednym kolażu, jeden kolaż na wydarzenie).
    Najpierw wydarzenia z najlepszymi zdjęciami; lata wyrównane jak przy wyborze (pierwiastek z liczby)."""
    cands = []
    for ev in wybor.events(chosen):
        if len(ev) < 2:
            continue
        ev = sorted(ev, key=lambda e: (-_score(e), e["id"]))
        size = 3 if len(ev) >= 3 and int(ev[0]["id"], 16) % 2 == 0 else 2
        g = sorted(ev[:size], key=lambda e: (wybor.taken_ms(e), e["id"]))
        cands.append((sum(_score(e) for e in g) / len(g), g))
    by_year: dict[int, list] = {}
    for c in cands:
        by_year.setdefault(wybor.year_of(c[1][0]), []).append(c)
    quota = wybor.allocate({y: len(v) for y, v in by_year.items()}, min(count, len(cands)))
    out = []
    for y, v in by_year.items():
        v.sort(key=lambda c: (-c[0], c[1][0]["id"]))
        out += [g for _, g in v[: quota.get(y, 0)]]
    return sorted(out, key=lambda g: (wybor.taken_ms(g[0]), g[0]["id"]))


def _score(e: dict) -> int:
    return int((e.get("review") or {}).get("s", 0))


def index_entry(group: list[dict]) -> dict:
    """Wpis spisu: podpis, ocena i czas najlepszego zdjęcia, `k` = id zdjęć w kolażu."""
    best = max(group, key=lambda e: (_score(e), e["id"]))
    ids = [e["id"] for e in group]
    return {
        "id": collage_id(ids),
        "t": int(wybor.taken_ms(best)),
        "c": wybor.clean_caption((best.get("review") or {}).get("c", "")),
        "s": _score(best),
        "w": W,
        "h": H,
        "f": SAFE_BOX,
        "k": ids,
    }


# ------------------------------------------------------------------ kadrowanie


def focus_point(e: dict, rotated: bool) -> tuple[float, float]:
    """Środek tego, co ważne (ułamki zdjęcia): motyw / fragment z przeglądu, twarze, a bez nich trochę powyżej środka."""
    r = e.get("review") or {}
    box = wybor.clean_box(r.get("m")) or wybor.clean_box(r.get("f"))
    if box:
        return box[0] + box[2] / 2, box[1] + box[3] / 2
    faces = [] if rotated else [f for f in e.get("faces") or [] if len(f) == 4]
    if faces:
        l = min(f[0] for f in faces)
        t = min(f[1] for f in faces)
        rr = max(f[0] + f[2] for f in faces)
        b = max(f[1] + f[3] for f in faces)
        return (l + rr) / 2, (t + b) / 2 + 0.05
    return 0.5, 0.42


def cover_box(iw: int, ih: int, w: int, h: int, focus: tuple[float, float]) -> tuple[float, float, float, float]:
    """Wycinek zdjęcia (l, t, szer., wys. w pikselach) o proporcjach w×h z punktem [focus] możliwie w środku."""
    scale = max(w / iw, h / ih)
    cw, ch = min(w / scale, iw), min(h / scale, ih)
    l = max(0.0, min(focus[0] * iw - cw / 2, iw - cw))
    t = max(0.0, min(focus[1] * ih - ch / 2, ih - ch))
    return l, t, cw, ch


def cover(img: Image.Image, w: int, h: int, focus: tuple[float, float]) -> Image.Image:
    """Wypełnij w×h (przytnij nadmiar), zachowując punkt [focus] możliwie w środku."""
    l, t, cw, ch = cover_box(*img.size, w, h, focus)
    return img.resize((w, h), Image.LANCZOS, box=(l, t, l + cw, t + ch))


def important_boxes(e: dict, rotated: bool) -> list[list[float]]:
    """Ważne miejsca zdjęcia (ułamki): twarze, a bez nich motyw / fragment z przeglądu."""
    faces = [] if rotated else [f for f in e.get("faces") or [] if len(f) == 4]
    if faces:
        return faces
    r = e.get("review") or {}
    box = wybor.clean_box(r.get("m")) or wybor.clean_box(r.get("f"))
    return [box] if box else []


def to_canvas(boxes: list[list[float]], size: tuple[int, int], crop: tuple, w: int, h: int) -> list[tuple]:
    """Pudełka z ułamków zdjęcia na piksele płótna po [cover] na całe w×h."""
    iw, ih = size
    l, t, cw, ch = crop
    out = []
    for b in boxes:
        x0, y0 = (b[0] * iw - l) / cw * w, (b[1] * ih - t) / ch * h
        x1, y1 = ((b[0] + b[2]) * iw - l) / cw * w, ((b[1] + b[3]) * ih - t) / ch * h
        out.append((x0, y0, x1, y1))
    return out


def overlap(a: tuple, b: tuple) -> float:
    return max(0.0, min(a[2], b[2]) - max(a[0], b[0])) * max(0.0, min(a[3], b[3]) - max(a[1], b[1]))


# ------------------------------------------------------------------ karty (zdjęcie z ramką i cieniem)


def card(photo: Image.Image, border: int = 8, bottom: int | None = None, angle: float = 0.0,
         radius: int = 0, round_mask: bool = False) -> Image.Image:
    """Zdjęcie w białej ramce (polaroid: grubszy dół) z miękkim cieniem, obrócone o [angle] stopni; RGBA."""
    pw, ph = photo.size
    bottom = border if bottom is None else bottom
    fw, fh = pw + 2 * border, ph + border + bottom
    if round_mask:
        frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        d = ImageDraw.Draw(frame)
        d.ellipse((0, 0, fw - 1, fh - 1), fill=(255, 255, 255, 255))
        mask = Image.new("L", (pw, ph), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, pw - 1, ph - 1), fill=255)
        frame.paste(photo, (border, border), mask)
    else:
        frame = Image.new("RGBA", (fw, fh), (250, 250, 247, 255))
        frame.paste(photo, (border, border))
        if radius:
            mask = Image.new("L", (fw, fh), 0)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, fw - 1, fh - 1), radius, fill=255)
            frame.putalpha(mask)
    pad = 18
    shadow = Image.new("RGBA", (fw + 2 * pad, fh + 2 * pad), (0, 0, 0, 0))
    alpha = frame.getchannel("A").point(lambda a: a * 0.55)
    shadow.paste((0, 0, 0, 255), (pad + 4, pad + 6), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(7))
    shadow.alpha_composite(frame, (pad, pad))
    if angle:
        shadow = shadow.rotate(angle, resample=Image.BICUBIC, expand=True)
    return shadow


def place(canvas: Image.Image, item: Image.Image, cx: float, cy: float) -> None:
    canvas.alpha_composite(item, (round(cx - item.width / 2), round(cy - item.height / 2)))


# ------------------------------------------------------------------ tła


def theme_of(group: list[dict], rng: random.Random) -> str:
    text = " ".join(((e.get("review") or {}).get("c", "")).lower() for e in group)
    month = datetime.fromtimestamp(wybor.taken_ms(group[0]) / 1000).month
    if re.search(r"urodzin|tort|świecz|swiecz|zdmuch", text):
        return "urodziny"
    if re.search(r"choink|święt|swiet|mikołaj|mikolaj|wigili|śnieg|snieg|sanki|bałwan|balwan", text) or month == 12:
        return "zima" if rng.random() < 0.8 else "rozmyte"
    if re.search(r"wielkan|pisank|jajk|zajączek|zajaczek", text):
        return "wiosna"
    r = rng.random()
    if r < 0.18:
        return {3: "wiosna", 4: "wiosna", 5: "wiosna", 6: "lato", 7: "lato", 8: "lato",
                9: "jesien", 10: "jesien", 11: "jesien", 1: "zima", 2: "zima"}.get(month, "papier")
    return "rozmyte" if r < 0.68 else "papier"


def gradient(c1: tuple, c2: tuple, vertical: bool = True) -> Image.Image:
    g = Image.linear_gradient("L").resize((W, H) if vertical else (H, W))
    if not vertical:
        g = g.rotate(90, expand=True)
    return Image.composite(Image.new("RGB", (W, H), c2), Image.new("RGB", (W, H), c1), g).convert("RGBA")


def background(theme: str, photos: list[Image.Image], rng: random.Random) -> Image.Image:
    if theme == "rozmyte":
        bg = cover(photos[0], W, H, (0.5, 0.5)).filter(ImageFilter.GaussianBlur(22))
        dark = Image.new("RGB", (W, H), (0, 0, 0))
        return Image.blend(bg, dark, 0.35).convert("RGBA")
    if theme == "papier":
        base = rng.choice([(238, 232, 220), (226, 232, 236), (236, 228, 232), (228, 236, 226), (52, 56, 64)])
        bg = Image.new("RGB", (W, H), base)
        noise = Image.effect_noise((W, H), 18).convert("RGB")
        return Image.blend(bg, noise, 0.06).convert("RGBA")
    if theme == "zima":
        bg = gradient((18, 40, 78), (70, 110, 160))
        d = ImageDraw.Draw(bg)
        for _ in range(70):
            x, y, s = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(3, 11)
            a = int(rng.uniform(110, 230))
            for k in range(3):
                ang = math.pi / 3 * k
                dx, dy = math.cos(ang) * s, math.sin(ang) * s
                d.line((x - dx, y - dy, x + dx, y + dy), fill=(255, 255, 255, a), width=2 if s > 7 else 1)
        if rng.random() < 0.5:  # gałązka świerku z bombkami w rogu
            for i in range(9):
                d.line((0, 40 + i * 6, 70 + i * 4, 0), fill=(28, 92, 52, 255), width=4)
            for bx, by, col in ((60, 46, (200, 30, 40)), (30, 70, (230, 180, 40))):
                d.ellipse((bx - 11, by - 11, bx + 11, by + 11), fill=col + (255,))
        return bg
    if theme == "urodziny":
        bg = gradient((255, 236, 210), (250, 205, 220))
        d = ImageDraw.Draw(bg)
        cols = [(230, 70, 90), (60, 150, 230), (250, 190, 40), (90, 190, 110), (170, 90, 210)]
        for _ in range(110):
            x, y = rng.uniform(0, W), rng.uniform(0, H)
            c = rng.choice(cols) + (255,)
            if rng.random() < 0.5:
                d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=c)
            else:
                a = rng.uniform(0, math.pi)
                d.line((x, y, x + 10 * math.cos(a), y + 10 * math.sin(a)), fill=c, width=4)
        return bg
    if theme == "wiosna":
        bg = gradient((236, 248, 228), (206, 232, 196))
        d = ImageDraw.Draw(bg)
        for _ in range(28):
            x, y, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(5, 10)
            c = rng.choice([(250, 200, 220), (255, 240, 170), (210, 200, 250), (255, 255, 255)])
            for k in range(5):
                a = 2 * math.pi * k / 5
                px, py = x + math.cos(a) * r, y + math.sin(a) * r
                d.ellipse((px - r * 0.7, py - r * 0.7, px + r * 0.7, py + r * 0.7), fill=c + (255,))
            d.ellipse((x - r * 0.45, y - r * 0.45, x + r * 0.45, y + r * 0.45), fill=(245, 190, 60, 255))
        return bg
    if theme == "lato":
        bg = gradient((120, 190, 240), (250, 225, 170))
        d = ImageDraw.Draw(bg)
        d.ellipse((W - 150, -70, W + 30, 110), fill=(255, 236, 140, 255))
        return bg
    if theme == "jesien":
        bg = gradient((120, 70, 40), (205, 140, 70))
        d = ImageDraw.Draw(bg)
        for _ in range(40):
            x, y, s = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(6, 14)
            c = rng.choice([(200, 80, 30), (230, 150, 40), (170, 50, 30), (210, 180, 60)])
            a = rng.uniform(0, math.pi)
            d.ellipse((x - s, y - s / 2.2, x + s, y + s / 2.2), fill=c + (230,))
            d.line((x - s * math.cos(a), y, x + s * math.cos(a), y), fill=(90, 50, 20, 200), width=1)
        return bg
    raise ValueError(theme)


# ------------------------------------------------------------------ układy


def _tilt(rng: random.Random, lo: float = 1.5, hi: float = 5.0) -> float:
    return rng.choice((-1, 1)) * rng.uniform(lo, hi)


def layout_obok(bg, ph, fc, rng):
    """Dwie karty obok siebie (polaroidy albo cienka ramka), lekko przechylone."""
    pol = rng.random() < 0.5
    w, h = (250, 300) if pol else (265, 355)
    for i, x in enumerate((265, 535)):
        c = card(cover(ph[i], w, h, fc[i]), border=10 if pol else 6, bottom=40 if pol else None,
                 angle=_tilt(rng, 1, 4) * (1 if i else -1))
        place(bg, c, x + rng.uniform(-8, 8), 225 + rng.uniform(-10, 10))


def wstawka_spot(ph, fc, imp) -> tuple | None:
    """Miejsce na wstawkę: róg bez twarzy, daleko od głównego motywu; None = to zdjęcie się nie nadaje."""
    crop = cover_box(*ph[0].size, W, H, fc[0])
    faces = to_canvas(imp[0], ph[0].size, crop, W, H)
    if len(faces) > 2:
        return None
    fx = (fc[0][0] * ph[0].width - crop[0]) / crop[2] * W
    fy = (fc[0][1] * ph[0].height - crop[1]) / crop[3] * H
    land = ph[1].width >= ph[1].height
    w, h = (240, 180) if land else (170, 225)
    for y in (H - h / 2 - 35, h / 2 + 30):
        for x in (SAFE_X1 - w / 2 - 25, SAFE_X0 + w / 2 + 25):
            r = (x - w / 2 - 15, y - h / 2 - 15, x + w / 2 + 15, y + h / 2 + 15)
            if any(overlap(r, f) for f in faces) or math.hypot(x - fx, y - fy) < 280:
                continue
            return crop, (x, y), (w, h)
    return None


def layout_wstawka(bg, ph, fc, rng, spot):
    """Pierwsze zdjęcie na całe płótno, drugie mniejsze w ramce w wolnym rogu."""
    crop, (x, y), (w, h) = spot
    l, t, cw, ch = crop
    bg.paste(ph[0].resize((W, H), Image.LANCZOS, box=(l, t, l + cw, t + ch)).convert("RGBA"), (0, 0))
    vign = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vign).rectangle((0, H - 120, W, H), fill=90)
    bg.paste(Image.new("RGBA", (W, H), (0, 0, 0, 255)), (0, 0), vign.filter(ImageFilter.GaussianBlur(40)))
    place(bg, card(cover(ph[1], w, h, fc[1]), border=7, angle=_tilt(rng, 2, 6)), x, y)


def layout_duze_male(bg, ph, fc, rng):
    """Duża karta i mniejsza zachodząca na jej róg."""
    big = card(cover(ph[0], 400, 300, fc[0]), border=8, angle=_tilt(rng, 1, 3))
    small = card(cover(ph[1], 210, 230, fc[1]), border=7, angle=_tilt(rng, 3, 7))
    left = rng.random() < 0.5
    place(bg, big, 330 if left else 470, 200)
    place(bg, small, 575 if left else 225, 300)


def layout_okno(bg, ph, fc, rng):
    """Duże zdjęcie z zaokrąglonymi rogami na środku i drugie w kółku z białym brzegiem."""
    big = card(cover(ph[0], 470, 352, fc[0]), border=0, radius=18)
    place(bg, big, 380, 220)
    d = 190
    ring = card(cover(ph[1], d, d, fc[1]), border=7, round_mask=True)
    place(bg, ring, 590 if rng.random() < 0.6 else 205, 315)


def layout_trojka(bg, ph, fc, rng):
    """Duża karta po lewej, dwie mniejsze jedna pod drugą po prawej."""
    big = card(cover(ph[0], 300, 380, fc[0]), border=7, angle=_tilt(rng, 0.5, 2.5))
    place(bg, big, 270, 225)
    for i, y in enumerate((118, 330)):
        c = card(cover(ph[i + 1], 240, 168, fc[i + 1]), border=6, angle=_tilt(rng, 1.5, 4))
        place(bg, c, 545, y)


def layout_polaroidy(bg, ph, fc, rng):
    """Trzy polaroidy w wachlarzu, zachodzące na siebie."""
    angles = (-9 + rng.uniform(-2, 2), rng.uniform(-2, 2), 9 + rng.uniform(-2, 2))
    for i, (x, y) in enumerate(((235, 240), (400, 215), (565, 240))):
        c = card(cover(ph[i], 200, 235, fc[i]), border=10, bottom=38, angle=angles[i])
        place(bg, c, x, y)


LAYOUTS = {
    2: [("obok", layout_obok), ("wstawka", layout_wstawka), ("duze_male", layout_duze_male), ("okno", layout_okno)],
    3: [("trojka", layout_trojka), ("polaroidy", layout_polaroidy)],
}


def render(group: list[dict], images: list[Image.Image]) -> tuple[Image.Image, str]:
    """Kolaż grupy (obrazy już obrócone) - deterministyczny dla tej samej grupy. Zwraca (RGB 800×450, opis)."""
    rng = random.Random(collage_id([e["id"] for e in group]))
    fc = [focus_point(e, bool((e.get("review") or {}).get("o"))) for e in group]
    name, fn = rng.choice(LAYOUTS[len(group)])
    imp = [important_boxes(e, bool((e.get("review") or {}).get("o"))) for e in group]
    theme = theme_of(group, rng)
    spot = None
    if name == "wstawka":
        spot = wstawka_spot(images, fc, imp)
        if spot is None:
            name, fn = "duze_male", layout_duze_male
        else:
            theme = "papier"  # tło i tak zakrywa pierwsze zdjęcie
    bg = background(theme, images, rng)
    if spot:
        fn(bg, images, fc, rng, spot)
    else:
        fn(bg, images, fc, rng)
    return bg.convert("RGB"), f"{name}/{theme}"


def save_jpeg(img: Image.Image) -> bytes:
    for q in (86, 80, 72, 64):
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=q, optimize=True, progressive=False, subsampling=2)
        if buf.tell() <= MAX_JPEG:
            return buf.getvalue()
    raise ValueError("kolaż za duży")


def open_rgb(path: str) -> Image.Image:
    with Image.open(path) as im:
        return ImageOps.exif_transpose(im).convert("RGB")
