"""Ikona aplikacji Dom, płomień (grzanie) i podglądy ekranów do README.

Uruchom w folderze homeautomation/watch:  python tools/gen_assets.py
Wymaga: Pillow, font Segoe UI (jest w Windows 10/11 - tylko do podglądu,
zegarek ma własny font).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SS = 8  # rysowanie w 8x i zmniejszanie = gładkie krawędzie

WHITE = (255, 255, 255)
GREY = (138, 138, 138)
PILL = (38, 38, 38)
ORANGE = (255, 145, 0)
ACTIVE = (230, 126, 0)
YELLOW = (255, 214, 0)
DARK = (28, 28, 28)


def font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf", size)


def flame(d, x, y, w, h, outer, inner):
    """Płomień w prostokącie (x, y, w, h): dwie krople zaostrzone u góry."""

    def drop(cx, top, bottom, half, color):
        r = half
        cy = bottom - r
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
        d.polygon([(cx - r * 0.97, cy - r * 0.25), (cx + r * 0.1, top), (cx + r * 0.97, cy - r * 0.25), (cx, cy)], fill=color)

    drop(x + w / 2, y, y + h, w / 2, outer)
    drop(x + w / 2, y + h * 0.42, y + h * 0.97, w * 0.27, inner)


def make_icon():
    """Okrągły termostat z płomieniem na pomarańczowym kole."""
    S = 248 * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, S - 1, S - 1], fill=ORANGE)
    m = int(S * 0.17)
    d.ellipse([m, m, S - m, S - m], fill=DARK)
    # podziałka na obwodzie tarczy
    cx = cy = S / 2
    r1, r2 = S * 0.27, S * 0.31
    for k in range(13):
        a = math.radians(135 + k * 22.5)
        color = ORANGE if k <= 8 else (90, 90, 90)
        d.line([cx + r1 * math.cos(a), cy + r1 * math.sin(a), cx + r2 * math.cos(a), cy + r2 * math.sin(a)], fill=color, width=int(S * 0.018))
    flame(d, S * 0.39, S * 0.33, S * 0.22, S * 0.33, ORANGE, YELLOW)
    icon = im.resize((248, 248), Image.LANCZOS)
    icon.save(os.path.join(ROOT, "assets", "gt.r", "icon.png"))


def make_flame():
    W, H = 48, 60
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    flame(ImageDraw.Draw(im), W * SS * 0.08, H * SS * 0.04, W * SS * 0.84, H * SS * 0.94, ORANGE, YELLOW)
    im.resize((W, H), Image.LANCZOS).save(os.path.join(ROOT, "assets", "gt.r", "flame.png"))


def text_c(d, cx, cy, s, f, fill):
    d.text((cx, cy), s, font=f, fill=fill, anchor="mm")


def round_save(im, name):
    S = 480
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, S - 1, S - 1], fill=255)
    out = Image.new("RGB", (S, S), (40, 40, 40))
    out.paste(im, (0, 0), mask)
    out.save(os.path.join(ROOT, "docs", name))


def make_list_preview():
    """Pulpit zegarka: big + dwa half + full (wymiary jak utils/layout.js dla 480x480)."""
    S = 480
    im = Image.new("RGB", (S, S), (0, 0, 0))
    d = ImageDraw.Draw(im)
    text_c(d, 240, 41, "DOM", font(24), ORANGE)
    y = 92
    d.text((77, y + 20), "Wieczór", font=font(20), fill=GREY, anchor="lm")
    y += 40
    # współrzędne z utils/layout.js (layoutPages dla tej strony)
    x0, x1 = 40, 440
    d.rounded_rectangle([x0, y, x1, y + 186], 24, fill=DARK)
    text_c(d, 240, y + 26, "Salon", font(22), WHITE)
    text_c(d, 240, y + 86, "21,4°", font(64), WHITE)
    text_c(d, 240, y + 147, "nastawa 21,5° · grzeje", font(20), ORANGE)
    y += 196
    # dwa half - przy dolnej krawędzi koła węższe
    w = 160
    for i, (name, value, on) in enumerate((("Dwór", "4,2°", None), ("Sufit", None, True))):
        x = 75 + i * (w + 10)
        d.rounded_rectangle([x, y, x + w, y + 88], 24, fill=DARK)
        d.text((x + 14, y + 22), name, font=font(20), fill=WHITE, anchor="lm")
        if value:
            d.text((x + 14, y + 59), value, font=font(30), fill=WHITE, anchor="lm")
        else:
            d.rounded_rectangle([x + w - 72, y + 44, x + w - 12, y + 78], 17, fill=ACTIVE if on else PILL)
            text_c(d, x + w - 42, y + 61, "WŁ" if on else "WYŁ", font(18), WHITE)
    round_save(im, "home.png")


def make_preview():
    """Ekran termostatu jak na zegarku (wymiary z page/gt/thermostat/index.page.r.layout.js)."""
    S = 480
    im = Image.new("RGB", (S, S), (0, 0, 0))
    d = ImageDraw.Draw(im)
    text_c(d, 240, 48, "Salon", font(24), ORANGE)
    text_c(d, 240, 155, "21,4°", font(100), WHITE)
    fl = Image.open(os.path.join(ROOT, "assets", "gt.r", "flame.png"))
    im.paste(fl, (372, 126), fl)
    text_c(d, 240, 221, "na zewnątrz 4,2°", font(22), GREY)
    text_c(d, 240, 252, "nastawa", font(18), GREY)
    text_c(d, 240, 292, "21,5°", font(58), ORANGE)
    for cx, s in ((112, "−"), (368, "+")):
        d.ellipse([cx - 42, 288 - 42, cx + 42, 288 + 42], fill=PILL)
        text_c(d, cx, 288, s, font(56), ORANGE)
    d.rounded_rectangle([100, 340, 380, 392], 26, fill=PILL)
    d.rounded_rectangle([240, 340, 380, 392], 26, fill=ACTIVE)
    text_c(d, 170, 366, "RĘCZNY", font(22), GREY)
    text_c(d, 310, 366, "AUTO", font(22), WHITE)
    text_c(d, 240, 412, "komfort do 22:30", font(20), GREY)
    round_save(im, "thermostat.png")


if __name__ == "__main__":
    make_icon()
    make_flame()
    make_preview()
    make_list_preview()
    print("ok: assets/gt.r/icon.png, assets/gt.r/flame.png, docs/home.png, docs/thermostat.png")
