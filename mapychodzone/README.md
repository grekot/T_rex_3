# MapyChodzone

Piesza mapa turystyczna **offline** na Androida (nazwa to gra słów: mapy piesze, do chodzenia).
Plan i decyzje: `C:\TMP\My_GIT\MapyChodzone\plan_aplikacji.md` (poza repozytorium).

Stan: **0.0.6** (28.11.2026): przytrzymanie palca pokazuje kółko i menu rodzaju punktu, zwijany panel trasy
z osobno przewijaną listą punktów; w przeglądarce mysz jak w programach do map (lewy = menu punktu,
prawy = przesuwanie, kółko nad panelem przewija panel), podświetlanie punktu z listy na mapie.
0.0.5: konto i trasy zapisane na koncie, wspólne dla telefonu i strony.
0.0.4: 7 regionów z polskimi górami (dane w formacie 3: poziomice, cieniowanie, przeszkody),
trasa na przełaj, wersja przeglądarkowa na https://mapychodzone.web.app.

## Co umie

- **menedżer regionów**: kilka regionów z [grekot/mapychodzone-dane](https://github.com/grekot/mapychodzone-dane)
  naraz (mapa bazowa PMTiles, szlaki i punkty GeoJSON, poziomice, model terenu, przeszkody, styl,
  dane tras BRouter `*.rd5` z brouter.de); pobieranie, aktualizacja (tylko zmienione pliki),
  usuwanie (wspólne `*.rd5` zostają), przełączanie regionu z menu mapy,
- pokazuje mapę bez internetu: szlaki w kolorach PTTK obok siebie, ścieżki, szczyty według rangi
  (najważniejsze od zoomu 8), schroniska, przełęcze, wiaty, źródła, **poziomice** (co 10/20/50 m)
  i **cieniowanie rzeźby terenu** (Copernicus DEM GLO-30),
- pozycja GPS z kierunkiem (po zgodzie na lokalizację),
- **trasa** liczona offline przez BRouter (profil `hiking-mountain`) w trzech trybach:
  Szlakami, Ze skrótami, Najkrócej (`hiking_routes_preference` 5 / 1 / 0; Najkrócej bez kary
  za trudność ścieżki), opcjonalnie **bez stromych podejść** (koszt podejść ponad 15 %);
  z tą opcją tryb liczy też tryby bliżej szlaków i bierze najkrótszy wynik; szlaki T4–T6
  dozwolone z ostrzeżeniem o trudnym terenie,
- tryb **Azymut**: trasa na przełaj z modelu terenu (A* na siatce ok. 25 m), omija urwiska i wodę
  z OSM oraz stoki powyżej 35° (25° bez stromych), podaje azymuty odcinków prostych i ostrzega
  o parkach narodowych i brodach,
- przytrzymanie palca: start, cel, potem **prowadź tędy** (punkt „przez”, nie jest celem),
  **przystanek** (cel pośredni, dzieli trasę na odcinki) albo nowy cel; **lista punktów** w panelu
  z „postaw w nowym miejscu” i „usuń”; dotknięcie punktu – zmiana rodzaju, przeniesienie,
  usunięcie; punkty przy nazwanych obiektach dostają ich nazwę,
- **powrót tą samą drogą** (ślad tam + ten sam ślad odwrócony),
- panel: długość, podejścia, zejścia, czas wg DIN 33466, profil wysokości, odcinki,
- **konto (dobrowolne)**: to samo co w Zakupach, Powrocie i Wadze (Firebase `zakupy-8ec54`, ekran z pakietu
  `wspolne`); „Zapisz” w panelu trasy i **Moje trasy** w menu – trasy w Firestore `trasy/{id}` z gotowym
  śladem, wspólne dla telefonu i strony (w telefonie działają też bez sieci).

## Budowa

```
phone\build_apk.cmd
```

APK: `phone\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
Wydanie do Sklepu rodzinnego: tag `mapychodzone-vX.Y.Z` → `.github/workflows/release-mapychodzone.yml`.

Wersja przeglądarkowa: `phone\build_web.cmd` (Flutter web + dane z `mapychodzone-dane\build`),
test `node tool\web.mjs serwer 8090`, wydanie `npx firebase-tools deploy --only hosting`
(Firebase Hosting, projekt `zakupy-8ec54`, strona `mapychodzone`). W przeglądarce trasy liczy
brouter.de, a przytrzymanie palca to podwójne kliknięcie.

Firebase: `node tool\configure.mjs` zapisuje `lib/firebase_options.dart` (poza repozytorium) z
`android/app/google-services.json` i `tool/firebase-web.json`; CI bierze go z sekretu
`FIREBASE_OPTIONS_MAPYCHODZONE_B64`. Bez pliku aplikacja działa bez konta. Test z emulatorami Firebase:
`flutter build web --dart-define=EMULATOR=localhost` (Auth 9099, Firestore 8080).

Testy: `flutter test` w `phone` (trasa i DIN, katalog paczek, styl, magazyn regionów, PMTiles,
trasa na przełaj, zapisana trasa).

## Układ kodu (`phone/lib`)

| Folder | Zawartość |
|---|---|
| `dane/` | katalog paczek, pobieranie z SHA-256, źródła danych: telefon (`Magazyn`) i przeglądarka (`ZrodloWww`) |
| `mapa/` | przygotowanie stylu (adresy `file://` albo `https://`, opcjonalne poziomice i teren) |
| `teren/` | czytnik PMTiles, model terenu z kafelków PNG terrarium |
| `trasa/` | BRouter (kanał `Trasy.kt` albo brouter.de), trasa na przełaj, model trasy, czas DIN 33466 |
| `pamiec/` | ostatni region w przeglądarce (localStorage) |
| `konto/` | Firebase, zapisana trasa (ślad jako tekst), repozytorium tras w Firestore |
| `ui/` | ekrany: start, regiony, mapa z panelem trasy, Moje trasy i logowanie |

Android: `MainActivity.kt` (kanały `urzadzenie` i `trasy`), `Trasy.kt` (BRouter),
`android/app/libs/brouter-1.7.10-ro.jar`.

## Licencje

- Dane mapy i szlaków: © OpenStreetMap contributors (ODbL); mapa bazowa: Protomaps.
- Poziomice i model terenu: Copernicus DEM GLO-30 © DLR e.V. 2010-2014 i © Airbus Defence and Space GmbH 2014-2018 (Copernicus, UE, ESA).
- [BRouter](https://github.com/abrensch/brouter) 1.7.10: MIT (jar i profil `hiking-mountain.brf`, `lookups.dat`).
- Fonty Noto Sans: SIL OFL (`assets/mapa/glify/OFL.txt`); ikony mapy: Protomaps basemaps-assets (MIT).
- [MapLibre Native](https://github.com/maplibre/maplibre-native) przez `maplibre_gl`: BSD-2-Clause.
