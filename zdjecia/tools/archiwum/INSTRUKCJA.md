# Instrukcja: archiwum zdjęć od Takeoutu do telefonu

Ta instrukcja jest dla osobnej sesji Claude Code, bez wcześniejszego kontekstu, i dla właściciela.
Kroki, przy których Claude ma się zatrzymać i poczekać na właściciela, mają oznaczenie **[TY]**.

## O co chodzi

Z eksportu Google Takeout (cała biblioteka Zdjęć Google) wybieramy **~1000 najciekawszych zdjęć**.
Zapisujemy je jako JPEG-i ≤ 800×600 bez EXIF w Firestore:
- spis: `archiwum/{uid}`,
- zdjęcia: `archiwum/{uid}/zdjecia/{id}`,
- kontrakt danych: [../../ARCHIWUM.md](../../ARCHIWUM.md).

Aplikacja „Zdjęcia” na telefonie (od 0.11.0) bierze z archiwum wspomnienia dla zegarka i co godzinę 4 zdjęcia
dla zegarów HomeAutomation.

Co robi kto:
- **Skrypt na PC** odsiewa technicznie i robi arkusze miniatur. Nie zużywa tokenów.
- **Claude** ogląda arkusze, ocenia zdjęcia i pisze podpisy. **Nie używamy Gemini ani żadnego zewnętrznego API do zdjęć.**
- **[TY]** pobierasz Takeout i logujesz się hasłem.

Stan na 2026-11-16 (Zdjęcia 0.11.0 i HomeAutomation 1.31.0 w sklepie):
- reguły Firestore `archiwum` są opublikowane,
- narzędzie jest gotowe i przetestowane (18 testów),
- przegląd ma objąć **4000 kandydatów** (decyzja właściciela),
- Takeout pobrany i przetworzony - patrz „Stan na 2026-11-16 (wieczór)” niżej.

**Zdjęcia telefon 0.12.0 wydane** (2026-11-16, tag `zdjecia-v0.12.0` na d975059, w sklepie 0.12.0):
telefon sam dokłada do archiwum najlepsze nowe zdjęcia (ocena Gemini 7+, po 3 dniach,
`lib/archive/archive_add.dart`, opis: [../../README.md](../../README.md#nowe-zdjęcia-z-telefonu-do-archiwum-telefon-0120)),
a `wyslij` z tej wersji narzędzia te zdjęcia zachowuje (scalanie spisu z warunkiem wersji). Co dalej:
1. Właściciel sprawdza na telefonie (nie było jeszcze sprawdzane): aktualizacja ze sklepu, logowanie
   w „Archiwum zdjęć”, po kilku dniach liczba „Z telefonu w archiwum” rośnie, przycisk „Dodaj do archiwum”.
2. Archiwum z Takeoutu - kroki niżej. `wyslij` zawsze z aktualnej wersji narzędzia (starsza nadpisałaby spis
   bez zdjęć dodanych z telefonu).

**Zdjęcia telefon 0.13.0 wydane** (2026-11-17, tag `zdjecia-v0.13.0` na f3ecc6d): kolaże z archiwum (wpisy `k`)
idą tylko na zegary biurkowe, nie do wspomnień na okrągły zegarek. 150 kolaży gotowych w `praca/kolaze`
(`archiwum.py kolaze`, opis w [README.md](README.md#kolaże)) - **czekają na wysyłkę** (`wyslij`), aż właściciel
potwierdzi, że telefon ma już 0.13.0 (starsza wersja dałaby kolaże też jako wspomnienia na zegarek).

**Stan na 2026-11-16 (wieczór): archiwum z Takeoutu WYSŁANE.**
- Takeout: 2 ZIP-y (34 + 33 GB), komplet (JSON-y i zdjęcia parują się między paczkami).
- Skan: katalog **24 996 zdjęć**, 0 błędów odczytu (pominięte: zrzuty/komunikatory 367, bez JSON-a 165, duplikaty albumów 32).
- Kandydaci: 4000 (po odsiewie 22 885; odpadły głównie rozmazane - 1872), 134 arkusze.
- Przegląd: 134/134 arkusze, **1629** zdjęć z oceną ≥ 6 (6: 521, 7: 672, 8: 365, 9–10: 71).
  Stare aparaty (2005–2008) bywają bez orientacji - doszło pole oceny `o` (obrót, opis w README.md).
- Wybór: **1000**, eksport 96 MB; wysłane **1000** zdjęć + spis (113 KB, z telefonu 0).
- Folder roboczy `C:\TMP\Takeout\praca` (oceny, wybrane, eksport, sesja) zostaje do późniejszych zmian.
- Do zrobienia przez właściciela: krok 8 (sprawdzenie na telefonie).

## Ustalenia z właścicielem (2026-11-15/16)

Problem: zdjęcia na zegarku i zegarach biurkowych zmieniały się za rzadko i nie sięgały w starszą historię.
Cała biblioteka jest w Zdjęciach Google, a telefon ma tylko jej część.

| Temat | Ustalenie |
|---|---|
| Źródło całej historii | **jednorazowy Google Takeout** (Library API od 31.03.2025 nie daje dostępu do biblioteki; Picker = ręczny wybór pojedynczych zdjęć) |
| Kto wybiera | **Claude z arkuszy miniatur**, lokalnie - nie Gemini ani inne API; skrypt na PC robi tylko odsiew techniczny |
| Ile | **1000** zdjęć w archiwum, przegląd **4000 kandydatów** (~134 arkusze; koszt tokenów zaakceptowany) |
| Gdzie | **Firestore** (projekt `zakupy-8ec54`, plan Spark) - nie Google Drive i nie kopia na telefonie; Storage wymaga Blaze |
| Rozdzielczość | **≤ 800×600** (zegar salonowy ma 480×272) |
| Szybsza wymiana (0.11.0) | wspomnienie 1–2 dni, świeże 1–2 dni, odświeżanie w tle co 6 h; zegary biurkowe - osobna lista `/clocks.json` (pula + 4 zdjęcia z archiwum na godzinę, 6–23) |
| Nowe zdjęcia (0.12.0) | telefon sam dokłada do archiwum: ocena Gemini 7+ (ta, którą zdjęcie już ma - płatny klucz właściciela), po 3 dniach, ≤ 2 z wydarzenia, ≤ 3 z dnia, przypięte zawsze, przycisk „Dodaj do archiwum”, przełącznik na ekranie „Archiwum zdjęć” |
| Kroki właściciela | pobranie Takeoutu, hasło w `zaloguj`, sekrety GitHuba (sekret Zdjęć już ustawiony), sprawdzenie na telefonie |
| Commity i wydania | commit / push / tag tylko na prośbę właściciela; wydanie aplikacji = tag `zdjecia-vX.Y.Z` (wersja z tagu) |

## Zasady, które obowiązują cały czas

- **Prywatność.** Miniatury, arkusze i zdjęcia to prywatne zdjęcia rodzinne. Zostają w folderze roboczym
  `C:\TMP\Takeout\praca`, poza repozytorium.
  - Repozytorium `T_rex_3` jest **publiczne**: żadnych zdjęć, miniatur, arkuszy, ocen ani tokenów w gicie.
  - Niczego z tego nie wysyłamy gdzie indziej: żadnych artefaktów, wklejania do innych usług ani Gemini.
- **Hasło.** Claude nie wpisuje hasła ani e-maila konta. Krok `zaloguj` robi właściciel w swoim terminalu.
  - `sesja.json` w folderze roboczym zawiera token odświeżania. Nie wyświetlać go i nie kopiować.
- **Klucz API.** `zdjecia/phone/lib/cloud/firebase_config.dart` (klucz API Firebase, plik w `.gitignore`):
  nie wyświetlać, nie commitować.
- **Język.** Odpowiadamy właścicielowi po polsku.
- **Konsola.** Polskie znaki w konsoli: przed każdym poleceniem `PYTHONIOENCODING=utf-8` (Git Bash)
  albo `$env:PYTHONIOENCODING='utf-8'` (PowerShell).

## 0. Przygotowanie (Claude)

Narzędzie: `C:\TMP\My_GIT\T_rex_3\zdjecia\tools\archiwum` (Python 3.10+).

```bash
cd /c/TMP/My_GIT/T_rex_3/zdjecia/tools/archiwum
python -c "import PIL, numpy, cv2; print('ok')"     # brakuje? pip install pillow numpy opencv-python
PYTHONIOENCODING=utf-8 python -m unittest test_archiwum   # 18 testów, ok. 10 s
python -c "import chmura; chmura.load_config(); print('konfiguracja Firebase ok')"
```

Jeśli brakuje konfiguracji Firebase (inny komputer albo sesja w worktree, bo plik jest w `.gitignore`):
- Najprościej uruchamiać skrypt z głównego checkoutu: `python C:\TMP\My_GIT\T_rex_3\zdjecia\tools\archiwum\archiwum.py ...`.
  Skrypt nic w repo nie zmienia, a cały stan trzyma w folderze roboczym.
- Na innym komputerze plik da się odtworzyć z sekretu GitHuba `FIREBASE_OPTIONS_ZDJECIA_B64` (base64 pliku).
  Można też ustawić zmienne `ZDJECIA_API_KEY` (klucz Android z projektu `zakupy-8ec54`, ten sam co w Wadze)
  i `ZDJECIA_PROJECT=zakupy-8ec54`. Klucza nie wypisywać w czacie.

HEIC (zdjęcia z iPhone'a): Android robi JPEG-i, więc zwykle niepotrzebne.
- Jeśli skan pokaże błędy „HEIC bez pillow-heif”, zainstaluj `pip install pillow-heif`.
- Potem uruchom `skanuj ... --ponow-bledy`.

Miejsce na dysku: miniatury mają ok. 20 KB na zdjęcie (50 tys. zdjęć to ok. 1 GB). Eksport to ok. 100–150 MB.

## 1. Takeout [TY]

1. https://takeout.google.com → **Odznacz wszystko** → zaznacz tylko **Zdjęcia Google** (wszystkie albumy).
2. **Dalej** → eksport jednorazowy, **.zip**, rozmiar **50 GB** → **Utwórz eksport**.
3. Google przysyła mail z linkami (kilka godzin do 1–2 dni). Pobierz **wszystkie** ZIP-y do `C:\TMP\Takeout`
   i **nie rozpakowuj** ich. Skrypt czyta ZIP-y bezpośrednio, a zdjęcie i jego JSON często są w różnych ZIP-ach.
4. Napisz Claude'owi, że pliki są.

## 2. Skan (Claude)

Skan zwykle trwa dłużej niż limit pojedynczego polecenia, więc uruchom go **w tle** (Bash z `run_in_background`), z logiem:

```bash
cd /c/TMP/My_GIT/T_rex_3/zdjecia/tools/archiwum
PYTHONIOENCODING=utf-8 python archiwum.py skanuj C:/TMP/Takeout > C:/TMP/Takeout/skan.log 2>&1
```

- **Wynik:** `praca/katalog.jsonl` (pomiary, daty z JSON-ów Takeoutu, ulubione, osoby) i `praca/miniatury/<id>.jpg` (320 px).
- **Wznowienie:** po przerwaniu uruchom to samo polecenie. Zeskanowane zdjęcia są pomijane.
  Nowe ZIP-y w tym samym folderze dopisują się do katalogu.
- **Log:** na początku liczby („Pliki”, „zdjęcia”, „pominięte - …”: kosz, zrzuty, komunikatory, duplikaty albumów,
  oryginały z wersją edytowaną). Potem postęp co 400 zdjęć, na końcu „Katalog: N zdjęć, błędy odczytu: …”.
- **Błędów odczytu** powinno być niewiele (uszkodzone pliki). Dużo błędów HEIC → patrz krok 0.

## 3. Kandydaci i arkusze (Claude)

```bash
PYTHONIOENCODING=utf-8 python archiwum.py kandydaci --ile 4000
```

Co robi:
- odsiewa zdjęcia za małe, rozmazane, ciemne, prześwietlone, grafiki i bez daty;
- z serii wybiera najlepsze ujęcie, z wydarzenia kilka najlepszych, a lata wyrównuje (pierwiastek z liczby zdjęć);
- zapisuje `praca/kandydaci.json` i arkusze `praca/arkusze/arkusz_NNN.jpg` (30 miniatur 6×5, chronologicznie)
  oraz `arkusze.json`.

Wypisuje też, ile zdjęć odpadło z każdego powodu, i rozkład kandydatów na lata.
Pokaż to właścicielowi w 3–4 linijkach razem z liczbą arkuszy (dla 4000 kandydatów: 134).

> **Uwaga:** oceny wskazują kafelki po numerze arkusza. Ponowne `kandydaci` unieważnia cały przegląd,
> dlatego skrypt odmawia, gdy w `praca/oceny` są już pliki. `--od-nowa` przenosi stare oceny
> do `oceny_stare_<data>` i zaczyna przegląd od zera, czyli ponowny koszt tokenów. Używać tylko świadomie.

## 4. Przegląd arkuszy (Claude) - tu idą tokeny

### Koszt

- Jeden arkusz (1376×1278 px) to ok. **2,3 tys. tokenów** wejścia, czyli ok. 80 na zdjęcie.
- Odpowiedź to 1–2 tys. tokenów na arkusz.
- Dla 134 arkuszy:
  - wejście: obrazy ok. 0,3 mln + polecenia ok. 0,2–0,4 mln;
  - odczyty z cache: kilka mln;
  - wyjście: ok. 0,2–0,3 mln.
- Można to rozłożyć na kilka dni: każdy arkusz zapisuje się od razu, a `stan` pokazuje postęp.

### Organizacja

- **Nie oglądaj arkuszy w głównej sesji** (poza kalibracją niżej), bo kontekst szybko się zapcha.
  Rozdaj je **pomocnikom** (narzędzie Agent): ok. 11 arkuszy na pomocnika, czyli 12–13 pomocników dla 134 arkuszy.
- Uruchamiaj po ok. 6 pomocników naraz.
- Pomocnicy powinni mieć ten sam model co sesja główna. Nie używaj najtańszego modelu, bo ocena „co jest ciekawe” na nim cierpi.
- Przed rozdaniem zrób **kalibrację**:
  1. Sam przejrzyj `arkusz_001.jpg` i jeden ze środka i zapisz ich oceny.
  2. Pokaż właścicielowi kilka wybranych podpisów i ocen.
  3. Jeśli właściciel jest dostępny i ma uwagi, dopisz je do polecenia dla pomocników.
- Arkusze z istniejącym `praca/oceny/arkusz_NNN.json` są już zrobione. Pomijaj je, co pozwala wznawiać pracę.
- Po każdej partii uruchom `python archiwum.py stan`.

### Polecenie dla pomocnika

Wstaw numery arkuszy i ewentualne uwagi właściciela:

````text
Oceniasz prywatne zdjęcia rodzinne na arkuszach miniatur, żeby wybrać ~1000 najciekawszych z całej biblioteki
(pokazywane losowo na okrągłym zegarku 480×480 i na zegarach biurkowych 480×272 / 320×240).
Prywatność: obrazów nie kopiuj, nie opisuj poza plikami ocen, nie wysyłaj nigdzie. Zapisujesz TYLKO pliki ocen.

Arkusze: C:\TMP\Takeout\praca\arkusze\arkusz_NNN.jpg dla NNN = <np. 012 … 022> (trzy cyfry).
Dla każdego arkusza po kolei:
1. Jeśli C:\TMP\Takeout\praca\oceny\arkusz_NNN.json już istnieje - pomiń.
2. Obejrzyj obraz (narzędzie Read na pliku .jpg).
3. Od razu zapisz C:\TMP\Takeout\praca\oceny\arkusz_NNN.json (UTF-8, narzędzie Write), zanim przejdziesz dalej.

Co jest na arkuszu: nagłówek „Arkusz N/134 data – data”; 30 kafelków (6 kolumn × 5 rzędów) w kolejności
chronologicznej; żółty numer 1-30 w lewym górnym rogu kafelka (liczony wierszami: 1-6 pierwszy rząd, 7-12 drugi…).
Pod kafelkiem: data, „ulub.” = ulubione w Zdjęciach Google (lekki plus), imiona = osoby rozpoznane przez Zdjęcia
Google. Sąsiednie kafelki to często to samo wydarzenie.

Format pliku (TYLKO kafelki z oceną ≥ 6; reszta = odrzucone, nie wpisuj ich):
{"arkusz": 12, "wybrane": {
  "3":  {"s": 8, "c": "Ognisko nad jeziorem"},
  "17": {"s": 9, "c": "Kuba na rowerze", "f": [0.35, 0.20, 0.40, 0.55]}
}}
Pusty arkusz (nic dobrego): {"arkusz": 12, "wybrane": {}}

s - ocena (liczba całkowita):
  9-10 wyjątkowe: silna emocja, ważna chwila, piękne światło/kadr - chce się je pokazać rodzinie;
  7-8  bardzo dobre wspomnienie: ludzie w ciekawej chwili, podróż, krajobraz, święta, zwierzęta;
  6    dobre, warte pokazania raz na jakiś czas.
  Zwykle 8-14 kafelków na arkusz dostaje ≥ 6 (słaby arkusz mniej, mocny więcej). Z serii prawie takich samych
  ujęć tylko JEDNO (najlepsze). Różnicuj oceny - wybór końcowy bierze najpierw najwyższe.
Wybieraj: ludzi i ich chwile (twarze, emocje, rodzina, spotkania), podróże i krajobrazy, święta i wydarzenia,
zwierzęta, ładne światło i kolory - zdjęcia, które miło zobaczyć po latach. Dobre na mały ekran: czytelny motyw.
Odrzucaj: dokumenty, paragony, tablice, ekrany, zdjęcia „do zapamiętania” (półki, ceny, części, usterki),
przypadkowe, nieostre, prześwietlone, tłum drobnych szczegółów bez motywu.

c - podpis po polsku, najwyżej 28 znaków, wielka litera na początku, bez kropki, bez daty ani roku (zegarek dopisze
„ · 2014”), bez „Zdjęcie…”. Opis sceny: „Ognisko nad jeziorem”, „Tort urodzinowy”, „Spacer po Krakowie” (miejsce
tylko gdy pewne). Imiona TYLKO z podpisu pod kafelkiem (nie zgaduj, kto jest kim).

f - opcjonalnie najciekawszy fragment, gdy wyraźnie nie jest w środku albo jest mały: [left, top, width, height]
jako ułamki 0-1 SAMEGO ZDJĘCIA (miniatura jest wpasowana i wyśrodkowana w kwadracie kafelka - pionowe zdjęcie
zajmuje tylko jego środek, liczysz względem zdjęcia, nie kwadratu). m - opcjonalnie główny motyw, ten sam format.
Bez f/m telefon sam kadruje (twarze, ciekawe pasy) - dawaj je tylko, gdy to wyraźnie pomoże.

o - obrót, gdy zdjęcie na kafelku leży bokiem albo do góry nogami (stare aparaty nie zapisywały orientacji):
90 = obrócić o 90° w prawo (zgodnie z zegarem), 270 = w lewo, 180 = do góry nogami. Np. {"s": 7, "c": "…", "o": 90}.
Oceniaj takie zdjęcie tak, jakby było już obrócone; f/m licz względem zdjęcia po obrocie.

<uwagi właściciela z kalibracji, jeśli są>

Na koniec odpowiedz krótko: jedna linia na arkusz „arkusz_NNN: K wybranych, s 9-10: X” i ewentualne problemy
(nieczytelny arkusz, puste kafelki). Nic więcej.
````

### Kontrola po przeglądzie

```bash
PYTHONIOENCODING=utf-8 python archiwum.py stan
```

- Ma pokazać `Arkusze ocenione: 134/134`, a zdjęć z oceną ≥ 6 **ok. 1300 lub więcej**.
  Wybór końcowy ma limity, więc potrzebny jest zapas ponad 1000.
- Jeśli wyszło mniej niż ok. 1100, wybierz mniej (`wybierz --ile 800`) albo przejrzyj ponownie arkusze
  z najmniejszą liczbą wybranych.
- Sprawdź też kilka losowych plików ocen: JSON poprawny, klucze to numery 1–30 jako tekst, `s` to liczba.

## 5. Wybór końcowy i eksport (Claude)

```bash
PYTHONIOENCODING=utf-8 python archiwum.py wybierz --ile 1000
PYTHONIOENCODING=utf-8 python archiwum.py eksport
```

- **`wybierz`** bierze zdjęcia z oceną ≥ 6, najlepsze najpierw, w limitach: ≤ 3 z wydarzenia, ≤ 4 z dnia, lata wyrównane.
  Gdy brakuje zdjęć, limity się luzują. Wynik: `praca/wybrane.json` i rozkład na lata.
  Ponowne uruchomienie (np. z innym `--ile`) nie wymaga przeglądu.
- **`eksport`** zapisuje `praca/eksport/<id>.jpg` (≤ 800×600, krótszy bok ≤ 600, JPEG baseline, bez EXIF/GPS, ≤ 300 KB)
  i `praca/eksport/spis.json`. Wypisuje liczbę i rozmiar (oczekiwane ok. 100–150 MB).
- Jako kontrolę obejrzyj 3–4 losowe pliki z `eksport`: orientacja i kolory.
- Pokaż właścicielowi rozkład na lata i rozmiar.

### Kolaże (opcjonalnie)

```bash
PYTHONIOENCODING=utf-8 python archiwum.py kolaze --proba 12   # próbki do praca/kolaze_proba - obejrzyj
PYTHONIOENCODING=utf-8 python archiwum.py kolaze              # 150 kolaży do praca/kolaze, wysyła je wyslij
```

Kolaże idą tylko na zegary biurkowe - wymagają Zdjęć na telefonie **0.13.0+** (starsza wersja pokazałaby je też
jako wspomnienie na okrągłym zegarku). Opis układów: [README.md](README.md#kolaże).

## 6. Logowanie [TY]

W **swoim** terminalu (PowerShell), bo Claude nie wpisuje hasła, a skrypt pyta interaktywnie:

```powershell
cd C:\TMP\My_GIT\T_rex_3\zdjecia\tools\archiwum
python archiwum.py zaloguj
```

- Wpisz e-mail i hasło **tego samego konta co w Zakupach / Wadze** (hasła nie widać przy wpisywaniu).
- Skrypt wypisze „Zalogowano: … (uid …)”. W `C:\TMP\Takeout\praca\sesja.json` zostaje tylko token odświeżania.
- Napisz Claude'owi, że gotowe.

## 7. Wysyłka (Claude)

```bash
PYTHONIOENCODING=utf-8 python archiwum.py wyslij
```

- Najpierw wysyła zdjęcia, których jeszcze nie ma w bazie (4 naraz, postęp co 50), **na końcu spis**,
  bo telefon nie może zobaczyć wpisów bez zdjęć.
- Ponowne uruchomienie wysyła tylko brakujące. Spis jest układany od nowa, ale **zostają w nim zdjęcia dodane
  z telefonu** (Zdjęcia 0.12.0+ same dokładają najlepsze nowe zdjęcia, wpisy `src: "tel"`). Jeśli takie zdjęcie
  jest też w wyborze z Takeoutu, zostaje wersja z przeglądu. Wypisze się „Spis: N zdjęć, w tym z telefonu K”.
- Spis zapisuje się z warunkiem wersji. Gdy telefon dopisze coś w trakcie, `wyslij` sam odczyta i scali jeszcze raz;
  po 5 nieudanych próbach kończy się komunikatem - wystarczy uruchomić `wyslij` ponownie.
- **Limity** Firestore (plan Spark, projekt dzielony z innymi aplikacjami) mieszczą się z zapasem:
  - ok. 1001 zapisów przy limicie 20 tys./dzień;
  - ok. 150 MB przy limicie 1 GiB;
  - spis ok. 120 KB w jednym dokumencie przy limicie 1 MiB.

## 8. Sprawdzenie na telefonie [TY]

1. Zdjęcia 0.11.0+ → ikona **„Archiwum zdjęć”** (u góry) → zaloguj się tym samym kontem.
2. Ekran pokazuje „Zdjęć w archiwum: …” (ok. 1000). „Sprawdź teraz” odświeża spis.
3. Wspomnienia z archiwum wchodzą przy najbliższym odświeżeniu puli (do 6 h albo przycisk „Odśwież”).
   Na zegary HomeAutomation trafiają 4 zdjęcia z archiwum na godzinę (6–23).

## Później: zmiany w archiwum

- **Zmiana podpisu albo oceny:** popraw `praca/oceny/arkusz_NNN.json` → `wybierz` → `eksport` → `wyslij`.
  Zdjęcia nie są wysyłane drugi raz, zmienia się tylko spis.
- **Usunięcie zdjęcia:** usuń jego kafelek z pliku ocen → `wybierz` → `eksport` → `wyslij --usun-stare`.
  (`--usun-stare` nie rusza zdjęć dodanych z telefonu.)
- **Nowe zdjęcia z telefonu:** nic nie trzeba robić - od Zdjęć 0.12.0 telefon sam dokłada najlepsze
  (ocena Gemini 7+, 3 dni po zrobieniu, przełącznik na ekranie „Archiwum zdjęć”).
- **Więcej albo mniej zdjęć:** `wybierz --ile N` → `eksport` → `wyslij` (przy zmniejszaniu z `--usun-stare`).
- **Nowy Takeout po latach:** nowe ZIP-y → `skanuj` (dopisuje) → `kandydaci --od-nowa` → pełny przegląd od nowa
  (koszt jak za pierwszym razem) → dalej jak wyżej z `wyslij --usun-stare`.

## Kłopoty

| Objaw | Co zrobić |
|---|---|
| `Brak konfiguracji Firebase (...)` | krok 0: uruchom skrypt z głównego checkoutu albo ustaw `ZDJECIA_API_KEY` / `ZDJECIA_PROJECT` |
| `Brak sesji - najpierw: python archiwum.py zaloguj` albo `HTTP 400` przy odświeżaniu tokenu (`TOKEN_EXPIRED`, `INVALID_REFRESH_TOKEN`) | właściciel jeszcze raz robi krok 6 |
| `HTTP 403 ... PERMISSION_DENIED` przy `wyslij` | reguły `archiwum` nieopublikowane (App_storage `firebase/firestore.rules`, publikuje CI po push na main) albo inne konto |
| `Są już oceny przeglądu ...` przy `kandydaci` | to celowa blokada, patrz uwaga w kroku 3 |
| błędy odczytu HEIC | `pip install pillow-heif`, potem `skanuj C:/TMP/Takeout --ponow-bledy` |
| krzaki zamiast polskich liter | `PYTHONIOENCODING=utf-8` |
| telefon pokazuje 0 zdjęć | w aplikacji inne konto niż przy `zaloguj` (spis jest pod `archiwum/{uid}`) |
| pomocnik zapisał zły JSON | `stan` go nie liczy (arkusz „nieoceniony”); usuń plik i oceń arkusz jeszcze raz |

Szczegóły narzędzia i formatu ocen: [README.md](README.md). Testy: `python -m unittest test_archiwum`.
