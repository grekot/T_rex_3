#!/usr/bin/env python3
"""Generuje grafikę Sapera i plik utils/geometry.js.

Poziomy (rozmiar planszy, liczba min, rozmiar pola) i położenie elementów ekranu
są tutaj - JS dostaje je z wygenerowanego geometry.js, a kafelki muszą mieć
dokładnie rozmiar pola, więc jedno źródło prawdy zapobiega rozjazdom.

Uruchom z folderu saper:   python tools/gen_assets.py
Wymaga: Pillow, fonty Bahnschrift i Segoe UI (są w Windows 10/11).
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
SS = 8  # supersampling przy rysowaniu
DIGIT_FONT = "C:/Windows/Fonts/bahnschrift.ttf"
TEXT_FONT = "C:/Windows/Fonts/segoeui.ttf"  # tylko do podglądu (zegarek ma własny font)

# --- poziomy -------------------------------------------------------------------
# Wszystkie plansze zajmują ten sam kwadrat 360 x 360 px na środku ekranu;
# pola, które wystają poza okrąg (rogi), są wycięte z gry.
SCREEN = 480
BOARD = 360
BOARD_X = BOARD_Y = (SCREEN - BOARD) // 2
MASK_RADIUS = 236  # pole gra, jeśli jego najdalszy róg mieści się w tym promieniu

LEVELS = [
    {"id": "easy", "name": "Łatwy", "cols": 6, "rows": 6, "mines": 5},
    {"id": "medium", "name": "Średni", "cols": 8, "rows": 8, "mines": 10},
    {"id": "hard", "name": "Trudny", "cols": 9, "rows": 9, "mines": 15},
]

# --- elementy ekranu gry (px na ekranie 480 x 480) ----------------------------------
UI = {
    "smiley": {"x": 216, "y": 7, "w": 48, "h": 48},
    "mineIcon": {"x": 15, "y": 196, "w": 30, "h": 30},
    "mineText": {"x": 2, "y": 228, "w": 56, "h": 40},
    "clockIcon": {"x": 435, "y": 196, "w": 30, "h": 30},
    "timeText": {"x": 422, "y": 228, "w": 56, "h": 40},
    "mode": {"x": 170, "y": 425, "w": 140, "h": 44},
}

# --- kolory ----------------------------------------------------------------------
HIDDEN_TOP = (92, 104, 120)
HIDDEN_BOTTOM = (60, 69, 82)
HIDDEN_EDGE = (124, 136, 152)
OPEN_BG = (30, 30, 30)
MINE_BG = (104, 104, 104)
BOOM_BG = (229, 57, 53)
MINE_BODY = (12, 12, 12)
FLAG_RED = (255, 59, 48)
POLE = (236, 239, 241)
ORANGE = (255, 145, 0)
SWITCH_BG = (43, 43, 43)
ICON_OFF = (158, 158, 158)
ICON_ON = (26, 26, 26)
NUMBER_COLORS = {
    1: (79, 163, 255),
    2: (95, 208, 104),
    3: (255, 90, 78),
    4: (176, 124, 255),
    5: (255, 159, 28),
    6: (46, 211, 211),
    7: (240, 240, 240),
    8: (158, 158, 158),
}


def level_geometry(level):
    cols, rows = level["cols"], level["rows"]
    cell = BOARD // max(cols, rows)
    left = BOARD_X + (BOARD - cols * cell) // 2
    top = BOARD_Y + (BOARD - rows * cell) // 2
    c = SCREEN / 2
    active = ""
    for r in range(rows):
        for col in range(cols):
            x0, y0 = left + col * cell, top + r * cell
            far = max(math.hypot(x - c, y - c) for x in (x0, x0 + cell) for y in (y0, y0 + cell))
            active += "1" if far <= MASK_RADIUS else "0"
    return {**level, "cell": cell, "x": left, "y": top, "active": active}


GEOM = [level_geometry(l) for l in LEVELS]


# --- rysowanie ---------------------------------------------------------------------
def canvas(w, h):
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def S(v):
    return round(v * SS)


def vgradient(w, h, top, bottom):
    g = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(g)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    return g


def tile_base(s, kind):
    """Pusty kafelek: 'hidden' (wypukły), 'open' / 'mine' / 'boom' (płaski)."""
    img, d = canvas(s, s)
    inset = 1 if s < 50 else 2
    box = [S(inset), S(inset), S(s - inset), S(s - inset)]
    if kind == "hidden":
        radius = S(s * 0.14)
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
        img.paste(vgradient(img.size[0], img.size[1], HIDDEN_TOP, HIDDEN_BOTTOM), (0, 0), mask)
        # jasna krawędź u góry daje wrażenie wypukłego klawisza
        d.rounded_rectangle(box, radius, outline=HIDDEN_EDGE + (110,), width=S(1.2))
    else:
        bg = {"open": OPEN_BG, "mine": MINE_BG, "boom": BOOM_BG}[kind]
        d.rounded_rectangle(box, S(s * 0.1), fill=bg + (255,))
    return img, d


def draw_mine(d, s, cx, cy, body=MINE_BODY, highlight=(255, 255, 255)):
    r = s * 0.22
    w = max(S(s * 0.075), SS)
    for k in range(8):
        a = k * math.pi / 4
        length = s * (0.37 if k % 2 == 0 else 0.32)
        d.line([S(cx), S(cy), S(cx + math.cos(a) * length), S(cy + math.sin(a) * length)], fill=body + (255,), width=w)
    d.ellipse([S(cx - r), S(cy - r), S(cx + r), S(cy + r)], fill=body + (255,))
    hr = s * 0.055
    hx, hy = cx - r * 0.38, cy - r * 0.38
    d.ellipse([S(hx - hr), S(hy - hr), S(hx + hr), S(hy + hr)], fill=highlight + (255,))


def draw_flag(d, s, ox=0.0, oy=0.0, scale=1.0):
    def P(x, y):
        return (S(ox + x * s * scale), S(oy + y * s * scale))

    pole_w = max(S(s * scale * 0.065), SS)
    d.line([P(0.40, 0.20), P(0.40, 0.74)], fill=POLE + (255,), width=pole_w)
    d.polygon([P(0.42, 0.19), P(0.76, 0.35), P(0.42, 0.51)], fill=FLAG_RED + (255,))
    d.rounded_rectangle([*P(0.25, 0.71), *P(0.63, 0.80)], S(s * scale * 0.03), fill=POLE + (255,))


def tile(s, name):
    if name == "hidden":
        img, d = tile_base(s, "hidden")
    elif name == "flag":
        img, d = tile_base(s, "hidden")
        draw_flag(d, s)
    elif name.startswith("n"):
        n = int(name[1:])
        img, d = tile_base(s, "open")
        if n:
            f = ImageFont.truetype(DIGIT_FONT, S(s * 0.66))
            f.set_variation_by_name("Bold")
            d.text((S(s / 2), S(s / 2 + s * 0.02)), str(n), font=f, fill=NUMBER_COLORS[n] + (255,), anchor="mm")
    elif name == "mine":
        img, d = tile_base(s, "mine")
        draw_mine(d, s, s / 2, s / 2)
    elif name == "boom":
        img, d = tile_base(s, "boom")
        draw_mine(d, s, s / 2, s / 2)
    elif name == "wrong":
        # flaga postawiona tam, gdzie miny nie było: przekreślona mina
        img, d = tile_base(s, "mine")
        draw_mine(d, s, s / 2, s / 2)
        w = max(S(s * 0.08), SS)
        a, b = s * 0.2, s * 0.8
        d.line([S(a), S(a), S(b), S(b)], fill=FLAG_RED + (255,), width=w)
        d.line([S(b), S(a), S(a), S(b)], fill=FLAG_RED + (255,), width=w)
    else:
        raise ValueError(name)
    return finish(img, s, s)


TILE_NAMES = ["hidden", "flag", "mine", "boom", "wrong"] + ["n%d" % n for n in range(9)]


def smiley(face, size=48):
    img, d = canvas(size, size)
    c = size / 2
    r = size * 0.46
    d.ellipse([S(c - r), S(c - r), S(c + r), S(c + r)], fill=(255, 202, 40, 255), outline=(120, 80, 0, 255), width=S(1.6))
    ink = (40, 28, 10, 255)
    eye_y = c - size * 0.1
    ex = size * 0.16
    if face == "cool":
        # okulary przeciwsłoneczne
        for sx in (-1, 1):
            x0 = c + sx * ex
            d.rounded_rectangle([S(x0 - size * 0.13), S(eye_y - size * 0.07), S(x0 + size * 0.13), S(eye_y + size * 0.08)], S(size * 0.05), fill=ink)
        d.line([S(c - ex), S(eye_y - size * 0.03), S(c + ex), S(eye_y - size * 0.03)], fill=ink, width=S(2))
        d.line([S(c - r * 0.92), S(eye_y - size * 0.05), S(c - ex - size * 0.12), S(eye_y - size * 0.04)], fill=ink, width=S(1.6))
        d.line([S(c + r * 0.92), S(eye_y - size * 0.05), S(c + ex + size * 0.12), S(eye_y - size * 0.04)], fill=ink, width=S(1.6))
    elif face == "dead":
        k = size * 0.055
        for sx in (-1, 1):
            x0 = c + sx * ex
            d.line([S(x0 - k), S(eye_y - k), S(x0 + k), S(eye_y + k)], fill=ink, width=S(2.2))
            d.line([S(x0 + k), S(eye_y - k), S(x0 - k), S(eye_y + k)], fill=ink, width=S(2.2))
    else:
        er = size * 0.045
        for sx in (-1, 1):
            x0 = c + sx * ex
            d.ellipse([S(x0 - er), S(eye_y - er * 1.3), S(x0 + er), S(eye_y + er * 1.3)], fill=ink)
    mw = size * 0.2
    my = c + size * 0.14
    if face == "wow":
        d.ellipse([S(c - size * 0.07), S(my - size * 0.07), S(c + size * 0.07), S(my + size * 0.08)], fill=ink)
    elif face == "dead":
        d.arc([S(c - mw), S(my), S(c + mw), S(my + size * 0.24)], 200, 340, fill=ink, width=S(2.4))
    else:
        d.arc([S(c - mw), S(my - size * 0.2), S(c + mw), S(my + size * 0.06)], 20, 160, fill=ink, width=S(2.4))
    return finish(img, size, size)


def draw_shovel(d, cx, cy, size, color):
    """Łopata po skosie: uchwyt w prawym górnym rogu, ostrze w lewym dolnym."""
    def P(x, y):
        return (S(cx + (x - 0.5) * size), S(cy + (y - 0.5) * size))

    dvec = (-1 / math.sqrt(2), 1 / math.sqrt(2))  # w stronę ostrza
    pvec = (1 / math.sqrt(2), 1 / math.sqrt(2))  # w poprzek
    d.line([P(0.86, 0.14), P(0.47, 0.53)], fill=color, width=S(size * 0.1))
    d.line([P(0.72, 0.10), P(0.90, 0.28)], fill=color, width=S(size * 0.1))  # rączka T
    bx, by = 0.48, 0.52

    def B(along, across):
        return P(bx + dvec[0] * along + pvec[0] * across, by + dvec[1] * along + pvec[1] * across)

    d.polygon([B(0, 0.17), B(0.27, 0.17), B(0.44, 0), B(0.27, -0.17), B(0, -0.17)], fill=color)


def mode_switch(active):
    w, h = UI["mode"]["w"], UI["mode"]["h"]
    img, d = canvas(w, h)
    d.rounded_rectangle([0, 0, S(w), S(h)], S(h / 2), fill=SWITCH_BG + (255,))
    pad = 3
    half = w / 2
    x0 = pad if active == "dig" else half
    d.rounded_rectangle([S(x0), S(pad), S(x0 + half - pad), S(h - pad)], S(h / 2 - pad), fill=ORANGE + (255,))
    dig_color = (ICON_ON if active == "dig" else ICON_OFF) + (255,)
    draw_shovel(d, half / 2 + 1, h / 2, 30, dig_color)
    flag_img, fd = canvas(34, 34)
    draw_flag(fd, 34)
    flag_small = finish(flag_img, 34, 34)
    if active != "flag":
        # nieaktywna flaga - szara jak łopata
        grey = Image.new("RGBA", flag_small.size, ICON_OFF + (255,))
        flag_small = Image.composite(grey, Image.new("RGBA", flag_small.size, (0, 0, 0, 0)), flag_small.split()[3])
    out = finish(img, w, h)
    out.alpha_composite(flag_small, (round(half + half / 2 - 17), round(h / 2 - 17)))
    return out


def restart_button():
    w, h = UI["mode"]["w"], UI["mode"]["h"]
    img, d = canvas(w, h)
    d.rounded_rectangle([0, 0, S(w), S(h)], S(h / 2), fill=ORANGE + (255,))
    cx, cy, r = w / 2, h / 2, 12
    d.arc([S(cx - r), S(cy - r), S(cx + r), S(cy + r)], 300, 240, fill=ICON_ON + (255,), width=S(4))
    # grot strzałki na końcu łuku (kąt 240°, ruch zgodny z zegarem)
    a = math.radians(240)
    ex, ey = cx + r * math.cos(a), cy + r * math.sin(a)
    tx, ty = -math.sin(a), math.cos(a)  # styczna
    nx, ny = math.cos(a), math.sin(a)
    tip = (ex - tx * 7, ey - ty * 7)
    d.polygon([(S(tip[0]), S(tip[1])), (S(ex + nx * 6.5), S(ey + ny * 6.5)), (S(ex - nx * 6.5), S(ey - ny * 6.5))], fill=ICON_ON + (255,))
    return finish(img, w, h)


def icon_mine(size, body=(207, 216, 220), highlight=(255, 255, 255)):
    img, d = canvas(size, size)
    draw_mine(d, size, size / 2, size / 2, body=body, highlight=(40, 40, 40))
    return finish(img, size, size)


def icon_clock(size):
    img, d = canvas(size, size)
    c = size / 2
    col = (207, 216, 220, 255)
    r = size * 0.36
    cy = c + size * 0.06
    d.ellipse([S(c - r), S(cy - r), S(c + r), S(cy + r)], outline=col, width=S(size * 0.09))
    d.rounded_rectangle([S(c - size * 0.1), S(size * 0.02), S(c + size * 0.1), S(size * 0.12)], S(1), fill=col)
    d.line([S(c), S(cy), S(c), S(cy - r * 0.6)], fill=col, width=S(size * 0.08))
    d.line([S(c), S(cy), S(c + r * 0.45), S(cy)], fill=col, width=S(size * 0.08))
    return finish(img, size, size)


def app_icon(size=248):
    img, d = canvas(size, size)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse([0, 0, S(size), S(size)], fill=255)
    img.paste(vgradient(img.size[0], img.size[1], (98, 112, 130), (44, 52, 63)), (0, 0), mask)
    # mina narysowana w mniejszym kwadracie, żeby kolce nie dochodziły do flagi
    mine_size = size * 0.8
    draw_mine(d, mine_size, size * 0.40, size * 0.59, body=MINE_BODY)
    flag_img, fd = canvas(size, size)
    draw_flag(fd, size, ox=size * 0.50, oy=size * 0.02, scale=0.5)
    out = finish(img, size, size)
    out.alpha_composite(finish(flag_img, size, size))
    return out


# --- zapis --------------------------------------------------------------------------
def save(img, *parts):
    path = os.path.join(ASSETS, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def write_geometry():
    levels = [
        {k: g[k] for k in ("id", "name", "cols", "rows", "mines", "cell", "x", "y", "active")} for g in GEOM
    ]
    lines = [
        "// WYGENEROWANE przez tools/gen_assets.py - nie edytuj ręcznie, zmieniaj generator.",
        "// Współrzędne w px dla ekranu 480 x 480 (strona dosuwa je na środek innych ekranów).",
        "",
        "export const SCREEN = %d;" % SCREEN,
        "",
        "// active: \"1\" = pole w grze, \"0\" = pole wycięte (wystaje poza okrągły ekran)",
        "export const LEVELS = %s;" % json.dumps(levels, ensure_ascii=False, indent=2),
        "",
        "export const UI = %s;" % json.dumps(UI, indent=2),
        "",
    ]
    with open(os.path.join(ROOT, "utils", "geometry.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


# --- podgląd do README ---------------------------------------------------------------
def text_font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else TEXT_FONT, size)


def neighbors(g, i):
    cols, rows = g["cols"], g["rows"]
    r, c = divmod(i, cols)
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            rr, cc = r + dr, c + dc
            if (dr or dc) and 0 <= rr < rows and 0 <= cc < cols and g["active"][rr * cols + cc] == "1":
                yield rr * cols + cc


def demo_board(g, first, seed):
    """Partia w trakcie: miny z ziarna, jedno kliknięcie z rozlaniem zer i kilka flag."""
    rnd = random.Random(seed)
    n = g["cols"] * g["rows"]
    safe = {first, *neighbors(g, first)}
    cand = [i for i in range(n) if g["active"][i] == "1" and i not in safe]
    mines = set(rnd.sample(cand, g["mines"]))
    count = lambda i: sum(1 for j in neighbors(g, i) if j in mines)
    opened, stack = set(), [first]
    while stack:
        i = stack.pop()
        if i in opened:
            continue
        opened.add(i)
        if count(i) == 0:
            stack.extend(j for j in neighbors(g, i) if j not in opened)
    # flagi na minach, które graniczą z odkrytym obszarem (jak po kilku ruchach gracza)
    flags = [m for m in sorted(mines) if any(j in opened for j in neighbors(g, m))][:3]
    names = {}
    for i in range(n):
        if g["active"][i] != "1":
            continue
        names[i] = ("n%d" % count(i)) if i in opened else ("flag" if i in flags else "hidden")
    return names, len(flags)


def screen_canvas():
    img = Image.new("RGBA", (SCREEN, SCREEN), (255, 255, 255, 255))
    ImageDraw.Draw(img).ellipse([0, 0, SCREEN - 1, SCREEN - 1], fill=(0, 0, 0, 255))
    return img


def centered_text(img, rect, text, size, color, bold=False):
    d = ImageDraw.Draw(img)
    d.text((rect["x"] + rect["w"] / 2, rect["y"] + rect["h"] / 2), text, font=text_font(size, bold), fill=color, anchor="mm")


def preview_game():
    g = GEOM[1]
    names, flags = demo_board(g, first=3 * g["cols"] + 3, seed=7)
    img = screen_canvas()
    tiles = {}
    for i, name in names.items():
        if name not in tiles:
            tiles[name] = tile(g["cell"], name)
        r, c = divmod(i, g["cols"])
        img.alpha_composite(tiles[name], (g["x"] + c * g["cell"], g["y"] + r * g["cell"]))
    img.alpha_composite(smiley("smile"), (UI["smiley"]["x"], UI["smiley"]["y"]))
    img.alpha_composite(icon_mine(30), (UI["mineIcon"]["x"], UI["mineIcon"]["y"]))
    img.alpha_composite(icon_clock(30), (UI["clockIcon"]["x"], UI["clockIcon"]["y"]))
    centered_text(img, UI["mineText"], str(g["mines"] - flags), 28, (255, 255, 255))
    centered_text(img, UI["timeText"], "42", 28, (255, 255, 255))
    img.alpha_composite(mode_switch("dig"), (UI["mode"]["x"], UI["mode"]["y"]))
    return img


def preview_menu():
    # układ jak w page/gt/home/index.page.r.layout.js
    img = screen_canvas()
    d = ImageDraw.Draw(img)
    img.alpha_composite(icon_mine(40), (240 - 40 // 2 - 70, 34))
    d.text((240 + 22, 54), "SAPER", font=text_font(36, True), fill=(255, 255, 255), anchor="mm")
    d.rounded_rectangle([110, 92, 370, 146], 27, fill=(230, 126, 0))
    d.text((240, 119), "Kontynuuj · Średni", font=text_font(24), fill=(255, 255, 255), anchor="mm")
    records = ["0:38", "2:14", "–"]
    for k, g in enumerate(GEOM):
        y = 160 + k * 74
        d.rounded_rectangle([70, y, 410, y + 64], 32, fill=(31, 31, 31))
        d.text((100, y + 32), "%s  %d×%d" % (g["name"], g["cols"], g["rows"]), font=text_font(28), fill=(255, 255, 255), anchor="lm")
        d.text((382, y + 32), records[k], font=text_font(26), fill=(255, 145, 0) if records[k] != "–" else (138, 138, 138), anchor="rm")
    d.text((240, 404), "przytrzymaj pole = flaga", font=text_font(22), fill=(138, 138, 138), anchor="mm")
    return img


def main():
    for g in GEOM:
        for name in TILE_NAMES:
            save(tile(g["cell"], name), "tiles", str(g["cell"]), name + ".png")
    for face in ("smile", "wow", "dead", "cool"):
        save(smiley(face), "ui", "face_%s.png" % face)
    save(mode_switch("dig"), "ui", "mode_dig.png")
    save(mode_switch("flag"), "ui", "mode_flag.png")
    save(restart_button(), "ui", "restart.png")
    save(icon_mine(30), "ui", "icon_mine.png")
    save(icon_mine(40), "ui", "icon_mine_big.png")
    save(icon_clock(30), "ui", "icon_clock.png")
    save(app_icon(), "icon.png")
    write_geometry()
    os.makedirs(DOCS, exist_ok=True)
    preview_game().convert("RGB").save(os.path.join(DOCS, "podglad.png"))
    preview_menu().convert("RGB").save(os.path.join(DOCS, "podglad-menu.png"))
    for g in GEOM:
        print("%-6s %dx%d  pole %d px  min %d  pól w grze %d" % (g["id"], g["cols"], g["rows"], g["cell"], g["mines"], g["active"].count("1")))


if __name__ == "__main__":
    main()
