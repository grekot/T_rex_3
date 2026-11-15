"""Arkusze do przeglądu: 30 miniatur (6 × 5) na jednym obrazku, z numerem, datą i osobami z Takeoutu.
Kolejność chronologiczna - sąsiednie kafelki to zwykle to samo wydarzenie (łatwiej o podpis i wybór najlepszego).
"""
from __future__ import annotations

import os
from datetime import datetime

from PIL import Image, ImageDraw, ImageFont

COLS, ROWS = 6, 5
PER_SHEET = COLS * ROWS
TILE = 220
LABEL = 20
GAP = 8
HEADER = 30

_FONT_PATHS = ["C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/arial.ttf", "DejaVuSans-Bold.ttf"]


def _font(size: int):
    for p in _FONT_PATHS:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


def sheet_chunks(ids: list[str], per_sheet: int = PER_SHEET) -> list[list[str]]:
    return [ids[i : i + per_sheet] for i in range(0, len(ids), per_sheet)]


def _day(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d")


def render_sheet(number: int, total: int, entries: list[dict], thumbs_dir: str, out_path: str) -> None:
    width = COLS * (TILE + GAP) + GAP
    height = HEADER + ROWS * (TILE + LABEL + GAP) + GAP
    sheet = Image.new("RGB", (width, height), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    big, small = _font(18), _font(13)
    first, last = _day(entries[0]["taken"]), _day(entries[-1]["taken"])
    draw.text((GAP, 6), f"Arkusz {number}/{total}   {first} – {last}", fill=(230, 230, 230), font=big)
    for i, e in enumerate(entries):
        col, row = i % COLS, i // COLS
        x = GAP + col * (TILE + GAP)
        y = HEADER + row * (TILE + LABEL + GAP)
        try:
            with Image.open(os.path.join(thumbs_dir, f"{e['id']}.jpg")) as t:
                t = t.convert("RGB")
                t.thumbnail((TILE, TILE), Image.LANCZOS)
                sheet.paste(t, (x + (TILE - t.width) // 2, y + (TILE - t.height) // 2))
        except OSError:
            draw.rectangle([x, y, x + TILE, y + TILE], outline=(120, 40, 40))
        tag = str(i + 1)
        tw = draw.textlength(tag, font=big)
        draw.rectangle([x, y, x + tw + 10, y + 24], fill=(0, 0, 0))
        draw.text((x + 5, y + 2), tag, fill=(255, 210, 0), font=big)
        label = _day(e["taken"])
        if e.get("favorite"):
            label += " ulub."
        people = ", ".join(e.get("people") or [])
        if people:
            label += "  " + people
        while draw.textlength(label, font=small) > TILE and len(label) > 4:
            label = label[:-2] + "…"
        draw.text((x, y + TILE + 3), label, fill=(200, 200, 200), font=small)
    sheet.save(out_path, "JPEG", quality=85)
