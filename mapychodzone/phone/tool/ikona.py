"""Ikona MapyChodzone: zielone tło, góry ze ścieżką i pień drzewa ze znakiem szlaku PTTK.

Użycie (w folderze phone):  python tool/ikona.py
Zapisuje android/app/src/main/res/mipmap-*/ic_launcher.png i tool/ikona-512.png (podgląd).
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROZMIARY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
TLO = (46, 107, 58)
GORA_TYL = (120, 170, 120)
GORA = (236, 240, 230)
SCIEZKA = (122, 86, 52)
CZERWONY = (227, 0, 15)
PIEN = (110, 82, 58)
PIEN_CIEN = (88, 64, 44)


def rysuj(n: int = 1024) -> Image.Image:
    s = n / 100
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, n - 1, n - 1], radius=22 * s, fill=TLO)
    # góry: tylna i przednia
    d.polygon([(8 * s, 78 * s), (38 * s, 36 * s), (62 * s, 78 * s)], fill=GORA_TYL)
    d.polygon([(30 * s, 82 * s), (62 * s, 24 * s), (94 * s, 82 * s)], fill=GORA)
    # ścieżka zakosami pod szczyt
    punkty = [(40 * s, 82 * s), (66 * s, 68 * s), (52 * s, 56 * s), (64 * s, 44 * s), (61 * s, 33 * s)]
    d.line(punkty, fill=SCIEZKA, width=int(3.2 * s), joint="curve")
    # dół tła pod górami
    d.rounded_rectangle([0, 82 * s, n - 1, n - 1], radius=22 * s, fill=TLO)
    d.rectangle([0, 82 * s, n - 1, 90 * s], fill=TLO)
    # pień drzewa ze znakiem szlaku PTTK (biały–czerwony–biały namalowany na korze)
    d.rectangle([12 * s, 8 * s, 30 * s, 92 * s], fill=PIEN)
    d.line([(16 * s, 46 * s), (16 * s, 60 * s)], fill=PIEN_CIEN, width=int(1.2 * s))
    d.line([(25 * s, 64 * s), (25 * s, 80 * s)], fill=PIEN_CIEN, width=int(1.2 * s))
    x0, y0, w, h = 14.5 * s, 20 * s, 13 * s, 15 * s
    d.rectangle([x0, y0, x0 + w, y0 + h / 3], fill="white")
    d.rectangle([x0, y0 + h / 3, x0 + w, y0 + 2 * h / 3], fill=CZERWONY)
    d.rectangle([x0, y0 + 2 * h / 3, x0 + w, y0 + h], fill="white")
    return img


def main() -> None:
    korzen = Path(__file__).resolve().parent.parent
    duza = rysuj()
    duza.resize((512, 512), Image.LANCZOS).save(korzen / "tool" / "ikona-512.png")
    for nazwa, px in ROZMIARY.items():
        cel = korzen / "android" / "app" / "src" / "main" / "res" / f"mipmap-{nazwa}" / "ic_launcher.png"
        duza.resize((px, px), Image.LANCZOS).save(cel)
        print(cel.relative_to(korzen), px)


if __name__ == "__main__":
    main()
