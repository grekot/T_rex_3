# Archiwum z Google Takeout

Wybiera ~1000 najciekawszych zdjęć z całej biblioteki Zdjęć Google i wysyła je do Firestore
(format: [../../ARCHIWUM.md](../../ARCHIWUM.md)). Aplikacja „Zdjęcia” na telefonie bierze z nich wspomnienia
dla zegarka i zdjęcia dla zegarów HomeAutomation. Bez Gemini: odsiew robi skrypt, wybór i podpisy - przegląd arkuszy.

**Pełna instrukcja krok po kroku (także dla nowej sesji Claude): [INSTRUKCJA.md](INSTRUKCJA.md).**

Wymagania: Python 3.10+, `pillow`, `numpy`, `opencv-python` (HEIC tylko z `pillow-heif`).
Folder roboczy: `C:\TMP\Takeout\praca` (zmiana: `--praca` albo `ZDJECIA_PRACA`) - **poza repozytorium**,
bo są w nim miniatury, zdjęcia i token konta.

## Kroki

1. **Takeout** (takeout.google.com): „Odznacz wszystko” → tylko **Zdjęcia Google** → w „Wszystkie albumy”
   zostaw foldery „Photos from RRRR” → plik .zip, 50 GB → pobierz ZIP-y do `C:\TMP\Takeout` (bez rozpakowywania).
2. `python archiwum.py skanuj C:\TMP\Takeout` - katalog (`katalog.jsonl`) i miniatury. Można przerwać i wznowić;
   kolejne ZIP-y (np. nowy eksport) dopisują się do katalogu. `--ponow-bledy` - jeszcze raz zdjęcia z błędem odczytu.
3. `python archiwum.py kandydaci` (gdy są już oceny - odmawia; `--od-nowa` przenosi je do `oceny_stare_<data>`) - odsiew (za małe, rozmazane, ciemne, zrzuty, komunikatory, grafiki, bez daty),
   serie → najlepsze ujęcie, kilka najlepszych z wydarzenia, lata wyrównane → ~4000 kandydatów
   na arkuszach `arkusze/arkusz_NNN.jpg` (30 miniatur, chronologicznie).
4. **Przegląd** (Claude): każdy arkusz → `oceny/arkusz_NNN.json`, niżej. `python archiwum.py stan` pokazuje postęp.
5. `python archiwum.py wybierz` - 1000 najlepszych (≤ 3 z wydarzenia, ≤ 4 z dnia, lata wyrównane).
6. `python archiwum.py eksport` - JPEG ≤ 800×600 (krótszy bok ≤ 600), bez EXIF/GPS, + `eksport/spis.json`.
7. `python archiwum.py zaloguj` - **wpisujesz sam** e-mail i hasło konta (tego co w Zakupach / Wadze);
   w `sesja.json` zostaje tylko token odświeżania.
8. `python archiwum.py wyslij` - zdjęcia, których jeszcze nie ma w bazie, potem spis - scalony ze zdjęciami
   dodanymi z telefonu (`src: "tel"`, Zdjęcia 0.12.0+) i zapisany z warunkiem wersji (gdy telefon w tym czasie
   coś dopisze - jeszcze raz). Zdjęcie z telefonu, które jest też w nowym wyborze z Takeoutu, ustępuje wersji
   z przeglądu. `--usun-stare` usuwa z bazy zdjęcia spoza nowego spisu (po ponownym wyborze; zdjęć z telefonu nie).

Klucz API i projekt bierze z `phone/lib/cloud/firebase_config.dart` (plik poza repo, jak w aplikacji)
albo ze zmiennych `ZDJECIA_API_KEY` i `ZDJECIA_PROJECT`.

## Kolaże

`python archiwum.py kolaze [--ile 150] [--proba N]` - kolaże 2-3 zdjęć z jednego wydarzenia (z eksportu, czyli ze zdjęć,
które są w archiwum) do `praca/kolaze/` + `spis.json`; `wyslij` wysyła je razem ze zdjęciami (wpisy z `k`, ARCHIWUM.md).
`--proba N` robi tylko N losowych do `praca/kolaze_proba/` (do obejrzenia, nie idą do bazy).

- Płótno 800×450 (zegar 480×272); zdjęcia w środkowym pasie 4:3 (x 100-700), bo zegar 320×240 obetnie boki.
- Układy (`kolaze.py`, losowane stale dla danej grupy): obok siebie (polaroidy / cienka ramka), wstawka (jedno
  na całe płótno, drugie w wolnym rogu - tylko gdy róg nie zasłania twarzy ani motywu), duże i małe zachodzące
  na siebie, okno (zaokrąglone + drugie w kółku), trójka (duże + dwa małe), polaroidy w wachlarzu.
- Tła: rozmyte zdjęcie, papier, a okazjonalnie motyw - zima / święta (grudzień, choinka), urodziny (tort, świeczki),
  wiosna (Wielkanoc), lato, jesień.
- Podpis, ocena i czas najlepszego zdjęcia z grupy. Lata wyrównane jak przy wyborze, jedno zdjęcie w jednym kolażu.
- Po zmianie wyboru (`wybierz` / `eksport`) uruchom `kolaze` jeszcze raz; `wyslij` pomija kolaże ze zdjęciami spoza eksportu.

## Oceny przeglądu

`oceny/arkusz_012.json` - tylko wybrane kafelki (numer z arkusza), reszta = odrzucone:

```json
{"arkusz": 12, "wybrane": {
  "3":  {"s": 8, "c": "Ognisko nad Wigrami"},
  "17": {"s": 9, "c": "Kuba na rowerze", "f": [0.35, 0.20, 0.40, 0.55]}
}}
```

- `s` - ocena 1-10; do archiwum wchodzą zdjęcia z oceną ≥ 6 (najlepsze najpierw).
- `c` - podpis po polsku, ≤ 28 znaków (zegarek dopisze „ · 2014”). Opis sceny, nie zgadywanie imion
  (imiona tylko z podpisu kafelka - osoby rozpoznane przez Zdjęcia Google).
- `f` - opcjonalnie najciekawszy fragment (left, top, width, height - ułamki zdjęcia), gdy wyraźnie nie jest
  w środku albo jest mały. `m` - opcjonalnie główny motyw. Bez nich kadr robi telefon (twarze, pasy ciekawości).
- `o` - opcjonalnie obrót: 90, 180 albo 270 stopni w prawo, gdy zdjęcie na kafelku leży bokiem albo do góry nogami
  (stare aparaty nie zapisywały orientacji). `eksport` obraca zdjęcie, `f`/`m` liczy się względem zdjęcia
  już obróconego. Zmiana `o` po eksporcie: usuń `eksport/<id>.jpg` (albo `eksport --od-nowa`).

Co wybierać (jak polecenie dla Gemini w telefonie): ludzie i ich chwile (twarze, emocje, rodzina, spotkania),
podróże i krajobrazy, święta i wydarzenia, zwierzęta, ładne światło i kolory - zdjęcia, które miło zobaczyć po latach.
Odrzucać: dokumenty, paragony, tablice, zrzuty, zdjęcia „do zapamiętania” (półki, ceny, części), przypadkowe,
nieostre, prawie takie same jak sąsiednie (z serii wybrać jedno). Zdjęcie dobre dla małego okrągłego ekranu:
czytelny motyw, nie tłum drobnych szczegółów.

## Testy

`python -m unittest test_archiwum` - dopasowanie JSON-ów Takeoutu (skracanie nazw, liczniki, wersje edytowane),
odsiew, wydarzenia i serie, wybór końcowy z limitami, rozmiar eksportu i cały przebieg na sztucznym Takeoucie (bez chmury).
