#!/usr/bin/env python3
"""Generuje grafikę Groota: klatki form z arkuszy Grok Imagine (import_art.py), ikony
pierścienia akcji, drobiazgi, utils/geometry.js, arkusz podglądu docs/arkusz.png
i makietę docs/podglad.png.

Postacie, doniczki, zajęcia, tła, rekwizyty gier i ikony akcji pochodzą z arkuszy w
../groot-art/ (opis w ../groot-art/prompts.md). Tu rysowane są tylko krążki pierścienia,
serca, strzałki i podobne drobiazgi (tools/icons.py, tools/draw.py). Forma bez arkusza
dostaje zastępczo klatki innej formy tego samego etapu (z ostrzeżeniem).

Uruchom z folderu groot:   python tools/gen_assets.py
Wymaga: Pillow, numpy, opencv-python, font Segoe UI (Windows 10/11) - do podpisów na arkuszu.
"""
import math
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont, ImageOps

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from draw import SS, Canvas, ell, poly, rrect  # noqa: E402
from icons import ICONS, OUT as ICON_OUT  # noqa: E402
import import_art  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets", "gt.r")
DOCS = os.path.join(ROOT, "docs")
FONT = "C:/Windows/Fonts/segoeui.ttf"
FONT_B = "C:/Windows/Fonts/segoeuib.ttf"

SPRITE = 168  # klatki w grach (pets/)
HOME = 240  # klatki na ekranie głównym (pet/) - jak HOME w import_art.py
THUMB = 64
EGG_PICK = 112  # doniczki na ekranie wyboru
DISC = 88  # krążek przycisku akcji w pierścieniu
RING_ICON = 58  # ikona na krążku
ICON = 48

LINES_SHEET = [
    ("Doniczki: klasyczny, kwitnący, jesienny", ["egg", "eggb", "egga"]),
    ("Klasyczny: Kiełek, Grocik, Nastolatek, Groot (wzorowo), Mszak", ["kielek", "grocik", "nastek", "groot", "mszak"]),
    ("Kwitnący: Pąk, Kwiatuś, Wisienka, Sakura (wzorowo), Jabłoń", ["pak", "kwiatus", "wisienka", "sakura", "jablon"]),
    ("Jesienny: Żołądź, Rudzik, Klonik, Klon (wzorowo), Dębisz", ["zoladz", "rudzik", "klonik", "klon", "debisz"]),
    ("Zaniedbane (wspólne): Suchar, Kolczak, Próchniak", ["suchar", "kolczak", "prochniak"]),
]
EGGS = ["egg", "eggb", "egga"]
EGG_LINE = {"egg": "classic", "eggb": "bloom", "egga": "autumn"}
STAGE_OF = {"suchar": "child", "kolczak": "teen", "prochniak": "adult"}
for _, _ids in LINES_SHEET[1:4]:
    for _st, _fid in zip(["baby", "child", "teen", "adult", "adult"], _ids):
        STAGE_OF[_fid] = _st
FORMS_NAMES = {
    "kielek": "Kiełek", "grocik": "Grocik", "nastek": "Nastolatek", "groot": "Groot", "mszak": "Mszak",
    "pak": "Pąk", "kwiatus": "Kwiatuś", "wisienka": "Wisienka", "sakura": "Sakura", "jablon": "Jabłoń",
    "zoladz": "Żołądź", "rudzik": "Rudzik", "klonik": "Klonik", "klon": "Klon", "debisz": "Dębisz",
    "suchar": "Suchar", "kolczak": "Kolczak", "prochniak": "Próchniak",
}
FRAME_ROWS = list(FORMS_NAMES)


# --- ikony i drobiazgi -----------------------------------------------------------


def icon_img(iid, size=ICON, flip=False, rotate=0):
    shapes, detail = ICONS[iid]()
    c = Canvas(ICON, ICON)
    c.body(shapes, ICON_OUT, 1.8)
    c.shapes(detail)
    img = c.img
    if rotate:
        img = img.rotate(rotate, resample=Image.BICUBIC)
    img = img.resize((size, size), Image.LANCZOS)
    return ImageOps.mirror(img) if flip else img


def disc(color, ring=None):
    big = Image.new("RGBA", (DISC * SS, DISC * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.ellipse([0, 0, DISC * SS - 1, DISC * SS - 1], fill=(ring or color) + (255,))
    if ring:
        w = 4 * SS
        d.ellipse([w, w, DISC * SS - 1 - w, DISC * SS - 1 - w], fill=color + (255,))
    return big.resize((DISC, DISC), Image.LANCZOS)


def ring_icon(iid):
    """Ikona na krążek: z arkusza ikon (ui/ic_<akcja>.png), a bez niego rysowana."""
    path = os.path.join(ASSETS, "ui", "ic_" + iid + ".png")
    if os.path.exists(path):
        return Image.open(path).convert("RGBA").resize((RING_ICON, RING_ICON), Image.LANCZOS)
    return icon_img(iid, RING_ICON)


def action_icon(iid, selected):
    base = disc((40, 62, 34), ring=(150, 214, 90)) if selected else disc((34, 34, 42))
    base.alpha_composite(ring_icon(iid), ((DISC - RING_ICON) // 2, (DISC - RING_ICON) // 2))
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
    ImageDraw.Draw(big).ellipse([0, 0, size * SS - 1, size * SS - 1], fill=(34, 70, 40, 255))
    img = big.resize((size, size), Image.LANCZOS)
    path = os.path.join(ASSETS, "pet", "grocik", "happy0.png")
    if os.path.exists(path):
        sprite = Image.open(path).convert("RGBA").resize((214, 214), Image.LANCZOS)
        img.alpha_composite(sprite, ((size - 214) // 2, (size - 214) // 2 - 6))
    return img


def save(img, *parts):
    path = os.path.join(ASSETS, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


# --- układ ekranu głównego -------------------------------------------------------

RING_IDS = ["meal", "snack", "light", "play", "medicine", "clean", "scold", "stats"]
RING_LABELS = ["Podlewanie", "Nawóz", "Noc", "Zabawa", "Oprysk", "Grabie", "Zgań", "Statystyki"]
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
        "export const SPRITE = %d; // klatki w grach (pets/)" % SPRITE,
        "export const HOME = %d; // klatki na ekranie głównym (pet/)" % HOME,
        "export const THUMB = %d;" % THUMB,
        "export const DISC = %d;" % DISC,
        "export const ICON = %d; // poop (opadłe liście), skull (mszyca), alert, meal, snack" % ICON,
        "export const HEART = 36;",
        "export const ARROW = 60;",
        "export const BALL = 32;",
        "export const EGG_PICK = %d;" % EGG_PICK,
        "export const ITEM = 36; // apple, rock, bone (żołądź), fish, nest (doniczka), hive",
        "export const POINTER = 140;",
        "export const ZZZ = { w: 56, h: 48 };",
        "export const LOG = { w: 192, h: 36 };",
        "export const RING = [\n%s,\n];" % ring,
    ]
    with open(os.path.join(ROOT, "utils", "geometry.js"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


# --- klatki form ---------------------------------------------------------------


def load_frames(fid):
    d = os.path.join(ASSETS, "pet", fid)
    if not os.path.isdir(d):
        return None
    return {n[:-4]: Image.open(os.path.join(d, n)).convert("RGBA") for n in os.listdir(d) if n.endswith(".png")}


def stand_in(missing, have):
    """Forma bez arkusza: kopia klatek formy tego samego etapu (żeby aplikacja działała)."""
    for fid in missing:
        donor = next((f for f in have if STAGE_OF.get(f) == STAGE_OF[fid]), None) or (have[0] if have else None)
        if not donor:
            raise SystemExit("brak jakiegokolwiek arkusza postaci w ../groot-art")
        print("  UWAGA: %s nie ma arkusza - zastępczo klatki %s" % (fid, donor))
        for sub in ("pet", "pets"):
            dst = os.path.join(ASSETS, sub, fid)
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(os.path.join(ASSETS, sub, donor), dst)
        for suf in ("", "_x"):
            shutil.copyfile(os.path.join(ASSETS, "thumb", donor + suf + ".png"), os.path.join(ASSETS, "thumb", fid + suf + ".png"))


# --- podglądy --------------------------------------------------------------------


def sheet(all_frames):
    font = ImageFont.truetype(FONT, 18)
    bold = ImageFont.truetype(FONT_B, 22)
    cell = 104
    shown = ["idle0", "idle1", "happy0", "happy1", "sad1", "sleep0", "dark0", "eat0", "left"]
    labels = ["spokój", "oddech", "radość", "podskok", "smutek", "sen", "ciemno", "pije", "w lewo"]
    left, top = 20, 60
    W = left * 2 + 130 + cell * len(shown)
    H = top + len(LINES_SHEET) * 150 + 50 + len(FRAME_ROWS) * cell + 60 + 2 * 110 + 20
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    d.text((left, 16), "Groot - linie i formy (na zegarku 168 px)", font=bold, fill=(255, 255, 255))
    y = top
    for title, ids in LINES_SHEET:
        d.text((left, y), title, font=font, fill=(255, 200, 90))
        for i, fid in enumerate(ids):
            fr = all_frames.get(fid)
            if fr:
                sp = fr["egg0" if fid in EGGS else "idle0"].resize((120, 120), Image.LANCZOS)
                img.alpha_composite(sp, (left + i * 150, y + 24))
        y += 150
    y += 10
    d.text((left, y), "Klatki animacji", font=bold, fill=(255, 255, 255))
    y += 40
    for i, lab in enumerate(labels):
        d.text((left + 130 + i * cell + cell // 2, y - 6), lab, font=font, fill=(150, 150, 160), anchor="ms")
    for fid in FRAME_ROWS:
        d.text((left, y + cell // 2), FORMS_NAMES[fid], font=font, fill=(255, 200, 90), anchor="lm")
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
    for name in ["drop", "heart", "poop", "skull", "alert"]:
        p = os.path.join(ASSETS, "ui", name + ".png")
        if os.path.exists(p):
            img.alpha_composite(Image.open(p).convert("RGBA").resize((48, 48), Image.LANCZOS), (x, y + 14))
        x += 58
    os.makedirs(DOCS, exist_ok=True)
    img.convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT).save(os.path.join(DOCS, "arkusz.png"), optimize=True)  # mały - trafia do .ip-package


def mock(all_frames, form, frame, selected, text, title, scene, feed, label):
    big = Image.new("RGBA", (480 * SS, 480 * SS), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, 480 * SS - 1, 480 * SS - 1], fill=(0, 0, 0, 255))
    img = big.resize((480, 480), Image.LANCZOS)
    bg = os.path.join(ASSETS, "ui", "bg_" + scene + ".png")
    if os.path.exists(bg):
        img.paste(Image.open(bg).convert("RGBA"), (0, 0), mask=img.getchannel("A"))
    d = ImageDraw.Draw(img)
    small = ImageFont.truetype(FONT, 22)
    tiny = ImageFont.truetype(FONT, 20)
    for i, (cx, cy) in enumerate(ring_positions()):
        iid = feed.get(RING_IDS[i], RING_IDS[i])
        img.alpha_composite(action_icon(iid, i == selected), (cx - DISC // 2, cy - DISC // 2))
    # jak w page/gt/home/index.page.r.layout.js: stopy na 366 px
    img.alpha_composite(all_frames[form][frame], (240 - HOME // 2, 366 - round(HOME * 160 / 168)))
    img.alpha_composite(Image.open(os.path.join(ASSETS, "ui", "poop.png")).convert("RGBA"), (334, 300))
    d.text((240, 118), text, font=small, fill=(255, 200, 90), anchor="mm")
    d.text((240, 380), title, font=tiny, fill=(150, 150, 160), anchor="mm")
    d.text((240, 412), label, font=tiny, fill=(255, 255, 255), anchor="mm")
    return img


def main():
    write_geometry()
    # drobiazgi rysowane; arkusze rekwizytów i ikon (import_art) nadpisują większość z nich
    save(icon_img("heart", 36), "ui", "heart.png")
    save(icon_img("heart_empty", 36), "ui", "heart_empty.png")
    for iid in ["poop", "skull", "alert", "meal", "snack", "bubble"]:
        save(icon_img(iid), "ui", iid + ".png")
    save(icon_img("ball", 32), "ui", "ball.png")
    save(icon_img("arrow", 60), "ui", "arrow_r.png")
    save(icon_img("arrow", 60, flip=True), "ui", "arrow_l.png")
    save(icon_img("arrow", 60, rotate=90), "ui", "arrow_u.png")
    save(icon_img("arrow", 60, rotate=-90), "ui", "arrow_d.png")
    for iid in ["apple", "rock", "bone", "fish", "nest", "hive"]:
        save(icon_img(iid, 36), "ui", iid + ".png")
    save(icon_img("bone", 96), "ui", "bone_big.png")
    save(icon_img("bone", 34), "ui", "egg_small.png")
    save(icon_img("pointer", 140), "ui", "pointer.png")
    save(icon_img("heart", 36), "ui", "drop.png")
    save(icon_img("heart_empty", 36), "ui", "drop_empty.png")
    save(zzz(), "ui", "zzz.png")
    save(trees(), "ui", "forest.png")
    save(log_img(), "ui", "log.png")

    # postacie, doniczki, zajęcia, rekwizyty i ikony z arkuszy (../groot-art/)
    have = []
    for fid in import_art.available():
        if import_art.import_form(fid):
            have.append(fid)
        import_art.import_acts(fid)
    eggs = import_art.import_eggs()
    import_art.import_props()
    import_art.import_icons()
    import_art.import_icons2()
    import_art.import_bgs()
    for name in import_art.SINGLES:
        import_art.import_single(name)
    stand_in([f for f in FRAME_ROWS if f not in have], have)
    for e in EGGS:
        if e not in eggs:
            print("  UWAGA: brak arkusza doniczek (pots) - zastępczo klatki Kiełka")
            d = os.path.join(ASSETS, "pet", e)
            os.makedirs(d, exist_ok=True)
            idle = Image.open(os.path.join(ASSETS, "pet", "kielek", "idle0.png"))
            for k in ("egg0", "egg1", "egg2"):
                idle.save(os.path.join(d, k + ".png"))
            idle.resize((EGG_PICK, EGG_PICK), Image.LANCZOS).save(os.path.join(ASSETS, "ui", "egg_" + EGG_LINE[e] + ".png"))
    import_art.write_art_list()
    # słońce i lody (karmienie od etapu dziecka) zamiast konewki i worka nawozu
    for iid in RING_IDS + ["sun", "icecream"]:
        if iid in ICONS or os.path.exists(os.path.join(ASSETS, "ui", "ic_" + iid + ".png")):
            save(action_icon(iid, False), "ring", iid + ".png")
            save(action_icon(iid, True), "ring", iid + "_sel.png")
    app_icon().save(os.path.join(ASSETS, "icon.png"), optimize=True)

    all_frames = {fid: load_frames(fid) for fid in FRAME_ROWS + EGGS}
    sheet(all_frames)
    m = Image.new("RGBA", (980, 480), (40, 40, 40, 255))
    potted = {}
    free = {"meal": "sun", "snack": "icecream"}
    m.alpha_composite(mock(all_frames, "kielek", "idle0", 0, "Zgrab opadłe liście", "Kiełek", "kokpit", potted, "Podlewanie"), (0, 0))
    m.alpha_composite(mock(all_frames, "groot", "happy0", 0, "Grzeje się w słońcu", "Groot", "knowhere", free, "Światło gwiazd"), (500, 0))
    m.convert("RGB").save(os.path.join(DOCS, "podglad.png"), optimize=True)
    print("gotowe:", len(have), "form z arkuszy")


if __name__ == "__main__":
    main()
