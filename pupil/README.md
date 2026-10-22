# Pupil – tamagotchi z dinozaurem

Klasyczne tamagotchi na Amazfit T-Rex 3: z jajka wykluwa się dinozaur (gładka, kreskówkowa grafika),
rośnie przez kilka etapów i zmienia formę zależnie od tego, jak o niego dbasz.
Tempo jest luźne – wystarczy zajrzeć 2–3 razy dziennie. Czas płynie także przy
zamkniętej aplikacji.

![Ekran główny](docs/podglad.png)

## Jak grać

Dinozaur stoi na środku tarczy, dookoła jest pierścień ikon akcji. Stuknij ikonę albo
wybierz ją przyciskami **góra/dół** i zatwierdź przyciskiem **wyboru** (`KEY_SELECT`; przycisk skrótu zostaje dla systemu).

| Ikona       | Co robi |
|-------------|---------|
| Jedzenie    | +1 serce głodu, +1 g. Najedzony odmawia. Przy słabej dyscyplinie nastolatek i dorosły czasem kręcą nosem |
| Przekąska   | +1 serce humoru, +2 g (chory nie chce) |
| Światło     | od 20:00 robi się senny – zgaś światło; o 21:30 zasypia sam, o 7:30 wstaje i światło zapala się samo. Zgaszonego w nocy nie da się przypadkiem zapalić. Pora dnia z systemowego zegara (`Time`) |
| Zabawa      | minigry (niżej); wygrana +1 humoru, każda gra −1 g |
| Lekarstwo   | leczy chorobę (1–2 dawki) |
| Sprzątanie  | usuwa kupy |
| Zgań        | gdy marudzi bez powodu: +1 dyscypliny; zganiony bez powodu się smuci |
| Statystyki  | serca, waga, wiek, pokolenie, błędy opieki → kolekcja form |

Stuknięcie w dinozaura – krótka reakcja. Wykrzyknik = czegoś potrzebuje, czaszka = chory,
kupy leżą obok niego.

### Upływ czasu (na jawie; w nocy nic nie spada)

| Etap      | Trwa         | Głód −1 co | Humor −1 co | Kupa co |
|-----------|--------------|-----------|-------------|---------|
| jajo      | 3 min        | –         | –           | –       |
| maluch    | 2 h          | ~1 h      | ~1 h        | ~1 h    |
| dziecko   | 1 dzień      | ~3 h      | ~3 h        | ~3,3 h  |
| nastolatek| 3 dni        | ~4 h      | ~3,5 h      | ~4,3 h  |
| dorosły   | do starości  | ~5 h      | ~4,5 h      | ~5 h    |

Odstępy mają rozrzut ±25%. Dziecko i starsze czasem marudzą bez powodu (ok. raz dziennie, przez 4 h).

**Błąd opieki** liczy się, gdy głód albo humor są na zerze dłużej niż 3 h czuwania
(potem co 12 h), choroba trwa ponad 6 h, śpi przy zapalonym świetle ponad 1 h (raz na noc)
albo marudzenie przeszło bez zganienia. Kupa leżąca ponad 6 h grozi chorobą, nadwaga też.

**Ewolucja** (według błędów w kończącym się etapie):

![Formy](docs/arkusz.png)

- maluch Pisklak → Tupek (0 błędów) albo Gapcio
- dziecko → Rogal (≤1), Kolec (2–3), Łobuz (4+)
- nastolatek → Rex (≤1 i dyscyplina ≥2), Szyjek (≤3), Ptero (≤6), Burczek

**Odejście jest łagodne**: ze starości (13 dni od wyklucia + do 8 dni premii, każde
2 błędy przez całe życie zabierają dzień) dinozaur zostawia jajo; po długim
zaniedbaniu (24 h czuwania w głodzie, smutku albo chorobie) ucieka do lasu. Wtedy
stuknij ekran – zaczynasz od nowego jaja, kolekcja zdobytych form zostaje.

### Minigry

- **Rzut piłką** – machnij nadgarstkiem, siła machnięcia = odległość. Dinozaur łapie,
  jeśli piłka spadnie do 12 m od niego. 2 złapane z 3 = wygrana.
- **Kołysanie do snu** – delikatnie bujaj ręką, aż pasek snu się zapełni (8 s); za mocno
  albo szarpnięcie budzi (3 pobudki albo 40 s = przegrana).
- **Balans na kłodzie** – przechylaj zegarek w bok, żeby dinozaur nie spadł przez 15 s
  (na początku 0,6 s kalibracji – trzymaj poziomo).
- **Lewo czy prawo?** – bez ruchu: zgadnij, w którą stronę spojrzy (strzałki albo
  przyciski góra = lewo, dół = prawo). 3 trafienia z 5 = wygrana.

Strony gier ruchowych trzymają ekran włączony (i przywracają ustawienia przy wyjściu).

### Przypomnienie (niesprawdzone na zegarku)

Przy wyjściu z aplikacji Pupil przewija czas do przodu (do 20 h), znajduje pierwszą
chwilę, kiedy będzie czegoś potrzebował (głód lub humor na zerze, kupa, choroba,
marudzenie, zapalone światło w nocy), i ustawia systemowy alarm `@zos/alarm`
(uprawnienie `device:os.alarm`), który o tej porze otworzy aplikację. Ekran główny
rozpoznaje to po zapisanej godzinie, wibruje i pokazuje „Pupil cię woła!”. Przypomnienia
padają tylko między 7:45 a 22:00; jeśli już czegoś potrzebuje, kolejne za 2 h.

## Jak to działa

- `utils/pet.js` – cały stan i logika (czysty JS). Stan z czasem `t` leży w LocalStorage
  (`pupil_state`); po otwarciu `advance()` przewija czas minuta po minucie, z losowością
  z generatora zapisanego w stanie – wynik jest deterministyczny, także przy przewijaniu
  kawałkami.
- `utils/games.js` – logika minigier (detektor machnięcia, kołysania, fizyka balansu).
- `utils/store.js` – zapis/odczyt; każda strona przewija czas i zapisuje, strona główna
  co sekundę sprawdza, czy stan się zmienił.
- `utils/reminder.js` – alarm z przypomnieniem (funkcja `nextReminder` w `pet.js`).
- `tools/smoke.mjs` – smoke test prawdziwych bundli zeusa w Node `vm` (atrapy `@zos/*`,
  sztuczny zegar); bundle przechwytuje `tools/capture-hook.cjs` (opis w nagłówku smoke.mjs).
- `tools/gen_assets.py` – grafika: postacie w `tools/forms.py` z prostych kształtów
  (elipsy, wielokąty, zwężające się „rurki”, `tools/draw.py`) rysowanych w 8× powiększeniu
  z obrysem jak naklejka; miny i klatki (oddech, radość, smutek, sen, jedzenie, lustro)
  dorysowuje generator. Ikony w `tools/icons.py`. Powstają też `utils/geometry.js`,
  arkusz `docs/arkusz.png` i makieta `docs/podglad.png`.

```bash
npm install
npm test                     # testy logiki w Node
python tools/gen_assets.py   # po zmianie grafiki
zeus preview                 # instalacja na zegarku
```

## Niesprawdzone na zegarku

- progi ruchu w minigrach (`THROW`, `ROCK`, `BALANCE` w `utils/games.js`) to szacunki;
- który fizyczny przycisk T-Rex 3 daje `KEY_SELECT` (zatwierdzanie akcji przyciskiem);
- kierunek przechyłu w balansie przyjęty jak w Labiryncie (tam sprawdzony);
- przypomnienie przez `@zos/alarm` (czy alarm otwiera aplikację i włącza ekran).
