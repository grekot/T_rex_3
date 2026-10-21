#!/usr/bin/env python3
"""Generuje grafikę Pupila: klatki animacji każdej formy, ikony akcji, drobiazgi
i arkusz podglądu docs/arkusz.png.

Postaci są w tools/forms.py (siatki 24 x 24), ikony w tools/icons.py (12 x 12).
Klatki powstają z jednej siatki: zmienia się oko, usta, policzek i położenie
(oddech = przykucnięcie, radość = podskok), sen przy zgaszonym świetle jest
przyciemniony, "lewo" to lustrzane odbicie.

Uruchom z folderu pupil:   python tools/gen_assets.py
Wymaga: Pillow, font Segoe UI (Windows 10/11) - tylko do podpisów na arkuszu.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forms import FORMS  # noqa: E402
from icons import ICONS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
FONT = "C:/Windows/Fonts/segoeui.ttf"
FONT_B = "C:/Windows/Fonts/segoeuib.ttf"

GRID = 24
SCALE = 7  # piksel siatki = 7 px ekranu
SPRITE = GRID * SCALE  # 168
THUMB_SCALE = 3  # miniatury w kolekcji: 72 px
ICON_SCALE = 4  # ikony akcji 48 px na krążku
DISC = 76
SS = 8

EYE = (16, 16, 22)
SHINE = (255, 255, 255)
MOUTH = (190, 40, 60)
CHEEK = (250, 120, 150)
TEAR = (110, 190, 255)
WHITE = (250, 248, 240)

FRAMES = ["idle0", "idle1", "happy0", "happy1", "sad0", "sad1", "sleep0", "sleep1", "dark0", "dark1", "eat0", "eat1", "left"]
EGG_FRAMES = ["egg0", "egg1", "egg2"]


def shade(c, f):
    return tuple(max(0, min(255, round(v * f))) for v in c)


def find(rows, ch):
    pts = [(x, y) for y, r in enumerate(rows) for x, v in enumerate(r) if v == ch]
    return pts


# --- klatki ----------------------------------------------------------------------


def face(fid, eyes="open", mouth="closed", cheek=False, tear=False):
    """Siatka kolorów (lista wierszy krotek albo None) z miną."""
    f = FORMS[fid]
    p = dict(f["palette"])
    p["O"] = shade(p["B"], 0.32)
    p["W"] = WHITE
    rows = f["rows"]
    grid = [[None] * GRID for _ in range(GRID)]
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == ".":
                continue
            if ch in "em":
                grid[y][x] = p["B"]
            elif ch == "c":
                grid[y][x] = CHEEK if cheek else p["B"]
            else:
                grid[y][x] = p[ch]
    eye = find(rows, "e")
    if eye:
        ex = min(x for x, _ in eye)
        ey = min(y for _, y in eye)
        if eyes == "open":
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                grid[ey + dy][ex + dx] = EYE
            grid[ey][ex + 1] = SHINE
        elif eyes == "happy":  # zamknięte łuki ^
            grid[ey + 1][ex] = EYE
            grid[ey][ex + 1] = EYE
            if ex + 2 < GRID and grid[ey + 1][ex + 2] is not None:
                grid[ey + 1][ex + 2] = EYE
        elif eyes == "closed":
            grid[ey + 1][ex] = EYE
            grid[ey + 1][ex + 1] = EYE
        elif eyes == "sad":
            grid[ey][ex] = EYE
            grid[ey + 1][ex] = EYE
            grid[ey + 1][ex + 1] = EYE
        if tear and ey + 2 < GRID:
            grid[ey + 2][ex] = TEAR
            if ey + 3 < GRID and grid[ey + 3][ex] is not None:
                grid[ey + 3][ex] = TEAR
    for x, y in find(rows, "m"):
        if mouth == "closed":
            grid[y][x] = p["O"]
        else:
            grid[y][x] = MOUTH
            if mouth == "wide" and y + 1 < GRID and rows[y + 1][x] in "BLc":
                grid[y + 1][x] = MOUTH
    return grid


def crouch(grid, legs):
    """Oddech: ciało nad nogami opada o piksel i przykrywa górę nóg."""
    hip = GRID - legs  # pierwszy wiersz nóg
    out = [row[:] for row in grid]
    out[0] = [None] * GRID
    for y in range(1, hip + 1):
        src = grid[y - 1]
        if y < hip:
            out[y] = src[:]
        else:
            out[y] = [src[x] if src[x] is not None else grid[y][x] for x in range(GRID)]
    return out


def lift(grid, n):
    top = 0
    while top < GRID and all(v is None for v in grid[top]):
        top += 1
    n = min(n, top)
    return grid[n:] + [[None] * GRID for _ in range(n)]


def dim(grid):
    return [[None if v is None else (round(v[0] * 0.3), round(v[1] * 0.32), round(v[2] * 0.48)) for v in r] for r in grid]


def mirror(grid):
    return [list(reversed(r)) for r in grid]


def wobble(grid, dx):
    out = []
    for y, r in enumerate(grid):
        s = dx if y < 12 else 0
        out.append(r[-s:] + r[:-s] if s > 0 else r[:])
    return out


def crack(grid):
    out = [row[:] for row in grid]
    line = [(5, 11), (6, 12), (7, 11), (8, 12), (9, 13), (10, 12), (11, 11), (12, 12), (13, 13), (14, 12), (15, 11), (16, 12), (17, 13), (18, 12)]
    for x, y in line:
        if out[y][x] is not None:
            out[y][x] = shade(FORMS["egg"]["palette"]["B"], 0.3)
    return out


def frames_for(fid):
    legs = FORMS[fid]["legs"]
    if fid == "egg":
        base = face(fid)
        return {"egg0": base, "egg1": wobble(base, 1), "egg2": crack(base)}
    idle = face(fid)
    happy = face(fid, eyes="happy", mouth="open", cheek=True)
    sad = face(fid, eyes="sad", tear=False)
    sleep = face(fid, eyes="closed")
    return {
        "idle0": idle,
        "idle1": crouch(idle, legs),
        "happy0": happy,
        "happy1": lift(face(fid, eyes="happy", mouth="wide", cheek=True), 2),
        "sad0": sad,
        "sad1": crouch(face(fid, eyes="sad", tear=True), legs),
        "sleep0": sleep,
        "sleep1": crouch(sleep, legs),
        "dark0": dim(sleep),
        "dark1": dim(crouch(sleep, legs)),
        "eat0": face(fid, mouth="wide", cheek=True),
        "eat1": crouch(face(fid, eyes="happy", cheek=True), legs),
        "left": mirror(idle),
    }


def to_image(grid, scale, silhouette=None):
    h = len(grid)
    w = len(grid[0])
    img = Image.new("RGBA", (w * scale, h * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y, r in enumerate(grid):
        for x, v in enumerate(r):
            if v is None:
                continue
            c = silhouette if silhouette else v
            d.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1], fill=c + (255,))
    return img


def icon_grid(iid, flip=False):
    ic = ICONS[iid]
    p = ic["palette"]
    g = [[None if ch == "." else p[ch] for ch in r] for r in ic["rows"]]
    return mirror(g) if flip else g


# --- obrazki interfejsu ----------------------------------------------------------


def disc(color, ring=None):
    big = Image.new("RGBA", (DISC * SS, DISC * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.ellipse([0, 0, DISC * SS - 1, DISC * SS - 1], fill=color + (255,))
    if ring:
        w = 4 * SS
        d.ellipse([0, 0, DISC * SS - 1, DISC * SS - 1], fill=ring + (255,))
        d.ellipse([w, w, DISC * SS - 1 - w, DISC * SS - 1 - w], fill=color + (255,))
    return big.resize((DISC, DISC), Image.LANCZOS)


def action_icon(iid, selected):
    base = disc((70, 56, 30), ring=(255, 170, 40)) if selected else disc((34, 34, 42))
    ic = to_image(icon_grid(iid), ICON_SCALE)
    base.alpha_composite(ic, ((DISC - ic.width) // 2, (DISC - ic.height) // 2))
    return base


def zzz():
    # trzy litery Z rosnące w prawo-górę
    g = [[None] * 14 for _ in range(12)]
    col = (170, 200, 255)

    def z(x0, y0, n):
        for i in range(n):
            g[y0][x0 + i] = col
            g[y0 + n - 1][x0 + i] = col
            g[y0 + n - 1 - i][x0 + i] = col

    z(0, 8, 3)
    z(4, 4, 4)
    z(9, 0, 5)
    return g


def trees():
    g = [[None] * GRID for _ in range(GRID)]
    dark = (30, 110, 60)
    light = (60, 160, 80)
    trunk = (120, 80, 45)
    for cx, top, h in ((6, 4, 16), (16, 2, 18), (11, 8, 13)):
        for y in range(h):
            half = 1 + y // 2
            for x in range(cx - half, cx + half + 1):
                if 0 <= x < GRID and top + y < GRID - 3:
                    g[top + y][x] = light if x < cx else dark
        for y in range(top + h - 3, GRID - 1):
            if y < GRID:
                g[y][cx] = trunk
    return g


def log_img():
    w, h = 32, 6
    g = [[None] * w for _ in range(h)]
    bark = (150, 95, 50)
    dark = (100, 60, 30)
    ring = (225, 180, 120)
    for y in range(h):
        for x in range(w):
            g[y][x] = dark if y in (0, h - 1) else bark
    for y in range(1, h - 1):
        g[y][0] = g[y][w - 1] = ring
    for x in range(4, w - 4, 6):
        g[2][x] = dark
    return g


def app_icon():
    size = 248
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.ellipse([0, 0, size * SS - 1, size * SS - 1], fill=(30, 60, 45, 255))
    img = big.resize((size, size), Image.LANCZOS)
    sprite = to_image(face("tupek", eyes="happy", mouth="open", cheek=True), 8)
    img.alpha_composite(sprite, ((size - sprite.width) // 2 - 6, (size - sprite.height) // 2 - 4))
    return img


def save(img, *parts):
    path = os.path.join(ASSETS, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


# --- arkusz podglądu -------------------------------------------------------------


def sheet(all_frames):
    font = ImageFont.truetype(FONT, 18)
    bold = ImageFont.truetype(FONT_B, 22)
    names = {
        "egg": "Jajo",
        "pisklak": "Pisklak (maluch)",
        "tupek": "Tupek (dziecko, dobra opieka)",
        "gapcio": "Gapcio (dziecko, błędy)",
        "rogal": "Rogal (nastolatek, wzorowo)",
        "kolec": "Kolec (nastolatek, średnio)",
        "lobuz": "Łobuz (nastolatek, zaniedbany)",
        "rex": "Rex (dorosły, wzorowo + dyscyplina)",
        "szyjek": "Szyjek (dorosły, dobrze)",
        "ptero": "Ptero (dorosły, średnio)",
        "burczek": "Burczek (dorosły, zaniedbany)",
    }
    cell = 120
    shown = ["idle0", "idle1", "happy0", "happy1", "sad1", "sleep0", "dark0", "eat0", "left"]
    labels = ["spokój", "oddech", "radość", "podskok", "smutek", "sen", "ciemno", "je", "w lewo"]
    left = 20
    top = 70
    row_h = cell + 44
    order = ["egg", "pisklak", "tupek", "gapcio", "rogal", "kolec", "lobuz", "rex", "szyjek", "ptero", "burczek"]
    icon_rows = 2
    W = left * 2 + cell * len(shown)
    H = top + row_h * len(order) + 60 + icon_rows * 110 + 20
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    d.text((left, 18), "Pupil - wszystkie formy (24 x 24 px, na zegarku 168 px)", font=bold, fill=(255, 255, 255))
    for i, lab in enumerate(labels):
        d.text((left + i * cell + cell // 2, top - 8), lab, font=font, fill=(150, 150, 160), anchor="ms")
    for r, fid in enumerate(order):
        y = top + r * row_h
        d.text((left, y + 6), names[fid], font=font, fill=(255, 200, 90))
        fr = all_frames[fid]
        keys = EGG_FRAMES if fid == "egg" else shown
        for i, k in enumerate(keys):
            x = left + i * cell
            bg = (12, 14, 30) if k.startswith("dark") else (16, 16, 18)
            d.rectangle([x + 4, y + 30, x + cell - 4, y + 30 + cell - 8], fill=bg)
            sp = to_image(fr[k], 4)  # 96 px
            img.alpha_composite(sp, (x + (cell - sp.width) // 2, y + 30 + (cell - 8 - sp.height) // 2))
    y = top + row_h * len(order) + 10
    d.text((left, y), "Ikony akcji (zwykła / wybrana) i drobiazgi", font=bold, fill=(255, 255, 255))
    y += 40
    x = left
    for iid in ["meal", "snack", "light", "play", "medicine", "clean", "scold", "stats"]:
        img.alpha_composite(action_icon(iid, False), (x, y))
        img.alpha_composite(action_icon(iid, iid == "meal"), (x, y + 90))
        x += 90
    x += 10
    for iid in ["heart", "heart_empty", "poop", "skull", "alert"]:
        im = to_image(icon_grid(iid), 4)
        img.alpha_composite(im, (x, y + 14))
        x += 58
    x = left + 90 * 8 + 10
    img.alpha_composite(to_image(zzz(), 4), (x, y + 104))
    img.alpha_composite(to_image(icon_grid("arrow", True), 4), (x + 70, y + 104))
    img.alpha_composite(to_image(icon_grid("ball"), 4), (x + 136, y + 110))
    img.alpha_composite(to_image(trees(), 3), (x + 180, y + 86))
    os.makedirs(DOCS, exist_ok=True)
    img.convert("RGB").save(os.path.join(DOCS, "arkusz.png"), optimize=True)


RING_IDS = ["meal", "snack", "light", "play", "medicine", "clean", "scold", "stats"]
RING_R = 192  # promień okręgu środków ikon


def ring_positions():
    """Środki ikon akcji: od godziny 12 zgodnie z ruchem wskazówek, z przerwą na dole na napis."""
    out = []
    n = len(RING_IDS)
    span = 290  # stopni zajętych przez ikony (dół wolny)
    for i in range(n):
        a = math.radians(-span / 2 + i * span / (n - 1))
        out.append((round(240 + RING_R * math.sin(a)), round(240 - RING_R * math.cos(a))))
    return out


def mock(all_frames, form, frame, selected, text):
    big = Image.new("RGBA", (480 * SS, 480 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, 480 * SS - 1, 480 * SS - 1], fill=(0, 0, 0, 255))
    img = big.resize((480, 480), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 26)
    small = ImageFont.truetype(FONT, 22)
    for i, (cx, cy) in enumerate(ring_positions()):
        ic = action_icon(RING_IDS[i], i == selected)
        img.alpha_composite(ic, (cx - DISC // 2, cy - DISC // 2))
    sp = to_image(all_frames[form][frame], SCALE)
    img.alpha_composite(sp, (240 - SPRITE // 2, 232 - SPRITE // 2))
    img.alpha_composite(to_image(icon_grid("poop"), 4), (300, 270))
    d.text((240, 128), "Tupek · 1 dzień", font=small, fill=(150, 150, 160), anchor="mm")
    d.text((240, 350), text, font=font, fill=(255, 200, 90), anchor="mm")
    d.text((240, 440), "Jedzenie", font=small, fill=(255, 255, 255), anchor="mm")
    return img


def main():
    all_frames = {}
    for fid in FORMS:
        fr = frames_for(fid)
        all_frames[fid] = fr
        for name, g in fr.items():
            save(to_image(g, SCALE), "pet", fid, name + ".png")
        if fid != "egg":
            save(to_image(fr["idle0"], THUMB_SCALE), "thumb", fid + ".png")
            save(to_image(fr["idle0"], THUMB_SCALE, silhouette=(44, 44, 52)), "thumb", fid + "_x.png")
    for iid in ["meal", "snack", "light", "play", "medicine", "clean", "scold", "stats"]:
        save(action_icon(iid, False), "ring", iid + ".png")
        save(action_icon(iid, True), "ring", iid + "_sel.png")
    for iid in ["heart", "heart_empty", "lock"]:
        save(to_image(icon_grid(iid), 3), "ui", iid + ".png")
    for iid in ["poop", "skull", "alert", "meal", "snack"]:
        save(to_image(icon_grid(iid), 4), "ui", iid + ".png")
    save(to_image(icon_grid("ball"), 4), "ui", "ball.png")
    save(to_image(icon_grid("arrow"), 5), "ui", "arrow_r.png")
    save(to_image(icon_grid("arrow", True), 5), "ui", "arrow_l.png")
    save(to_image(zzz(), 4), "ui", "zzz.png")
    save(to_image(trees(), SCALE), "ui", "forest.png")
    save(to_image(log_img(), 6), "ui", "log.png")
    app_icon().save(os.path.join(ASSETS, "icon.png"), optimize=True)
    sheet(all_frames)
    m = Image.new("RGBA", (980, 480), (40, 40, 40, 255))
    m.alpha_composite(mock(all_frames, "tupek", "idle0", 0, "Trzeba posprzątać"), (0, 0))
    m.alpha_composite(mock(all_frames, "rex", "happy0", 3, "Wygrana!"), (500, 0))
    m.convert("RGB").save(os.path.join(DOCS, "podglad.png"), optimize=True)
    print("gotowe:", len(FORMS), "form")


if __name__ == "__main__":
    main()
