#!/usr/bin/env python3
"""Kopiuje najnowszy, jeszcze nieużyty obraz z Gemini (Pobrane/Gemini_Generated_Image_*)
do ../pupil-art/<nazwa>_sheet.jpg i dopisuje do ../pupil-art/sources.txt, z którego pliku pochodzi.

    python tools/grab_gemini.py pisklak
"""
import glob
import os
import shutil
import sys

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


def main(name):
    os.makedirs(ART, exist_ok=True)
    files = sorted(glob.glob(os.path.join(DOWNLOADS, "Gemini_Generated_Image_*")), key=os.path.getmtime, reverse=True)
    taken = used()
    fresh = [f for f in files if os.path.basename(f) not in taken]
    if not fresh:
        sys.exit("brak nowego obrazu z Gemini w " + DOWNLOADS)
    src = fresh[0]
    ext = os.path.splitext(src)[1].lower()
    dst = os.path.join(ART, name + "_sheet" + ext)
    shutil.copyfile(src, dst)
    with open(SOURCES, "a", encoding="utf-8") as f:
        f.write(name + "\t" + os.path.basename(src) + "\n")
    print(name, "<-", os.path.basename(src))


if __name__ == "__main__":
    main(sys.argv[1])
