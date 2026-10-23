"""Ikona aplikacji Waga i podgląd ekranu do README.

Uruchom w folderze waga/watch:  python tools/gen_assets.py
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
DIM = (74, 74, 74)
PILL = (38, 38, 38)
ORANGE = (255, 145, 0)
BUTTON = (230, 126, 0)
GREEN = (76, 175, 80)
DARK = (28, 28, 28)


def font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf", size)


def make_icon():
    """Waga łazienkowa z okienkiem i wskazówką na pomarańczowym kole."""
    S = 248 * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, S - 1, S - 1], fill=ORANGE)
    # płyta wagi
    m = int(S * 0.2)
    d.rounded_rectangle([m, m, S - m, S - m], int(S * 0.1), fill=WHITE)
    # okienko z podziałką (półkole)
    cx, cy, r = S / 2, S * 0.47, S * 0.17
    d.pieslice([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=DARK)
    d.rectangle([cx - r, cy - S * 0.004, cx + r, cy + S * 0.03], fill=DARK)
    for k in range(9):
        a = math.radians(180 + 22.5 * k)
        r1, r2 = r * 0.72, r * 0.9
        w = int(S * 0.012)
        d.line([cx + r1 * math.cos(a), cy + r1 * math.sin(a), cx + r2 * math.cos(a), cy + r2 * math.sin(a)], fill=WHITE, width=w)
    a = math.radians(300)
    d.line([cx, cy, cx + r * 0.8 * math.cos(a), cy + r * 0.8 * math.sin(a)], fill=ORANGE, width=int(S * 0.02))
    d.ellipse([cx - S * 0.022, cy - S * 0.022, cx + S * 0.022, cy + S * 0.022], fill=ORANGE)
    # stopy
    for fx in (0.36, 0.64):
        x = S * fx
        d.rounded_rectangle([x - S * 0.07, S * 0.62, x + S * 0.07, S * 0.73], int(S * 0.035), fill=(225, 225, 225))
    icon = im.resize((248, 248), Image.LANCZOS)
    icon.save(os.path.join(ROOT, "assets", "gt.r", "icon.png"))
    return icon


def text_c(d, cx, cy, s, f, fill):
    d.text((cx, cy), s, font=f, fill=fill, anchor="mm")


def make_preview():
    """Ekran główny jak na zegarku (wymiary z page/gt/home/index.page.r.layout.js)."""
    S = 480
    im = Image.new("RGB", (S, S), (0, 0, 0))
    d = ImageDraw.Draw(im)
    text_c(d, 240, 52, "pt 23.10", font(26), GREY)
    text_c(d, 240, 172, "82,3", font(96), WHITE)
    text_c(d, 240, 239, "kg", font(26), GREY)
    for cx, s in ((80, "−"), (400, "+")):
        d.ellipse([cx - 52, 172 - 52, cx + 52, 172 + 52], fill=PILL)
        text_c(d, cx, 172, s, font(64), ORANGE)
    text_c(d, 240, 274, "−0,4 kg od wczoraj", font(24), GREEN)
    text_c(d, 240, 302, "średnia 7 dni: 82,6 kg", font(20), GREY)
    vals = [835, None, 833, 834, 831, None, 830, 829, 830, None, 828, 826, 827, 823]
    lo, hi = min(v for v in vals if v), max(v for v in vals if v)
    x0, y0, w, h = 121, 326, 238, 54
    pitch = w / 14
    bw = round(pitch * 0.7)
    for i, v in enumerate(vals):
        bh = 3 if v is None else round(6 + (v - lo) / (hi - lo) * (h - 6))
        x = round(x0 + i * pitch + (pitch - bw) / 2)
        color = DIM if v is None else ORANGE if i == 13 else GREY
        d.rounded_rectangle([x, y0 + h - bh, x + bw, y0 + h], 3 if bh > 6 else 1, fill=color)
    d.rounded_rectangle([140, 394, 340, 446], 26, fill=BUTTON)
    text_c(d, 240, 420, "ZAPISZ", font(28), WHITE)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, S - 1, S - 1], fill=255)
    out = Image.new("RGB", (S, S), (40, 40, 40))
    out.paste(im, (0, 0), mask)
    out.save(os.path.join(ROOT, "docs", "home.png"))


if __name__ == "__main__":
    make_icon()
    make_preview()
    print("ok: assets/gt.r/icon.png, docs/home.png")
