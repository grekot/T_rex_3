# Korona – zdobyte szczyty Korony Gór Polski

Aplikacja na zegarek (Zepp OS, Amazfit T-Rex 3 i inne okrągłe). Gdy stoisz na szczycie
z listy, zegarek to rozpoznaje po GPS, wibruje i pokazuje **„Jesteś na szczycie!”** z
przyciskiem **Zaliczam**, który zapisuje dzisiejszą datę. Pokazuje postęp „12 / 28”,
listę szczytów z datami zdobycia i najbliższe niezdobyte szczyty ze strzałką kompasu.
Działa bez telefonu i bez internetu.

| Ekran główny | Na szczycie | Lista |
|:---:|:---:|:---:|
| ![ekran główny](docs/podglad.png) | ![na szczycie](docs/podglad-szczyt-gps.png) | ![lista](docs/podglad-lista.png) |
| **Szczegóły** | **Najbliższe** | **Data zdobycia** |
| ![szczegóły](docs/podglad-szczegoly.png) | ![najbliższe](docs/podglad-najblizsze.png) | ![data](docs/podglad-data.png) |

*(podglądy rysowane w Pillow, nie zrzuty z zegarka)*

## Ważne: otwórz aplikację na szczycie

Mini-aplikacja Zepp OS **nie działa w tle**. Zegarek nie zauważy szczytu, jeśli
aplikacja jest zamknięta – trzeba ją otworzyć na wierzchołku (albo chwilę przed nim).
Po wygaszeniu ekranu i podniesieniu ręki wraca ta sama strona (GPS nie startuje od zera).
Szczyt, na którym byłeś bez otwartej aplikacji, dodasz ręcznie z datą.

## Ekrany

- **Ekran główny** – „12 / 28” z paskiem postępu, karta GPS i pod nią lista wszystkich
  szczytów (przewijana). Karta pokazuje kolejno: „Szukam GPS…”, najbliższy niezdobyty
  szczyt z odległością i kierunkiem albo – na wierzchołku – „Jesteś na szczycie!” i
  przycisk **Zaliczam**. Na liście zdobyte szczyty są białe z zieloną kropką i datą,
  niezdobyte szare z wysokością. Stuknięcie w szczyt otwiera szczegóły.
- **Szczegóły szczytu** – wysokość, pasmo, uwagi (wierzchołek graniczny, wariant),
  data zdobycia i czy zaliczony przez GPS, czy dodany ręcznie, odległość od Ciebie.
  Przyciski: niezdobyty → **Prowadź** / **Dodaj datę**; na szczycie → **Zaliczam** /
  **Inna data**; zdobyty → **Zmień datę** / **Cofnij** (z potwierdzeniem).
- **Najbliższe** – niezdobyte szczyty od najbliższego, strzałka kompasu (jak w aplikacji
  Powrót), odległość i kierunek; **‹ ›** przełącza na kolejny. Z przycisku „Prowadź”
  w szczegółach prowadzi do jednego wybranego szczytu.
- **Data zdobycia** – dzień / miesiąc / rok przyciskami + i −, dzień tygodnia dla
  kontroli, **Zapisz**. Daty z przyszłości są blokowane, 31 lutego zmienia się na 28/29.

## Lista: Korona Gór Polski (28 szczytów)

Aplikacja używa listy **Klubu Zdobywców Korony Gór Polski** – tej, na którą zbiera się
pieczątki do odznaki. Pierwsza wersja z 1997 r. („Poznaj Swój Kraj”) miała 27 szczytów;
potem dodano Ślężę, w Pieninach Wysoką zamiast Trzech Koron, a w Górach Bialskich
Rudawiec zamiast Postawnej. W tej postaci (28) lista obowiązuje do dziś, mimo że nowsze
pomiary wskazują w kilku pasmach inny najwyższy punkt.

| # | Szczyt | m n.p.m. | Pasmo |
|---:|---|---:|---|
| 1 | Rysy | 2499 | Tatry |
| 2 | Babia Góra (Diablak) | 1725 | Beskid Żywiecki |
| 3 | Śnieżka | 1603 | Karkonosze |
| 4 | Śnieżnik | 1423 | Masyw Śnieżnika |
| 5 | Tarnica | 1346 | Bieszczady |
| 6 | Turbacz | 1310 | Gorce |
| 7 | Radziejowa | 1266 | Beskid Sądecki |
| 8 | Skrzyczne | 1257 | Beskid Śląski |
| 9 | Mogielica | 1171 | Beskid Wyspowy |
| 10 | Wysoka Kopa | 1126 | Góry Izerskie |
| 11 | Rudawiec | 1106 | Góry Bialskie |
| 12 | Orlica | 1084 | Góry Orlickie |
| 13 | Wysoka (Wysokie Skałki) | 1050 | Pieniny |
| 14 | Wielka Sowa | 1015 | Góry Sowie |
| 15 | Lackowa | 997 | Beskid Niski |
| 16 | Kowadło | 989 | Góry Złote |
| 17 | Jagodna | 977 | Góry Bystrzyckie |
| 18 | Skalnik | 945 | Rudawy Janowickie |
| 19 | Waligóra | 936 | Góry Kamienne |
| 20 | Czupel | 931 | Beskid Mały |
| 21 | Szczeliniec Wielki | 919 | Góry Stołowe |
| 22 | Lubomir | 904 | Beskid Makowski |
| 23 | Biskupia Kopa | 889 | Góry Opawskie |
| 24 | Chełmiec | 850 | Góry Wałbrzyskie |
| 25 | Kłodzka Góra | 765 | Góry Bardzkie |
| 26 | Skopiec | 724 | Góry Kaczawskie |
| 27 | Ślęża | 718 | Masyw Ślęży |
| 28 | Łysica | 614 | Góry Świętokrzyskie |

### Warianty

Część osób chodzi też na „prawdziwie najwyższe” wierzchołki albo na te z pierwszej
wersji listy. Aplikacja je **rozpoznaje i zapisuje**, ale **nie liczą się do 28** (do
odznaki KZKGP liczy się szczyt z listy). Są na dole listy pod nagłówkiem „Warianty”.

| Wariant | m | Zamiast | Dlaczego |
|---|---:|---|---|
| Borowa | 853 | Chełmiec | faktycznie najwyższa w Górach Wałbrzyskich (Chełmiec był mierzony z wieżą) |
| Szeroka Góra | 766 | Kłodzka Góra | wg nowszych pomiarów wyższa |
| Okole | 725 | Skopiec | wg pomiarów z 2021 r. wyższe |
| Agata | 614 | Łysica | wschodni, najwyższy wierzchołek Łysicy (potwierdzone 2019) |
| Postawna | 1117 | Rudawiec | na pierwszej liście z 1997 r. |
| Trzy Korony | 982 | Wysoka | na pierwszej liście z 1997 r. |

**Barania Góra** (zamiast Skrzycznego) i **Wysoki Kamień** (zamiast Wysokiej Kopy)
nie są wariantami KGP – nie znalazłem źródła, które by je tak traktowało. Barania Góra
należy do osobnej odznaki *Korona Beskidu Śląskiego*. Dlatego ich nie dodałem.

### Skąd dane

- Skład listy i wysokości: Wikipedia, hasło
  [Korona Gór Polski](https://pl.wikipedia.org/wiki/Korona_G%C3%B3r_Polski)
  (wersja z 20.10.2026, CC BY-SA 4.0) – zgodne z listą Klubu Zdobywców KGP.
- Współrzędne wierzchołków: [OpenStreetMap](https://www.openstreetmap.org/), węzły
  `natural=peak` (© współtwórcy OpenStreetMap, licencja ODbL), pobrane 20.10.2026 przez
  Overpass API i Nominatim. Id węzła każdego szczytu jest w polu `osm` w
  [watch/utils/peaks.js](watch/utils/peaks.js) – można go podejrzeć pod adresem
  `https://www.openstreetmap.org/node/<id>`.

## Kiedy zegarek uznaje, że jesteś na szczycie

**W promieniu 120 m od wierzchołka, przez 2 kolejne odczyty GPS.** Dlaczego tyle:

- GPS zegarka w lesie myli się o 10–30 m, a węzeł szczytu w OSM bywa przesunięty o
  kilkanaście–kilkadziesiąt metrów;
- wiele szczytów Korony to płaskie, zalesione kopuły (Lubomir, Jagodna, Kłodzka Góra,
  Łysica, Mogielica), gdzie szlak mija najwyższy punkt o kilkadziesiąt metrów; 120 m na
  grzbiecie o nachyleniu 5–10% to 6–12 m poniżej wierzchołka – nadal „na szczycie”;
- najbliższe sobie wierzchołki w danych (Kłodzka Góra – Szeroka Góra, 432 m) mają
  rozłączne strefy, więc zegarek nie pomyli szczytów.

Wyjście ze szczytu liczy się dopiero od 200 m (żeby komunikat nie migał), a dwa odczyty
z rzędu chronią przed pojedynczym skokiem GPS. Wartości są w
[watch/utils/korona.js](watch/utils/korona.js) (`SUMMIT_RADIUS_M`, `LEAVE_RADIUS_M`, `CONFIRM_FIXES`).

## Instalacja

```bash
cd korona/watch
zeus preview
```

Dalej jak przy innych aplikacjach (główny [README](../README.md)): wybierz Amazfit
T-Rex 3, zeskanuj kod QR w aplikacji Zepp (Tryb dewelopera → „+” → Skanuj).

Uprawnienia: lokalizacja, kompas, pamięć zegarka, informacje o urządzeniu. API 3.0
(Zepp OS 3 i nowsze).

## Telefon

Aplikacja na Androida w [`phone/`](phone/README.md) (Flutter, `pl.grekot.korona`) pokazuje
zdobycia z zegarka: postęp każdej listy („12 / 28” z paskiem), listy szczytów z datami,
szczegóły szczytu, mapę (OpenTopoMap / OpenStreetMap, zdobyte na zielono) i historię wejść
po latach, także własne szczyty. Logowanie tym samym kontem co Zakupy i Powrót; dane czyta z
Firestore (`korona/{uid}`, patrz [SYNC.md](SYNC.md)) – zapisuje je zegarek. Bez zegarka
można obejrzeć przykładowe dane (menu ⋮).

## Pamięć

Zdobycia są w LocalStorage zegarka pod kluczem `korona_climbs`:
`{ "rysy": { "d": "2024-07-15", "gps": true }, ... }`. Usunięcie aplikacji z zegarka
kasuje zapis.

## Dla programisty

```
watch/                   aplikacja na zegarek (projekt zeus - tylko z tego folderu `zeus build`)
  app.json               appId 1087166, strony, uprawnienia
  page/gt/home/          ekran główny: postęp, karta GPS, lista
  page/gt/peak/          szczegóły szczytu, Zaliczam / Cofnij
  page/gt/date/          wybór daty zdobycia
  page/gt/nearest/       najbliższe niezdobyte + strzałka kompasu
  utils/peaks.js         lista szczytów (z data/peaks.json)
  utils/korona.js        rozpoznanie szczytu, najbliższe, postęp, daty (czyste funkcje)
  utils/geo.js           odległość, kierunek, formatowanie (z aplikacji Powrót)
  utils/sensors.js       GPS i kompas (z aplikacji Powrót)
  utils/store.js         zapis w LocalStorage
  test/*.test.mjs        testy Node: npm test
phone/                   aplikacja na telefon (Flutter) - wizualizacja zdobyć
data/peaks.json          wspólna lista szczytów dla zegarka i telefonu
SYNC.md                  kontrakt danych zegarek <-> telefon (peaks.json, Firestore)
tools/gen_assets.py      ikona, strzałka i podglądy (Pillow)
docs/                    podglądy ekranów
```

Testy (w `watch/`): `npm test` (dane listy, rozpoznanie z histerezą, najbliższe, postęp, daty).

Pomysły na później: druga lista (Korona Sudetów, Korona Beskidów, Korona Tatr) –
struktura `utils/peaks.js` to jedna tablica, wystarczy dodać drugą i przełącznik.
