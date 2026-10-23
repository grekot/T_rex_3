#!/usr/bin/env python3
"""Podgląd zaimportowanych postaci: wiersz na formę (spokój, radość, smutek, sen, ciemno)
na tle jak na zegarku, z ramką kadru 168 px. Zapisuje ../groot-art/_podglad.png.

    python tools/preview_art.py [forma ...]
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PET = os.path.join(ROOT, "assets", "gt.r", "pet")
NAMES = ["idle0", "happy0", "sad0", "sleep0", "dark0"]
S = 168


def main(ids):
    ids = ids or sorted(os.listdir(PET))
    img = Image.new("RGBA", (len(NAMES) * (S + 8) + 8, len(ids) * (S + 8) + 8), (18, 18, 22, 255))
    d = ImageDraw.Draw(img)
    for r, fid in enumerate(ids):
        for c, name in enumerate(NAMES):
            path = os.path.join(PET, fid, name + ".png")
            if not os.path.exists(path):
                continue
            x, y = 8 + c * (S + 8), 8 + r * (S + 8)
            d.rectangle([x - 1, y - 1, x + S, y + S], outline=(60, 60, 70))
            img.alpha_composite(Image.open(path).convert("RGBA"), (x, y))
        d.text((10, 10 + r * (S + 8)), fid, fill=(200, 200, 200))
    out = os.path.join(os.path.dirname(ROOT), "groot-art", "_podglad.png")
    img.convert("RGB").save(out)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
