# Zdjęcia

Najciekawsze zdjęcia z galerii telefonu losowo pokazywane na zegarku.

Stan: przesył przez most lokalny działa (etap 0), telefon wybiera najciekawsze zdjęcia (etap 1),
a zegarek sam pokazuje je w losowych chwilach ([zegarek 0.4.0](#losowe-zdjęcia-na-zegarku-zegarek-040)).
Dalej: etap 2 – synchronizacja przyrostowa i kasowanie starych zdjęć.

**Etap 0 – próba** sprawdzał dwie rzeczy, od których zależy cały pomysł:

1. czy aplikacja Zepp na telefonie może pobierać pliki z **mostu lokalnego** (`http://127.0.0.1:8765`),
   czyli z aplikacji „Zdjęcia” na tym samym telefonie – bez chmury i bez konta,
2. ile waży zdjęcie po konwersji do formatu zegarka i ile trwa jego przesłanie przez Bluetooth
   (od tego zależy, ile zdjęć zmieści się w puli na zegarku).

## Jak to działa

```
Telefon: aplikacja „Zdjęcia” (Flutter)
  ostatnie zdjęcia z galerii → kwadrat ze środka → PNG 480×480 (czarne narożniki)
  serwer tylko pod 127.0.0.1:8765:  /manifest.json  i  /p/<id>.png
        ↓  ten sam telefon
Side Service w aplikacji Zepp: lista → pobranie PNG → image.convert → TransferFile
        ↓  Bluetooth
Zegarek: odbiór do data://download/zd_<id>.png → IMG na cały ekran
```

Zdjęcia Google nie wchodzą w grę: od 31.03.2025 Google Photos API nie daje dostępu do biblioteki
(tylko ręczny wybór w Pickerze), a Ambient API jest wyłącznie dla firm partnerskich.
Dlatego źródłem jest galeria telefonu (te same zdjęcia, które Google Photos kopiuje do chmury).

| Folder   | Co to                                                          |
|----------|----------------------------------------------------------------|
| `watch/` | aplikacja na zegarek (zeus, appId 1087163, API 3.0)             |
| `phone/` | aplikacja na telefon (Flutter, `pl.grekot.zdjecia`)             |

## Test etapu 0

**Telefon**

1. Zainstaluj „Zdjęcia” ze **Sklepu rodzinnego** albo ręcznie
   `phone/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (budowanie: `phone/build_apk.cmd`).
2. Otwórz „Zdjęcia” → **Weź ostatnie** (domyślnie 3) → zezwól na dostęp do zdjęć.
   Przy każdym zdjęciu widać rozmiar PNG.
3. Włącz **Udostępnij zegarkowi** → **Sprawdź serwer** powinno pokazać „OK”.
   Zostaw aplikację otwartą – ekran telefonu nie zgaśnie, dopóki serwer działa.

**Zegarek**

1. W folderze `watch/`: `zeus preview` → Amazfit T-Rex 3 → kod QR w aplikacji Zepp.
2. Na zegarku otwórz **Zdjęcia** i naciśnij **Test sieci** – pobiera obrazek z internetu
   i przechodzi cały łańcuch (pobranie → konwersja → przesłanie) bez mostu.
3. Naciśnij **Pobierz z telefonu**. Status pokazuje kolejne kroki, a po każdym zdjęciu:
   rozmiar na zegarku, czas konwersji i czas przesłania (BT).
4. **Pokaż zdjęcia** – stuknięcie w zdjęcie = następne. Jeśli zamiast zdjęcia jest czarny ekran,
   naciskaj **ścieżka** (różne zapisy ścieżki pliku), aż zdjęcie się pojawi – wybór się zapamiętuje.
   **Wyczyść** usuwa zdjęcia z zegarka, żeby powtórzyć próbę.

**Co zgłosić**: linie z panelu zegarka (średni rozmiar i czas BT), która „ścieżka” zadziałała,
i czy w aplikacji na telefonie w „Zapytania z aplikacji Zepp” pojawiły się wpisy.

## Losowe zdjęcia na zegarku (zegarek 0.4.0)

Zegarek sam, w losowych chwilach, pokazuje ciekawe zdjęcie – bez powiadomienia i bez wyboru „Pokaż/Usuń”
(**sposób D**, sprawdzony na T-Rex 3):

```
budzik systemowy (@zos/alarm, store: true – przetrwa restart zegarka)
  → wprost ekran page/gt/photo (param {"m":"D","at":…})
  → zapowiedź „Zobacz to” (czarny ekran, zwykła jasność) + krótka wibracja
  → uniesienie ręki albo stuknięcie (albo tylko stuknięcie – ustawienie): ekran jaśniej, zdjęcie z worka
  → opuszczenie ręki albo podwójne stuknięcie: zdjęcie gaśnie, powrót do tarczy
  → od razu uzupełnienie planu budzików
```

Zegarek 0.7.0: zdjęcie jest losowane i wczytane od razu pod zapowiedzią (odsłonięcie bez opóźnienia), ale do worka
trafia dopiero przy odsłonięciu; bez reakcji zapowiedź znika po 30 s i nieobejrzane zdjęcie nie przepada,
odsłonięte zdjęcie gaśnie samo najpóźniej po 60 s. **Pojedyncze stuknięcie** w zdjęcie = następne z worka.
Uniesienie/opuszczenie ręki wykrywają naraz systemowe `onWristMotion` (@zos/interaction) i własna logika
z akcelerometru (`watch/utils/wrist.js`: ekran do twarzy = |z| ≥ 75% grawitacji przez 250 ms, ręka opuszczona
= |z| ≤ 45% przez 500 ms; testy `watch/test/wrist.test.mjs`) – liczy się to, co zgłosi się pierwsze.
Gaszenie ekranu po opuszczeniu ręki jest na czas strony wyłączone, żeby to aplikacja przywróciła jasność.

Zegarek 0.8.0: ustawienie **Odsłanianie zdjęcia** – „ręka lub stuknięcie” (domyślnie, jak wcześniej) albo
„tylko stuknięcie”. Przy „tylko stuknięcie” uniesienie ręki nie odsłania zdjęcia, a zapowiedź podpowiada
„stuknij, aby zobaczyć”; opuszczenie ręki nadal gasi już odsłonięte zdjęcie.

Zegarek 0.8.1: panel domowy sam pobiera zdjęcia po otwarciu i po każdym odebranym zdjęciu się przebudowywał –
gdy na wierzchu były Ustawienia, jego przyciski rysowały się na nich. Teraz strony zapisują, która jest na wierzchu
(`watch/utils/pages.js`, `globalData.top`), panel w tle tylko zapamiętuje zmianę i przebudowuje się po powrocie.

**Losowanie** (`watch/utils/schedule.js`, testy `watch/test/schedule.test.mjs`):

- okno godzin (domyślnie 9:00–21:00) dzielone na tyle równych przedziałów, ile zdjęć dziennie
  (domyślnie 3: 9–13, 13–17, 17–21); w każdym przedziale losowa minuta, ale nie bliżej poprzedniej niż **2 h**
  (gdy okno jest za krótkie na 2 h – połowa przedziału),
- **plan na dziś i 2 kolejne dni**; dziś tylko później niż za 2 min i proporcjonalnie mniej zdjęć
  (ustawienie o 15:00 przy 3 razy w 9–21 da dziś 2 zdjęcia),
- **worek**: zdjęcie losowane w chwili budzika spośród tych, których w tej rundzie jeszcze nie było; gdy były
  wszystkie – nowa runda (bez powtórzenia ostatniego). Nowe zdjęcia od razu trafiają do worka, usunięte z niego znikają.

**Uzupełnianie planu** (`watch/utils/alarms.js`) przy każdym starcie aplikacji i każdym otwarciu ekranu zdjęcia:
budziki aplikacji z systemu (`getAllAlarms`) porównywane z planem w pamięci zegarka – przeterminowane i obce
(np. próby z wersji 0.3) są anulowane, zgubione ustawiane jeszcze raz, brakujące dni dopisywane.
Łańcuch sam się podtrzymuje: każdy budzik otwiera ekran zdjęcia, a ten dokłada kolejne dni.
Godziny okna liczone są w czasie lokalnym z zegara systemowego (`Time` z `@zos/sensor`).

**Ustawienia** – panel **Ustawienia**:

| Pole | Domyślnie | Zakres |
|------|-----------|--------|
| Włączone / Wyłączone (stuknięcie w przycisk) | włączone | wyłączenie anuluje wszystkie budziki |
| Ile razy dziennie | 3 | 1–24 (powyżej 6 większymi krokami) |
| Od godziny | 9:00 | 0:00–23:00 |
| Do godziny | 21:00 | 1:00–24:00, zawsze co najmniej 1 h po „od” |
| Jasność przy zdjęciu | 70% | bez zmian albo 50–100% co 10% |
| Odsłanianie zdjęcia (stuknięcie w przycisk) | ręka lub stuknięcie | ręka lub stuknięcie / tylko stuknięcie |

Chwilę po zmianie liczby, godzin albo włączenia plan liczy się od nowa (stare budziki anulowane, nowe ustawione);
jasność i odsłanianie zapisują się od razu, bez przeliczania. Pod spodem:
najbliższe zdjęcia po dniach, kiedy zegarek ostatnio sam pokazał zdjęcie i przycisk **Próba za 1 min**
(jeden budzik za 60 s, działa też przy wyłączonym losowaniu). Panel domowy pokazuje „Następne zdjęcie: dziś 16:44”.

### Test na zegarku

1. Zainstaluj (`zeus preview` w `watch/`), otwórz **Zdjęcia** – na panelu powinno być „Następne zdjęcie: …”.
2. **Ustawienia → Próba za 1 min** → wyjdź z aplikacji i opuść rękę. Po minucie zegarek wibruje i pokazuje
   „Zobacz to”; unieś rękę → zdjęcie jaśniej, opuść rękę → zgaśnie (albo stuknij / stuknij 2 razy).
3. Krótkie okno zamiast czekania godzinami: **Od** = bieżąca godzina, **Do** = następna, **Ile razy** = 6
   (np. o 14:20 ustaw 14:00–15:00 → zdjęcia mniej więcej co 10 min do 15:00; lista „Najbliższe zdjęcia” pokazuje godziny).
4. Po próbie wróć do 3 razy, 9:00–21:00.

Historia: w próbie 0b (zegarek 0.2.0) sprawdziliśmy powiadomienie „Zobacz to” z budzika i trzy sposoby otwarcia
ekranu zdjęcia przyciskiem „Pokaż” (A – wprost ekran, B – `launchApp` z usługi, C – budzik z usługi). Działały
wszystkie, ale użytkownik woli bez powiadomienia, więc od 0.4.0 zostaje tylko sposób D; usługi w tle
i uprawnienie `device:os.notification` zostały usunięte.

## Diagnoza

| Objaw | Znaczenie |
|-------|-----------|
| Zegarek: „Most niedostępny”, na telefonie brak zapytań | Zepp nie łączy się z 127.0.0.1 – plan B: pliki w Firebase Storage |
| Na telefonie jest `GET /manifest.json`, ale nie ma `GET /p/...` | lista działa (fetch), a pobieranie plików (downloader) nie |
| „Test sieci” też kończy się błędem | problem z pobieraniem/konwersją/przesyłem w Zepp, nie z mostem |
| Zdjęcia doszły, ale żadna „ścieżka” ich nie pokazuje | IMG nie czyta plików z `data://download` – trzeba innego sposobu wyświetlania |

## Etap 1: telefon wybiera najciekawsze zdjęcia

Wszystko na telefonie, bez internetu (`phone/lib/select/` – czysta logika z testami, `phone/lib/media/` – galeria i ML Kit):

1. **Kandydaci**: zdjęcia z aparatu (folder `DCIM`, bez zrzutów ekranu i komunikatorów) z ostatnich 30 dni
   plus ulubione z innych folderów.
2. **Jakość** na miniaturze 256 px: ostrość (wariancja laplasjanu), jasność, prześwietlenia, kolorowość,
   odcisk dHash. Ostrość i kolorowość liczone względem pozostałych zdjęć z okresu (centyl) – 12% najmniej
   ostrych odpada.
3. **Treść** (ML Kit na miniaturze 512 px): twarze z uśmiechem i otwartymi oczami, etykiety (zwierzę, święto,
   krajobraz, zachód słońca…), a gdy nie ma twarzy – ilość tekstu. Paragony, kartki, dokumenty i zrzuty odpadają.
4. **Pula 20 zdjęć**: punkty + premia za ulubione i świeżość; z serii podobnych ujęć tylko najlepsze;
   najwyżej 2 zdjęcia z dnia, z różnych wydarzeń (≥ 2 h odstępu); gdy brakuje zdjęć, zasady łagodnieją.
5. **Kadr pod koło**: twarze z ramionami mieszczą się w kole (nie tylko w kwadracie), bez twarzy – najciekawszy
   pas zdjęcia; PNG z miniatury 1600 px, więc przybliżenie jest ostre. Kadr da się poprawić palcami.

Wyniki analizy są zapamiętywane (`analysis.json`), więc kolejne odświeżenia analizują tylko nowe zdjęcia.

**Ocena przez AI (od 0.3.0).** Sama punktacja z telefonu wybierała słabo (nie odróżnia wspomnień od zdjęć
„praktycznych”), więc decyduje Gemini – tak jak w EscapeRoom: klucz z Google AI Studio wpisany w aplikacji
(ikona ✨), trzymany w zaszyfrowanym magazynie Androida (`flutter_secure_storage`), zapytania wprost do
`generativelanguage.googleapis.com` (`phone/lib/ai/`). Telefon najpierw odsiewa nieostre zdjęcia, dokumenty
i serie, potem Gemini ocenia miniatury 512 px po 12 w zapytaniu (przerwa 4 s, ponawianie przy limicie)
i zwraca ocenę 1–10, „nadaje się / nie”, kategorię, polski podpis i prostokąt głównego motywu (kadr).
Preferencje właściciela („co lubię / czego nie chcę”) są dopisywane do polecenia; ich zmiana albo zmiana
modelu = ocena od nowa. Oceny w `ratings.json`. Bez klucza zostaje punktacja z telefonu.
Przy kluczu bez płatności w AI Studio obowiązują warunki darmowego Gemini API (Google może używać treści
do ulepszania usług).
Na ekranie: pula w okrągłych podglądach z powodem wyboru, przypinanie, usuwanie, poprawa kadru,
ręczne dodawanie zdjęć z galerii i ustawienia (dni, wielkość puli).

## Pełna automatyka (telefon 0.4.0, zegarek 0.5.0)

Bez udziału właściciela:

- **Telefon – usługa w tle** (`phone/lib/background/auto_service.dart`, `flutter_foreground_task`,
  typ `specialUse`: bez limitu czasu, start po restarcie telefonu i po aktualizacji). Most 127.0.0.1 działa
  cały czas i czyta pulę z plików (`published.json` + PNG), a co 12 h (po błędzie po godzinie) usługa sama
  odświeża pulę: nowe zdjęcia → analiza → Gemini → kadry. Ten sam `PoolController` działa w aplikacji
  i w usłudze (headless); blokada `refresh.lock` pilnuje, żeby nie odświeżały naraz. Android wymaga
  cichego stałego powiadomienia („Pula: 20 zdjęć · odświeżono …”).
- **Zegarek – przy każdym samoczynnym wyskoczeniu** zdjęcia (losowo 3×/dzień, 9–21) w tle dociąga
  najwyżej 2 nowe zdjęcia z puli telefonu (czeka na to najwyżej 60 s) i kasuje te, które z puli wypadły
  (tylko nadmiar ponad wielkość puli, najstarsze najpierw). Świeżo dociągnięte zdjęcie wyskakuje
  przy następnej okazji jako pierwsze; pod zdjęciem podpis od AI.
- **Ręczne otwarcie aplikacji na zegarku** od razu pobiera wszystkie nowe zdjęcia i robi porządek.

## Wspomnienia (telefon 0.5.0)

Starsze zdjęcia bywają ciekawsze, więc część puli (domyślnie 50%, w ustawieniach 0/25/50/75%) to
wspomnienia (`phone/lib/select/memories.dart`). Przy odświeżeniu, gdy wspomnień brakuje, telefon losuje
do 6 tygodniowych okresów z historii galerii (od najstarszego zdjęcia z aparatu do 30 dni wstecz; co trzeci
okres to ten sam tydzień w którymś z poprzednich lat). Z okresu bierze do 20 zdjęć rozłożonych w czasie
(bez serii), analizuje je, 10 najlepszych wg telefonu ocenia Gemini (jedno zapytanie), a do puli trafiają
najwyżej 2 z oceną ≥ 6. Wspomnienie zostaje w puli 3,5–7 dni (losowo, żeby wymieniały się po trochu),
przypięte – na stałe. Na zegarku podpis z rokiem, np. „Nad jeziorem · 2019”.

**Data zrobienia, nie dodania (0.6.1).** Filtry biblioteki galerii działają na `date_added` (kiedy plik
trafił na telefon), więc po przeniesieniu zdjęć ze starego telefonu wszystkie wyglądały na „z 2026”.
Zapytania idą teraz własnym warunkiem SQL po `datetaken` (`takenBetweenSql`, z zapasem na zdjęcia bez
tej daty i z dopisanym `media_type = 1`). Losowanie omija lata, które już są wśród wspomnień (do 4 prób),
a puste okresy nie zużywają limitu 6 zapytań AI (najwyżej 30 prób).

## Kadr od AI (telefon 0.6.0)

Gemini przy ocenie zwraca też `focus` – najciekawszy fragment zdjęcia pod okrągły ekran (cała scena
albo ciaśniejszy detal, bez ucinania ludzi). Kolejność kadrowania (`autoCropWithSource` w
`phone/lib/select/crop.dart`): ręczny → fragment od AI wypełniający kadr (bok = dłuższy bok fragmentu
+8%, najmocniej 0,4 krótszego boku zdjęcia) → gdy ucina twarz, kadr obejmuje fragment i twarz; gdy obu
nie da się zmieścić, wyraźna twarz (≥ 1% zdjęcia) wygrywa → twarze → główny motyw → najciekawszy pas.
Zdjęcia z puli ocenione przed 0.6.0 są oceniane ponownie, żeby dostały kadr od AI; nowy kadr = nowe
zdjęcie dla zegarka (dociągane po trochu). Skąd kadr, widać na karcie zdjęcia.

## Jaśniej i żywiej (telefon 0.7.0, zegarek 0.6.0)

- **Zegarek** podczas pokazu zdjęcia (samoczynnego i w podglądzie) wyłącza na chwilę jasność automatyczną
  i ustawia jasność z ustawień („Jasność przy zdjęciu”: bez zmian albo 50–100% co 10%, domyślnie 70%).
  Poprzednie ustawienia systemu są zapamiętane (`zd_bright_restore`) i przywracane przy zamknięciu zdjęcia,
  a gdyby aplikacja zamknęła się wcześniej – przy następnym starcie.
  Zegarek 0.7.1: od 0.7.0 jasność podbija się przy odsłonięciu zdjęcia (ekran już świeci, więc naprawdę działa)
  i 100% było za jaskrawe – domyślnie 70%, a zapisane wcześniej 100% zmienia się raz na 70% (`zd_settings_v`).
- **Telefon** przygotowuje PNG z żywszymi kolorami (`vivid` w `photo_prep.dart`: nasycenie ×1,25 względem
  jasności piksela, kontrast ×1,08, gamma 0,94, każdy krok przycięty do 0..255 – `img.adjustColor` zawijał
  kanały przy nasyconych barwach). Wersja obróbki jest w nazwie PNG i w id na zegarku, więc zegarek
  wymieni zdjęcia na nowe.
- **Telefon 0.9.0 (obróbka v3)**: jasne zdjęcia wyglądały na prześwietlone – liniowy kontrast robił biel ze wszystkiego
  powyżej ok. 92% jasności, a gamma 0,94 i nasycenie dociskały jasne kanały do 255. Teraz obróbka zależy od zdjęcia:
  - kontrast jako łagodna krzywa S (w środku ×1,08, czerń i biel zostają na miejscu – nic się nie przycina),
  - gamma od średniej jasności koła na zegarku i udziału prawie białych pikseli: ciemne zdjęcie 0,92 (jaśniej),
    przeciętne 1,0, jasne do 1,10 (ciemniej),
  - nasycenie do ×1,2, słabnące w jasnych miejscach (jasność 180 → 240) i wykorzystujące najwyżej 60% zapasu
    do granicy kanału, więc barwa zostaje, a jasne kolory nie robią się płaskie.

  Na próbnych przejściach kolorów (prawie biel = jasność ≥ 245): śnieg 25% → v2 48%, v3 25%; niebo z chmurami
  7,5% → v2 20%, v3 7,5%; ciemne wnętrze: średnia jasność 54 → v2 53, v3 58. Testy w `phone/test/photo_prep_test.dart`.

## Wydanie do Sklepu rodzinnego

Tag `zdjecia-vX.Y.Z` uruchamia [release-zdjecia.yml](../.github/workflows/release-zdjecia.yml)
(wspólny workflow z `grekot/App_storage`): APK arm64 podpisany wspólnym kluczem trafia do GitHub Release
jako `zdjecia.apk`, a wersja do biblioteki sklepu. Do grup przypisuje administrator:
`sklep przypisz zdjecia --grupa Ja`.

## Testy

```bash
cd watch && npm test
```

```bash
cd phone && flutter test
```
