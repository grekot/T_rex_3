#!/usr/bin/env python3
"""Postacie z arkuszy wygenerowanych w Gemini (../pupil-art/<forma>_sheet.jpg).

Arkusz to siatka 2 x 2 tej samej postaci na białym tle: spokój, radość, smutek, sen.
Skrypt wycina tło (białe połączone z brzegiem), zostawia tylko największy kształt
(znika np. napis "zZ" przy śpiącym), wyrównuje wszystkie cztery miny wspólną skalą
i stopami na tej samej wysokości, a potem robi z nich klatki gry jak gen_assets.py:
oddech = lekkie spłaszczenie, podskok, ciemno = przyciemnienie snu, lewo = lustro,
jedzenie = radość (otwarta buzia).

Uruchamia go gen_assets.py na końcu (nadpisuje klatki form, które mają arkusz),
ale można też samodzielnie:   python tools/import_art.py [forma ...]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# arkusze leżą poza folderem aplikacji: zeus pakuje cały folder do .ip-package
ART = os.path.join(os.path.dirname(ROOT), "pupil-art")
ASSETS = os.path.join(ROOT, "assets", "gt.r")

SPRITE = 168
THUMB = 64
FEET_Y = 160  # stopy na tej wysokości (jak w rysowanych postaciach)
MAX_H = 150  # najwyższa mina ma tyle px
MAX_W = 162
TAIL_OVER = 0.22  # o tyle szerokości może wystawać ogon
TAIL_KEEP = {"kolec": 0.0, "lotek": 0.0, "ptero": 0.0, "mewa": 0.0}  # formy, którym ogona/skrzydeł nie obcinamy
WORK = 4  # obróbka w 4-krotnym powiększeniu, potem zmniejszenie z antyaliasingiem
CELLS = ["idle", "happy", "sad", "sleep"]  # kolejność w siatce: wierszami


def cut_cell(cell):
    """Wycina postać z białego tła: zwraca RGBA przycięte do kształtu."""
    rgb = np.asarray(cell.convert("RGB")).astype(np.int16)
    near_white = rgb.min(axis=2) > 226
    lum = Image.fromarray((near_white * 255).astype(np.uint8), "L").copy()  # kopia: obraz z numpy jest tylko do odczytu
    h, w = near_white.shape
    # białe połączone z brzegiem = tło
    for x in range(0, w, 7):
        for y in (0, h - 1):
            if lum.getpixel((x, y)) == 255:
                ImageDraw.floodfill(lum, (x, y), 128, thresh=0)
    for y in range(0, h, 7):
        for x in (0, w - 1):
            if lum.getpixel((x, y)) == 255:
                ImageDraw.floodfill(lum, (x, y), 128, thresh=0)
    bg = np.asarray(lum) == 128
    fg = (~bg).astype(np.uint8) * 255
    # największy kształt: zalewanie od punktu w środku postaci
    ys, xs = np.nonzero(fg)
    if not len(xs):
        raise ValueError("pusta komórka")
    order = np.argsort(np.abs(ys - np.median(ys)) + np.abs(xs - np.median(xs)))
    sy, sx = int(ys[order[0]]), int(xs[order[0]])
    lab = Image.fromarray(fg, "L").copy()
    ImageDraw.floodfill(lab, (sx, sy), 100, thresh=0)
    mask = Image.fromarray(((np.asarray(lab) == 100) * 255).astype(np.uint8), "L")
    # bez białej obwódki z JPEG-a: zjedz 1 px i lekko zmiękcz brzeg
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = cell.convert("RGBA")
    out.putalpha(mask)
    bbox = mask.point(lambda v: 255 if v > 40 else 0).getbbox()
    return out.crop(bbox)


def load_sheet(path):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    cells = []
    for r in range(2):
        for c in range(2):
            cells.append(sheet.crop((c * w // 2, r * h // 2, (c + 1) * w // 2, (r + 1) * h // 2)))
    cuts = {name: cut_cell(cell) for name, cell in zip(CELLS, cells)}
    # Gemini czasem obraca jedną minę w lewo: odwróć ją, jeśli w lustrze lepiej pasuje do spokojnej
    ref = shape(cuts["idle"])
    for name in CELLS[1:]:
        flip = ImageOps.mirror(cuts[name])
        if overlap(ref, shape(flip)) > overlap(ref, shape(cuts[name])) + 0.03:
            cuts[name] = flip
            print("  %s: odwrócona do prawej" % name)
    return cuts


def shape(im, n=48):
    return np.asarray(im.getchannel("A").resize((n, n), Image.BILINEAR)) > 100


def overlap(a, b):
    return (a & b).sum() / max(1, (a | b).sum())


def place(cuts, tail=TAIL_OVER):
    """Wspólna skala dla wszystkich min, stopy na FEET_Y, środek w poziomie."""
    # bardzo szerokie postacie (długi ogon): ogon może wyjść do TAIL_OVER poza kadr po lewej,
    # głowa (po prawej) zostaje cała - lepiej niż mocno zmniejszona postać
    scale = min(MAX_H / max(im.height for im in cuts.values()), MAX_W * (1 + tail) / max(im.width for im in cuts.values()))
    out = {}
    S = SPRITE * WORK
    for name, im in cuts.items():
        nw, nh = max(1, round(im.width * scale * WORK)), max(1, round(im.height * scale * WORK))
        sm = im.resize((nw, nh), Image.LANCZOS)
        canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        x = (S - nw) // 2 if nw <= MAX_W * WORK else S - nw - (S - MAX_W * WORK) // 2
        canvas.alpha_composite(sm, (x, FEET_Y * WORK - nh))
        out[name] = canvas
    return out


def squash(img):
    w, h = img.size
    nw, nh = round(w * 1.025), round(h * 0.96)
    sq = img.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # stopy zostają na miejscu
    out.alpha_composite(sq, ((w - nw) // 2, round(FEET_Y * WORK * (1 - 0.96))))
    return out


def lift(img, px):
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img.crop((0, px * WORK, img.width, img.height)), (0, 0))
    return out


def dim(img):
    r, g, b, a = img.split()
    r = r.point(lambda v: v * 30 // 100)
    g = g.point(lambda v: v * 33 // 100)
    b = b.point(lambda v: v * 50 // 100)
    return Image.merge("RGBA", (r, g, b, a))


def frames(big):
    f = {
        "idle0": big["idle"],
        "idle1": squash(big["idle"]),
        "happy0": big["happy"],
        "happy1": lift(big["happy"], 8),
        "sad0": big["sad"],
        "sad1": squash(big["sad"]),
        "sleep0": big["sleep"],
        "sleep1": squash(big["sleep"]),
        "dark0": dim(big["sleep"]),
        "dark1": dim(squash(big["sleep"])),
        "eat0": big["happy"],
        "eat1": squash(big["happy"]),
        "left": ImageOps.mirror(big["idle"]),
    }
    return {k: v.resize((SPRITE, SPRITE), Image.LANCZOS) for k, v in f.items()}


def silhouette(img, color=(46, 46, 56)):
    out = Image.new("RGBA", img.size, color + (255,))
    out.putalpha(img.getchannel("A"))
    return out


def import_form(fid):
    path = os.path.join(ART, fid + "_sheet.jpg")
    if not os.path.exists(path):
        path = os.path.join(ART, fid + "_sheet.png")
    if not os.path.exists(path):
        return None
    big = place(load_sheet(path), TAIL_KEEP.get(fid, TAIL_OVER))
    fr = frames(big)
    d = os.path.join(ASSETS, "pet", fid)
    os.makedirs(d, exist_ok=True)
    for name, img in fr.items():
        img.save(os.path.join(d, name + ".png"), optimize=True)
    th = big["idle"].resize((THUMB, THUMB), Image.LANCZOS)
    th.save(os.path.join(ASSETS, "thumb", fid + ".png"), optimize=True)
    silhouette(th).save(os.path.join(ASSETS, "thumb", fid + "_x.png"), optimize=True)
    return fr


# --- jajka: jeden obraz (art/eggs_sheet.jpg), trzy jajka obok siebie --------------
EGG_IDS = ["egg", "eggh", "eggf"]  # od lewej: kremowe w zielone kropki, niebieskie, brzoskwiniowe
EGG_LINE = {"egg": "rex", "eggh": "herb", "eggf": "fly"}
EGG_PICK = 112  # jak w gen_assets.py
EGG_H = 128  # wysokość jajka w kadrze 168 px


def split_columns(path, n=3):
    """Dzieli obraz na n części w pionowych przerwach między obiektami na białym tle."""
    sheet = Image.open(path).convert("RGB")
    fg = np.asarray(sheet).astype(np.int16).min(axis=2) <= 226
    cols = fg.sum(axis=0) > 2
    runs, start = [], None
    for x, on in enumerate(list(cols) + [False]):
        if on and start is None:
            start = x
        elif not on and start is not None:
            runs.append((start, x))
            start = None
    runs = sorted(sorted(runs, key=lambda r: r[1] - r[0], reverse=True)[:n])
    if len(runs) < n:
        raise ValueError("nie znaleziono %d jajek" % n)
    pad = 6
    return [sheet.crop((max(0, a - pad), 0, min(sheet.width, b + pad), sheet.height)) for a, b in runs]


def crack(img):
    """Pęknięcie: zygzak przez środek jajka w kolorze obrysu."""
    a = np.asarray(img.getchannel("A")) > 128
    ys, xs = np.nonzero(a)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    y = y0 + (y1 - y0) * 0.45
    w = x1 - x0
    pts = []
    for i in range(9):
        t = i / 8
        pts.append((x0 + w * (0.1 + 0.8 * t), y + (-1 if i % 2 else 1) * (y1 - y0) * 0.05))
    out = img.copy()
    d = ImageDraw.Draw(out)
    d.line(pts, fill=(60, 44, 36, 255), width=max(2, round(3 * WORK)), joint="curve")
    return out


def import_eggs():
    path = os.path.join(ART, "eggs_sheet.jpg")
    if not os.path.exists(path):
        path = os.path.join(ART, "eggs_sheet.png")
    if not os.path.exists(path):
        return {}
    cuts = [cut_cell(c) for c in split_columns(path)]
    scale = EGG_H / max(c.height for c in cuts)  # wspólna skala: jajka różnej wielkości zostają różne
    S = SPRITE * WORK
    out = {}
    for fid, im in zip(EGG_IDS, cuts):
        nw, nh = round(im.width * scale * WORK), round(im.height * scale * WORK)
        big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        big.alpha_composite(im.resize((nw, nh), Image.LANCZOS), ((S - nw) // 2, FEET_Y * WORK - nh))
        center = (S // 2, FEET_Y * WORK)
        fr = {
            "egg0": big,
            "egg1": big.rotate(-7, resample=Image.BICUBIC, center=center),
            "egg2": crack(big).rotate(7, resample=Image.BICUBIC, center=center),
        }
        fr = {k: v.resize((SPRITE, SPRITE), Image.LANCZOS) for k, v in fr.items()}
        d = os.path.join(ASSETS, "pet", fid)
        os.makedirs(d, exist_ok=True)
        for name, img in fr.items():
            img.save(os.path.join(d, name + ".png"), optimize=True)
        big.resize((EGG_PICK, EGG_PICK), Image.LANCZOS).save(os.path.join(ASSETS, "ui", "egg_" + EGG_LINE[fid] + ".png"), optimize=True)
        if fid == "egg":
            big.resize((34, 34), Image.LANCZOS).save(os.path.join(ASSETS, "ui", "egg_small.png"), optimize=True)
        out[fid] = fr
    return out


def available():
    if not os.path.isdir(ART):
        return []
    return sorted({n.split("_sheet")[0] for n in os.listdir(ART) if "_sheet." in n} - {"eggs"})


def main(ids):
    done = []
    for fid in ids or available() + ["eggs"]:
        if fid == "eggs" and import_eggs() or fid != "eggs" and import_form(fid):
            done.append(fid)
    print("z arkuszy Gemini:", ", ".join(done) or "-")
    return done


if __name__ == "__main__":
    main(sys.argv[1:])
