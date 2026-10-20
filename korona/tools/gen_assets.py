"""Ikona aplikacji Korona, strzałka kompasu i podglądy ekranów do README.

Uruchom w folderze korona:  python tools/gen_assets.py
Wymaga: Pillow, font Segoe UI (jest w Windows 10/11 - tylko do podglądu,
zegarek ma własny font).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..")
SS = 8  # rysowanie w 8x i zmniejszanie = gładkie krawędzie

WHITE = (255, 255, 255)
GREY = (138, 138, 138)
DIM = (90, 90, 90)
ORANGE = (255, 145, 0)
BUTTON = (230, 126, 0)
GREEN = (76, 175, 80)
GREEN_BTN = (46, 125, 50)
ROW = (28, 28, 28)
TRACK = (51, 51, 51)
RED_BTN = (183, 28, 28)
GOLD = (255, 193, 7)
GOLD_DARK = (196, 140, 0)


def font(size, bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf", size)


def make_icon():
    S = 248 * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, S - 1, S - 1], fill=(14, 22, 30, 255))
    k = S / 248
    # Góry: tylna szara, przednia z białym czubkiem
    d.polygon([(30 * k, 190 * k), (92 * k, 108 * k), (150 * k, 190 * k)], fill=(70, 84, 98))
    front = [(58 * k, 196 * k), (140 * k, 82 * k), (222 * k, 196 * k)]
    d.polygon(front, fill=(110, 124, 138))
    snow = [(140 * k, 82 * k), (116 * k, 116 * k), (130 * k, 110 * k), (140 * k, 122 * k), (152 * k, 110 * k), (164 * k, 116 * k)]
    d.polygon(snow, fill=(240, 240, 240))
    # Ziemia - obcięcie dołu kołem tła
    d.rectangle([0, 196 * k, S, S], fill=(14, 22, 30))
    # Korona nad szczytem
    cx, top = 140 * k, 30 * k
    w, h = 76 * k, 40 * k
    crown = [
        (cx - w / 2, top + h),
        (cx - w / 2, top + 6 * k),
        (cx - w / 4, top + h * 0.55),
        (cx, top),
        (cx + w / 4, top + h * 0.55),
        (cx + w / 2, top + 6 * k),
        (cx + w / 2, top + h),
    ]
    d.polygon(crown, fill=GOLD)
    d.rectangle([cx - w / 2, top + h, cx + w / 2, top + h + 9 * k], fill=GOLD_DARK)
    for px_, py_ in ((cx - w / 2, top + 6 * k), (cx, top), (cx + w / 2, top + 6 * k)):
        r = 6 * k
        d.ellipse([px_ - r, py_ - r, px_ + r, py_ + r], fill=GOLD)
    im = mask_round(im).resize((248, 248), Image.LANCZOS)
    path = os.path.join(ROOT, "assets", "gt.r", "icon.png")
    im.save(path)
    print("zapisano", path)


def arrow_image(size=180):
    S = size * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    tip, back, wing, notch = S * 0.06, S * 0.86, S * 0.30, S * 0.66
    d.polygon([(c, tip), (c + wing, back), (c, notch), (c - wing, back)], fill=ORANGE)
    d.polygon([(c, tip), (c, notch), (c - wing, back)], fill=(255, 183, 77))
    return im.resize((size, size), Image.LANCZOS)


def make_arrow():
    path = os.path.join(ROOT, "assets", "gt.r", "arrow.png")
    arrow_image().save(path)
    print("zapisano", path)


def screen():
    im = Image.new("RGBA", (480, 480), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, 479, 479], fill=(0, 0, 0, 255))
    return im, d


def pill(d, rect, color, text, size, text_color=WHITE):
    x, y, w, h = rect
    d.rounded_rectangle([x, y, x + w, y + h], h / 2, fill=color)
    d.text((x + w / 2, y + h / 2), text, font=font(size), fill=text_color, anchor="mm")


def mask_round(im):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).ellipse([0, 0, im.width - 1, im.height - 1], fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def preview_home(at_summit=False):
    im, d = screen()
    d.text((240, 46), "KORONA GÓR POLSKI", font=font(22), fill=ORANGE, anchor="mm")
    d.text((240, 100), "12 / 28", font=font(64), fill=WHITE, anchor="mm")
    d.rounded_rectangle([120, 144, 360, 154], 5, fill=TRACK)
    d.rounded_rectangle([120, 144, 120 + 240 * 12 // 28, 154], 5, fill=ORANGE)
    d.rounded_rectangle([50, 170, 430, 288], 26, fill=ROW)
    if at_summit:
        d.text((240, 202), "Jesteś na szczycie!", font=font(28), fill=GREEN, anchor="mm")
        d.text((240, 248), "Ślęża · 718 m", font=font(20), fill=WHITE, anchor="mm")
        pill(d, (110, 300, 260, 62), GREEN_BTN, "Zaliczam", 30)
    else:
        d.text((240, 202), "Najbliższy: Ślęża", font=font(28), fill=WHITE, anchor="mm")
        d.text((240, 248), "23,4 km · Pd-Zach · Masyw Ślęży", font=font(20), fill=GREY, anchor="mm")
        pill(d, (110, 300, 260, 62), BUTTON, "Najbliższe ›", 26)
    d.text((240, 398), "Szczyty · stuknij po szczegóły", font=font(20), fill=GREY, anchor="mm")
    rows = [("Rysy", "15.07.2024", True), ("Babia Góra", "1725 m", False)]
    for i, (name, right, done) in enumerate(rows):
        y = 424 + i * 78
        d.rounded_rectangle([46, y, 434, y + 70], 20, fill=ROW)
        d.ellipse([74 - 9, y + 35 - 9, 74 + 9, y + 35 + 9], fill=GREEN if done else TRACK)
        d.text((94, y + 35), name, font=font(26), fill=WHITE if done else GREY, anchor="lm")
        d.text((418, y + 35), right, font=font(20), fill=GREEN if done else GREY, anchor="rm")
    return mask_round(im)


def preview_list():
    """Środek przewiniętej listy."""
    im, d = screen()
    rows = [
        ("Mogielica", "02.08.2023", True),
        ("Wysoka Kopa", "1126 m", False),
        ("Rudawiec", "1106 m", False),
        ("Orlica", "14.10.2025", True),
        ("Wysoka", "1050 m", False),
        ("Wielka Sowa", "01.05.2022", True),
    ]
    for i, (name, right, done) in enumerate(rows):
        y = 6 + i * 78
        d.rounded_rectangle([46, y, 434, y + 70], 20, fill=ROW)
        d.ellipse([74 - 9, y + 35 - 9, 74 + 9, y + 35 + 9], fill=GREEN if done else TRACK)
        d.text((94, y + 35), name, font=font(26), fill=WHITE if done else GREY, anchor="lm")
        d.text((418, y + 35), right, font=font(20), fill=GREEN if done else GREY, anchor="rm")
    return mask_round(im)


def preview_peak():
    im, d = screen()
    d.text((240, 59), "Śnieżka", font=font(36), fill=WHITE, anchor="mm")
    d.text((240, 100), "1603 m · Karkonosze", font=font(22), fill=GREY, anchor="mm")
    d.text((240, 140), "wierzchołek graniczny", font=font(18), fill=GREY, anchor="mm")
    d.text((240, 193), "Zdobyty 15.07.2024", font=font(34), fill=GREEN, anchor="mm")
    d.text((240, 230), "zaliczony na szczycie (GPS)", font=font(18), fill=GREY, anchor="mm")
    d.text((240, 263), "214 km stąd · Zach", font=font(22), fill=WHITE, anchor="mm")
    pill(d, (90, 294, 300, 60), TRACK, "Zmień datę", 26)
    pill(d, (110, 366, 260, 56), RED_BTN, "Cofnij", 26)
    return mask_round(im)


def preview_nearest():
    im, d = screen()
    d.text((240, 47), "Ślęża", font=font(30), fill=WHITE, anchor="mm")
    d.text((240, 80), "718 m · Masyw Ślęży", font=font(20), fill=GREY, anchor="mm")
    arrow = arrow_image().rotate(-35, resample=Image.BICUBIC)
    im.alpha_composite(arrow, (150, 98))
    d = ImageDraw.Draw(im)
    pill(d, (30, 156, 64, 64), TRACK, "‹", 36)
    pill(d, (386, 156, 64, 64), TRACK, "›", 36)
    d.text((70, 235), "1 / 16", font=font(18), fill=GREY, anchor="mm")
    d.text((240, 315), "23,4 km", font=font(54), fill=WHITE, anchor="mm")
    d.text((240, 360), "Pd-Zach · 214°", font=font(20), fill=GREY, anchor="mm")
    pill(d, (140, 408, 200, 46), TRACK, "Szczegóły", 22)
    return mask_round(im)


def preview_date():
    im, d = screen()
    d.text((240, 50), "Data zdobycia", font=font(22), fill=GREY, anchor="mm")
    d.text((240, 85), "Babia Góra", font=font(30), fill=WHITE, anchor="mm")
    cols = [("dzień", "21"), ("miesiąc", "06"), ("rok", "2019")]
    x0 = (480 - 3 * 104 - 2 * 14) // 2
    for i, (label, value) in enumerate(cols):
        x = x0 + i * 118
        d.text((x + 52, 125), label, font=font(18), fill=GREY, anchor="mm")
        pill(d, (x, 140, 104, 56), TRACK, "+", 36)
        d.text((x + 52, 231), value, font=font(36 if label == "rok" else 44), fill=WHITE, anchor="mm")
        pill(d, (x, 266, 104, 56), TRACK, "−", 36)
    d.text((240, 340), "piątek", font=font(18), fill=GREY, anchor="mm")
    pill(d, (120, 362, 240, 60), BUTTON, "Zapisz", 28)
    return mask_round(im)


def main():
    make_icon()
    make_arrow()
    docs = os.path.join(ROOT, "docs")
    os.makedirs(docs, exist_ok=True)
    previews = {
        "podglad.png": preview_home(),
        "podglad-szczyt-gps.png": preview_home(at_summit=True),
        "podglad-lista.png": preview_list(),
        "podglad-szczegoly.png": preview_peak(),
        "podglad-najblizsze.png": preview_nearest(),
        "podglad-data.png": preview_date(),
    }
    for name, im in previews.items():
        im.save(os.path.join(docs, name))
    print("zapisano podglądy w docs/")


if __name__ == "__main__":
    main()
