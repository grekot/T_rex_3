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

## Ikona

`python tools/ikona.py` rysuje ikonę (kartka kalendarza z kręgosłupem) i zapisuje ją w
`android/app/src/main/res/mipmap-*` (zwykła i adaptacyjna). Podgląd: `tools/ikona_podglad.png`.

## Uprawnienia

Celowo **brak** `INTERNET`: dane zostają na telefonie. `allowBackup=false`: bez automatycznej
kopii Google; kopia przez ręczny eksport (od wersji 1.0).
