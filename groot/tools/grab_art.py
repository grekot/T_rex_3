#!/usr/bin/env python3
"""Przenosi obraz z Grok Imagine z Pobranych do ../groot-art/<nazwa>_sheet.jpg
i dopisuje do ../groot-art/sources.txt, skąd pochodzi.

    python tools/grab_art.py grocik          # Pobrane/groot_grocik.jpg
    python tools/grab_art.py grocik --show   # warianty Pobrane/grootv_grocik_<k>.jpg -> ../groot-art/_warianty.png
    python tools/grab_art.py grocik 2        # wybrany wariant k (reszta wariantów do kosza)
    python tools/grab_art.py grocik --clip   # obraz ze schowka ("Kopiuj obraz")

Grok daje 4 warianty naraz; skrypt w przeglądarce zapisuje je linkami z atrybutem download
do obrazków data: jako grootv_<nazwa>_<k>.jpg (albo jeden wybrany jako groot_<nazwa>.jpg).
"""
import glob
import hashlib
import os
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# arkusze leżą poza folderem aplikacji: zeus pakuje cały folder do .ip-package
ART = os.path.join(os.path.dirname(ROOT), "groot-art")
DOWNLOADS = os.path.join(os.path.expanduser("~"), "Downloads")
SOURCES = os.path.join(ART, "sources.txt")


def log(name, tag):
    with open(SOURCES, "a", encoding="utf-8") as f:
        f.write(name + "\t" + tag + "\n")


def from_clipboard(name):
    from PIL import ImageGrab

    img = ImageGrab.grabclipboard()
    if img is None or isinstance(img, list):
        sys.exit("w schowku nie ma obrazu")
    dst = os.path.join(ART, name + "_sheet.png")
    img.convert("RGB").save(dst)
    log(name, "schowek " + hashlib.md5(img.convert("RGB").tobytes()).hexdigest()[:12])
    print(name, "<- schowek", "%dx%d" % img.size)


def take(name, src):
    if time.time() - os.path.getmtime(src) > 30 * 60:
        sys.exit("stary plik (ponad 30 min): " + src)
    dst = os.path.join(ART, name + "_sheet.jpg")
    shutil.move(src, dst)
    log(name, "grok " + hashlib.md5(open(dst, "rb").read()).hexdigest()[:12])
    print(name, "<-", os.path.basename(src))


def variants(name):
    return sorted(glob.glob(os.path.join(DOWNLOADS, "grootv_%s_[0-9].jpg" % name)))


def show(name):
    from PIL import Image, ImageDraw

    files = variants(name)
    if not files:
        sys.exit("brak wariantów grootv_%s_<k>.jpg w %s" % (name, DOWNLOADS))
    S = 560
    out = Image.new("RGB", (S * len(files) + 10 * (len(files) - 1), S + 30), (40, 40, 40))
    d = ImageDraw.Draw(out)
    for i, f in enumerate(files):
        out.paste(Image.open(f).convert("RGB").resize((S, S)), (i * (S + 10), 30))
        d.text((i * (S + 10) + 8, 6), os.path.basename(f)[-5:-4], fill=(255, 220, 90))
    path = os.path.join(ART, "_warianty.png")
    out.save(path)
    print(path)


def pick(name, k):
    files = variants(name)
    chosen = [f for f in files if f.endswith("_%d.jpg" % k)]
    if not chosen:
        sys.exit("brak wariantu %d" % k)
    take(name, chosen[0])
    for f in files:
        if f != chosen[0]:
            os.remove(f)


if __name__ == "__main__":
    os.makedirs(ART, exist_ok=True)
    name = sys.argv[1]
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    if arg == "--clip":
        from_clipboard(name)
    elif arg == "--show":
        show(name)
    elif arg.isdigit():
        pick(name, int(arg))
    else:
        src = os.path.join(DOWNLOADS, "groot_" + name + ".jpg")
        if not os.path.exists(src):
            sys.exit("brak " + src)
        take(name, src)
