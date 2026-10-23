#!/usr/bin/env python3
"""Postacie z arkuszy wygenerowanych w Grok Imagine (../groot-art/<forma>_sheet.jpg).

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
ART = os.path.join(os.path.dirname(ROOT), "groot-art")
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
HOLE = 0.0002  # zamknięta biała dziura większa niż tyle pola komórki = tło


def cut_cell(cell, keep_all=False, sticker=False, holes=True):
    """Wycina postać z białego tła: zwraca RGBA przycięte do kształtu.
    keep_all: zostają wszystkie większe kształty (klocki obok postaci, sznurek balonu),
    nie tylko największy. sticker: tłem jest też jasnoszara obwódka naklejki. holes: zamknięte
    białe dziury (między ręką a tułowiem) też są tłem - nie dla rekwizytów (perła, piłka)."""
    rgb = np.asarray(cell.convert("RGB")).astype(np.int16)
    near_white = rgb.min(axis=2) > 226
    if sticker:
        near_white = (rgb.min(axis=2) > 165) & (rgb.max(axis=2) - rgb.min(axis=2) < 40)
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
    # białe dziury zamknięte w kształcie (między patykowatą ręką a tułowiem) też są tłem;
    # małe białe plamki (blask w oku) zostają
    import cv2

    n, lab, stats, _ = cv2.connectedComponentsWithStats((np.asarray(lum) == 255).astype(np.uint8), connectivity=4)
    if holes:
        big = [i for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] > HOLE * h * w]
        bg |= np.isin(lab, big)
    fg = (~bg).astype(np.uint8) * 255
    ys, xs = np.nonzero(fg)
    if not len(xs):
        raise ValueError("pusta komórka")
    if keep_all:
        import cv2

        n, lab, stats, _ = cv2.connectedComponentsWithStats(fg, connectivity=8)
        areas = stats[1:, cv2.CC_STAT_AREA]
        big = [i + 1 for i, a in enumerate(areas) if a >= 0.02 * areas.max()]
        mask = Image.fromarray((np.isin(lab, big) * 255).astype(np.uint8), "L")
    else:
        # największy kształt: zalewanie od punktu w środku postaci
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


def grid(path, n):
    sheet = Image.open(path).convert("RGB")
    w, h = sheet.size
    return [sheet.crop((c * w // n, r * h // n, (c + 1) * w // n, (r + 1) * h // n)) for r in range(n) for c in range(n)]


def load_sheet(path):
    cuts = {name: cut_cell(cell) for name, cell in zip(CELLS, grid(path, 2))}
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


def place(cuts, tail=TAIL_OVER, max_h=MAX_H):
    """Wspólna skala dla wszystkich min, stopy na FEET_Y, środek w poziomie."""
    # bardzo szerokie postacie (długi ogon): ogon może wyjść do TAIL_OVER poza kadr po lewej,
    # głowa (po prawej) zostaje cała - lepiej niż mocno zmniejszona postać
    scale = min(max_h / max(im.height for im in cuts.values()), MAX_W * (1 + tail) / max(im.width for im in cuts.values()))
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


# --- start: jeden obraz (art/pots_sheet.jpg), trzy doniczki z patyczkiem obok siebie -
EGG_IDS = ["egg", "eggb", "egga"]  # od lewej: doniczka gliniana, różowa, pomarańczowa (z patyczkiem)
EGG_LINE = {"egg": "classic", "eggb": "bloom", "egga": "autumn"}
EGG_PICK = 112  # jak w gen_assets.py
EGG_H = 128  # wysokość doniczki z patyczkiem w kadrze 168 px


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
        raise ValueError("nie znaleziono %d doniczek" % n)
    pad = 6
    return [sheet.crop((max(0, a - pad), 0, min(sheet.width, b + pad), sheet.height)) for a, b in runs]


def import_eggs():
    path = sheet_path("pots")
    if not path:
        return {}
    cuts = [cut_cell(c) for c in split_columns(path)]
    scale = EGG_H / max(c.height for c in cuts)  # wspólna skala: różne doniczki zostają różne
    S = SPRITE * WORK
    out = {}
    for fid, im in zip(EGG_IDS, cuts):
        nw, nh = round(im.width * scale * WORK), round(im.height * scale * WORK)
        big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        big.alpha_composite(im.resize((nw, nh), Image.LANCZOS), ((S - nw) // 2, FEET_Y * WORK - nh))
        center = (S // 2, FEET_Y * WORK)
        # patyczek kiwa się w doniczce: lekkie przechyły w obie strony
        fr = {
            "egg0": big,
            "egg1": big.rotate(-4, resample=Image.BICUBIC, center=center),
            "egg2": big.rotate(4, resample=Image.BICUBIC, center=center),
        }
        fr = {k: v.resize((SPRITE, SPRITE), Image.LANCZOS) for k, v in fr.items()}
        d = os.path.join(ASSETS, "pet", fid)
        os.makedirs(d, exist_ok=True)
        for name, img in fr.items():
            img.save(os.path.join(d, name + ".png"), optimize=True)
        big.resize((EGG_PICK, EGG_PICK), Image.LANCZOS).save(os.path.join(ASSETS, "ui", "egg_" + EGG_LINE[fid] + ".png"), optimize=True)
        out[fid] = fr
    return out


# --- zajęcia na ekranie głównym: art/<forma>_act_sheet.jpg, 2 x 2 ----------------
ACTS = ["dance", "flower", "game", "spores"]  # taniec, kwiatek na dłoni, konsola, świetliki


# świetliki: na arkuszu są za małe i za jasne, wycinanie je gubi - dorysowane wokół postaci
SPORES = [(-0.55, 0.15), (0.6, 0.05), (-0.35, 0.55), (0.5, 0.45), (0.1, -0.05), (-0.65, 0.8), (0.7, 0.75)]


def glow(img, phase):
    """Świecące zarodniki wokół postaci; w drugiej klatce część gaśnie, reszta lekko się unosi."""
    box = img.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    if not box:
        return img
    cx, w, top, h = (box[0] + box[2]) / 2, box[2] - box[0], box[1], box[3] - box[1]
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, (fx, fy) in enumerate(SPORES):
        if phase and i % 3 == 1:
            continue
        x = cx + fx * max(w, h * 0.6)
        y = top + fy * h - phase * 5 * WORK
        r = (3.2 if i % 2 else 2.4) * WORK
        d.ellipse([x - r * 2.2, y - r * 2.2, x + r * 2.2, y + r * 2.2], fill=(255, 220, 90, 70))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 246, 170, 255))
    layer = Image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2 * WORK)), layer)
    out = img.copy()
    out.alpha_composite(layer)
    return out


def wobble(img, deg):
    return img.rotate(deg, resample=Image.BICUBIC, center=(img.width // 2, FEET_Y * WORK - 40 * WORK))


def import_acts(fid):
    path = sheet_path(fid + "_act")
    if not path:
        return None
    # sticker: jasnoszary cień pod stopami (Gemini czasem go dorysowuje) też jest tłem
    cuts = {name: cut_cell(cell, keep_all=True, sticker=True) for name, cell in zip(ACTS, grid(path, 2))}
    # nie większy niż w spoczynku (formy z długim ogonem są w kadrze pomniejszone)
    idle = os.path.join(ASSETS, "pet", fid, "idle0.png")
    max_h = MAX_H
    if os.path.exists(idle):
        box = Image.open(idle).getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        if box:
            max_h = min(MAX_H, round((box[3] - box[1]) * 1.1))
    big = place(cuts, 0.0, max_h)
    f = {
        "act_dance0": wobble(big["dance"], -4),
        "act_dance1": wobble(big["dance"], 4),
        "act_flower0": big["flower"],
        "act_flower1": squash(big["flower"]),
        "act_game0": big["game"],
        "act_game1": squash(big["game"]),
        "act_spores0": glow(big["spores"], 0),
        "act_spores1": glow(big["spores"], 1),
    }
    d = os.path.join(ASSETS, "pet", fid)
    for name, img in f.items():
        img.resize((SPRITE, SPRITE), Image.LANCZOS).save(os.path.join(d, name + ".png"), optimize=True)
    return f


# --- rekwizyty gier: art/props_sheet.jpg, siatka 4 x 4 ---------------------------
# (nazwa w ui/, rozmiar kadru); kolejność jak w prompcie, wierszami
PROPS = [
    ("apple", 36), ("rock", 36), ("bone", 36), ("fish", 36),  # bone = żołądź, nest = doniczka
    ("nest", 36), ("hive", 36), ("ball", 32), ("log", (192, 36)),
    ("forest", 168), ("balloon", 0), ("pearl", 48), ("chest", 72),
    ("flag", 56), ("star", 40), ("bobber", 40), ("stump", 36),
]
EXTRA = {"bone": [("bone_big", 96), ("egg_small", 34)], "apple": [("apple_big", 72)], "fish": [("fish_big", 72)], "flag": [("flag_s", 40)], "star": [("star_ok", 60)]}
SHADOW = {"flag": ("flag_x", 40)}  # nieodblokowane: szary cień
BALLOON_SIZES = [28 + round(148 * i / 10) for i in range(11)]  # balon rośnie przy pompowaniu (średnica 28-176 jak w grze)


def fit(im, box):
    """Mieści kształt w kadrze box (w, h) z zachowaniem proporcji, wyśrodkowany, przy dole."""
    bw, bh = (box, box) if isinstance(box, int) else box
    sc = min(bw * WORK / im.width, bh * WORK / im.height)
    sm = im.resize((max(1, round(im.width * sc)), max(1, round(im.height * sc))), Image.LANCZOS)
    c = Image.new("RGBA", (bw * WORK, bh * WORK), (0, 0, 0, 0))
    c.alpha_composite(sm, ((c.width - sm.width) // 2, c.height - sm.height))
    return c.resize((bw, bh), Image.LANCZOS)


def stickers(path, n, cols):
    """Naklejki na arkuszu: n największych kształtów, wierszami od góry, w wierszu od lewej
    (Gemini nie trzyma się równej siatki, więc nie tniemy na kratki)."""
    import cv2

    sheet = Image.open(path).convert("RGB")
    fg = (np.asarray(sheet).astype(np.int16).min(axis=2) <= 226).astype(np.uint8)
    _, _, stats, cent = cv2.connectedComponentsWithStats(fg, connectivity=8)
    idx = sorted(range(1, len(stats)), key=lambda i: stats[i, cv2.CC_STAT_AREA], reverse=True)[:n]
    idx.sort(key=lambda i: cent[i][1])
    rows = [sorted(idx[r : r + cols], key=lambda i: cent[i][0]) for r in range(0, n, cols)]
    out = []
    for i in [i for row in rows for i in row]:
        x, y, w, h = stats[i, :4]
        pad = 12
        out.append(sheet.crop((max(0, x - pad), max(0, y - pad), min(sheet.width, x + w + pad), min(sheet.height, y + h + pad))))
    return out


def import_props():
    path = sheet_path("props")
    if not path:
        return []
    done = []
    for (name, size), cell in zip(PROPS, stickers(path, len(PROPS), 4)):
        im = cut_cell(cell, keep_all=True, holes=False)  # realistyczne rendery: bez obwódki naklejki, białe części zostają
        ui = os.path.join(ASSETS, "ui")
        if name == "balloon":
            for i, sz in enumerate(BALLOON_SIZES):
                fit(im, sz).save(os.path.join(ui, "balloon%d.png" % i), optimize=True)
        elif name == "log":
            # kłoda do balansu musi być długa: rozciągnięta na cały kadr
            im.resize(size, Image.LANCZOS).save(os.path.join(ui, name + ".png"), optimize=True)
        else:
            fit(im, size).save(os.path.join(ui, name + ".png"), optimize=True)
        for ename, esize in EXTRA.get(name, []):
            fit(im, esize).save(os.path.join(ui, ename + ".png"), optimize=True)
        if name in SHADOW:
            sname, ssize = SHADOW[name]
            silhouette(fit(im, ssize), (70, 70, 82)).save(os.path.join(ui, sname + ".png"), optimize=True)
        done.append(name)
    return done


# --- ikony akcji: art/icons_sheet.jpg, 2 rzędy po 4 ------------------------------
# nazwy plików w ui/ (ic_<akcja>.png na krążek pierścienia, reszta jak w grze)
ICONS = ["ic_meal", "ic_snack", "ic_light", "ic_medicine", "ic_clean", "poop", "skull", "drop"]
ICON_SIZE = 58  # jak RING_ICON w gen_assets.py
SMALL = {"poop": 48, "skull": 48, "drop": 36}


def import_icons():
    path = sheet_path("icons")
    if not path:
        return []
    done = []
    for name, cell in zip(ICONS, stickers(path, len(ICONS), 4)):
        im = cut_cell(cell, keep_all=True, sticker=True, holes=False)  # sticker: bez miękkiego cienia pod ikoną
        fit(im, SMALL.get(name, ICON_SIZE)).save(os.path.join(ASSETS, "ui", name + ".png"), optimize=True)
        if name == "ic_snack":
            fit(im, 48).save(os.path.join(ASSETS, "ui", "snack.png"), optimize=True)
        if name == "drop":
            fit(im, 48).save(os.path.join(ASSETS, "ui", "meal.png"), optimize=True)
            # pusta kropla wody: szary cień
            silhouette(fit(im, 36), (70, 70, 82)).save(os.path.join(ASSETS, "ui", "drop_empty.png"), optimize=True)
        done.append(name)
    return done


def sheet_path(name):
    for ext in (".jpg", ".png"):
        p = os.path.join(ART, name + "_sheet" + ext)
        if os.path.exists(p):
            return p
    return None


def write_art_list():
    """utils/art.js: formy, które mają klatki zajęć (strona główna nie umie sprawdzić plików)."""
    pet = os.path.join(ASSETS, "pet")
    forms = sorted(f for f in os.listdir(pet) if os.path.exists(os.path.join(pet, f, "act_dance0.png")))
    with open(os.path.join(ROOT, "utils", "art.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("// Wygenerowane przez tools/import_art.py - nie edytować ręcznie.\n")
        f.write("// Formy z klatkami zajęć (taniec, kwiatek, konsola, świetliki).\n")
        f.write("export const ACT_FORMS = [%s];\n" % ", ".join('"%s"' % x for x in forms))
    return forms


def available():
    """Formy z arkuszem postaci (bez jajek, rekwizytów i arkuszy zajęć)."""
    if not os.path.isdir(ART):
        return []
    names = {n.split("_sheet")[0] for n in os.listdir(ART) if "_sheet." in n}
    return sorted(n for n in names if n not in ("pots", "props", "icons") and not n.endswith("_act"))


def main(ids):
    done = []
    for fid in ids or available() + ["pots", "props", "icons"]:
        if fid == "pots":
            ok = import_eggs()
        elif fid == "icons":
            ok = import_icons()
        elif fid == "props":
            ok = import_props()
        elif fid.endswith("_act"):
            ok = import_acts(fid[:-4])
        else:
            ok = import_form(fid)
            import_acts(fid)
        if ok:
            done.append(fid)
    write_art_list()
    print("z arkuszy:", ", ".join(done) or "-")
    return done


if __name__ == "__main__":
    main(sys.argv[1:])
