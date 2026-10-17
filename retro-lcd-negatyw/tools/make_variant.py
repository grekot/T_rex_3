#!/usr/bin/env python3
"""Tworzy kopię tarczy w innej palecie jako osobną tarczę (własne appId i nazwa).

Dzięki temu na zegarku mogą być jednocześnie np. wersja szara i negatyw.
Kopia jest generowana: zmiany rób w retro-lcd i uruchom skrypt ponownie.

Z folderu retro-lcd:
    python tools/make_variant.py negative 1087159 "Retro LCD Negatyw" ../retro-lcd-negatyw
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKER = ".wariant-retro-lcd"  # chroni przed nadpisaniem folderu, którego nie wygenerowaliśmy


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    palette, app_id, name, out = sys.argv[1], int(sys.argv[2]), sys.argv[3], os.path.abspath(sys.argv[4])
    if os.path.abspath(out) == ROOT:
        sys.exit("Folder docelowy to sam projekt retro-lcd.")
    if os.path.exists(out) and not os.path.exists(os.path.join(out, MARKER)):
        sys.exit(f"{out} istnieje i nie jest wygenerowanym wariantem - nie nadpisuję.")

    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, MARKER), "w").close()
    for d in ("tools", "watchface"):
        shutil.copytree(os.path.join(ROOT, d), os.path.join(out, d), dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("__pycache__"))
    for f in ("app.js", "package.json"):
        shutil.copy2(os.path.join(ROOT, f), out)

    with open(os.path.join(ROOT, "app.json"), encoding="utf-8") as f:
        app = json.load(f)
    app["app"]["appId"] = app_id
    app["app"]["appName"] = name
    app["app"]["description"] = f"{name} - wariant kolorystyczny tarczy Retro LCD"
    for lang in app["i18n"].values():
        lang["appName"] = name
    with open(os.path.join(out, "app.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(app, f, indent=2, ensure_ascii=False)
        f.write("\n")

    with open(os.path.join(out, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"# {name}\n\n"
                f"Wariant tarczy [Retro LCD](../retro-lcd/README.md) w palecie `{palette}`, "
                f"jako osobna tarcza (appId {app_id}).\n\n"
                "Folder jest **generowany** - nie edytuj go. Zmiany rób w `retro-lcd`, potem z tamtego folderu:\n\n"
                "```bash\n"
                f'python tools/make_variant.py {palette} {app_id} "{name}" ../{os.path.basename(out)}\n'
                "```\n\n"
                "![Podgląd](docs/podglad.png)\n\n"
                "Instalacja: `zeus preview` w tym folderze.\n")

    subprocess.run([sys.executable, os.path.join(out, "tools", "gen_assets.py"), palette], check=True)


if __name__ == "__main__":
    main()
