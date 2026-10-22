#!/usr/bin/env python3
"""Kopiuje najnowszy, jeszcze nieużyty obraz z Gemini (Pobrane/Gemini_Generated_Image_*)
do ../pupil-art/<nazwa>_sheet.jpg i dopisuje do ../pupil-art/sources.txt, z którego pliku pochodzi.

    python tools/grab_gemini.py pisklak
    python tools/grab_gemini.py pisklak --clip   # obraz ze schowka (Gemini: "Kopiuj obraz")

--clip przydaje się, gdy Chrome przestaje zapisywać pobrania z Gemini (kopia ma 1024 px
szerokości zamiast pełnego rozmiaru - na klatki 168 px wystarcza).
"""
import glob
import os
import shutil
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# arkusze leżą poza folderem aplikacji: zeus pakuje cały folder do .ip-package
ART = os.path.join(os.path.dirname(ROOT), "pupil-art")
DOWNLOADS = os.path.join(os.path.expanduser("~"), "Downloads")
SOURCES = os.path.join(ART, "sources.txt")


def used():
    if not os.path.exists(SOURCES):
        return set()
    with open(SOURCES, encoding="utf-8") as f:
        return {line.split("\t")[1].strip() for line in f if "\t" in line}


def from_clipboard(name):
    from PIL import ImageGrab

    img = ImageGrab.grabclipboard()
    if img is None or isinstance(img, list):
        sys.exit("w schowku nie ma obrazu")
    import hashlib

    tag = "schowek " + hashlib.md5(img.convert("RGB").tobytes()).hexdigest()[:12]
    if tag in used():
        sys.exit("w schowku jest obraz, który już był użyty (kopiowanie jeszcze trwa?)")
    dst = os.path.join(ART, name + "_sheet.png")
    img.convert("RGB").save(dst)
    with open(SOURCES, "a", encoding="utf-8") as f:
        f.write(name + "\t" + tag + "\n")
    print(name, "<- schowek", "%dx%d" % img.size)


def main(name):
    os.makedirs(ART, exist_ok=True)
    files = sorted(glob.glob(os.path.join(DOWNLOADS, "Gemini_Generated_Image_*")), key=os.path.getmtime, reverse=True)
    taken = used()
    # tylko świeże pliki: w Pobranych leżą też stare obrazy z Gemini, a pobieranie może jeszcze trwać
    fresh = [f for f in files if os.path.basename(f) not in taken and time.time() - os.path.getmtime(f) < 15 * 60]
    if not fresh:
        sys.exit("brak nowego (z ostatnich 15 min) obrazu z Gemini w " + DOWNLOADS)
    src = fresh[0]
    ext = os.path.splitext(src)[1].lower()
    dst = os.path.join(ART, name + "_sheet" + ext)
    shutil.copyfile(src, dst)
    with open(SOURCES, "a", encoding="utf-8") as f:
        f.write(name + "\t" + os.path.basename(src) + "\n")
    print(name, "<-", os.path.basename(src))


if __name__ == "__main__":
    if "--clip" in sys.argv:
        from_clipboard(sys.argv[1])
    else:
        main(sys.argv[1])
