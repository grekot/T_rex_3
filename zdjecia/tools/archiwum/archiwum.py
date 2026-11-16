"""Archiwum zdjęć z Google Takeout dla aplikacji „Zdjęcia” (format: ../../ARCHIWUM.md, opis: README.md).

  python archiwum.py skanuj C:\\TMP\\Takeout          ZIP-y (albo rozpakowane foldery): katalog + miniatury
                    [--ponow-bledy]                  ponownie zdjęcia z błędem odczytu (np. HEIC po pip install pillow-heif)
  python archiwum.py kandydaci [--ile 4000]          odsiew, wydarzenia, serie -> arkusze do przeglądu
                    [--od-nowa]                      gdy są już oceny (przenosi je do oceny_stare_<data>)
  python archiwum.py stan                            ile arkuszy ocenionych, ile wybranych
  python archiwum.py wybierz [--ile 1000]            wybór końcowy z ocen przeglądu
  python archiwum.py eksport                         JPEG-i ≤ 800×600 bez EXIF + spis
  python archiwum.py zaloguj                         konto (hasło wpisujesz sam, zostaje tylko token)
  python archiwum.py wyslij [--usun-stare]           do Firestore: zdjęcia, potem spis

Folder roboczy (domyślnie C:\\TMP\\Takeout\\praca, albo --praca / ZDJECIA_PRACA) jest poza repozytorium -
miniatury i zdjęcia nie mogą trafić do publicznego repo.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import getpass
import io
import json
import os
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime

from PIL import Image, ImageOps

import arkusze
import takeout
import wybor

DEFAULT_WORK = os.environ.get("ZDJECIA_PRACA", r"C:\TMP\Takeout\praca")
MAX_JPEG = 300 * 1024


def p(work: str, *parts: str) -> str:
    return os.path.join(work, *parts)


def load_jsonl(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass  # ucięta ostatnia linia po przerwaniu - zostanie zeskanowana jeszcze raz
    return out


def save_json(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def load_json(path: str, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


# ------------------------------------------------------------------ skanuj


def _scan_chunk(job: tuple[str, list[dict], str]) -> list[dict]:
    """W osobnym procesie: pomiary zdjęć z jednego ZIP-a (albo folderu)."""
    import metryki

    container, items, thumbs = job
    reader = takeout.Reader()
    out = []
    try:
        for it in items:
            rec = dict(it)
            try:
                if os.path.splitext(it["member"])[1].lower() in (".heic", ".heif") and not metryki.HEIC:
                    raise ValueError("HEIC bez pillow-heif")
                data = reader.read(takeout.Entry(container, it["member"], it["size"]))
                m, thumb = metryki.measure(data)
                with open(os.path.join(thumbs, f"{it['id']}.jpg"), "wb") as f:
                    f.write(thumb)
                exif_ms = m.pop("exif_ms")
                rec.update(m)
                if not rec.get("taken") and exif_ms:
                    rec["taken"], rec["taken_from"] = exif_ms, "exif"
            except Exception as e:  # noqa: BLE001 - zły plik nie przerywa skanu
                rec["error"] = f"{type(e).__name__}: {e}"[:120]
            out.append(rec)
    finally:
        reader.close()
    return out


def cmd_skanuj(args) -> None:
    work = args.praca
    thumbs = p(work, "miniatury")
    os.makedirs(thumbs, exist_ok=True)
    t0 = time.time()
    entries = takeout.list_entries(args.zrodla)
    reader = takeout.Reader()
    try:
        photos, stats = takeout.match_photos(entries, reader)
    finally:
        reader.close()
    katalog = p(work, "katalog.jsonl")
    if args.ponow_bledy:
        recs = load_jsonl(katalog)
        ok = [r for r in recs if not r.get("error")]
        if len(ok) < len(recs):
            with open(katalog + ".tmp", "w", encoding="utf-8") as f:
                for r in ok:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
            os.replace(katalog + ".tmp", katalog)
            print(f"Ponowny skan {len(recs) - len(ok)} zdjęć z błędem odczytu")
    done = {e["id"] for e in load_jsonl(katalog)}
    todo = [ph for ph in photos if ph.id not in done]
    print(f"Pliki: {len(entries)}, zdjęcia: {len(photos)} (już w katalogu: {len(photos) - len(todo)}, do skanu: {len(todo)})")
    for k, v in sorted(stats.items()):
        print(f"  pominięte - {k}: {v}")

    by_container: dict[str, list[dict]] = defaultdict(list)
    for ph in todo:
        by_container[ph.entry.container].append(
            {
                "id": ph.id,
                "title": ph.title,
                "container": ph.entry.container,
                "member": ph.entry.member,
                "size": ph.entry.size,
                "taken": ph.taken_ms,
                "taken_from": "json" if ph.taken_ms else None,
                "edited": ph.edited,
                "favorite": ph.favorite,
                "people": ph.people,
            }
        )
    jobs = []
    for container, items in by_container.items():
        for i in range(0, len(items), 40):
            jobs.append((container, items[i : i + 40], thumbs))
    n = 0
    with open(katalog, "a", encoding="utf-8") as out, cf.ProcessPoolExecutor(max_workers=args.procesy) as pool:
        for recs in pool.map(_scan_chunk, jobs):
            for r in recs:
                out.write(json.dumps(r, ensure_ascii=False) + "\n")
            out.flush()
            n += len(recs)
            if n % 400 < len(recs) or n == len(todo):
                rate = n / max(0.1, time.time() - t0)
                print(f"  {n}/{len(todo)}  ({rate:.0f}/s)", flush=True)
    all_ = load_jsonl(katalog)
    errors = Counter(e["error"].split(":")[0] for e in all_ if e.get("error"))
    print(f"Katalog: {len(all_)} zdjęć, błędy odczytu: {dict(errors) or 0}, czas {time.time() - t0:.0f} s")


# ------------------------------------------------------------------ kandydaci


def cmd_kandydaci(args) -> None:
    work = args.praca
    entries = load_jsonl(p(work, "katalog.jsonl"))
    if not entries:
        sys.exit("Pusty katalog - najpierw: skanuj")
    # Oceny wskazują kafelki po numerze arkusza - nowe arkusze unieważniłyby cały przegląd
    oceny = p(work, "oceny")
    if os.path.isdir(oceny) and any(f.startswith("arkusz_") for f in os.listdir(oceny)):
        if not args.od_nowa:
            sys.exit(
                "Są już oceny przeglądu (oceny/arkusz_*.json) - nowe arkusze by je pomieszały.\n"
                "Przegląd od nowa: kandydaci --od-nowa (stare oceny trafią do oceny_stare_<data>)."
            )
        old = p(work, "oceny_stare_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
        os.replace(oceny, old)
        print(f"Stare oceny przeniesione do {old}")
    kept, rejected = wybor.score_all(entries)
    cands = wybor.candidates(kept, args.ile)
    print(f"Katalog {len(entries)}, po odsiewie {len(kept)}, kandydaci {len(cands)}")
    for k, v in sorted(rejected.items(), key=lambda x: -x[1]):
        print(f"  odrzucone - {k}: {v}")
    years = Counter(wybor.year_of(e) for e in cands)
    print("  lata: " + ", ".join(f"{y}: {c}" for y, c in sorted(years.items())))
    save_json(p(work, "kandydaci.json"), cands)
    sheets_dir = p(work, "arkusze")
    os.makedirs(sheets_dir, exist_ok=True)
    for f in os.listdir(sheets_dir):
        if f.startswith("arkusz_"):
            os.remove(os.path.join(sheets_dir, f))
    chunks = arkusze.sheet_chunks([e["id"] for e in cands])
    by_id = {e["id"]: e for e in cands}
    for i, ids in enumerate(chunks, 1):
        arkusze.render_sheet(i, len(chunks), [by_id[x] for x in ids], p(work, "miniatury"), p(sheets_dir, f"arkusz_{i:03d}.jpg"))
    save_json(p(sheets_dir, "arkusze.json"), {"sheets": chunks})
    print(f"Arkusze: {len(chunks)} w {sheets_dir} (oceny zapisuj w {p(work, 'oceny')})")


def load_reviews(work: str) -> tuple[dict[str, dict], int, int]:
    """Oceny z oceny/arkusz_NNN.json (numery kafelków -> id). Zwraca też: ile arkuszy ocenionych / wszystkich."""
    sheets = (load_json(p(work, "arkusze", "arkusze.json"), {}) or {}).get("sheets", [])
    reviews: dict[str, dict] = {}
    reviewed = 0
    for i, ids in enumerate(sheets, 1):
        r = load_json(p(work, "oceny", f"arkusz_{i:03d}.json"))
        if not isinstance(r, dict):
            continue
        reviewed += 1
        for tile, val in (r.get("wybrane") or {}).items():
            try:
                k = int(tile)
            except ValueError:
                continue
            if 1 <= k <= len(ids) and isinstance(val, dict):
                reviews[ids[k - 1]] = val
    return reviews, reviewed, len(sheets)


def cmd_stan(args) -> None:
    reviews, reviewed, total = load_reviews(args.praca)
    good = sum(1 for r in reviews.values() if r.get("s", 0) >= wybor.PICK_SCORE)
    print(f"Arkusze ocenione: {reviewed}/{total}, zdjęcia z oceną ≥ {wybor.PICK_SCORE}: {good}")
    chosen = load_json(p(args.praca, "wybrane.json"), [])
    if chosen:
        print(f"Wybrane: {len(chosen)}")
    spis = load_json(p(args.praca, "eksport", "spis.json"), [])
    if spis:
        print(f"Wyeksportowane: {len(spis)}")


# ------------------------------------------------------------------ wybierz / eksport


def cmd_wybierz(args) -> None:
    work = args.praca
    cands = load_json(p(work, "kandydaci.json"), [])
    reviews, reviewed, total = load_reviews(work)
    if reviewed < total:
        print(f"Uwaga: ocenione {reviewed}/{total} arkuszy")
    chosen = wybor.final_choice(cands, reviews, args.ile)
    save_json(p(work, "wybrane.json"), chosen)
    years = Counter(wybor.year_of(e) for e in chosen)
    print(f"Wybrane: {len(chosen)} (z {len(reviews)} ocenionych)")
    print("  lata: " + ", ".join(f"{y}: {c}" for y, c in sorted(years.items())))


def export_jpeg(data: bytes) -> tuple[bytes, int, int]:
    img = Image.open(io.BytesIO(data))
    img = ImageOps.exif_transpose(img).convert("RGB")
    w, h = wybor.export_size(*img.size)
    if (w, h) != img.size:
        img = img.resize((w, h), Image.LANCZOS)
    for q in (85, 78, 70, 60):
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=q, optimize=True, progressive=False, subsampling=2)  # bez exif=
        if buf.tell() <= MAX_JPEG:
            return buf.getvalue(), w, h
    raise ValueError("JPEG za duży")


def cmd_eksport(args) -> None:
    work = args.praca
    chosen = load_json(p(work, "wybrane.json"), [])
    if not chosen:
        sys.exit("Brak wybranych - najpierw: wybierz")
    import metryki  # noqa: F401 - rejestruje HEIC w Pillow (gdy jest pillow-heif)

    out_dir = p(work, "eksport")
    os.makedirs(out_dir, exist_ok=True)
    reader = takeout.Reader()
    spis = []
    try:
        for i, e in enumerate(chosen, 1):
            path = p(out_dir, f"{e['id']}.jpg")
            try:
                if os.path.exists(path) and not args.od_nowa:
                    with Image.open(path) as im:
                        w, h = im.size
                else:
                    jpg, w, h = export_jpeg(reader.read(takeout.Entry(e["container"], e["member"], e["size"])))
                    with open(path, "wb") as f:
                        f.write(jpg)
            except Exception as err:  # noqa: BLE001
                print(f"  {e['id']} ({e.get('title')}): {err}")
                continue
            spis.append(wybor.index_entry(e, w, h))
            if i % 100 == 0:
                print(f"  {i}/{len(chosen)}", flush=True)
    finally:
        reader.close()
    keep = {f"{s['id']}.jpg" for s in spis}
    for f in os.listdir(out_dir):
        if f.endswith(".jpg") and f not in keep:
            os.remove(p(out_dir, f))
    save_json(p(out_dir, "spis.json"), spis)
    size = sum(os.path.getsize(p(out_dir, f"{s['id']}.jpg")) for s in spis)
    print(f"Eksport: {len(spis)} zdjęć, {size / 1024 / 1024:.1f} MB w {out_dir}")


# ------------------------------------------------------------------ chmura


def cmd_zaloguj(args) -> None:
    import chmura

    cloud = chmura.Cloud(p(args.praca, "sesja.json"))
    email = input("E-mail konta (to samo co w Zakupach / Wadze): ").strip()
    password = getpass.getpass("Hasło (nie będzie widać): ")
    cloud.login(email, password)
    print(f"Zalogowano: {cloud.email} (uid {cloud.uid}). Sesja: {cloud.session_path}")


def cmd_wyslij(args) -> None:
    import chmura

    work = args.praca
    spis = load_json(p(work, "eksport", "spis.json"), [])
    if not spis:
        sys.exit("Brak eksportu - najpierw: eksport")
    cloud = chmura.Cloud(p(work, "sesja.json"))
    cloud.token()
    base = f"archiwum/{cloud.uid}"
    have = set(cloud.list_ids(f"{base}/zdjecia"))
    todo = [s for s in spis if args.wszystkie or s["id"] not in have]
    print(f"Konto {cloud.email}: w bazie {len(have)}, do wysłania {len(todo)}")

    def send(s: dict) -> None:
        with open(p(work, "eksport", f"{s['id']}.jpg"), "rb") as f:
            cloud.set(f"{base}/zdjecia/{s['id']}", {"jpeg": f.read(), "t": int(s["t"])})

    done = 0
    with cf.ThreadPoolExecutor(max_workers=4) as pool:
        for fut in cf.as_completed([pool.submit(send, s) for s in todo]):
            fut.result()
            done += 1
            if done % 50 == 0 or done == len(todo):
                print(f"  {done}/{len(todo)}", flush=True)
    # Spis na końcu: telefon nie zobaczy wpisów bez zdjęć
    items = json.dumps(spis, ensure_ascii=False, separators=(",", ":"))
    cloud.set(base, {"v": 1, "count": len(spis), "items": items, "updatedAt": chmura.Timestamp()})
    print(f"Spis: {len(spis)} zdjęć ({len(items.encode()) / 1024:.0f} KB)")
    if args.usun_stare:
        wanted = {s["id"] for s in spis}
        old = [x for x in have if x not in wanted]
        for x in old:
            cloud.delete(f"{base}/zdjecia/{x}")
        print(f"Usunięte spoza spisu: {len(old)}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Archiwum zdjęć z Google Takeout dla aplikacji Zdjęcia")
    ap.add_argument("--praca", default=DEFAULT_WORK, help="folder roboczy (poza repozytorium)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("skanuj")
    s.add_argument("zrodla", nargs="+", help="ZIP-y Takeoutu albo foldery z nimi / rozpakowane")
    s.add_argument("--procesy", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    s.add_argument("--ponow-bledy", action="store_true", help="zeskanuj jeszcze raz zdjęcia z błędem (np. HEIC)")
    s.set_defaults(fn=cmd_skanuj)
    s = sub.add_parser("kandydaci")
    s.add_argument("--ile", type=int, default=4000)
    s.add_argument("--od-nowa", action="store_true", help="nowe arkusze mimo ocen (stare oceny - do oceny_stare_*)")
    s.set_defaults(fn=cmd_kandydaci)
    sub.add_parser("stan").set_defaults(fn=cmd_stan)
    s = sub.add_parser("wybierz")
    s.add_argument("--ile", type=int, default=1000)
    s.set_defaults(fn=cmd_wybierz)
    s = sub.add_parser("eksport")
    s.add_argument("--od-nowa", action="store_true")
    s.set_defaults(fn=cmd_eksport)
    sub.add_parser("zaloguj").set_defaults(fn=cmd_zaloguj)
    s = sub.add_parser("wyslij")
    s.add_argument("--wszystkie", action="store_true", help="wyślij też te, które już są w bazie")
    s.add_argument("--usun-stare", action="store_true", help="usuń z bazy zdjęcia spoza spisu")
    s.set_defaults(fn=cmd_wyslij)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
