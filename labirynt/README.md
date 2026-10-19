# Labirynt – gra na Amazfit T-Rex 3

Drewniany labirynt z kulką: przechylasz zegarek, kulka toczy się w stronę
pochylenia, a Ty prowadzisz ją do zielonej mety, omijając dziury.

| Gra                                  | Menu                                       |
|--------------------------------------|--------------------------------------------|
| ![Podgląd gry](docs/podglad.png)     | ![Podgląd menu](docs/podglad-menu.png)     |

## Jak grać

| Co                                   | Działanie                                                   |
|--------------------------------------|-------------------------------------------------------------|
| przechylenie zegarka                 | kulka toczy się w stronę pochylenia                         |
| stuknięcie w ekran                   | **wyzeruj pochylenie** – tak trzymany zegarek to od teraz „poziomo” |
| przyciski góra/dół                   | to samo co stuknięcie                                       |
| dziura                               | kulka wpada, zegarek wibruje, kulka wraca na start          |
| zielona meta                         | koniec poziomu, po 1,5 s następny                           |
| przycisk wstecz / przesunięcie w prawo | powrót do menu                                            |

Na początku każdego poziomu zegarek przez pół sekundy zapamiętuje, jak go trzymasz –
to jest „poziomo”. Nie trzeba więc trzymać ręki płasko; wystarczy patrzeć na ekran
i trzymać nadgarstek nieruchomo. Uderzenie kulki w ścianę czuć jako lekką wibrację.

W trakcie gry ekran nie gaśnie ani po czasie, ani po opuszczeniu nadgarstka
(wraca do normy po wyjściu z gry).

## Poziomy

Każdy poziom ma zawsze ten sam labirynt (numer poziomu jest ziarnem losowania),
więc po wpadnięciu do dziury albo wyjściu z gry wracasz do tego samego układu.
Plansza rośnie co dwa poziomy, a dziur przybywa:

| Poziom | Plansza | Dziury |
|--------|---------|--------|
| 1–2    | 5 × 5   | 0–1    |
| 3–4    | 6 × 6   | 1–2    |
| 5–6    | 7 × 7   | 2–3    |
| 7–8    | 8 × 8   | 3–4    |
| 9+     | 9 × 9   | 4–9    |

Meta jest zawsze na polu najdalszym od startu (po korytarzach). Dziury leżą tylko
poza właściwą drogą – najchętniej w odnogach, w które kulka łatwo wjedzie rozpędzona.
Gra zapamiętuje poziom, na którym skończyłeś, najwyższy ukończony poziom i najlepszy
czas każdego poziomu.

## Ekran „Czujnik”

Kulka toczy się swobodnie w kole, a u góry widać surowe odczyty akcelerometru
(x, y, z w cm/s²). Jeśli kulka ucieka w złą stronę, przyciski **lewo–prawo**
i **góra–dół** odwracają osie – ustawienie działa też w grze.

Dokumentacja Zepp OS nie mówi, czy leżący zegarek pokazuje z = +980 czy −980, więc
gra rozpoznaje to sama po znaku osi z podczas kalibracji. Odwracanie osi jest zapasem
na wypadek, gdyby osie x/y na zegarku były skierowane inaczej, niż mówi dokumentacja.

## Jak to jest zbudowane

| Plik                                    | Zawartość                                              |
|-----------------------------------------|--------------------------------------------------------|
| [utils/maze.js](utils/maze.js)          | labirynt bez UI: generowanie (wędrówka z cofaniem), meta, dziury, ściany jako prostokąty |
| [utils/physics.js](utils/physics.js)    | fizyka kulki: pochylenie → przyspieszenie, tarcie, odbicia od ścian, kalibracja |
| [utils/device.js](utils/device.js)      | akcelerometr, utrzymanie włączonego ekranu, wibracje   |
| [utils/geometry.js](utils/geometry.js)  | rozmiary plansz i położenie napisów – **generowany**   |
| [utils/store.js](utils/store.js)        | zapis poziomu, rekordów i odwrócenia osi               |
| [page/gt/home](page/gt/home)            | menu                                                   |
| [page/gt/game](page/gt/game)            | gra (25 klatek na sekundę)                              |
| [page/gt/sensor](page/gt/sensor)        | test czujnika                                          |
| [tools/gen_assets.py](tools/gen_assets.py) | rysuje kulki, dziury, mety, ikonę, podglądy i `utils/geometry.js` |

Po zmianie rozmiarów plansz albo wyglądu uruchom generator (Python + Pillow + Node.js):

```bash
python tools/gen_assets.py
```

Testy (wymagają tylko Node.js, nie zegarka):

```bash
node test/maze.test.mjs
```

Sprawdzają m.in. 40 pierwszych poziomów (labirynt bez pętli, każde pole osiągalne,
dziury poza drogą, przejścia wolne dla kulki) i puszczają autopilota, który
przechylając wirtualny zegarek przejeżdża poziomy 1–20 prawdziwą fizyką – bez
wjechania w ścianę i bez wpadnięcia do dziury.

## Budowanie i instalacja

W tym folderze:

```bash
zeus preview
```

Potem w aplikacji Zepp: **Urządzenie → Ogólne → Tryb dewelopera → „+” → Skanuj**.
