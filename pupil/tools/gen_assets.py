#!/usr/bin/env python3
"""Generuje grafikę Pupila: klatki animacji każdej formy, ikony akcji, drobiazgi,
utils/geometry.js, arkusz podglądu docs/arkusz.png i makietę docs/podglad.png.

Styl gładki: postacie z tools/forms.py (elipsy, wielokąty, zwężające się "rurki")
rysowane w 8-krotnym powiększeniu z obrysem jak naklejka; miny (oczy, usta, rumieniec,
łza) dorysowuje render(). Klatki: oddech = lekkie spłaszczenie, radość = podskok,
sen przy zgaszonym świetle = przyciemnienie, "lewo" = lustrzane odbicie.

Uruchom z folderu pupil:   python tools/gen_assets.py
Wymaga: Pillow, font Segoe UI (Windows 10/11) - tylko do podpisów na arkuszu.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from draw import SS, Canvas, ell, poly, rrect, shade  # noqa: E402
from forms import FORMS  # noqa: E402
from icons import ICONS, OUT as ICON_OUT  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
FONT = "C:/Windows/Fonts/segoeui.ttf"
FONT_B = "C:/Windows/Fonts/segoeuib.ttf"

SPRITE = 168
THUMB = 64
EGG_PICK = 112  # jajka na ekranie wyboru
EGGS = {"rex": "egg", "herb": "eggh", "fly": "eggf"}
DISC = 76
ICON = 48
OUTLINE = 2.6  # grubość obrysu postaci (px)

EYE = (22, 20, 28)
MOUTH = (176, 40, 62)
TONGUE = (246, 120, 140)
CHEEK = (255, 120, 150)
TEAR = (120, 196, 255)
WHITE = (252, 250, 244)

FRAMES = ["idle0", "idle1", "happy0", "happy1", "sad0", "sad1", "sleep0", "sleep1", "dark0", "dark1", "eat0", "eat1", "left"]
EGG_FRAMES = ["egg0", "egg1", "egg2"]


# --- twarz -----------------------------------------------------------------------


def draw_eye(c, P, f, eyes, tear):
    x, y, r = f["eye"]
    if eyes in ("open", "sad"):
        c.shapes([ell(x, y, r * 0.86 + 1.2, r + 1.2, P["O"]), ell(x, y, r * 0.86, r, WHITE)])
        dy = r * (0.28 if eyes == "sad" else 0.08)
        c.shapes([ell(x + r * 0.2, y + dy, r * 0.56, r * 0.66, EYE), ell(x + r * 0.38, y + dy - r * 0.3, r * 0.22, r * 0.22, WHITE)])
        if eyes == "sad":
            c.line([(x - r * 1.0, y - r * 1.65), (x + r * 0.9, y - r * 1.1)], shade(P["B"], 0.4), r * 0.32, curve=False)
    elif eyes == "happy":
        c.line([(x - r * 0.85, y + r * 0.35), (x, y - r * 0.75), (x + r * 0.85, y + r * 0.35)], EYE, r * 0.34)
    elif eyes == "closed":
        c.line([(x - r * 0.85, y), (x, y + r * 0.6), (x + r * 0.85, y)], EYE, r * 0.3)
    if f.get("brow") and eyes == "open":
        if f.get("grumpy"):
            c.line([(x - r * 1.1, y - r * 1.45), (x + r * 1.0, y - r * 0.85)], shade(P["B"], 0.45), r * 0.42, curve=False)
        else:
            c.line([(x - r * 1.1, y - r * 1.15), (x, y - r * 1.35), (x + r * 1.1, y - r * 1.05)], shade(P["B"], 0.55), r * 0.4)
    if tear:
        c.shapes([poly([(x - r * 0.1, y + r * 1.15), (x - r * 0.45, y + r * 1.9), (x + r * 0.25, y + r * 1.9)], TEAR), ell(x - r * 0.1, y + r * 1.95, r * 0.36, r * 0.36, TEAR)])


def draw_mouth(c, P, f, mouth):
    kind, x0, x1, y = f["mouth"]
    mid = (x0 + x1) / 2
    w = x1 - x0
    if kind == "smile":
        if mouth == "closed":
            c.line([(x0, y - 1.5), (mid, y + 2.5), (x1, y - 2)], P["O"], 2.2)
        else:
            h = 6 if mouth == "open" else 9
            c.shapes([ell(mid, y + h * 0.4, w * 0.42 + 1.4, h + 1.4, P["O"]), ell(mid, y + h * 0.4, w * 0.42, h, MOUTH), ell(mid + 1, y + h * 0.9, w * 0.26, h * 0.45, TONGUE)])
    elif kind == "jaw":
        if mouth == "closed":
            c.line([(x0, y + 1), (mid, y + 3), (x1, y - 1)], P["O"], 2.4)
            return
        h = 10 if mouth == "open" else 16
        pts = [(x0, y + 1), (x1, y - 1), (x1 - 3, y + h * 0.7), (mid, y + h), (x0 + 6, y + h * 0.6)]
        c.body([poly(pts, MOUTH)], P["O"], 1.2)
        c.shapes([ell(mid + 4, y + h * 0.7, w * 0.22, h * 0.25, TONGUE)])
        n = max(3, int(w // 9))
        for i in range(n):
            tx = x0 + 8 + i * (w - 12) / n
            c.shapes([poly([(tx, y), (tx + 4, y), (tx + 2, y + 4.5)], WHITE)])
    elif kind == "beak":
        if mouth == "closed":
            c.line([(x0, y), (x1 - 4, y)], P["O"], 1.6, curve=False)
        else:
            h = 9 if mouth == "open" else 14
            c.body([poly([(x0, y - 1), (x1 - 2, y - 2), (x1 - 8, y + h * 0.4), (x0 + 4, y + h)], MOUTH)], P["O"], 1.2)


def render(fid, eyes="open", mouth="closed", cheek=False, tear=False, squash=False, lift=0, dark=False, mirror=False, big=False):
    """Klatka postaci. big=True zwraca obraz w powiększeniu SS (do miniatur i ikony)."""
    F = FORMS[fid]
    P = F["P"]
    parts = F["build"](P)
    c = Canvas(SPRITE, SPRITE)
    for sh in parts["back"]:
        c.body([sh], P["O"], OUTLINE)
    c.body(parts["body"], P["O"], OUTLINE)
    c.shapes(parts["detail"])
    f = parts["face"]
    if f:
        if cheek:
            cx, cy = f["cheek"]
            c.layer([ell(cx, cy, 7, 4.5, CHEEK)], 150)
        draw_eye(c, P, f, eyes, tear)
        draw_mouth(c, P, f, mouth)
    img = c.img
    if squash:  # oddech: odrobinę niższy i szerszy, stopy w miejscu
        w, h = img.size
        nw, nh = round(w * 1.025), round(h * 0.96)
        sq = img.resize((nw, nh), Image.LANCZOS)
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        img.alpha_composite(sq, ((w - nw) // 2, h - nh))
    if lift:
        moved = Image.new("RGBA", img.size, (0, 0, 0, 0))
        moved.alpha_composite(img.crop((0, lift * SS, img.width, img.height)), (0, 0))
        img = moved
    if dark:
        r, g, b, a = img.split()
        r = r.point(lambda v: v * 30 // 100)
        g = g.point(lambda v: v * 33 // 100)
        b = b.point(lambda v: v * 50 // 100)
        img = Image.merge("RGBA", (r, g, b, a))
    if mirror:
        img = ImageOps.mirror(img)
    return img if big else img.resize((SPRITE, SPRITE), Image.LANCZOS)


def egg_frame(fid="egg", angle=0, crack=False, size=SPRITE):
    F = FORMS[fid]
    P = F["P"]
    parts = F["build"](P)
    c = Canvas(SPRITE, SPRITE)
    c.body(parts["body"], shade(P["B"], 0.45), OUTLINE)
    c.shapes(parts["detail"])
    if crack:
        c.line([(38, 100), (50, 92), (60, 104), (72, 92), (84, 106), (96, 92), (108, 104), (120, 94), (130, 100)], shade(P["B"], 0.35), 2.6, curve=False)
    img = c.img
    if angle:
        img = img.rotate(angle, resample=Image.BICUBIC, center=(84 * SS, 158 * SS))
    return img.resize((size, size), Image.LANCZOS)


def frames_for(fid):
    if fid in EGGS.values():
        return {"egg0": egg_frame(fid), "egg1": egg_frame(fid, -7), "egg2": egg_frame(fid, 7, crack=True)}
    return {
        "idle0": render(fid),
        "idle1": render(fid, squash=True),
        "happy0": render(fid, eyes="happy", mouth="open", cheek=True),
        "happy1": render(fid, eyes="happy", mouth="wide", cheek=True, lift=8),
        "sad0": render(fid, eyes="sad"),
        "sad1": render(fid, eyes="sad", tear=True, squash=True),
        "sleep0": render(fid, eyes="closed"),
        "sleep1": render(fid, eyes="closed", squash=True),
        "dark0": render(fid, eyes="closed", dark=True),
        "dark1": render(fid, eyes="closed", squash=True, dark=True),
        "eat0": render(fid, mouth="wide", cheek=True),
        "eat1": render(fid, eyes="happy", cheek=True, squash=True),
        "left": render(fid, mirror=True),
    }


# --- ikony i drobiazgi -----------------------------------------------------------


def icon_img(iid, size=ICON, flip=False):
    shapes, detail = ICONS[iid]()
    c = Canvas(ICON, ICON)
    c.body(shapes, ICON_OUT, 1.8)
    c.shapes(detail)
    img = c.result((size, size))
    return ImageOps.mirror(img) if flip else img


def disc(color, ring=None):
    big = Image.new("RGBA", (DISC * SS, DISC * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.ellipse([0, 0, DISC * SS - 1, DISC * SS - 1], fill=(ring or color) + (255,))
    if ring:
        w = 4 * SS
        d.ellipse([w, w, DISC * SS - 1 - w, DISC * SS - 1 - w], fill=color + (255,))
    return big.resize((DISC, DISC), Image.LANCZOS)


def action_icon(iid, selected):
    base = disc((70, 56, 30), ring=(255, 170, 40)) if selected else disc((34, 34, 42))
    base.alpha_composite(icon_img(iid), ((DISC - ICON) // 2, (DISC - ICON) // 2))
    return base


def zzz():
    c = Canvas(56, 48)
    col = (176, 204, 255)
    for x, y, s in ((2, 34, 10), (18, 20, 13), (36, 2, 17)):
        c.line([(x, y), (x + s, y), (x, y + s), (x + s, y + s)], col, 3.2, curve=False)
    return c.result()


def trees():
    c = Canvas(SPRITE, SPRITE)
    out = (18, 50, 30)
    for cx, top, h, col in ((50, 30, 118, (52, 150, 82)), (120, 14, 134, (40, 128, 70)), (86, 52, 100, (70, 172, 92))):
        shapes = [rrect(cx - 5, top + h - 18, cx + 5, top + h + 12, 3, (122, 82, 48))]
        for k in range(3):
            y0 = top + k * h * 0.26
            wdt = 22 + k * 10
            shapes.append(poly([(cx, y0), (cx + wdt, y0 + h * 0.42), (cx - wdt, y0 + h * 0.42)], col))
        c.body(shapes, out, 2.2)
    return c.result()


def log_img():
    c = Canvas(192, 36)
    c.body([rrect(4, 4, 188, 32, 14, (152, 98, 52))], (70, 42, 20), 2)
    c.shapes([ell(176, 18, 10, 13, (226, 182, 122)), ell(176, 18, 5, 7, (196, 146, 90))])
    for x in (30, 70, 112, 146):
        c.line([(x, 11), (x + 18, 12)], (112, 70, 34), 2, curve=False)
    return c.result()


def app_icon():
    size = 248
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, size * SS - 1, size * SS - 1], fill=(30, 62, 46, 255))
    img = big.resize((size, size), Image.LANCZOS)
    sprite = render("tupek", eyes="happy", mouth="open", cheek=True, big=True).resize((200, 200), Image.LANCZOS)
    img.alpha_composite(sprite, ((size - 200) // 2, (size - 200) // 2 + 4))
    return img


def silhouette(img, color=(46, 46, 56)):
    out = Image.new("RGBA", img.size, color + (255,))
    out.putalpha(img.getchannel("A"))
    return out


def save(img, *parts):
    path = os.path.join(ASSETS, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


# --- układ ekranu głównego -------------------------------------------------------

RING_IDS = ["meal", "snack", "light", "play", "medicine", "clean", "scold", "stats"]
RING_LABELS = ["Jedzenie", "Przekąska", "Światło", "Zabawa", "Lekarstwo", "Sprzątanie", "Zgań", "Statystyki"]
RING_R = 192  # promień okręgu środków ikon


def ring_positions():
    """Środki ikon akcji: łuk 290° od dołu po lewej zgodnie z ruchem wskazówek, dół wolny na napis."""
    out = []
    n = len(RING_IDS)
    span = 290
    for i in range(n):
        a = math.radians(-span / 2 + i * span / (n - 1))
        out.append((round(240 + RING_R * math.sin(a)), round(240 - RING_R * math.cos(a))))
    return out


def write_geometry():
    """utils/geometry.js - rozmiary obrazków i położenie ikon pierścienia (projekt 480 px)."""
    ring = ",\n".join('  { id: "%s", cx: %d, cy: %d }' % (iid, cx, cy) for iid, (cx, cy) in zip(RING_IDS, ring_positions()))
    lines = [
        "// Wygenerowane przez tools/gen_assets.py - nie edytować ręcznie.",
        "export const SPRITE = %d;" % SPRITE,
        "export const THUMB = %d;" % THUMB,
        "export const DISC = %d;" % DISC,
        "export const ICON = %d; // poop, skull, alert, meal, snack" % ICON,
        "export const HEART = 36;",
        "export const ARROW = 60;",
        "export const BALL = 32;",
        "export const EGG_PICK = %d;" % EGG_PICK,
        "export const ZZZ = { w: 56, h: 48 };",
        "export const LOG = { w: 192, h: 36 };",
        "export const RING = [\n%s,\n];" % ring,
    ]
    with open(os.path.join(ROOT, "utils", "geometry.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


# --- podglądy --------------------------------------------------------------------

NAMES = {
    "egg": "Jaja: drapieżniki, roślinożercy, latające",
    "pisklak": "Drapieżniki: Pisklak, Tupek, Łobuz, Rex (wzorowo), Allo",
    "kropek": "Roślinożercy: Kropek, Rożek, Rogal, Szyjek (wzorowo), Kolec",
    "piorko": "Latające: Piórko, Pterek, Lotek, Ptero (wzorowo), Mewa",
    "gapcio": "Zaniedbane (wspólne): Gapcio, Mruk, Burczek",
}
LINES_SHEET = [
    ("egg", ["egg", "eggh", "eggf"]),
    ("pisklak", ["pisklak", "tupek", "lobuz", "rex", "allo"]),
    ("kropek", ["kropek", "rozek", "rogal", "szyjek", "kolec"]),
    ("piorko", ["piorko", "pterek", "lotek", "ptero", "mewa"]),
    ("gapcio", ["gapcio", "mruk", "burczek"]),
]
FRAME_ROWS = ["pisklak", "tupek", "lobuz", "rex", "allo", "kropek", "rozek", "rogal", "szyjek", "kolec", "piorko", "pterek", "lotek", "ptero", "mewa", "gapcio", "mruk", "burczek"]


def sheet(all_frames):
    font = ImageFont.truetype(FONT, 18)
    bold = ImageFont.truetype(FONT_B, 22)
    cell = 104
    shown = ["idle0", "idle1", "happy0", "happy1", "sad1", "sleep0", "dark0", "eat0", "left"]
    labels = ["spokój", "oddech", "radość", "podskok", "smutek", "sen", "ciemno", "je", "w lewo"]
    left, top = 20, 60
    W = left * 2 + 130 + cell * len(shown)
    lines_h = len(LINES_SHEET) * 150
    H = top + lines_h + 50 + len(FRAME_ROWS) * cell + 60 + 2 * 110 + 20
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    d.text((left, 16), "Pupil - linie i formy (na zegarku 168 px)", font=bold, fill=(255, 255, 255))
    y = top
    for key, ids in LINES_SHEET:
        d.text((left, y), NAMES[key], font=font, fill=(255, 200, 90))
        for i, fid in enumerate(ids):
            fr = all_frames[fid]
            sp = fr["egg0" if fid in EGGS.values() else "idle0"].resize((120, 120), Image.LANCZOS)
            img.alpha_composite(sp, (left + i * 150, y + 24))
        y += 150
    y += 10
    d.text((left, y), "Klatki animacji", font=bold, fill=(255, 255, 255))
    y += 40
    for i, lab in enumerate(labels):
        d.text((left + 130 + i * cell + cell // 2, y - 6), lab, font=font, fill=(150, 150, 160), anchor="ms")
    for fid in FRAME_ROWS:
        d.text((left, y + cell // 2), FORMS_NAMES.get(fid, fid), font=font, fill=(255, 200, 90), anchor="lm")
        for i, k in enumerate(shown):
            x = left + 130 + i * cell
            bg = (12, 14, 30) if k.startswith("dark") else (16, 16, 18)
            d.rectangle([x + 3, y + 3, x + cell - 3, y + cell - 3], fill=bg)
            img.alpha_composite(all_frames[fid][k].resize((96, 96), Image.LANCZOS), (x + 4, y + 4))
        y += cell
    y += 10
    d.text((left, y), "Ikony akcji (zwykła / wybrana) i drobiazgi", font=bold, fill=(255, 255, 255))
    y += 40
    x = left
    for iid in RING_IDS:
        img.alpha_composite(action_icon(iid, False), (x, y))
        img.alpha_composite(action_icon(iid, iid == "meal"), (x, y + 90))
        x += 90
    x += 10
    for iid in ["heart", "heart_empty", "poop", "skull", "alert"]:
        img.alpha_composite(icon_img(iid), (x, y + 14))
        x += 58
    x = left + 90 * 8 + 10
    img.alpha_composite(zzz(), (x, y + 104))
    img.alpha_composite(icon_img("arrow", flip=True), (x + 70, y + 104))
    img.alpha_composite(icon_img("ball", 32), (x + 130, y + 112))
    img.alpha_composite(trees().resize((84, 84), Image.LANCZOS), (x + 180, y + 86))
    os.makedirs(DOCS, exist_ok=True)
    img.convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT).save(os.path.join(DOCS, "arkusz.png"), optimize=True)  # mały - trafia do .ip-package


FORMS_NAMES = {
    "pisklak": "Pisklak", "tupek": "Tupek", "lobuz": "Łobuz", "rex": "Rex", "allo": "Allo",
    "kropek": "Kropek", "rozek": "Rożek", "rogal": "Rogal", "szyjek": "Szyjek", "kolec": "Kolec",
    "piorko": "Piórko", "pterek": "Pterek", "lotek": "Lotek", "ptero": "Ptero", "mewa": "Mewa",
    "gapcio": "Gapcio", "mruk": "Mruk", "burczek": "Burczek",
}


def mock(all_frames, form, frame, selected, text, title):
    big = Image.new("RGBA", (480 * SS, 480 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, 480 * SS - 1, 480 * SS - 1], fill=(0, 0, 0, 255))
    img = big.resize((480, 480), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, 26)
    small = ImageFont.truetype(FONT, 22)
    for i, (cx, cy) in enumerate(ring_positions()):
        img.alpha_composite(action_icon(RING_IDS[i], i == selected), (cx - DISC // 2, cy - DISC // 2))
    img.alpha_composite(all_frames[form][frame], (240 - SPRITE // 2, 232 - SPRITE // 2))
    img.alpha_composite(icon_img("poop"), (324, 272))
    d.text((240, 122), title, font=small, fill=(150, 150, 160), anchor="mm")
    d.text((240, 338), text, font=font, fill=(255, 200, 90), anchor="mm")
    d.text((240, 424), RING_LABELS[selected], font=small, fill=(255, 255, 255), anchor="mm")
    return img


def main():
    write_geometry()
    all_frames = {}
    for fid in FORMS:
        fr = frames_for(fid)
        all_frames[fid] = fr
        for name, img in fr.items():
            save(img, "pet", fid, name + ".png")
        if fid in EGGS.values():
            line = [k for k, v in EGGS.items() if v == fid][0]
            save(egg_frame(fid, size=EGG_PICK), "ui", "egg_" + line + ".png")
        else:
            th = render(fid, big=True).resize((THUMB, THUMB), Image.LANCZOS)
            save(th, "thumb", fid + ".png")
            save(silhouette(th), "thumb", fid + "_x.png")
    for iid in RING_IDS:
        save(action_icon(iid, False), "ring", iid + ".png")
        save(action_icon(iid, True), "ring", iid + "_sel.png")
    save(icon_img("heart", 36), "ui", "heart.png")
    save(icon_img("heart_empty", 36), "ui", "heart_empty.png")
    for iid in ["poop", "skull", "alert", "meal", "snack"]:
        save(icon_img(iid), "ui", iid + ".png")
    save(icon_img("ball", 32), "ui", "ball.png")
    save(icon_img("arrow", 60), "ui", "arrow_r.png")
    save(icon_img("arrow", 60, flip=True), "ui", "arrow_l.png")
    save(zzz(), "ui", "zzz.png")
    save(trees(), "ui", "forest.png")
    save(log_img(), "ui", "log.png")
    lock = os.path.join(ASSETS, "ui", "lock.png")
    if os.path.exists(lock):
        os.remove(lock)  # nieużywana
    app_icon().save(os.path.join(ASSETS, "icon.png"), optimize=True)
    sheet(all_frames)
    m = Image.new("RGBA", (980, 480), (40, 40, 40, 255))
    m.alpha_composite(mock(all_frames, "tupek", "idle0", 0, "Trzeba posprzątać", "Tupek · 1 dzień"), (0, 0))
    m.alpha_composite(mock(all_frames, "rex", "happy0", 3, "Wygrana!", "Rex · 9 dni"), (500, 0))
    m.convert("RGB").save(os.path.join(DOCS, "podglad.png"), optimize=True)
    print("gotowe:", len(FORMS), "form")


if __name__ == "__main__":
    main()
