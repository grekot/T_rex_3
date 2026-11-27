# MapyChodzone

Piesza mapa turystyczna **offline** na Androida (nazwa to gra słów: mapy piesze, do chodzenia).
Plan i decyzje: `C:\TMP\My_GIT\MapyChodzone\plan_aplikacji.md` (poza repozytorium).

Stan: **prototyp M0** (27.11.2026): jeden region testowy (Beskid Makowski, Wyspowy i Gorce).

## Co umie M0

- pobiera region z [grekot/mapychodzone-dane](https://github.com/grekot/mapychodzone-dane):
  mapę bazową (PMTiles), szlaki (GeoJSON), styl mapy i dane tras BRouter (`*.rd5` z brouter.de),
- pokazuje mapę bez internetu: szlaki w kolorach PTTK obok siebie, ścieżki, szczyty z wysokością,
- pozycja GPS z kierunkiem (po zgodzie na lokalizację),
- **trasa po ścieżkach**: przytrzymaj palec na mapie (start, cel, kolejne punkty przedłużają trasę);
  BRouter liczy ją offline (profil `hiking-mountain`), panel pokazuje długość, podejścia, zejścia,
  czas wg DIN 33466 i profil wysokości.

## Budowa

```
phone\build_apk.cmd
```

APK: `phone\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
Wydanie do Sklepu rodzinnego: tag `mapychodzone-vX.Y.Z` → `.github/workflows/release-mapychodzone.yml`.

Testy: `flutter test` w `phone` (trasa i DIN, katalog paczek, styl).

## Układ kodu (`phone/lib`)

| Folder | Zawartość |
|---|---|
| `dane/` | katalog paczek, pobieranie z SHA-256, pliki w telefonie (`Magazyn`) |
| `mapa/` | przygotowanie stylu (ścieżki `file://`, `pmtiles://file://`) |
| `trasa/` | BRouter przez kanał (`Trasy.kt`), model trasy, przewyższenia, czas DIN 33466 |
| `ui/` | ekrany: start, pobieranie regionu, mapa z panelem trasy |

Android: `MainActivity.kt` (kanały `urzadzenie` i `trasy`), `Trasy.kt` (BRouter),
`android/app/libs/brouter-1.7.10-ro.jar`.

## Licencje

- Dane mapy i szlaków: © OpenStreetMap contributors (ODbL); mapa bazowa: Protomaps.
- [BRouter](https://github.com/abrensch/brouter) 1.7.10: MIT (jar i profil `hiking-mountain.brf`, `lookups.dat`).
- Fonty Noto Sans: SIL OFL (`assets/mapa/glify/OFL.txt`); ikony mapy: Protomaps basemaps-assets (MIT).
- [MapLibre Native](https://github.com/maplibre/maplibre-native) przez `maplibre_gl`: BSD-2-Clause.
