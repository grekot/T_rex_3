"""Ikona aplikacji Szczyty, obrazki na ekran (szczyt na pasku, strzałki) i podglądy do README.

Uruchom w folderze szczyty:  python tools/gen_assets.py
Wymaga: Pillow, font Segoe UI (jest w Windows 10/11 - tylko do podglądu,
zegarek ma własny font).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
SS = 8  # rysowanie w 8x i zmniejszanie = gładkie krawędzie

WHITE = (255, 255, 255)
GREY = (154, 154, 154)
DIM = (92, 92, 92)
ORANGE = (255, 145, 0)
FROZEN = (79, 195, 247)
PILL = (38, 38, 38)
GREEN = (46, 125, 50)
ROCK = (96, 110, 130)
ROCK_DARK = (62, 72, 88)
SNOW = (240, 244, 248)
PEAK_GREY = (150, 150, 150)


def font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf", size)


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)
    print("zapisano", os.path.relpath(path, ROOT))


def big(w, h):
    im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def scale_pts(pts):
    return [(x * SS, y * SS) for x, y in pts]


def make_icon():
    S = 248
    im, d = big(S, S)
    d.ellipse([0, 0, S * SS - 1, S * SS - 1], fill=(14, 22, 34, 255))
    # góry: tylna szara, przednia z czapą śniegu
    d.polygon(scale_pts([(28, 178), (88, 96), (128, 150), (150, 128), (220, 178)]), fill=ROCK_DARK)
    d.polygon(scale_pts([(46, 186), (124, 70), (204, 186)]), fill=ROCK)
    d.polygon(scale_pts([(124, 70), (102, 100), (114, 96), (124, 106), (136, 95), (147, 101)]), fill=SNOW)
    # podstawa (dolina) przycięta do koła
    d.rectangle([0, 182 * SS, S * SS, S * SS], fill=(14, 22, 34, 255))
    d.line([(36 * SS, 184 * SS), (212 * SS, 184 * SS)], fill=(70, 80, 96), width=3 * SS)
    # pomarańczowa strzałka "12:00" wskazująca szczyt
    d.polygon(scale_pts([(124, 30), (110, 56), (138, 56)]), fill=ORANGE)
    d.rectangle([121 * SS, 54 * SS, 127 * SS, 62 * SS], fill=ORANGE)
    # pasek "· 1725 m ·" pod spodem
    im = im.resize((S, S), Image.LANCZOS)
    dd = ImageDraw.Draw(im)
    f = font(30, bold=True)
    t = "1725 m"
    w = dd.textlength(t, font=f)
    dd.text(((S - w) / 2, 192), t, font=f, fill=ORANGE)
    # maska koła
    mask = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, S * SS - 1, S * SS - 1], fill=255)
    mask = mask.resize((S, S), Image.LANCZOS)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    save(out, os.path.join(ASSETS, "icon.png"))


def triangle_icon(color, w=24, h=16):
    im, d = big(w, h)
    d.polygon(scale_pts([(0.5, h - 0.5), (w / 2, 0.5), (w - 0.5, h - 0.5)]), fill=color)
    return im.resize((w, h), Image.LANCZOS)


def arrow_icon(direction, w=14, h=22):
    im, d = big(w, h)
    if direction == "left":
        pts = [(w - 1, 1), (1, h / 2), (w - 1, h - 1)]
    else:
        pts = [(1, 1), (w - 1, h / 2), (1, h - 1)]
    d.polygon(scale_pts(pts), fill=ORANGE)
    return im.resize((w, h), Image.LANCZOS)


def make_ui():
    save(triangle_icon(PEAK_GREY), os.path.join(ASSETS, "peak.png"))
    save(triangle_icon(ORANGE), os.path.join(ASSETS, "peak_best.png"))
    save(arrow_icon("left"), os.path.join(ASSETS, "arrow_left.png"))
    save(arrow_icon("right"), os.path.join(ASSETS, "arrow_right.png"))


# --- podglądy ekranów (układ jak w page/gt/*/index.page.r.layout.js) -------------------------


def screen():
    im = Image.new("RGB", (480, 480), (40, 40, 40))
    mask = Image.new("L", (480, 480), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 479, 479], fill=255)
    black = Image.new("RGB", (480, 480), (0, 0, 0))
    im.paste(black, (0, 0), mask)
    return im, ImageDraw.Draw(im)


def center_text(d, y, h, text, size, color, bold=False, x0=50, x1=430):
    f = font(size, bold)
    lines = text.split("\n")
    lh = size * 1.25
    top = y + (h - lh * len(lines)) / 2
    for i, line in enumerate(lines):
        w = d.textlength(line, font=f)
        d.text((x0 + (x1 - x0 - w) / 2, top + i * lh), line, font=f, fill=color)


def make_home_preview():
    im, d = screen()
    center_text(d, 30, 40, "278° Zach", 30, ORANGE)
    center_text(d, 70, 28, "GPS · 1310 m n.p.m.", 20, GREY)
    center_text(d, 102, 112, "Babia Góra", 42, WHITE)
    center_text(d, 214, 42, "1725 m · 42 km", 34, WHITE)
    center_text(d, 256, 30, "kierunek 275° · 3° w lewo", 21, GREY)
    # pasek horyzontu
    d.rectangle([60, 346, 420, 347], fill=DIM)
    peaks = [(-3.2, 0.4, True), (-9.3, 0.02, False), (-24, 1.3, False), (12, -0.5, False), (21, 0.9, False)]
    tri_grey, tri_best = triangle_icon(PEAK_GREY), triangle_icon(ORANGE)
    for off, elev, best in peaks:
        e = max(-2, min(8, elev))
        cx = 240 + off / 30 * 180
        bottom = 346 - (e + 2) * 5
        im.paste(tri_best if best else tri_grey, (int(cx - 12), int(bottom - 16)), tri_best if best else tri_grey)
    d.rectangle([239, 292, 240, 351], fill=ORANGE)
    la, ra = arrow_icon("left"), arrow_icon("right")
    im.paste(la, (52, 363), la)
    im.paste(ra, (414, 363), ra)
    f = font(21)
    d.text((70, 358), "Pilsko 9°", font=f, fill=WHITE)
    t = "Gorc 41°"
    d.text((410 - d.textlength(t, font=f), 358), t, font=f, fill=WHITE)
    center_text(d, 388, 28, "za nim: Romanka 1366 m", 19, GREY, x0=80, x1=400)
    d.rounded_rectangle([216, 420, 264, 460], 20, fill=PILL)
    center_text(d, 420, 40, "i", 26, GREY, x0=216, x1=264)
    save(im, os.path.join(DOCS, "podglad.png"))


def make_info_preview():
    im, d = screen()
    center_text(d, 34, 44, "Szczyty", 34, ORANGE)
    center_text(d, 80, 56, "Baza: 9000 szczytów\nstan OSM: 20.10.2026", 22, WHITE)
    center_text(d, 138, 54, "Dane: © OpenStreetMap contributors,\nlicencja ODbL", 20, GREY, x0=40, x1=440)
    d.rounded_rectangle([50, 200, 430, 260], 30, fill=GREEN)
    center_text(d, 200, 60, "Korekta deklinacji: TAK (+6,3°)", 21, WHITE)
    center_text(
        d, 270, 120,
        "Kompas: zatocz nadgarstkiem ósemkę.\nStuknięcie w nazwę albo przycisk =\nzatrzymaj odczyt. Widoczności nie\nsprawdzam - szczyt może być zasłonięty.",
        19, GREY, x0=40, x1=440,
    )
    d.rounded_rectangle([160, 400, 320, 448], 24, fill=PILL)
    center_text(d, 400, 48, "Wróć", 26, WHITE)
    save(im, os.path.join(DOCS, "podglad-info.png"))


def make_gps_preview():
    im, d = screen()
    center_text(d, 30, 40, "kompas ?", 30, ORANGE)
    center_text(d, 70, 28, "szukam GPS...", 20, GREY)
    center_text(d, 102, 112, "Szukam GPS...", 42, WHITE)
    center_text(d, 214, 42, "wyjdź na otwartą przestrzeń", 26, WHITE)
    center_text(d, 256, 30, "pierwszy fix trwa do 1-2 min", 21, GREY)
    d.rectangle([60, 346, 420, 347], fill=DIM)
    d.rectangle([239, 292, 240, 351], fill=ORANGE)
    d.rounded_rectangle([216, 420, 264, 460], 20, fill=PILL)
    center_text(d, 420, 40, "i", 26, GREY, x0=216, x1=264)
    save(im, os.path.join(DOCS, "podglad-gps.png"))


if __name__ == "__main__":
    make_icon()
    make_ui()
    make_home_preview()
    make_info_preview()
    make_gps_preview()
