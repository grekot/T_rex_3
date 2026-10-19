#!/usr/bin/env python3
"""Generuje grafikę Labiryntu i plik utils/geometry.js.

Rozmiary plansz (pole, kulka, dziura, meta, grubość ścian) i położenie napisów
są tutaj - JS dostaje je z wygenerowanego geometry.js, a obrazki kulki, dziur
i mety muszą pasować do rozmiaru pola.

Podgląd do README rysuje prawdziwy poziom z utils/maze.js (przez Node),
więc najpierw powstaje geometry.js, potem obrazki, na końcu podgląd.

Uruchom z folderu labirynt:   python tools/gen_assets.py
Wymaga: Pillow, Node.js, font Segoe UI (jest w Windows 10/11).
"""
import json
import math
import os
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
SS = 8  # supersampling przy rysowaniu
TEXT_FONT = "C:/Windows/Fonts/segoeui.ttf"  # tylko do podglądu (zegarek ma własny font)

# --- plansze -------------------------------------------------------------------
# Jak w Saperze: każda plansza wypełnia kwadrat 360 x 360 px na środku ekranu,
# a pola wystające poza okrąg (rogi) są wycięte z labiryntu.
SCREEN = 480
BOARD = 360
BOARD_X = BOARD_Y = (SCREEN - BOARD) // 2
MASK_RADIUS = 236
FLOOR_RADIUS = 238  # ciemne „drewno” pod labiryntem
GRID_SIZES = [7, 8, 9, 10, 11]

UI = {
    "title": {"x": 120, "y": 12, "w": 240, "h": 44},
    "time": {"x": 160, "y": 426, "w": 160, "h": 42},
    "floor": {"cx": 240, "cy": 240, "r": FLOOR_RADIUS},
    # ekran testu czujnika: kulka toczy się swobodnie w tym okręgu
    "arena": {"cx": 240, "cy": 240, "r": 150},
}

# --- kolory ----------------------------------------------------------------------
FLOOR = (28, 21, 15)
WALL = (217, 163, 95)
GOAL = (95, 208, 104)


def size_geometry(n):
    cell = BOARD // n
    left = BOARD_X + (BOARD - n * cell) // 2
    c = SCREEN / 2
    active = ""
    for r in range(n):
        for col in range(n):
            x0, y0 = left + col * cell, left + r * cell
            far = max(math.hypot(x - c, y - c) for x in (x0, x0 + cell) for y in (y0, y0 + cell))
            active += "1" if far <= MASK_RADIUS else "0"
    return {
        "n": n,
        "cell": cell,
        "x": left,
        "y": left,
        "active": active,
        "ball": round(cell * 0.28),  # promień kulki
        "hole": round(cell * 0.32),  # promień dziury
        "goal": round(cell * 0.34),  # promień mety
        "wall": max(4, round(cell * 0.1)),  # grubość ściany
    }


SIZES = [size_geometry(n) for n in GRID_SIZES]


# --- rysowanie ---------------------------------------------------------------------
def canvas(w, h):
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def S(v):
    return round(v * SS)


def radial(d, cx, cy, r, inner, outer, steps=48, offset=(0.0, 0.0)):
    """Kula z gradientem: od `outer` na brzegu do `inner` w punkcie przesuniętym o offset."""
    for k in range(steps):
        t = k / (steps - 1)
        rr = r * (1 - t)
        ox, oy = cx + offset[0] * t, cy + offset[1] * t
        col = tuple(round(a + (b - a) * t) for a, b in zip(outer, inner)) + (255,)
        d.ellipse([S(ox - rr), S(oy - rr), S(ox + rr), S(oy + rr)], fill=col)


def ball(r):
    size = 2 * r
    img, d = canvas(size, size)
    radial(d, r, r, r, (250, 252, 255), (70, 76, 86), offset=(-r * 0.35, -r * 0.35))
    hr = r * 0.22
    hx, hy = r - r * 0.38, r - r * 0.38
    d.ellipse([S(hx - hr), S(hy - hr), S(hx + hr), S(hy + hr)], fill=(255, 255, 255, 230))
    return finish(img, size, size)


def hole(r):
    size = 2 * r
    img, d = canvas(size, size)
    # jasny brzeg odcina dziurę od ciemnej podłogi, w środku czarne zagłębienie
    d.ellipse([0, 0, S(size), S(size)], fill=(168, 128, 84, 255))
    inner = r - max(1.6, r * 0.13)
    radial(d, r, r, inner, (0, 0, 0), (70, 52, 36), offset=(0, -r * 0.2))
    return finish(img, size, size)


def goal(r):
    size = 2 * r
    img, d = canvas(size, size)
    w = max(r * 0.2, 2)
    d.ellipse([S(w / 2), S(w / 2), S(size - w / 2), S(size - w / 2)], outline=GOAL + (255,), width=S(w))
    ir = r * 0.42
    d.ellipse([S(r - ir), S(r - ir), S(r + ir), S(r + ir)], fill=GOAL + (255,))
    return finish(img, size, size)


def app_icon(size=248):
    img, d = canvas(size, size)
    d.ellipse([0, 0, S(size), S(size)], fill=FLOOR + (255,))
    # kawałek labiryntu: kilka ścian w kolorze drewna
    t = size * 0.055
    segs = [
        ((0.22, 0.30), (0.62, 0.30)), ((0.62, 0.30), (0.62, 0.50)),
        ((0.38, 0.30), (0.38, 0.70)), ((0.38, 0.70), (0.80, 0.70)),
        ((0.20, 0.50), (0.38, 0.50)), ((0.62, 0.50), (0.80, 0.50)),
        ((0.80, 0.50), (0.80, 0.70)), ((0.20, 0.50), (0.20, 0.78)),
    ]
    for (x0, y0), (x1, y1) in segs:
        d.line([S(x0 * size), S(y0 * size), S(x1 * size), S(y1 * size)], fill=WALL + (255,), width=S(t))
        for x, y in ((x0, y0), (x1, y1)):
            d.ellipse([S(x * size - t / 2), S(y * size - t / 2), S(x * size + t / 2), S(y * size + t / 2)], fill=WALL + (255,))
    out = finish(img, size, size)
    hr = round(size * 0.07)
    out.alpha_composite(hole(hr), (round(size * 0.71 - hr), round(size * 0.6 - hr)))
    gr = round(size * 0.075)
    out.alpha_composite(goal(gr), (round(size * 0.29 - gr), round(size * 0.64 - gr)))
    # kulka w korytarzu między ścianami na wysokości 0.30 i 0.50
    br = round(size * 0.07)
    out.alpha_composite(ball(br), (round(size * 0.5 - br), round(size * 0.4 - br)))
    return out


# --- zapis --------------------------------------------------------------------------
def save(img, *parts):
    path = os.path.join(ASSETS, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def write_geometry():
    lines = [
        "// WYGENEROWANE przez tools/gen_assets.py - nie edytuj ręcznie, zmieniaj generator.",
        "// Współrzędne w px dla ekranu 480 x 480 (strony przeliczają je przez px()).",
        "",
        "export const SCREEN = %d;" % SCREEN,
        "",
        "// Rozmiary plansz. active: \"1\" = pole labiryntu, \"0\" = wycięty róg.",
        "// ball / hole / goal = promienie w px, wall = grubość ściany w px.",
        "export const SIZES = %s;" % json.dumps(SIZES, indent=2),
        "",
        "export const UI = %s;" % json.dumps(UI, indent=2),
        "",
    ]
    with open(os.path.join(ROOT, "utils", "geometry.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


# --- podgląd do README ---------------------------------------------------------------
def text_font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else TEXT_FONT, size)


def dump_level(level):
    out = subprocess.run(
        ["node", os.path.join(ROOT, "tools", "dump-level.mjs"), str(level)],
        check=True, capture_output=True, text=True,
    )
    return json.loads(out.stdout)


def screen_canvas():
    img = Image.new("RGBA", (SCREEN, SCREEN), (255, 255, 255, 255))
    ImageDraw.Draw(img).ellipse([0, 0, SCREEN - 1, SCREEN - 1], fill=(0, 0, 0, 255))
    return img


def centered_text(img, rect, text, size, color, bold=False):
    d = ImageDraw.Draw(img)
    d.text((rect["x"] + rect["w"] / 2, rect["y"] + rect["h"] / 2), text, font=text_font(size, bold), fill=color, anchor="mm")


def preview_game(level_no):
    lv = dump_level(level_no)
    sz = lv["size"]
    img = screen_canvas()
    d = ImageDraw.Draw(img)
    f = UI["floor"]
    d.ellipse([f["cx"] - f["r"], f["cy"] - f["r"], f["cx"] + f["r"], f["cy"] + f["r"]], fill=FLOOR)
    for w in lv["walls"]:
        d.rounded_rectangle([w["x"], w["y"], w["x"] + w["w"] - 1, w["y"] + w["h"] - 1], 2, fill=WALL)
    for h in lv["holes"]:
        img.alpha_composite(hole(sz["hole"]), (h["x"] - sz["hole"], h["y"] - sz["hole"]))
    g = lv["goal"]
    img.alpha_composite(goal(sz["goal"]), (g["x"] - sz["goal"], g["y"] - sz["goal"]))
    # kulka w drodze: kilka pól od startu
    p = lv["pathPoints"][min(3, len(lv["pathPoints"]) - 1)]
    img.alpha_composite(ball(sz["ball"]), (p["x"] - sz["ball"], p["y"] - sz["ball"]))
    centered_text(img, UI["title"], "Poziom %d" % level_no, 26, (255, 255, 255))
    centered_text(img, UI["time"], "0:17", 26, (200, 200, 200))
    return img


def preview_menu():
    # układ jak w page/gt/home/index.page.r.layout.js
    img = screen_canvas()
    d = ImageDraw.Draw(img)
    img.alpha_composite(ball(18), (240 - 18 - 92, 36))
    d.text((240 + 18, 54), "LABIRYNT", font=text_font(34, True), fill=(255, 255, 255), anchor="mm")
    d.rounded_rectangle([90, 98, 390, 162], 32, fill=(230, 126, 0))
    d.text((240, 130), "Graj · poziom 6", font=text_font(28), fill=(255, 255, 255), anchor="mm")
    d.rounded_rectangle([90, 174, 390, 230], 28, fill=(31, 31, 31))
    d.text((240, 202), "Od poziomu 1", font=text_font(26), fill=(255, 255, 255), anchor="mm")
    d.rounded_rectangle([90, 242, 390, 298], 28, fill=(31, 31, 31))
    d.text((240, 270), "Czujnik", font=text_font(26), fill=(255, 255, 255), anchor="mm")
    d.text((240, 330), "rekord: poziom 7", font=text_font(24), fill=(255, 145, 0), anchor="mm")
    d.text((240, 372), "stuknij ekran w grze =", font=text_font(21), fill=(138, 138, 138), anchor="mm")
    d.text((240, 398), "wyzeruj pochylenie", font=text_font(21), fill=(138, 138, 138), anchor="mm")
    return img


def main():
    write_geometry()
    for s in SIZES:
        save(ball(s["ball"]), "maze", "ball_%d.png" % s["cell"])
        save(hole(s["hole"]), "maze", "hole_%d.png" % s["cell"])
        save(goal(s["goal"]), "maze", "goal_%d.png" % s["cell"])
    save(ball(18), "ui", "ball_menu.png")
    save(ball(22), "ui", "ball_arena.png")
    save(app_icon(), "icon.png")
    os.makedirs(DOCS, exist_ok=True)
    preview_game(5).convert("RGB").save(os.path.join(DOCS, "podglad.png"))
    preview_menu().convert("RGB").save(os.path.join(DOCS, "podglad-menu.png"))
    for s in SIZES:
        print("%dx%d  pole %d px  kulka r=%d  dziura r=%d  sciana %d  pol %d" % (
            s["n"], s["n"], s["cell"], s["ball"], s["hole"], s["wall"], s["active"].count("1")))


if __name__ == "__main__":
    main()
