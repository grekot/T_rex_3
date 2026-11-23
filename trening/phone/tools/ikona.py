"""Ikona aplikacji Trening: kartka kalendarza z kręgosłupem i znaczkiem „zrobione”.

Uruchom z folderu trening/phone:  python tools/ikona.py
Zapisuje:
  android/app/src/main/res/mipmap-*/ic_launcher.png             (zwykła ikona, cały kwadrat)
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  (warstwa ikony adaptacyjnej)
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml     (ikona adaptacyjna)
  android/app/src/main/res/values/ic_launcher_background.xml     (kolor tła)
  tools/ikona_podglad.png                                        (podgląd 512 px, poza APK)
Rysuje w 8-krotnym powiększeniu i zmniejsza, żeby krawędzie były gładkie.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

TLO_GORA = (14, 76, 102)
TLO_DOL = (30, 136, 168)
TLO_ADAPTACYJNE = "#15688A"
KARTKA = (250, 250, 247)
NAGLOWEK = (242, 140, 40)
KOLKA = (60, 60, 66)
KREG = (30, 136, 168)
KREG_JASNY = (98, 178, 204)
KRAZEK = (170, 214, 228)
ZIELONY = (67, 160, 71)

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def gradient(size):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(TLO_GORA, TLO_DOL))
        for x in range(size):
            px[x, y] = c + (255,)
    return img


def tresc(d, x0, y0, s):
    """Kartka kalendarza z kręgosłupem w kwadracie (x0, y0, bok s)."""
    def p(u, v):
        return (x0 + u * s, y0 + v * s)

    def rect(u0, v0, u1, v1, r, fill):
        d.rounded_rectangle([p(u0, v0), p(u1, v1)], radius=r * s, fill=fill)

    # cień i kartka
    rect(0.10, 0.13, 0.90, 0.97, 0.10, (0, 0, 0, 60))
    rect(0.08, 0.10, 0.88, 0.94, 0.10, KARTKA)
    # pasek nagłówka (górne rogi zaokrąglone, dolna krawędź prosta)
    rect(0.08, 0.10, 0.88, 0.34, 0.10, NAGLOWEK)
    d.rectangle([p(0.08, 0.24), p(0.88, 0.30)], fill=NAGLOWEK)
    # kółka segregatora
    for u in (0.28, 0.68):
        d.ellipse([p(u - 0.055, 0.04), p(u + 0.055, 0.18)], fill=KOLKA)
        d.ellipse([p(u - 0.025, 0.08), p(u + 0.025, 0.14)], fill=KARTKA)
    # kręgosłup od przodu: 5 kręgów z wyrostkami poprzecznymi i krążkami między nimi
    u = 0.42
    for i in range(5):
        v = 0.385 + i * 0.105
        if i:
            d.ellipse([p(u - 0.07, v - 0.03), p(u + 0.07, v + 0.005)], fill=KRAZEK)
        rect(u - 0.18, v + 0.022, u + 0.18, v + 0.052, 0.015, KREG_JASNY)
        rect(u - 0.085, v, u + 0.085, v + 0.075, 0.03, KREG)
    # znaczek „zrobione”
    d.ellipse([p(0.62, 0.66), p(0.94, 0.98)], fill=ZIELONY)
    d.line([p(0.70, 0.82), p(0.765, 0.885), p(0.87, 0.75)], fill=(255, 255, 255), width=round(0.045 * s), joint="curve")


def legacy(size):
    big = size * 8
    img = gradient(big)
    d = ImageDraw.Draw(img)
    tresc(d, 0.12 * big, 0.12 * big, 0.76 * big)
    return img.resize((size, size), Image.LANCZOS)


def foreground(size):
    big = size * 8
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # bezpieczna strefa ikony adaptacyjnej: środkowe 66 z 108 dp
    s = big * 60 / 108
    off = (big - s) / 2
    tresc(d, off, off, s)
    return img.resize((size, size), Image.LANCZOS)


def main():
    for dpi, size in LEGACY.items():
        folder = RES / f"mipmap-{dpi}"
        folder.mkdir(parents=True, exist_ok=True)
        legacy(size).convert("RGB").save(folder / "ic_launcher.png", optimize=True)
    for dpi, size in FOREGROUND.items():
        foreground(size).save(RES / f"mipmap-{dpi}" / "ic_launcher_foreground.png", optimize=True)
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n',
        encoding="utf-8",
    )
    (RES / "values" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{TLO_ADAPTACYJNE}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )
    legacy(512).save(Path(__file__).parent / "ikona_podglad.png")
    print("Ikony zapisane w", RES)


if __name__ == "__main__":
    main()
