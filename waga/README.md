# Waga

Codzienne poranne ważenie na zegarku + (w planie) aplikacja na telefon z wykresem,
kaloriami i aktywnościami z Health Connect.

| Folder   | Co to                                                        | Stan            |
| -------- | ------------------------------------------------------------ | --------------- |
| `watch/` | Aplikacja Zepp OS na Amazfit T-Rex 3 (appId 1087168), offline | etap 1 – gotowa |
| `phone/` | Aplikacja Flutter: wykres wagi, trend, kalorie, aktywności   | etap 3–4        |

## Zegarek (`watch/`)

![Ekran główny](watch/docs/home.png)

- Ekran startuje od **ostatniego pomiaru** – zwykle wystarczy kilka stuknięć **−** / **+** (0,1 kg).
- **Przytrzymanie** −/+ powtarza krok coraz szybciej. Przyciski zegarka **góra/dół** też zmieniają wagę.
- **ZAPISZ** zapisuje pomiar z dziś (jeden na dzień; ponowny zapis tego samego dnia – przycisk
  **POPRAW** – nadpisuje). Po zapisie liczba i napis **ZAPISANO** są zielone.
- Pod liczbą: zmiana od poprzedniego pomiaru (zielona = mniej, czerwona = więcej) i średnia z 7 dni.
- Wykres 14 dni (dziś na pomarańczowo, kreska = dzień bez pomiaru). **Stuknięcie w wykres** otwiera
  historię: zmiana w 7 i 30 dniach oraz lista pomiarów (do 60).
- Dane w pliku `waga.json` (+ `waga.bak`) w pamięci aplikacji (`@zos/fs`), w dziesiątych częściach kg.

Instalacja:

```
cd waga/watch
zeus preview
```

(wybierz „Amazfit T-Rex 3”, potem w Zepp: Profil → urządzenie → Ogólne → Tryb dewelopera → „+” → Skanuj).

Testy logiki: `npm test` w `waga/watch`. Ikona i podgląd: `python tools/gen_assets.py`.

## Plan dalej

2. Synchronizacja zegarek → Firestore `waga/{uid}/pomiary/{RRRR-MM-DD}` przez Side Service
   (logowanie w ustawieniach Zepp, to samo konto co Zakupy/Powrót).
3. Telefon: wykres wagi z trendem, zmiana tygodniowa, cel i prognoza, edycja pomiarów.
4. Telefon: kalorie, kroki i treningi z Health Connect (wysyła je tam aplikacja Zepp).
5. Przypomnienie rano (`@zos/alarm`), eksport CSV, wydanie w sklepie.
