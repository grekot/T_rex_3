"""Pomiary jednego zdjęcia na PC (bez internetu): ostrość, naświetlenie, kolor, odcisk do wykrywania serii,
twarze (OpenCV) i data z EXIF, gdy w Takeout nie było JSON-a. Przy okazji miniatura do arkuszy przeglądu.
"""
from __future__ import annotations

import io
from datetime import datetime

import cv2
import numpy as np
from PIL import Image, ImageOps

THUMB = 320  # dłuższy bok miniatury do arkuszy

_faces = None


def _face_detector():
    global _faces
    if _faces is None:
        _faces = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    return _faces


try:  # HEIC tylko, gdy jest pillow-heif (Android robi JPEG-i, więc zwykle niepotrzebne)
    import pillow_heif  # type: ignore

    pillow_heif.register_heif_opener()
    HEIC = True
except ImportError:
    HEIC = False


def exif_taken_ms(img: Image.Image) -> int | None:
    try:
        exif = img.getexif()
        raw = exif.get_ifd(0x8769).get(36867) or exif.get(306)
    except Exception:
        return None
    if not isinstance(raw, str):
        return None
    try:
        return int(datetime.strptime(raw.strip()[:19], "%Y:%m:%d %H:%M:%S").timestamp() * 1000)
    except ValueError:
        return None


def camera_of(img: Image.Image) -> str:
    try:
        exif = img.getexif()
        make, model = exif.get(271), exif.get(272)
    except Exception:
        return ""
    return " ".join(str(v).strip() for v in (make, model) if v)[:40]


def dhash(gray: np.ndarray) -> int:
    small = cv2.resize(gray, (9, 8), interpolation=cv2.INTER_AREA)
    bits = (small[:, 1:] > small[:, :-1]).flatten()
    v = 0
    for b in bits:
        v = (v << 1) | int(b)
    return v


def hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


def colorfulness(rgb: np.ndarray) -> float:
    r, g, b = (rgb[..., i].astype(np.float32) for i in range(3))
    rg = np.abs(r - g)
    yb = np.abs(0.5 * (r + g) - b)
    return float(np.sqrt(rg.std() ** 2 + yb.std() ** 2) + 0.3 * np.sqrt(rg.mean() ** 2 + yb.mean() ** 2))


def sharpness(gray: np.ndarray) -> tuple[float, float]:
    """Wariancja Laplasjanu: całe zdjęcie i najostrzejsze pole siatki 3×3 (ostry motyw na rozmytym tle)."""
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    h, w = gray.shape
    best = 0.0
    for i in range(3):
        for j in range(3):
            cell = lap[i * h // 3 : (i + 1) * h // 3, j * w // 3 : (j + 1) * w // 3]
            best = max(best, float(cell.var()))
    return float(lap.var()), best


def faces(gray512: np.ndarray) -> list[list[float]]:
    h, w = gray512.shape
    found = _face_detector().detectMultiScale(
        gray512, scaleFactor=1.1, minNeighbors=6, minSize=(max(24, w // 25), max(24, w // 25))
    )
    boxes = [[x / w, y / h, fw / w, fh / h] for (x, y, fw, fh) in found]
    boxes.sort(key=lambda b: -b[2] * b[3])
    return [[round(v, 3) for v in b] for b in boxes[:4]]


def measure(data: bytes) -> tuple[dict, bytes]:
    """Pomiary i miniatura JPEG. Wyjątek = pliku nie da się odczytać."""
    img = Image.open(io.BytesIO(data))
    fmt = img.format or ""
    full_w, full_h = img.size
    taken = exif_taken_ms(img)
    camera = camera_of(img)
    if fmt == "JPEG":
        img.draft("RGB", (1024, 1024))  # szybkie dekodowanie w zmniejszeniu (DCT)
    img = ImageOps.exif_transpose(img)
    rotated = img.size[0] < img.size[1] and full_w > full_h
    if rotated:
        full_w, full_h = full_h, full_w
    img = img.convert("RGB")
    img.thumbnail((512, 512), Image.LANCZOS)
    rgb = np.asarray(img)
    gray512 = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    scale = 256 / max(gray512.shape)
    gray = cv2.resize(gray512, (max(1, round(gray512.shape[1] * scale)), max(1, round(gray512.shape[0] * scale))), interpolation=cv2.INTER_AREA)
    luma = gray.astype(np.float32) / 255
    sharp, sharp_cell = sharpness(gray)
    m = {
        "fmt": fmt,
        "w": full_w,
        "h": full_h,
        "exif_ms": taken,
        "camera": camera,
        "sharp": round(sharp, 1),
        "sharp_cell": round(sharp_cell, 1),
        "mean": round(float(luma.mean()), 3),
        "std": round(float(luma.std()), 3),
        "dark": round(float((luma < 0.03).mean()), 3),
        "bright": round(float((luma > 0.97).mean()), 3),
        "color": round(colorfulness(rgb), 1),
        "dhash": dhash(gray),
        "faces": faces(gray512),
    }
    thumb = img.copy()
    thumb.thumbnail((THUMB, THUMB), Image.LANCZOS)
    buf = io.BytesIO()
    thumb.save(buf, "JPEG", quality=82)
    return m, buf.getvalue()
