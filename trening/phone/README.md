# Trening: aplikacja na telefon

Flutter 3.41, tylko Android, pakiet `pl.grekot.trening`, minSdk 26.

## Polecenia

```bash
flutter pub get
flutter analyze
flutter test
```

APK release (wspólny klucz z `android/key.properties`, poza gitem; bez niego klucz debug):
`build_apk.cmd` → `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
Na Windows przy błędzie Gradle „Unable to establish loopback connection” ustaw `TEMP`/`TMP`
na zwykły katalog (np. `C:\TMP\jtmp`).

## Kod

| Folder | Co to jest |
|---|---|
| `lib/plan/` | model `plan.json` i `atlas.json` ze ścisłym odczytem (`json.dart`), sprawdzanie odwołań (`sprawdz.dart`) |
| `lib/silnik/` | czysta logika bez Fluttera: kalendarz z etapami według kryteriów (`kalendarz.dart`), flagi ćwiczeń z wyniku testu kierunkowego i zasięgu bólu (`flagi.dart`), daty w UTC (`daty.dart`) |
| `tool/` | `atlas_do_json.dart`: atlas ćwiczeń (Markdown) → `assets/plan/atlas.json` + rysunki |
| `assets/plan/` | dane planu: `plan.json`, `atlas.json`, `img/` |

## Ikona

`python tools/ikona.py` rysuje ikonę (kartka kalendarza z kręgosłupem) i zapisuje ją w
`android/app/src/main/res/mipmap-*` (zwykła i adaptacyjna). Podgląd: `tools/ikona_podglad.png`.

## Uprawnienia

Celowo **brak** `INTERNET`: dane zostają na telefonie. `allowBackup=false`: bez automatycznej
kopii Google; kopia przez ręczny eksport (od wersji 1.0).
