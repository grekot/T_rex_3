"""Testy narzędzia archiwum: python -m unittest test_archiwum (w tym folderze)."""
from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from datetime import datetime

import numpy as np
from PIL import Image

import takeout
import wybor

HERE = os.path.dirname(os.path.abspath(__file__))


def ms(y, mo, d, h=12, mi=0, s=0) -> int:
    return int(datetime(y, mo, d, h, mi, s).timestamp() * 1000)


def jpeg(seed: int, w: int = 1600, h: int = 1200, blur: bool = False, dark: bool = False) -> bytes:
    rng = np.random.default_rng(seed)
    base = rng.integers(0, 255, size=(h // 40, w // 40, 3), dtype=np.uint8)
    img = Image.fromarray(base).resize((w, h), Image.NEAREST if not blur else Image.BICUBIC)
    if blur:
        img = img.resize((w // 20, h // 20)).resize((w, h), Image.BICUBIC)
    if dark:
        img = Image.eval(img, lambda v: v // 20)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    return buf.getvalue()


def sidecar(title: str, taken: int, **extra) -> bytes:
    return json.dumps({"title": title, "photoTakenTime": {"timestamp": str(taken // 1000)}, **extra}).encode()


class SidecarNames(unittest.TestCase):
    def test_plain_and_supplemental(self):
        names = takeout.sidecar_names("IMG_20190703_123456.jpg")
        self.assertEqual(names[0], "IMG_20190703_123456.jpg.supplemental-metadata.json")
        self.assertIn("IMG_20190703_123456.jpg.json", names)

    def test_truncated_to_51(self):
        names = takeout.sidecar_names("PXL_20230812_101112345.MP.jpg")
        # Google skraca nazwę JSON-a do 51 znaków razem z „.json”
        self.assertEqual(names[0], "PXL_20230812_101112345.MP.jpg.supplemental-met.json")
        self.assertEqual(len(names[0]), 51)

    def test_counter_and_edited(self):
        self.assertEqual(takeout.split_counter("IMG_1(2).jpg"), ("IMG_1.jpg", "(2)"))
        self.assertEqual(takeout.original_name("IMG_1-edited.jpg"), ("IMG_1.jpg", True))
        self.assertEqual(takeout.original_name("IMG_1-edytowane.jpg"), ("IMG_1.jpg", True))
        names = takeout.sidecar_names("IMG_1(2).jpg")
        self.assertIn("IMG_1.jpg.supplemental-metadata(2).json", names)
        self.assertIn("IMG_1.jpg(2).json", names)
        self.assertIn("IMG_1.jpg.supplemental-metadata.json", takeout.sidecar_names("IMG_1-edited.jpg"))

    def test_sidecar_info(self):
        info = takeout.sidecar_info(
            json.loads(sidecar("a.jpg", ms(2014, 7, 3), favorited=True, people=[{"name": "Ola"}], geoData={"latitude": 0.0, "longitude": 0.0}))
        )
        self.assertEqual(info["taken_ms"], ms(2014, 7, 3))
        self.assertTrue(info["favorite"])
        self.assertEqual(info["people"], ["Ola"])
        self.assertNotIn("lat", info)

    def test_skips(self):
        self.assertEqual(takeout.skip_reason(takeout.Entry("", "T/Photos from 2020/Screenshot_2020.png", 1)), "zrzut/komunikator")
        self.assertEqual(takeout.skip_reason(takeout.Entry("", "T/Photos from 2020/IMG-20200101-WA0003.jpg", 1)), "zrzut/komunikator")
        self.assertEqual(takeout.skip_reason(takeout.Entry("", "T/Kosz/IMG_1.jpg", 1)), "kosz/zablokowane")
        self.assertIsNone(takeout.skip_reason(takeout.Entry("", "T/Photos from 2020/IMG_1.jpg", 1)))


class Selection(unittest.TestCase):
    def entry(self, i, t, score=0.5, dh=0, **kw):
        return {"id": f"id{i:04d}", "taken": t, "score": score, "dhash": dh, **kw}

    def test_events_and_bursts(self):
        base = ms(2015, 5, 1, 10)
        ev = [
            self.entry(1, base, dh=0),
            self.entry(2, base + 30_000, dh=0b111),  # seria: 3 bity różnicy, 30 s
            self.entry(3, base + 600_000, dh=(1 << 64) - 1),  # inne ujęcie
            self.entry(4, base + 5 * 3600_000, dh=0),  # nowe wydarzenie (prawie identyczne, ale inne wydarzenie)
        ]
        evs = wybor.events(ev)
        self.assertEqual([len(e) for e in evs], [3, 1])
        self.assertEqual([len(g) for g in wybor.bursts(evs[0])], [2, 1])

    def test_quota(self):
        self.assertEqual(wybor.event_quota(1), 1)
        self.assertEqual(wybor.event_quota(2), 2)
        self.assertEqual(wybor.event_quota(10), 6)
        self.assertEqual(wybor.event_quota(500), 10)

    def test_allocate_favours_sparse_years(self):
        a = wybor.allocate({2010: 10, 2020: 1000}, 100)
        self.assertEqual(sum(a.values()), 100)
        self.assertEqual(a[2010], 10)
        a = wybor.allocate({2010: 100, 2020: 10000}, 100)
        self.assertGreater(a[2010], 5)  # proporcjonalnie byłoby ~1

    def test_candidates_limit_and_order(self):
        rows = []
        for y in range(2008, 2024):
            for k in range(60):
                rows.append(self.entry(len(rows), ms(y, 1 + k % 12, 1 + k % 27, 9 + k % 8), score=(k % 7) / 7, dh=k * 7919))
        out = wybor.candidates(rows, 300)
        self.assertLessEqual(len(out), 300)
        self.assertEqual(out, sorted(out, key=lambda e: (e["taken"], e["id"])))
        self.assertEqual(len({wybor.year_of(e) for e in out}), 16)

    def test_reject_reasons(self):
        good = {"id": "x", "taken": ms(2012, 1, 1), "w": 4000, "h": 3000, "sharp_cell": 300, "mean": 0.5, "fmt": "JPEG", "camera": "Sony"}
        self.assertIsNone(wybor.reject_reason(good, 0.5))
        self.assertEqual(wybor.reject_reason({**good, "taken": None}, 0.5), "bez daty")
        self.assertEqual(wybor.reject_reason({**good, "w": 400, "h": 300}, 0.5), "za małe")
        self.assertEqual(wybor.reject_reason({**good, "w": 9000}, 0.5), "panorama/pasek")
        self.assertEqual(wybor.reject_reason({**good, "fmt": "PNG", "camera": ""}, 0.5), "grafika")
        self.assertEqual(wybor.reject_reason(good, 0.01), "rozmazane")
        self.assertEqual(wybor.reject_reason({**good, "mean": 0.02}, 0.5), "ciemne")

    def test_final_choice_caps(self):
        cands, reviews = [], {}
        for d in range(1, 21):  # 20 dni po 6 zdjęć z oceną 8 w jednym wydarzeniu dziennie
            for k in range(6):
                e = self.entry(len(cands), ms(2016, 3, d, 10, k), score=k / 10)
                cands.append(e)
                reviews[e["id"]] = {"s": 8, "c": "x"}
        reviews[cands[0]["id"]] = {"s": 5}  # za słabe
        out = wybor.final_choice(cands, reviews, 40)
        self.assertEqual(len(out), 40)
        per_day = {}
        for e in out:
            per_day[wybor.day_of(e)] = per_day.get(wybor.day_of(e), 0) + 1
        self.assertLessEqual(max(per_day.values()), wybor.PER_EVENT)
        self.assertNotIn(cands[0]["id"], {e["id"] for e in out})
        # Gdy brakuje zdjęć, limity się luzują
        self.assertEqual(len(wybor.final_choice(cands, reviews, 110)), 110)

    def test_export_size(self):
        self.assertEqual(wybor.export_size(4000, 3000), (800, 600))
        self.assertEqual(wybor.export_size(3000, 4000), (600, 800))
        self.assertEqual(wybor.export_size(4000, 4000), (600, 600))
        self.assertEqual(wybor.export_size(1920, 1080), (800, 450))
        self.assertEqual(wybor.export_size(640, 480), (640, 480))

    def test_caption_and_boxes(self):
        self.assertEqual(wybor.clean_caption("  Nad   jeziorem "), "Nad jeziorem")
        long = "Wieczorne ognisko nad jeziorem z przyjaciółmi"
        c = wybor.clean_caption(long)
        self.assertLessEqual(len(c), 28)
        self.assertTrue(long.startswith(c))
        self.assertEqual(wybor.clean_box([0.9, 0.5, 0.5, 0.2]), [0.9, 0.5, 0.1, 0.2])
        self.assertIsNone(wybor.clean_box([0.5, 0.5, 0.01, 0.2]))
        self.assertIsNone(wybor.clean_box("x"))
        e = {"id": "abc", "taken": 1000, "review": {"s": 9, "c": "Las", "f": [0.1, 0.1, 0.5, 0.5]}}
        self.assertEqual(wybor.index_entry(e, 800, 600), {"id": "abc", "t": 1000, "c": "Las", "s": 9, "w": 800, "h": 600, "f": [0.1, 0.1, 0.5, 0.5]})


class EndToEnd(unittest.TestCase):
    """Sztuczny Takeout w dwóch ZIP-ach (JSON-y osobno), cały przebieg bez chmury."""

    def test_pipeline(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "takeout")
            os.makedirs(src)
            folder = "Takeout/Zdjęcia Google/Photos from 2014/"
            album = "Takeout/Zdjęcia Google/Wakacje/"
            photos = {}
            for i in range(12):
                t = ms(2014, 7, 1 + i, 12)
                photos[f"IMG_{i:04d}.jpg"] = (jpeg(i), t)
            with zipfile.ZipFile(os.path.join(src, "takeout-001.zip"), "w") as z1, zipfile.ZipFile(os.path.join(src, "takeout-002.zip"), "w") as z2:
                for name, (data, t) in photos.items():
                    z1.writestr(folder + name, data)
                    z2.writestr(folder + name + ".supplemental-metadata.json", sidecar(name, t))
                # ta sama fotka w albumie (duplikat) i jej wersja edytowana
                z1.writestr(album + "IMG_0000.jpg", photos["IMG_0000.jpg"][0])
                z1.writestr(album + "IMG_0000.jpg.json", sidecar("IMG_0000.jpg", photos["IMG_0000.jpg"][1]))
                z1.writestr(folder + "IMG_0001-edited.jpg", jpeg(101))
                # rozmazane, ciemne, zrzut ekranu, bez JSON-a (data z EXIF brak -> bez daty)
                z1.writestr(folder + "BLUR.jpg", jpeg(50, blur=True))
                z2.writestr(folder + "BLUR.jpg.json", sidecar("BLUR.jpg", ms(2014, 8, 1)))
                z1.writestr(folder + "DARK.jpg", jpeg(51, dark=True))
                z2.writestr(folder + "DARK.jpg.json", sidecar("DARK.jpg", ms(2014, 8, 2)))
                z1.writestr(folder + "Screenshot_20140801.png", jpeg(52))
                z1.writestr(folder + "NOJSON.jpg", jpeg(53))
                z1.writestr(folder + "BROKEN.jpg", bytes([0xFF, 0xD8]) + b" to nie jest JPEG")
                z2.writestr(folder + "BROKEN.jpg.json", sidecar("BROKEN.jpg", ms(2014, 8, 3)))
            work = os.path.join(tmp, "praca")

            def run(*args):
                env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
                r = subprocess.run(
                    [sys.executable, os.path.join(HERE, "archiwum.py"), "--praca", work, *args],
                    capture_output=True, text=True, encoding="utf-8", cwd=HERE, env=env,
                )
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
                return r.stdout

            out = run("skanuj", src, "--procesy", "2")
            self.assertIn("zrzut/komunikator: 1", out)
            self.assertIn("duplikat (album): 1", out)
            self.assertIn("oryginał (jest edytowana): 1", out)
            with open(os.path.join(work, "katalog.jsonl"), encoding="utf-8") as f:
                katalog = [json.loads(line) for line in f]
            self.assertEqual(len(katalog), 16)  # 12 - oryginał + edytowana + BLUR + DARK + NOJSON + BROKEN
            self.assertEqual([e["title"] for e in katalog if e.get("error")], ["BROKEN.jpg"])
            edited = next(e for e in katalog if e["edited"])
            self.assertEqual(edited["taken"], photos["IMG_0001.jpg"][1])
            self.assertTrue(os.path.exists(os.path.join(work, "miniatury", f"{edited['id']}.jpg")))
            # Drugi skan nic nie dodaje
            self.assertIn("do skanu: 0", run("skanuj", src, "--procesy", "1"))
            # Ponowienie błędów: zdjęcie z błędem skanowane jeszcze raz, bez dubli w katalogu
            out = run("skanuj", src, "--procesy", "1", "--ponow-bledy")
            self.assertIn("Ponowny skan 1", out)
            self.assertIn("do skanu: 1", out)
            with open(os.path.join(work, "katalog.jsonl"), encoding="utf-8") as f:
                self.assertEqual(len(f.readlines()), 16)

            out = run("kandydaci", "--ile", "100")
            self.assertIn("bez daty: 1", out)
            self.assertIn("ciemne: 1", out)
            with open(os.path.join(work, "kandydaci.json"), encoding="utf-8") as f:
                cands = json.load(f)
            self.assertEqual(len(cands), 12)
            self.assertTrue(os.path.exists(os.path.join(work, "arkusze", "arkusz_001.jpg")))
            os.makedirs(os.path.join(work, "oceny"))
            with open(os.path.join(work, "oceny", "arkusz_001.json"), "w", encoding="utf-8") as f:
                review = {"1": {"s": 9, "c": "Plaża w Dębkach", "f": [0.2, 0.2, 0.5, 0.5]}, "3": {"s": 7, "c": "Zachód słońca"}, "4": {"s": 4}}
                json.dump({"arkusz": 1, "wybrane": review}, f)
            self.assertIn("ocenione 1/1", run("stan").replace("Arkusze ocenione: ", "ocenione "))
            # Nowe arkusze unieważniłyby oceny - kandydaci odmawia bez --od-nowa
            env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
            r = subprocess.run(
                [sys.executable, os.path.join(HERE, "archiwum.py"), "--praca", work, "kandydaci", "--ile", "100"],
                capture_output=True, text=True, encoding="utf-8", cwd=HERE, env=env,
            )
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("--od-nowa", r.stderr)
            self.assertIn("Wybrane: 2", run("wybierz", "--ile", "10"))
            self.assertIn("Eksport: 2", run("eksport"))
            with open(os.path.join(work, "eksport", "spis.json"), encoding="utf-8") as f:
                spis = json.load(f)
            self.assertEqual([s["c"] for s in spis], ["Plaża w Dębkach", "Zachód słońca"])
            self.assertEqual((spis[0]["w"], spis[0]["h"]), (800, 600))
            with Image.open(os.path.join(work, "eksport", f"{spis[0]['id']}.jpg")) as im:
                self.assertEqual(im.size, (800, 600))
                self.assertFalse(im.info.get("progressive"))
                self.assertEqual(len(im.getexif()), 0)
            self.assertIn("Stare oceny przeniesione", run("kandydaci", "--ile", "100", "--od-nowa"))
            self.assertFalse(os.path.exists(os.path.join(work, "oceny")))
            self.assertTrue(any(d.startswith("oceny_stare_") for d in os.listdir(work)))


if __name__ == "__main__":
    unittest.main()
