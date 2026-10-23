# Groot – tamagotchi z drzewkiem

Tamagotchi na Amazfit T-Rex 3: z patyczka w doniczce wyrasta stworek-drzewko w stylu
Groota. Rośnie przez kilka etapów i zmienia formę zależnie od tego, jak o niego dbasz.
To ta sama gra co [Pupil](../pupil/README.md) (wersja 1.3.0, z wszystkimi minigrami),
tylko z nowym bohaterem i nową grafiką. Tempo jest luźne – wystarczy zajrzeć 2–3 razy
dziennie. Czas płynie także przy zamkniętej aplikacji.

Grafika to realistyczne rendery z Grok Imagine (fan-art) – aplikacja jest tylko do
prywatnego użytku na własnym zegarku (`zeus preview`), nie do sklepu Zepp.

![Ekran główny](docs/podglad.png)

## Jak grać

Drzewko stoi na środku tarczy, dookoła jest pierścień ikon akcji. Stuknij ikonę albo
wybierz ją przyciskami **góra/dół** i zatwierdź przyciskiem **wyboru** (`KEY_SELECT`).

| Ikona       | Co robi |
|-------------|---------|
| Podlewanie (konewka) | +1 kropla wody, +1 g. Podlany odmawia. Przy słabej dyscyplinie nastolatek i dorosły czasem kręcą nosem |
| Nawóz (worek) | +1 serce humoru, +2 g (z mszycami nie chce) |
| Noc (księżyc) | od 20:00 robi się senny – zgaś światło; o 21:30 zasypia sam, o 7:30 wstaje |
| Zabawa      | minigry (jak w Pupilu); wygrana +1 humoru, każda gra −1 g |
| Oprysk      | usuwa mszyce (1–2 opryski) |
| Grabie      | zgrabia opadłe liście |
| Zgań        | gdy marudzi bez powodu: +1 dyscypliny; zganiony bez powodu się smuci |
| Statystyki  | woda, humor, dyscyplina, waga, wiek, pokolenie, błędy opieki → zmiana imienia, kolekcja form |

Gdy nic mu nie trzeba, drzewko samo się czymś zajmuje: tańczy, wyczarowuje kwiatek na
dłoni, gra na konsoli albo wypuszcza świecące zarodniki (`utils/idle.js`).

Czasy, błędy opieki, ewolucja, odejście, przypomnienia i wyzwania (prośby o zabawę,
gra o premię po akcji, poranna rozgrzewka) działają jak w Pupilu – szczegóły w
[README Pupila](../pupil/README.md). Pod spodem „kupa” to opadłe liście, a „choroba” to mszyce.

**Ewolucja** (według błędów w kończącym się etapie):

![Formy](docs/arkusz.png)

Przy nowym patyczku wybierasz jedną z trzech doniczek (linię) i imię z listy.
Doniczka to tylko krótki początek, jak w filmach: patyczek na start i maluch (tańczący
patyczek z końca 1. części). Od dziecka (Baby Groot z 2. części) chodzi już sam.

| Doniczka      | maluch  | dziecko (0 błędów) | nastolatek (≤2) | dorosły: wzorowo (≤1 i dyscyplina ≥2) | dorosły: dobrze (≤4) |
|---------------|---------|--------------------|-----------------|---------------------------------------|----------------------|
| gliniana – klasyczny | Kiełek | Grocik | Nastolatek | Groot | Mszak |
| różowa – kwitnący | Pąk | Kwiatuś | Wisienka | Sakura | Jabłoń |
| pomarańczowa – jesienny | Żołądź | Rudzik | Klonik | Klon | Dębisz |

Zaniedbane formy są wspólne: Suchar (maluch z błędami), Kolczak (dziecko z 3+ błędami),
Próchniak (nastolatek z 5+ błędami albo Kolczak z 2+). Razem 18 form w kolekcji.

**Odejście jest łagodne**: ze starości drzewko zostawia patyczek; po długim zaniedbaniu
odchodzi do lasu. Kolekcja zdobytych form zostaje.

Minigry są te same co w Pupilu (22 gry, logika w `utils/games.js`, `utils/moves.js`,
`utils/walks.js`); zmienione są tylko nazwy i rekwizyty: Wykopywanie żołędzi, Labirynt
żołędzia (do doniczki), Szukanie wody, Celowanie opryskiem.

## Jak to działa

- `utils/pet.js` – stan i logika (jak w Pupilu: formy, linie `classic`/`bloom`/`autumn`,
  teksty). Stan leży w pliku `groot_state.json` w `/data` aplikacji (+ kopia `.bak`), osobno od Pupila.
- Grafika z Grok Imagine według `../groot-art/prompts.md`. Arkusze leżą w `../groot-art/`,
  poza folderem aplikacji, bo `zeus build` pakuje cały folder do `.ip-package`:
  - `<forma>_sheet.jpg` – 2×2: spokój, radość, smutek, sen,
  - `<forma>_act_sheet.jpg` – 2×2 zajęcia: taniec, kwiatek, konsola, świetliki,
  - `pots_sheet.jpg` – trzy doniczki z patyczkiem (start),
  - `props_sheet.jpg` – 16 rekwizytów gier, `icons_sheet.jpg` – 8 ikon akcji.
- `tools/grab_art.py` – warianty z Pobranych (`grootv_<nazwa>_<k>.jpg`): `--show` składa je
  w `../groot-art/_warianty.png`, `<k>` bierze wybrany; `--clip` – obraz ze schowka.
- `tools/import_art.py` wycina tło (także zamknięte białe dziury między rękami a tułowiem),
  wyrównuje miny wspólną skalą i robi klatki; `tools/preview_art.py` – podgląd.
- `tools/gen_assets.py` – całość: drobiazgi (strzałki, serca, krążki pierścienia), import
  wszystkich arkuszy, `utils/geometry.js`, `docs/arkusz.png`, `docs/podglad.png`, ikona aplikacji.
- `tools/smoke.mjs` – smoke test prawdziwych bundli zeusa w Node `vm` (bundle przechwytuje
  `tools/capture-hook.cjs`).

```bash
npm install
npm test                     # testy logiki w Node
python tools/gen_assets.py   # po zmianie grafiki (importuje arkusze z ../groot-art)
zeus preview                 # instalacja na zegarku
```

## Niesprawdzone na zegarku

Wszystko, co niesprawdzone w Pupilu (progi ruchu w minigrach, `KEY_SELECT`, alarm
przypomnienia), a do tego wygląd realistycznych renderów w 168 px na ekranie zegarka.
