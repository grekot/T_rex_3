#!/usr/bin/env python3
"""Generuje grafikę tarczy Retro LCD i plik watchface/layout.js.

Wszystkie współrzędne są tutaj - tło (z „duchami” niezapalonych segmentów),
cyfry i widżety muszą trafiać w te same piksele, więc JS dostaje je
z wygenerowanego layout.js.

Uruchom z folderu retro-lcd:   python tools/gen_assets.py [paleta]
(palety: patrz PALETTES niżej, domyślnie "grey")
Wymaga: Pillow, font Bahnschrift (jest w Windows 10/11).
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
SS = 4  # supersampling przy rysowaniu
SLANT = math.tan(math.radians(6))  # pochylenie cyfr LCD
FONT_FILE = "C:/Windows/Fonts/bahnschrift.ttf"

# --- kolory -----------------------------------------------------------------
# Paleta = (góra LCD, dół LCD, zapalony segment, alfa „ducha”, linie/drugorzędne napisy).
# Wybór: python tools/gen_assets.py [nazwa palety]
PALETTES = {
    "green": ((156, 168, 146), (180, 192, 170), (24, 30, 22), 26, (66, 76, 62)),
    "grey": ((178, 181, 175), (198, 201, 195), (26, 28, 28), 24, (72, 76, 74)),
    "cool": ((192, 199, 202), (212, 218, 220), (22, 27, 34), 22, (70, 78, 88)),
    "dim": ((112, 118, 112), (132, 138, 132), (12, 14, 12), 34, (40, 46, 40)),
    "negative": ((0, 0, 0), (12, 14, 12), (196, 218, 184), 30, (96, 108, 90)),
    "indiglo": ((52, 160, 152), (74, 182, 172), (8, 30, 30), 30, (20, 74, 70)),
}
PALETTE = sys.argv[1] if len(sys.argv) > 1 else "grey"
LCD_TOP, LCD_BOTTOM, SEG, GHOST_ALPHA, PRINT_SOFT = PALETTES[PALETTE]
AOD_SEG = (150, 172, 140)  # segmenty w trybie AOD (na czarnym tle)
AOD_FRAME = (58, 64, 54)
PRINT = SEG  # nadruk na LCD (napisy jak na kopercie)

# --- układ (px na ekranie 480x480) -------------------------------------------
# Dwie poziome linie dzielą ekran na strefy: górna (kroki | tętno), środkowa (czas),
# dolna (pogoda | bateria); pionowe kreski na x=240 dzielą górną i dolną na pół.
LINE_TOP = 146
LINE_BOTTOM = 332


def font(size, var="Bold Condensed"):
    f = ImageFont.truetype(FONT_FILE, size)
    f.set_variation_by_name(var)
    return f


# --- wyświetlacz segmentowy ------------------------------------------------------
DIGITS = {
    "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
    "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    "-": "g",
}
# 14 segmentów: a b c d e f, g1 g2 (środek), tc bc (pion środkowy),
# tl tr bl br (przekątne z rogów do środka)
LETTERS = {
    "M": ["b", "c", "e", "f", "tl", "tr"],
    "O": ["a", "b", "c", "d", "e", "f"],
    "T": ["a", "tc", "bc"],
    "U": ["b", "c", "d", "e", "f"],
    "W": ["b", "c", "e", "f", "bl", "br"],
    "E": ["a", "d", "e", "f", "g1"],
    "H": ["b", "c", "e", "f", "g1", "g2"],
    "F": ["a", "e", "f", "g1"],
    "R": ["a", "b", "e", "f", "g1", "g2", "br"],
    "S": ["a", "c", "d", "f", "g1", "g2"],
    "A": ["a", "b", "c", "e", "f", "g1", "g2"],
    "P": ["a", "b", "e", "f", "g1", "g2"],
    "N": ["b", "c", "e", "f", "tl", "br"],
    "C": ["a", "d", "e", "f"],
    "Z": ["a", "d", "tr", "bl"],
    "B": ["a", "b", "c", "d", "g2", "tc", "bc"],
    "D": ["a", "b", "c", "d", "tc", "bc"],
    "Ś": ["a", "c", "d", "f", "g1", "g2", "acc"],  # acc = kreska akcentu nad komórką
    "8": ["a", "b", "c", "d", "e", "f", "g1", "g2", "tc", "bc", "tl", "tr", "bl", "br"],
}
WEEKDAYS_PL = ["PN", "WT", "ŚR", "CZ", "PT", "SB", "ND"]  # poniedziałek pierwszy, jak w IMG_WEEK


class SegFont:
    """Pochylony wyświetlacz segmentowy: `cells` komórek o szerokości w."""

    def __init__(self, w, h, t, cells=1, gap=0, square=False, top_pad=0):
        self.w, self.h, self.t, self.cells, self.gap = w, h, t, cells, gap
        self.square = square  # prostokątne segmenty - czytelniejsze w małych rozmiarach
        self.top_pad = top_pad  # miejsce nad komórkami na segment akcentu (Ś)
        self.off = (h + top_pad) * SLANT
        self.box_w = cells * w + (cells - 1) * gap
        self.img_w = math.ceil(self.box_w + self.off) + 1
        self.img_h = h + top_pad

    def _lines(self, cx):
        w, h, t = self.w, self.h, self.t
        x0, x1, xm = cx + t / 2, cx + w - t / 2, cx + w / 2
        y0, ym, y1 = t / 2, h / 2, h - t / 2
        return {
            "a": ((x0, y0), (x1, y0)), "d": ((x0, y1), (x1, y1)),
            "g": ((x0, ym), (x1, ym)),
            "g1": ((x0, ym), (xm, ym)), "g2": ((xm, ym), (x1, ym)),
            "f": ((x0, y0), (x0, ym)), "b": ((x1, y0), (x1, ym)),
            "e": ((x0, ym), (x0, y1)), "c": ((x1, ym), (x1, y1)),
            "tc": ((xm, y0), (xm, ym)), "bc": ((xm, ym), (xm, y1)),
            "tl": ((x0, y0), (xm, ym)), "tr": ((x1, y0), (xm, ym)),
            "bl": ((x0, y1), (xm, ym)), "br": ((x1, y1), (xm, ym)),
        }

    def _poly(self, p, q, diagonal):
        t = self.t
        g = max(0.6, t * 0.14)
        (ax, ay), (bx, by) = p, q
        length = math.hypot(bx - ax, by - ay)
        ux, uy = (bx - ax) / length, (by - ay) / length
        nx, ny = -uy, ux
        if diagonal:  # cienki pasek, skrócony żeby nie dotykał sąsiadów
            ins = g + t * 0.75
            hw = t * 0.36
            a = (ax + ux * ins, ay + uy * ins)
            b = (bx - ux * ins, by - uy * ins)
            return [(a[0] + nx * hw, a[1] + ny * hw), (b[0] + nx * hw, b[1] + ny * hw),
                    (b[0] - nx * hw, b[1] - ny * hw), (a[0] - nx * hw, a[1] - ny * hw)]
        h2 = t / 2
        if self.square:
            g = 0.3
            a = (ax - ux * (h2 - g), ay - uy * (h2 - g))
            b = (bx + ux * (h2 - g), by + uy * (h2 - g))
            return [(a[0] + nx * h2, a[1] + ny * h2), (b[0] + nx * h2, b[1] + ny * h2),
                    (b[0] - nx * h2, b[1] - ny * h2), (a[0] - nx * h2, a[1] - ny * h2)]
        a = (ax + ux * g, ay + uy * g)
        b = (bx - ux * g, by - uy * g)
        return [a,
                (a[0] + ux * h2 + nx * h2, a[1] + uy * h2 + ny * h2),
                (b[0] - ux * h2 + nx * h2, b[1] - uy * h2 + ny * h2),
                b,
                (b[0] - ux * h2 - nx * h2, b[1] - uy * h2 - ny * h2),
                (a[0] + ux * h2 - nx * h2, a[1] + uy * h2 - ny * h2)]

    def _accent(self, cx):
        """Ukośna kreska nad górnym segmentem (w pasie top_pad)."""
        w, t, pad = self.w, self.t, self.top_pad
        x0, y0 = cx + w * 0.42, -1.6
        x1, y1 = cx + w * 0.70, -pad + 0.8
        hw = t * 0.42
        length = math.hypot(x1 - x0, y1 - y0)
        nx, ny = -(y1 - y0) / length * hw, (x1 - x0) / length * hw
        return [(x0 + nx, y0 + ny), (x1 + nx, y1 + ny), (x1 - nx, y1 - ny), (x0 - nx, y0 - ny)]

    def mask(self, cells_segs):
        m = Image.new("L", (self.img_w * SS, self.img_h * SS), 0)
        d = ImageDraw.Draw(m)
        pad = self.top_pad
        for i, segs in enumerate(cells_segs):
            cx = i * (self.w + self.gap)
            lines = self._lines(cx)
            for s in segs:
                if s == "acc":
                    poly = self._accent(cx)
                else:
                    p, q = lines[s]
                    poly = self._poly(p, q, s in ("tl", "tr", "bl", "br"))
                d.polygon([((x + (self.h - y) * SLANT) * SS, (y + pad) * SS) for x, y in poly], fill=255)
        return m.resize((self.img_w, self.img_h), Image.BOX)

    def image(self, cells_segs, color, alpha=255):
        return colorize(self.mask(cells_segs), color, alpha)

    def digit(self, ch, color=SEG, alpha=255):
        return self.image([DIGITS[ch]], color, alpha)


def colorize(mask, color, alpha=255):
    img = Image.new("RGBA", mask.size, color + (0,))
    img.putalpha(mask.point(lambda v: v * alpha // 255))
    return img


def paste(dst, img, x, y):
    dst.alpha_composite(img, (int(x), int(y)))


def save(img, rel):
    path = os.path.join(ASSETS, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return rel.replace("\\", "/")


# Fonty cyfr
BIG = SegFont(66, 108, 13)
MED = SegFont(30, 48, 7.5)
SMALL = SegFont(19, 34, 5.2)
TINY = SegFont(12, 22, 3.6)  # drugie rzędy, budzik, bateria; < 22 px było nieczytelne
LABEL = 16  # rozmiar nadruków przy danych (BPM, KCAL, BARO)
WEEK = SegFont(30, 48, 6, cells=2, gap=10, top_pad=7)
BIG_PITCH = 79  # odstęp między początkami cyfr
MED_PITCH = 38
LARGE = SegFont(24, 44, 6.4)  # wartości w dolnej strefie (temperatura, wysokość)
ROW2 = SegFont(14, 28, 4.2)  # drugi rząd dolnej strefy (max/min, ciśnienie)
SMALL_SPACE = 1
TINY_SPACE = 1
LARGE_SPACE = 1
ROW2_SPACE = 1


# --- ikony wektorowe (rysowane w maskach z supersamplingiem) --------------------
class Icon:
    """Ikona rysowana we współrzędnych w x h; k skaluje gotowy obrazek (np. 28 -> 34 px)."""

    def __init__(self, w, h, k=1.0):
        self.w, self.h = round(w * k), round(h * k)
        self.S = SS * k
        self.m = Image.new("L", (self.w * SS, self.h * SS), 0)
        self.d = ImageDraw.Draw(self.m)

    def _p(self, pts):
        return [(x * self.S, y * self.S) for x, y in pts]

    def circle(self, cx, cy, r, fill=255):
        S = self.S
        self.d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=fill)

    def ellipse(self, x0, y0, x1, y1, fill=255):
        S = self.S
        self.d.ellipse([x0 * S, y0 * S, x1 * S, y1 * S], fill=fill)

    def rect(self, x0, y0, x1, y1, fill=255, r=0):
        S = self.S
        box = [x0 * S, y0 * S, x1 * S, y1 * S]
        if r:
            self.d.rounded_rectangle(box, radius=r * S, fill=fill)
        else:
            self.d.rectangle(box, fill=fill)

    def poly(self, pts, fill=255):
        self.d.polygon(self._p(pts), fill=fill)

    def line(self, pts, width, fill=255):
        self.d.line(self._p(pts), width=int(round(width * self.S)), fill=fill, joint="curve")
        for x, y in (pts[0], pts[-1]):  # zaokrąglone końce
            self.circle(x, y, width / 2 - 0.05, fill)

    def arc(self, box, start, end, width, fill=255):
        self.d.arc([v * self.S for v in box], start, end, fill=fill, width=int(round(width * self.S)))

    def done(self, color=SEG, alpha=255):
        return colorize(self.m.resize((self.w, self.h), Image.BOX), color, alpha)


def ic_cloud(ic, x, y, s=1.0, grow=0.0, fill=255):
    """Chmura w pudełku ~22x13 * s od (x, y)."""
    for cx, cy, r in ((6.5, 8.5, 4.6), (12.5, 6.2, 6.0), (18.3, 8.8, 4.2)):
        ic.circle(x + cx * s, y + cy * s, r * s + grow, fill)
    ic.rect(x + 2.0 * s - grow, y + 8.5 * s - grow, x + 22.3 * s + grow, y + 13.0 * s + grow,
            fill, r=2.2 * s + grow)


def ic_sun(ic, cx, cy, r, rays=True):
    ic.circle(cx, cy, r)
    if rays:
        for k in range(8):
            a = k * math.pi / 4
            ic.line([(cx + math.cos(a) * (r + 2.0), cy + math.sin(a) * (r + 2.0)),
                     (cx + math.cos(a) * (r + 4.2), cy + math.sin(a) * (r + 4.2))], 1.6)


def ic_moon(ic, cx, cy, r):
    ic.circle(cx, cy, r)
    ic.circle(cx + r * 0.55, cy - r * 0.4, r * 0.82, 0)


def ic_drops(ic, n, long=False, y=19.5, xs=None):
    xs = xs or {1: [14], 2: [10, 17], 3: [8, 14, 20], 4: [6.5, 11.5, 16.5, 21.5], 5: [5, 9.5, 14, 18.5, 23]}[n]
    ln = 6.5 if long else 4.2
    for x in xs:
        ic.line([(x + 1.2, y), (x + 1.2 - ln * 0.35, y + ln)], 1.7)


def ic_flakes(ic, n, y=21.5):
    xs = {1: [14], 2: [9.5, 18.5], 3: [7, 14, 21], 4: [6, 11.3, 16.6, 22], 5: [5, 9.5, 14, 18.5, 23]}[n]
    for i, x in enumerate(xs):
        yy = y + (2.5 if (i % 2) else 0)
        for a in (0, 60, 120):
            r = math.radians(a)
            ic.line([(x - math.cos(r) * 2.3, yy - math.sin(r) * 2.3),
                     (x + math.cos(r) * 2.3, yy + math.sin(r) * 2.3)], 1.0)


def ic_bolt(ic, x=11.5, y=16.5):
    ic.poly([(x + 3.5, y), (x - 1.0, y + 6.0), (x + 2.2, y + 6.0), (x - 0.5, y + 11.0),
             (x + 6.2, y + 4.2), (x + 2.8, y + 4.2), (x + 5.5, y)])


def ic_hail(ic, xs, y=24.5):
    for x in xs:
        ic.circle(x, y, 1.6)


def ic_wind(ic, y0=7, heavy=False):
    rows = [(3, 19, y0), (6, 24, y0 + 6), (3, 16, y0 + 12)]
    if heavy:
        rows.append((8, 25, y0 + 18))
    for x0, x1, y in rows:
        ic.line([(x0, y), (x1, y)], 2.0)
    for x0, x1, y in rows[:2]:  # zawijasy na końcach

        ic.arc([x1 - 2.6, y - 5.2, x1 + 2.6, y], -90, 90, 1.8)


def ic_dust(ic, line=True):
    for x, y in ((5, 6), (12, 4), (20, 7), (8, 12), (16, 11), (23, 14), (5, 18), (13, 19), (21, 21), (10, 25)):
        ic.circle(x, y, 1.3)
    if line:
        ic.line([(3, 15), (25, 15)], 1.6)


def ic_fog(ic, y0=17):
    ic_cloud(ic, 3, 1, 1.0)
    for i, (x0, x1) in enumerate(((3, 25), (6, 22), (3, 25))):
        ic.line([(x0, y0 + 1 + i * 4), (x1, y0 + 1 + i * 4)], 2.0)


def sun_and_cloud(ic, night=False):
    if night:
        ic_moon(ic, 9, 8.5, 6.5)
    else:
        ic_sun(ic, 9, 8.5, 4.2)
    ic_cloud(ic, 6, 9, 0.98, grow=1.8, fill=0)
    ic_cloud(ic, 6, 9, 0.98)


def weather_icon(idx, k=1.0):
    """(28x28)*k ikona pogody dla indeksu Zepp OS 0..28."""
    ic = Icon(28, 28, k)
    top_cloud = lambda: ic_cloud(ic, 3, 2, 1.0)  # noqa: E731
    if idx == 3:  # Sunny
        ic_sun(ic, 14, 14, 6.5)
        ic.done()
    elif idx == 28:  # Sunny Nighttime
        ic_moon(ic, 13, 14, 9)
    elif idx in (0, 26):  # Cloudy (= częściowe zachmurzenie)
        sun_and_cloud(ic, night=(idx == 26))
    elif idx == 4:  # Overcast
        ic_cloud(ic, 9, 3, 0.8)
        ic_cloud(ic, 2, 9, 1.05, grow=1.8, fill=0)
        ic_cloud(ic, 2, 9, 1.05)
    elif idx in (1, 27):  # Showers (dzień / noc)
        if idx == 27:
            ic_moon(ic, 7, 6.5, 5.2)
        else:
            ic_sun(ic, 7, 6.5, 3.4)
        ic_cloud(ic, 5, 4.5, 0.98, grow=1.8, fill=0)
        ic_cloud(ic, 5, 4.5, 0.98)
        ic_drops(ic, 3)
    elif idx == 2:  # Snow Showers
        ic_sun(ic, 7, 6.5, 3.4)
        ic_cloud(ic, 5, 4.5, 0.98, grow=1.8, fill=0)
        ic_cloud(ic, 5, 4.5, 0.98)
        ic_flakes(ic, 3)
    elif idx == 5:
        top_cloud(); ic_drops(ic, 2)
    elif idx == 7:
        top_cloud(); ic_drops(ic, 3)
    elif idx in (10, 24):
        top_cloud(); ic_drops(ic, 4, long=True)
    elif idx in (18, 21):
        top_cloud(); ic_drops(ic, 5, long=True)
    elif idx == 6:
        top_cloud(); ic_flakes(ic, 2)
    elif idx == 8:
        top_cloud(); ic_flakes(ic, 3)
    elif idx == 9:
        top_cloud(); ic_flakes(ic, 4)
    elif idx == 16:
        top_cloud(); ic_flakes(ic, 5)
    elif idx == 12:  # Rain and Snow
        top_cloud()
        ic_drops(ic, 2, xs=[6.5, 21.5])
        ic_flakes(ic, 1, y=22.5)
    elif idx == 13:  # Fog
        ic_fog(ic)
    elif idx == 14:  # Hazy
        ic_sun(ic, 14, 9, 4.5, rays=False)
        ic.rect(0, 13, 28, 28, fill=0)
        for i, (x0, x1) in enumerate(((3, 25), (6, 22), (3, 25))):
            ic.line([(x0, 16 + i * 4.5), (x1, 16 + i * 4.5)], 2.0)
    elif idx == 15:  # T-Storms
        top_cloud(); ic_bolt(ic)
    elif idx == 19:  # Rain and Hail
        top_cloud(); ic_drops(ic, 2)
        ic_hail(ic, (14, 22))
    elif idx == 20:  # T-Storms and Hail
        top_cloud(); ic_bolt(ic, x=13)
        ic_hail(ic, (7, 22.5))
    elif idx in (11, 23):  # Sandstorm
        ic_wind(ic, heavy=(idx == 23))
    elif idx == 17:  # Floating dust
        ic_dust(ic, line=False)
    elif idx == 22:  # Dust
        ic_dust(ic, line=True)
    else:  # 25 Unknown
        d = ImageDraw.Draw(ic.m)
        f = font(round(26 * ic.S))
        d.text((14 * ic.S, 14 * ic.S), "?", font=f, fill=255, anchor="mm")
    return ic.done()


def icon_bell(k=1.0):
    ic = Icon(22, 20, k)
    ic.circle(11, 1.8, 1.4)
    ic.circle(11, 8.2, 5.4)
    ic.poly([(5.6, 8.2), (16.4, 8.2), (17.6, 14.2), (4.4, 14.2)])
    ic.rect(2.6, 13.6, 19.4, 15.8, r=1.0)
    ic.circle(11, 17.6, 1.9)
    return ic


def icon_bt_off():
    ic = Icon(22, 20)
    ic.line([(6.5, 5.5), (15, 13.5), (10.8, 17.5), (10.8, 2.5), (15, 6.5), (6.5, 14.5)], 1.7)
    ic.line([(4, 18.5), (19, 1.5)], 3.6, fill=0)
    ic.line([(4, 18.5), (19, 1.5)], 1.5)
    return ic


def icon_dnd():
    ic = Icon(22, 20)
    ic.circle(10.5, 10, 8.2)
    ic.circle(15.2, 6.2, 7.2, 0)
    return ic


def icon_steps(k=1.0):
    ic = Icon(18, 26, k)
    ic.ellipse(0.8, 1.0, 7.8, 12.2)
    ic.ellipse(1.6, 13.4, 7.0, 18.6)
    ic.ellipse(10.0, 6.4, 17.0, 17.6)
    ic.ellipse(10.8, 18.8, 16.2, 24.0)
    return ic


def icon_mountain(k=1.0):
    """(30x22)*k: dwa szczyty, na wyższym linia śniegu."""
    ic = Icon(30, 22, k)
    ic.poly([(16, 21.5), (22, 10.5), (29.5, 21.5)])
    ic.poly([(0.5, 21.5), (11.5, 2.5), (22.5, 21.5)], fill=0)  # szczelina między szczytami
    ic.poly([(2.5, 21.5), (11.5, 5.0), (20.5, 21.5)])
    ic.poly([(8.2, 11.0), (10.0, 12.6), (11.5, 11.0), (13.0, 12.6), (14.8, 11.0), (11.5, 7.6)], fill=0)
    return ic


def icon_gauge():
    """24x24: tarcza barometru otwarta u dołu, z kreskami skali i wskazówką."""
    ic = Icon(24, 24)
    ic.circle(12, 12.5, 11.2)
    ic.circle(12, 12.5, 8.9, 0)
    ic.poly([(12, 12.5), (3, 25), (21, 25)], fill=0)
    for deg in (200, 270, 340):
        r = math.radians(deg)
        ic.line([(12 + math.cos(r) * 5.6, 12.5 + math.sin(r) * 5.6),
                 (12 + math.cos(r) * 7.4, 12.5 + math.sin(r) * 7.4)], 1.3)
    ic.line([(12, 12.5), (17.0, 7.2)], 2.0)
    ic.circle(12, 12.5, 2.5)
    return ic


def icon_calendar(k=1.0):
    """(26x28)*k: kartka kalendarza - nagłówek, dwa uchwyty, siatka dni."""
    ic = Icon(26, 28, k)
    ic.rect(1, 5, 25, 27, r=3)
    ic.rect(3.2, 11.5, 22.8, 24.8, fill=0)
    for x in (6.5, 17.5):
        ic.rect(x - 1.8, 0.5, x + 3.8, 8.5, fill=0)  # szczelina wokół uchwytu
        ic.rect(x, 1.5, x + 2, 8, r=1)
    for gy in (14.5, 19.5):
        for gx in (6, 11.5, 17):
            ic.rect(gx, gy, gx + 3, gy + 3)
    return ic


def icon_heart(k=1.0):
    ic = Icon(22, 20, k)
    ic.circle(6.2, 6.4, 5.4)
    ic.circle(15.8, 6.4, 5.4)
    ic.poly([(1.2, 8.6), (20.8, 8.6), (11, 19.0)])
    return ic


def icon_battery(level, levels=5, s=1.0):
    """(26x14)*s: obrys + `level` z `levels` kresek."""
    ic = Icon(round(26 * s), round(14 * s))
    ic.rect(0.5 * s, 0.5 * s, 22.5 * s, 13.5 * s, r=1.5 * s)
    ic.rect(2.5 * s, 2.5 * s, 20.5 * s, 11.5 * s, fill=0)
    ic.rect(22.5 * s, 4.0 * s, 25.5 * s, 10.0 * s)
    inner_w = 16.0
    bw = (inner_w - (levels - 1) * 1.0) / levels
    for i in range(level):
        x = 3.5 + i * (bw + 1.0)
        ic.rect(x * s, 3.5 * s, (x + bw) * s, 10.5 * s)
    return ic


def bar_image(lit, total=10, seg_w=12, gap=2, h=8, color=SEG, alpha=255):
    w = total * seg_w + (total - 1) * gap
    off = h * SLANT
    img_w = math.ceil(w + off) + 1
    m = Image.new("L", (img_w * SS, h * SS), 0)
    d = ImageDraw.Draw(m)
    for i in range(lit):
        x = i * (seg_w + gap)
        pts = [(x, h), (x + seg_w, h), (x + seg_w + off, 0), (x + off, 0)]
        d.polygon([(px * SS, py * SS) for px, py in pts], fill=255)
    return colorize(m.resize((img_w, h), Image.BOX), color, alpha)


def text_image(text, size, color=SEG, var="Bold Condensed", height=None, spacing=0):
    """Napis jako obraz RGBA; height = wysokość obrazka (napis wyrównany do góry)."""
    f = font(size * SS, var)
    widths = [f.getlength(c) for c in text]
    total = sum(widths) + spacing * SS * (len(text) - 1)
    asc, desc = f.getmetrics()
    bbox = f.getbbox("H")
    cap_top = bbox[1]
    cap_h = bbox[3] - bbox[1]
    W = math.ceil(total / SS) + 2
    H = height or math.ceil(cap_h / SS) + 2
    m = Image.new("L", (W * SS, H * SS), 0)
    d = ImageDraw.Draw(m)
    x = SS
    for c, cw in zip(text, widths):
        d.text((x, -cap_top), c, font=f, fill=255)
        x += cw + spacing * SS
    return colorize(m.resize((W, H), Image.BOX), color)


def unit_bottom(text, size, height, var="Bold Condensed"):
    """Jednostka jako obraz o wysokości cyfr, wyrównana do ich dołu (m, ft, hPa)."""
    im = text_image(text, size, var=var)
    out = Image.new("RGBA", (im.width, height), (0, 0, 0, 0))
    out.alpha_composite(im, (0, height - im.height))
    return out


# --- tło ------------------------------------------------------------------------
def gradient(w, h, top, bottom):
    g = Image.new("RGBA", (w, h))
    px = g.load()
    for y in range(h):
        t = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        for x in range(w):
            px[x, y] = c
    return g


def bezel_text(big, text, cx=None, x=None, right=None, y=0, size=15, color=PRINT,
               var="SemiBold Condensed", spacing=0.6):
    f = font(size * SS, var)
    d = ImageDraw.Draw(big)
    widths = [f.getlength(c) + spacing * SS for c in text]
    total = sum(widths) - spacing * SS
    if cx is not None:
        xs = cx * SS - total / 2
    elif right is not None:
        xs = right * SS - total
    else:
        xs = x * SS
    for c, cw in zip(text, widths):
        d.text((xs, y * SS), c, font=f, fill=color + (255,), anchor="ls")
        xs += cw
    return total / SS


def text_img_slots(n, font_, space, unit_w=0):
    """Szerokość pola TEXT_IMG dla n cyfr (+ jednostka)."""
    w = n * font_.img_w + (n - 1) * space
    if unit_w:
        w += space + unit_w
    return w


def chord(y, margin=0):
    """Zakres x okręgu ekranu na wysokości y, zwężony o margin z obu stron."""
    half = math.sqrt(max(0, 240 ** 2 - (y - 240) ** 2))
    return 240 - half + margin, 240 + half - margin


def print_line(big, pts, width=2.0, color=PRINT_SOFT):
    """Nadrukowana linia na LCD (big w skali SS), zaokrąglone końce."""
    d = ImageDraw.Draw(big)
    fill = color + (255,)
    d.line([(x * SS, y * SS) for x, y in pts], fill=fill, width=int(width * SS))
    r = width / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS], fill=fill)


def zone_lines(big, color, dividers=True):
    for y in (LINE_TOP, LINE_BOTTOM):
        x0, x1 = chord(y, 16)
        print_line(big, [(x0, y), (x1, y)], color=color)
    if dividers:
        print_line(big, [(240, 62), (240, LINE_TOP)], color=color)
        print_line(big, [(240, LINE_BOTTOM), (240, 408)], color=color)


def main():
    L = {}
    # cały ekran to jeden LCD; strefy oddzielone nadrukowanymi liniami
    big = gradient(1, 480 * SS, LCD_TOP, LCD_BOTTOM).resize((480 * SS, 480 * SS))
    zone_lines(big, PRINT_SOFT)
    bezel_text(big, "GREKOT", cx=240, y=461, size=15, var="Bold", spacing=3.0)
    bg = big.resize((480, 480), Image.BOX)

    # ---- środkowa strefa: dzień, data, wskaźniki, czas ----------------------------
    t_y = 214
    hour_x, minute_x, sec_x = 35, 213, 370
    sec_y = t_y + BIG.h - MED.h
    row1_y = LINE_TOP + 10

    for i in range(10):
        save(BIG.digit(str(i)), f"big/{i}.png")
        save(MED.digit(str(i)), f"med/{i}.png")
        save(BIG.digit(str(i), AOD_SEG), f"aod/big/{i}.png")
        save(MED.digit(str(i), AOD_SEG), f"aod/med/{i}.png")

    ghost_big = BIG.digit("8", alpha=GHOST_ALPHA)
    ghost_med = MED.digit("8", alpha=GHOST_ALPHA)
    for x in (hour_x, hour_x + BIG_PITCH, minute_x, minute_x + BIG_PITCH):
        paste(bg, ghost_big, x, t_y)
    for x in (sec_x, sec_x + MED_PITCH):
        paste(bg, ghost_med, x, sec_y)

    # dwukropek (na stałe w tle) + wersja AOD
    colon_box_x = hour_x + BIG_PITCH + BIG.w + 8

    def colon_img(color):
        cw = 30
        m = Image.new("L", (cw * SS, BIG.h * SS), 0)
        dd = ImageDraw.Draw(m)
        s = 11
        for cy in (BIG.h * 0.31, BIG.h * 0.71):
            pts = [(0, cy + s / 2), (s, cy + s / 2), (s, cy - s / 2), (0, cy - s / 2)]
            dd.polygon([((x + (BIG.h - y) * SLANT) * SS, y * SS) for x, y in pts], fill=255)
        return colorize(m.resize((cw, BIG.h), Image.BOX), color)

    paste(bg, colon_img(SEG), colon_box_x, t_y)
    save(colon_img(AOD_SEG), "aod/colon.png")

    # dzień tygodnia (14 segmentów) nad minutami, data nad sekundami
    date_x = sec_x
    week_x = date_x - 24 - WEEK.box_w
    names = WEEKDAYS_PL
    for i, n in enumerate(names):
        save(WEEK.image([LETTERS[c] for c in n], SEG), f"week/{i + 1}.png")
        save(WEEK.image([LETTERS[c] for c in n], AOD_SEG), f"aod/week/{i + 1}.png")
    week_y = row1_y - WEEK.top_pad  # obraz ma nad komórkami pas na akcent Ś
    paste(bg, WEEK.image([LETTERS["8"] + ["acc"], LETTERS["8"]], SEG, GHOST_ALPHA), week_x, week_y)
    for x in (date_x, date_x + MED_PITCH):
        paste(bg, ghost_med, x, row1_y)
    cal = icon_calendar(k=1.3).done()
    paste(bg, cal, week_x - 10 - cal.width, row1_y + (MED.h - cal.height) // 2)

    # wskaźniki: dzwonek + godzina budzika, niżej PM, brak BT, nie przeszkadzać
    ind = {"bell": (34, row1_y + 1), "bt": (66, row1_y + 30), "dnd": (92, row1_y + 30)}
    big_bell = lambda: icon_bell(k=1.35)  # noqa: E731
    for name, fn in (("bell", big_bell), ("bt", icon_bt_off), ("dnd", icon_dnd)):
        save(fn().done(), f"status/{name}.png")
        paste(bg, fn().done(SEG, GHOST_ALPHA), *ind[name])
    pm = text_image("PM", 16)
    save(pm, "time/pm.png")
    save(Image.new("RGBA", pm.size, (0, 0, 0, 0)), "time/am.png")
    ampm = (38, row1_y + 34)
    paste(bg, colorize(pm.getchannel("A"), SEG, GHOST_ALPHA), *ampm)

    L["time"] = dict(hourX=hour_x, minuteX=minute_x, y=t_y, space=BIG_PITCH - BIG.img_w,
                     secondX=sec_x, secondY=sec_y, secondSpace=MED_PITCH - MED.img_w,
                     ampmX=ampm[0], ampmY=ampm[1], colonX=colon_box_x)
    L["week"] = dict(x=week_x, y=week_y)
    L["date"] = dict(x=date_x, y=row1_y, space=MED_PITCH - MED.img_w)
    L["status"] = {k: dict(x=v[0], y=v[1]) for k, v in ind.items()}

    # ---- cyfry pól, jednostki ----------------------------------------------------------
    for i in range(10):
        save(SMALL.digit(str(i)), f"small/{i}.png")
        save(TINY.digit(str(i)), f"tiny/{i}.png")
    save(SMALL.digit("-"), "small/minus.png")
    save(TINY.digit("-"), "tiny/minus.png")
    save(SegFont(SMALL.w, SMALL.h, SMALL.t, cells=2, gap=SMALL_SPACE + SMALL.img_w - SMALL.w)
         .image([DIGITS["-"], DIGITS["-"]], SEG), "small/none.png")
    save(SegFont(TINY.w, TINY.h, TINY.t, cells=2, gap=TINY_SPACE + TINY.img_w - TINY.w)
         .image([DIGITS["-"], DIGITS["-"]], SEG), "tiny/none.png")
    unit_c = text_image("°C", 18, height=SMALL.h)
    save(unit_c, "small/unit_c.png")
    save(text_image("°F", 18, height=SMALL.h), "small/unit_f.png")
    unit_pct = text_image("%", 18, height=SMALL.h)
    save(unit_pct, "small/unit_pct.png")
    ghost_small = SMALL.digit("8", alpha=GHOST_ALPHA)
    ghost_tiny = TINY.digit("8", alpha=GHOST_ALPHA)
    small_pitch = SMALL.img_w + SMALL_SPACE

    def ghosts(img, right, y, n, pitch):
        for k in range(n):
            paste(bg, img, right - (k + 1) * pitch + (pitch - img.width), y)

    def label(text, x, y, size=LABEL):
        """Nadruk wyrównany dołem do pola mikrocyfr zaczynającego się na y."""
        im = text_image(text, size)
        paste(bg, im, x, y + TINY.h - im.height)
        return im.width

    def label_groups(groups, cx, y):
        """Rząd par „NADRUK pole” wyśrodkowany na cx; zwraca pudełka pól."""
        widths = [text_image(t, LABEL).width for t, _ in groups]
        total = sum(lw + 4 + fw for lw, (_, fw) in zip(widths, groups)) + 18 * (len(groups) - 1)
        x = round(cx - total / 2)
        boxes = []
        for lw, (t, fw) in zip(widths, groups):
            label(t, x, y)
            x += lw + 4
            boxes.append(dict(x=x, y=y, w=fw, h=TINY.h))
            x += fw + 18
        return boxes

    # godzina budzika obok dzwonka, fontem drugiego rzędu (28 px); dwukropek = dot_image
    colon_w = 9

    def row2_colon(alpha=255):
        m = Image.new("L", (colon_w * SS, ROW2.h * SS), 0)
        dd = ImageDraw.Draw(m)
        s = ROW2.t * 0.95
        for cy in (ROW2.h * 0.3, ROW2.h * 0.72):
            pts = [(1, cy - s / 2), (1 + s, cy - s / 2), (1 + s, cy + s / 2), (1, cy + s / 2)]
            dd.polygon([((x + (ROW2.h - y) * SLANT) * SS, y * SS) for x, y in pts], fill=255)
        return colorize(m.resize((colon_w, ROW2.h), Image.BOX), SEG, alpha)

    save(row2_colon(), "row2/colon.png")
    save(Image.new("RGBA", (ROW2.img_w, ROW2.h), (0, 0, 0, 0)), "row2/blank.png")
    hhmm_w = 4 * ROW2.img_w + colon_w + 4 * ROW2_SPACE
    alarm = dict(x=ind["bell"][0] + 36, y=row1_y + 1, w=hhmm_w, h=ROW2.h)
    ghost_r2 = ROW2.digit("8", alpha=GHOST_ALPHA)
    right = alarm["x"] + hhmm_w
    for im in reversed([ghost_r2, ghost_r2, row2_colon(GHOST_ALPHA), ghost_r2, ghost_r2]):
        right -= im.width
        paste(bg, im, right, alarm["y"])
        right -= ROW2_SPACE
    L["alarm"] = alarm

    # ---- górna strefa: kroki | tętno -------------------------------------------------------
    vy = 76  # rząd wartości
    row2_y = vy + SMALL.h + 6  # drugi rząd (pasek kroków, KCAL)
    cell_r = (228, 402)  # prawe krawędzie zawartości lewego i prawego pola
    click_wh = (160, 76)
    save(Image.new("RGBA", click_wh, (0, 0, 0, 0)), "click.png")

    paste(bg, icon_steps(k=1.25).done(), 78, vy + 1)
    w = text_img_slots(5, SMALL, SMALL_SPACE)
    steps = dict(x=cell_r[0] - w, y=vy, w=w, h=SMALL.h)
    ghosts(ghost_small, cell_r[0] + SMALL_SPACE, vy, 5, small_pitch)
    bar_kw = dict(seg_w=12, gap=3, h=10)
    for i in range(11):
        save(bar_image(i, **bar_kw), f"bar/{i}.png")
    bar = dict(x=81, y=row2_y + TINY.h // 2 - 5)
    paste(bg, bar_image(10, alpha=GHOST_ALPHA, **bar_kw), bar["x"], bar["y"])
    L["steps"] = dict(text=steps, bar=bar, click=dict(x=74, y=64, w=click_wh[0], h=click_wh[1]))

    paste(bg, icon_heart(k=1.35).done(), 252, vy + 4)
    bpm = text_image("BPM", LABEL)
    bpm_x = cell_r[1] - bpm.width
    paste(bg, bpm, bpm_x, vy + SMALL.h - bpm.height)
    w = text_img_slots(3, SMALL, SMALL_SPACE)
    heart = dict(x=bpm_x - 5 - w, y=vy, w=w, h=SMALL.h)
    ghosts(ghost_small, bpm_x - 5 + SMALL_SPACE, vy, 3, small_pitch)
    label("KCAL", 254, row2_y)
    w = text_img_slots(4, TINY, TINY_SPACE)
    L["cal"] = dict(text=dict(x=cell_r[1] - w, y=row2_y, w=w, h=TINY.h))
    L["heart"] = dict(text=heart, click=dict(x=246, y=64, w=click_wh[0], h=click_wh[1]))

    # ---- dolna strefa: pogoda | wysokość -------------------------------------------------
    # Większe cyfry niż w górnej strefie - na dole jest więcej miejsca (okrąg zwęża się
    # dopiero niżej), a górne pole kroków musi zmieścić 5 cyfr.
    for i in range(10):
        save(LARGE.digit(str(i)), f"large/{i}.png")
        save(ROW2.digit(str(i)), f"row2/{i}.png")
    save(LARGE.digit("-"), "large/minus.png")
    save(ROW2.digit("-"), "row2/minus.png")
    save(SegFont(LARGE.w, LARGE.h, LARGE.t, cells=2, gap=LARGE_SPACE + LARGE.img_w - LARGE.w)
         .image([DIGITS["-"], DIGITS["-"]], SEG), "large/none.png")
    save(SegFont(ROW2.w, ROW2.h, ROW2.t, cells=2, gap=ROW2_SPACE + ROW2.img_w - ROW2.w)
         .image([DIGITS["-"], DIGITS["-"]], SEG), "row2/none.png")
    ghost_large = LARGE.digit("8", alpha=GHOST_ALPHA)
    large_pitch = LARGE.img_w + LARGE_SPACE

    wy = LINE_BOTTOM + 8  # rząd wartości
    row2_b = wy + LARGE.h + 6  # drugi rząd
    for i in range(29):
        save(weather_icon(i, k=1.5), f"weather/{i}.png")  # 42x42
    unit_cl = text_image("°C", 26, var="Bold", height=LARGE.h)
    save(unit_cl, "large/unit_c.png")
    save(text_image("°F", 26, var="Bold", height=LARGE.h), "large/unit_f.png")
    w = text_img_slots(3, LARGE, LARGE_SPACE, unit_cl.width)
    temp = dict(x=cell_r[0] - w, y=wy, w=w, h=LARGE.h)
    ghosts(ghost_large, cell_r[0] - unit_cl.width, wy, 3, large_pitch)

    # max / min: nadrukowane strzałki ▲ ▼, wartości wyrównane do lewej tuż za nimi
    w3 = text_img_slots(3, ROW2, ROW2_SPACE)

    def arrow(up):
        ic = Icon(14, 13)
        ic.poly([(0.5, 12.5), (13.5, 12.5), (7, 0.5)] if up else [(0.5, 0.5), (13.5, 0.5), (7, 12.5)])
        return ic.done()

    ay = row2_b + (ROW2.h - 13) // 2
    paste(bg, arrow(True), 90, ay)
    paste(bg, arrow(False), 166, ay)
    hi = dict(x=90 + 14 + 4, y=row2_b, w=w3, h=ROW2.h)
    lo = dict(x=166 + 14 + 4, y=row2_b, w=w3, h=ROW2.h)
    click_b = dict(w=click_wh[0], h=84)
    L["weather"] = dict(icon=dict(x=60, y=wy + 1), temp=temp, hi=hi, lo=lo,
                        click=dict(x=74, y=LINE_BOTTOM + 4, **click_b))

    # wysokość n.p.m. (duża) + ciśnienie (drugi rząd)
    unit_m = unit_bottom("m", 26, LARGE.h, var="Bold")
    save(unit_m, "large/unit_m.png")
    save(unit_bottom("ft", 26, LARGE.h, var="Bold"), "large/unit_ft.png")
    mountain = icon_mountain().done()
    paste(bg, mountain, 245, wy + (LARGE.h - mountain.height) // 2)
    alt_r = 420
    w = text_img_slots(4, LARGE, LARGE_SPACE, unit_m.width)
    alt = dict(x=alt_r - w, y=wy, w=w, h=LARGE.h)
    ghosts(ghost_large, alt_r - unit_m.width, wy, 4, large_pitch)
    unit_hpa = unit_bottom("hPa", 20, ROW2.h, var="Bold")
    save(unit_hpa, "row2/unit_hpa.png")
    paste(bg, icon_gauge().done(), 250, row2_b + (ROW2.h - 24) // 2)
    w = text_img_slots(4, ROW2, ROW2_SPACE, unit_hpa.width + 2)
    L["altitude"] = dict(text=alt, click=dict(x=246, y=LINE_BOTTOM + 4, **click_b))
    L["pressure"] = dict(text=dict(x=394 - w, y=row2_b, w=w, h=ROW2.h))

    # ---- bateria: na górze, nad polami ------------------------------------------------------
    for i in range(6):
        save(icon_battery(i).done(), f"battery/{i}.png")
    tpct = unit_bottom("%", LABEL, TINY.h)
    save(tpct, "tiny/unit_pct.png")
    # procent wyrównany do lewej, tuż za ikoną; grupa wyśrodkowana dla wartości 2-cyfrowej
    w = text_img_slots(3, TINY, TINY_SPACE, tpct.width)
    bx = 240 - (26 + 5 + text_img_slots(2, TINY, TINY_SPACE, tpct.width)) // 2
    by = 28
    L["battery"] = dict(icon=dict(x=bx, y=by + TINY.h // 2 - 7), text=dict(x=bx + 26 + 5, y=by, w=w, h=TINY.h))

    # ---- AOD: przygaszone linie stref ------------------------------------------------------
    fr = Image.new("RGBA", (480 * SS, 480 * SS), (0, 0, 0, 0))
    zone_lines(fr, AOD_FRAME, dividers=False)
    fr = fr.resize((480, 480), Image.BOX)
    box = fr.getbbox()
    save(fr.crop(box), "aod/frame.png")
    L["aod"] = dict(frameX=box[0], frameY=box[1])
    L["space"] = dict(small=SMALL_SPACE, tiny=TINY_SPACE, large=LARGE_SPACE, row2=ROW2_SPACE)

    save(bg, "bg.png")

    # ---- layout.js -------------------------------------------------------------------
    js = ("// Wygenerowane przez tools/gen_assets.py - nie edytuj ręcznie.\n"
          "export const L = " + json.dumps(L, indent=2) + "\n")
    with open(os.path.join(ROOT, "watchface", "layout.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write(js)

    # ---- podglądy -----------------------------------------------------------------------
    sample = dict(h="10", m="58", s="50", pm=True, week=3, day="30", steps="8670", step_lvl=8,
                  hr="86", cal="280", weather=0, temp="22", hi="24", lo="13", batt="75", batt_lvl=4,
                  alt="245", baro="1013", alarm="06:45")
    normal = render_preview(bg, L, sample, aod=False)
    aod = render_preview(None, L, sample, aod=True)
    os.makedirs(DOCS, exist_ok=True)
    circle(normal).save(os.path.join(DOCS, "podglad.png"))
    circle(aod).save(os.path.join(DOCS, "podglad-aod.png"))
    circle(normal).resize((324, 324), Image.LANCZOS).save(os.path.join(ASSETS, "icon.png"))
    print("OK:", len(os.listdir(ASSETS)), "pozycji w assets/gt.r")


def a(rel):
    return Image.open(os.path.join(ASSETS, rel)).convert("RGBA")


def text_img(canvas, box, text, folder, unit=None, space=SMALL_SPACE, dot=None, left=False):
    """Emulacja TEXT_IMG z wyrównaniem do prawej."""
    imgs = []
    for c in text:
        if c == ".":
            imgs.append(a(dot))
        elif c == ":":
            imgs.append(a(f"{folder}/colon.png"))
        elif c == "-":
            imgs.append(a(f"{folder}/minus.png"))
        else:
            imgs.append(a(f"{folder}/{c}.png"))
    if unit:
        imgs.append(a(unit))
    total = sum(i.width for i in imgs) + space * (len(imgs) - 1)
    x = box["x"] if left else box["x"] + box["w"] - total
    for i in imgs:
        paste(canvas, i, x, box["y"])
        x += i.width + space


def render_preview(bg, L, s, aod):
    c = Image.new("RGBA", (480, 480), (0, 0, 0, 255))
    t = L["time"]
    if aod:
        paste(c, a("aod/frame.png"), L["aod"]["frameX"], L["aod"]["frameY"])
        paste(c, a("aod/colon.png"), t["colonX"], t["y"])
        pre = "aod/"
    else:
        c.alpha_composite(bg)
        pre = ""
    pitch_big = BIG.img_w + t["space"]
    for i, ch in enumerate(s["h"]):
        paste(c, a(f"{pre}big/{ch}.png"), t["hourX"] + i * pitch_big, t["y"])
    for i, ch in enumerate(s["m"]):
        paste(c, a(f"{pre}big/{ch}.png"), t["minuteX"] + i * pitch_big, t["y"])
    pitch_med = MED.img_w + L["date"]["space"]
    for i, ch in enumerate(s["day"]):
        paste(c, a(f"{pre}med/{ch}.png"), L["date"]["x"] + i * pitch_med, L["date"]["y"])
    paste(c, a(f"{pre}week/{s['week']}.png"), L["week"]["x"], L["week"]["y"])
    if aod:
        return c
    for i, ch in enumerate(s["s"]):
        paste(c, a(f"med/{ch}.png"), t["secondX"] + i * pitch_med, t["secondY"])
    if s["pm"]:
        paste(c, a("time/pm.png"), t["ampmX"], t["ampmY"])
    if s["alarm"]:
        st = L["status"]["bell"]
        paste(c, a("status/bell.png"), st["x"], st["y"])
        text_img(c, L["alarm"], s["alarm"], "row2", space=ROW2_SPACE)
    text_img(c, L["steps"]["text"], s["steps"], "small")
    paste(c, a(f"bar/{s['step_lvl']}.png"), L["steps"]["bar"]["x"], L["steps"]["bar"]["y"])
    text_img(c, L["heart"]["text"], s["hr"], "small")
    text_img(c, L["cal"]["text"], s["cal"], "tiny", space=TINY_SPACE)
    w = L["weather"]
    paste(c, a(f"weather/{s['weather']}.png"), w["icon"]["x"], w["icon"]["y"])
    text_img(c, w["temp"], s["temp"], "large", unit="large/unit_c.png", space=LARGE_SPACE)
    text_img(c, w["hi"], s["hi"], "row2", space=ROW2_SPACE, left=True)
    text_img(c, w["lo"], s["lo"], "row2", space=ROW2_SPACE, left=True)
    text_img(c, L["altitude"]["text"], s["alt"], "large", unit="large/unit_m.png", space=LARGE_SPACE)
    text_img(c, L["pressure"]["text"], s["baro"], "row2", space=ROW2_SPACE, unit="row2/unit_hpa.png")
    b = L["battery"]
    paste(c, a(f"battery/{s['batt_lvl']}.png"), b["icon"]["x"], b["icon"]["y"])
    text_img(c, b["text"], s["batt"], "tiny", space=TINY_SPACE, unit="tiny/unit_pct.png", left=True)
    return c


def circle(img):
    m = Image.new("L", (480 * SS, 480 * SS), 0)
    ImageDraw.Draw(m).ellipse([0, 0, 480 * SS - 1, 480 * SS - 1], fill=255)
    out = img.copy()
    out.putalpha(m.resize((480, 480), Image.LANCZOS))
    return out


if __name__ == "__main__":
    main()
