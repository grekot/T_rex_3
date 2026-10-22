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
    return {name: cut_cell(cell) for name, cell in zip(CELLS, cells)}


def place(cuts):
    """Wspólna skala dla wszystkich min, stopy na FEET_Y, środek w poziomie."""
    # bardzo szerokie postacie (długi ogon): ogon może wyjść do TAIL_OVER poza kadr po lewej,
    # głowa (po prawej) zostaje cała - lepiej niż mocno zmniejszona postać
    scale = min(MAX_H / max(im.height for im in cuts.values()), MAX_W * (1 + TAIL_OVER) / max(im.width for im in cuts.values()))
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
    big = place(load_sheet(path))
    fr = frames(big)
    d = os.path.join(ASSETS, "pet", fid)
    os.makedirs(d, exist_ok=True)
    for name, img in fr.items():
        img.save(os.path.join(d, name + ".png"), optimize=True)
    th = big["idle"].resize((THUMB, THUMB), Image.LANCZOS)
    th.save(os.path.join(ASSETS, "thumb", fid + ".png"), optimize=True)
    silhouette(th).save(os.path.join(ASSETS, "thumb", fid + "_x.png"), optimize=True)
    return fr


def available():
    if not os.path.isdir(ART):
        return []
    return sorted({n.split("_sheet")[0] for n in os.listdir(ART) if "_sheet." in n})


def main(ids):
    done = []
    for fid in ids or available():
        if import_form(fid):
            done.append(fid)
    print("z arkuszy Gemini:", ", ".join(done) or "-")
    return done


if __name__ == "__main__":
    main(sys.argv[1:])
