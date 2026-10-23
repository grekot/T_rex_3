"""Rysowanie gładkiej grafiki: kształty w układzie projektu (px), rysowane w SS-krotnym
powiększeniu i zmniejszane z antyaliasingiem.

Postać to lista kształtów ciała (z obrysem jak naklejka - jeden wspólny kontur sylwetki)
i lista detali bez obrysu (brzuch, plamy, twarz).
"""
import math

from PIL import Image, ImageDraw

SS = 8


def shade(c, f):
    return tuple(max(0, min(255, round(v * f))) for v in c[:3])


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def bezier(pts, n=40):
    """Krzywa Béziera przez punkty kontrolne (2 = odcinek, 3 = kwadratowa, 4 = sześcienna)."""
    out = []
    k = len(pts) - 1
    for i in range(n + 1):
        t = i / n
        x = y = 0.0
        for j, (px, py) in enumerate(pts):
            b = math.comb(k, j) * (t ** j) * ((1 - t) ** (k - j))
            x += b * px
            y += b * py
        out.append((x, y))
    return out


def ellipse_pts(cx, cy, rx, ry, rot=0.0, n=72):
    a = math.radians(rot)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


class Shape:
    def __init__(self, kind, color, **kw):
        self.kind = kind
        self.color = color
        self.kw = kw

    def draw(self, d, grow=0.0, color=None, s=SS):
        c = (color or self.color)[:3] + (255,)
        k = self.kw
        if self.kind == "ell":
            pts = ellipse_pts(k["cx"], k["cy"], k["rx"] + grow, k["ry"] + grow, k.get("rot", 0))
            d.polygon([(x * s, y * s) for x, y in pts], fill=c)
        elif self.kind == "poly":
            pts = [(x * s, y * s) for x, y in k["pts"]]
            d.polygon(pts, fill=c)
            if grow > 0:
                d.line(pts + [pts[0]], fill=c, width=max(1, round(2 * grow * s)), joint="curve")
                for x, y in pts:
                    r = grow * s
                    d.ellipse([x - r, y - r, x + r, y + r], fill=c)
        elif self.kind == "tube":
            path = bezier(k["pts"], k.get("n", 40))
            r0, r1 = k["r0"], k["r1"]
            for i, (x, y) in enumerate(path):
                t = i / (len(path) - 1)
                r = (r0 + (r1 - r0) * t + grow) * s
                d.ellipse([x * s - r, y * s - r, x * s + r, y * s + r], fill=c)
        elif self.kind == "rrect":
            x0, y0, x1, y1, r = k["x0"] - grow, k["y0"] - grow, k["x1"] + grow, k["y1"] + grow, k["r"] + grow
            d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s], radius=r * s, fill=c)


def ell(cx, cy, rx, ry, color, rot=0.0):
    return Shape("ell", color, cx=cx, cy=cy, rx=rx, ry=ry, rot=rot)


def poly(pts, color):
    return Shape("poly", color, pts=pts)


def tube(pts, r0, r1, color, n=40):
    return Shape("tube", color, pts=pts, r0=r0, r1=r1, n=n)


def rrect(x0, y0, x1, y1, r, color):
    return Shape("rrect", color, x0=x0, y0=y0, x1=x1, y1=y1, r=r)


class Canvas:
    """Płótno w powiększeniu SS; współrzędne podaje się w px projektu."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def body(self, shapes, outline, width):
        # najpierw powiększone kształty w kolorze konturu (wspólna sylwetka), potem wypełnienia
        for sh in shapes:
            sh.draw(self.d, grow=width, color=outline)
        for sh in shapes:
            sh.draw(self.d)

    def shapes(self, shapes):
        for sh in shapes:
            sh.draw(self.d)

    def layer(self, shapes, alpha):
        """Kształty półprzezroczyste (rumieńce, cienie)."""
        lay = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(lay)
        for sh in shapes:
            sh.draw(d)
        a = lay.getchannel("A").point(lambda v: v * alpha // 255)
        lay.putalpha(a)
        self.img.alpha_composite(lay)

    def line(self, pts, color, width, curve=True):
        s = SS
        path = bezier(pts) if curve and len(pts) > 2 else pts
        p = [(x * s, y * s) for x, y in path]
        self.d.line(p, fill=color[:3] + (255,), width=max(1, round(width * s)), joint="curve")
        r = width * s / 2
        for x, y in (p[0], p[-1]):
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=color[:3] + (255,))

    def result(self, size=None):
        w, h = size or (self.w, self.h)
        return self.img.resize((w, h), Image.LANCZOS)
