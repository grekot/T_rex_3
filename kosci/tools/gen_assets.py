"""Ikona aplikacji Kości i podglądy ekranów do README.

Uruchom w folderze kosci:  python tools/gen_assets.py
Wymaga: Pillow, font Segoe UI (jest w Windows 10/11 - tylko do podglądu,
zegarek ma własny font).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SS = 8  # rysowanie w 8x i zmniejszanie = gładkie krawędzie

WHITE = (244, 244, 244)
SHADOW = (158, 158, 158)
INK = (28, 28, 28)
RED = (211, 47, 47)
ORANGE = (255, 145, 0)
ORANGE_DARK = (163, 93, 0)
PILL = (38, 38, 38)
BUTTON = (230, 126, 0)
GREY = (138, 138, 138)

PIPS = {1: [6], 2: [0, 5], 3: [0, 6, 5], 4: [0, 1, 4, 5], 5: [0, 1, 4, 5, 6], 6: [0, 1, 2, 3, 4, 5]}
SPOTS = [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1), (0, 0)]


def font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf", size)


def die_image(size, face, colors=(WHITE, SHADOW, INK), angle=0):
    """Kość K6 jako obrazek RGBA (z cieniem pod spodem), opcjonalnie obrócona."""
    face_c, shadow_c, ink = colors
    pad = int(size * 0.25)
    S = (size + 2 * pad) * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x0, y0, s = pad * SS, pad * SS, size * SS
    r = int(s * 0.18)
    d.rounded_rectangle([x0, y0 + int(s * 0.06), x0 + s, y0 + s + int(s * 0.06)], r, fill=shadow_c)
    d.rounded_rectangle([x0, y0, x0 + s, y0 + s], r, fill=face_c)
    pr, off = s * 0.09, s * 0.27
    for k in PIPS[face]:
        cx = x0 + s / 2 + SPOTS[k][0] * off
        cy = y0 + s / 2 + SPOTS[k][1] * off
        d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=RED if face == 1 and face_c == WHITE else ink)
    if angle:
        im = im.rotate(angle, resample=Image.BICUBIC)
    return im.resize((size + 2 * pad, size + 2 * pad), Image.LANCZOS)


def paste_center(base, im, cx, cy):
    base.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def make_icon():
    S = 248
    im = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, S * SS - 1, S * SS - 1], fill=(12, 12, 12, 255))
    im = im.resize((S, S), Image.LANCZOS)
    paste_center(im, die_image(104, 5, angle=14), 92, 104)
    paste_center(im, die_image(96, 3, colors=(ORANGE, ORANGE_DARK, INK), angle=-12), 158, 150)
    path = os.path.join(ROOT, "assets", "gt.r", "icon.png")
    im.save(path)
    print("zapisano", path)


def layout(count, cy=218):
    """Kopia layoutDice z utils/dice.js (do podglądu)."""
    def row(n, size, gap, y):
        w = n * size + (n - 1) * gap
        return [(240 - w / 2 + size / 2 + i * (size + gap), y, size) for i in range(n)]

    return {
        1: lambda: row(1, 170, 0, cy),
        2: lambda: row(2, 140, 30, cy),
        3: lambda: row(3, 118, 18, cy),
        4: lambda: row(2, 110, 20, cy - 65) + row(2, 110, 20, cy + 65),
        5: lambda: row(3, 100, 16, cy - 58) + row(2, 100, 16, cy + 58),
    }.get(count, lambda: row(3, 100, 16, cy - 58) + row(3, 100, 16, cy + 58))()


def screen():
    im = Image.new("RGBA", (480, 480), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, 479, 479], fill=(0, 0, 0, 255))
    return im, d


def pill(d, rect, color, text, size, text_color=(255, 255, 255), bold=False):
    x, y, w, h = rect
    d.rounded_rectangle([x, y, x + w, y + h], h / 2, fill=color)
    d.text((x + w / 2, y + h / 2), text, font=font(size, bold), fill=text_color, anchor="mm")


def preview_table():
    im, d = screen()
    pill(d, (145, 28, 190, 50), PILL, "3 × K6  ›", 26)
    values, locked = [6, 6, 2], [True, True, False]
    for (cx, cy, size), v, l in zip(layout(3), values, locked):
        colors = (ORANGE, ORANGE_DARK, INK) if l else (WHITE, SHADOW, INK)
        paste_center(im, die_image(size, v, colors), cx, cy + 0)
    d = ImageDraw.Draw(im)
    d.text((240, 359), "Suma 14", font=font(30), fill=(255, 255, 255), anchor="mm")
    d.text((240, 389), "poprzednio 9", font=font(20), fill=GREY, anchor="mm")
    pill(d, (145, 406, 190, 48), BUTTON, "RZUĆ", 28)
    return im


def preview_setup():
    im, d = screen()
    d.text((240, 42), "Kości", font=font(32), fill=(255, 255, 255), anchor="mm")
    d.text((240, 80), "Liczba kości", font=font(22), fill=GREY, anchor="mm")
    for x, t in ((110, "−"), (312, "+")):
        d.ellipse([x, 96, x + 58, 154], fill=PILL)
        d.text((x + 29, 125), t, font=font(36), fill=(255, 255, 255), anchor="mm")
    d.text((240, 125), "3", font=font(44), fill=(255, 255, 255), anchor="mm")
    d.text((240, 180), "Rodzaj", font=font(22), fill=GREY, anchor="mm")
    for i, sides in enumerate([4, 6, 8, 10, 12, 20]):
        x, y = 78 + (i % 3) * 112, 196 + (i // 3) * 64
        pill(d, (x, y, 100, 54), BUTTON if sides == 6 else PILL, "K%d" % sides, 26)
    pill(d, (100, 330, 280, 50), BUTTON, "Potrząśnij = rzut: TAK", 22)
    pill(d, (160, 394, 160, 46), PILL, "Gotowe", 24)
    return im


def main():
    make_icon()
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    preview_table().save(os.path.join(docs, "podglad.png"))
    preview_setup().save(os.path.join(docs, "podglad-ustawienia.png"))
    print("zapisano podglądy w docs/")


if __name__ == "__main__":
    main()
