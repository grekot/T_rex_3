# Trening

Aplikacja na telefon (Android), która prowadzi przez 12-tygodniowy plan treningowy:
zdrowy odcinek lędźwiowy i redukcja wagi. Okienko kalendarza na każdy dzień, prowadzenie
treningu krok po kroku, ocena bólu po treningu, przypomnienia.

| Folder | Co to jest |
|---|---|
| [phone](phone/README.md) | aplikacja Flutter `pl.grekot.trening` |

## Zasady

- **Dane zostają na telefonie.** Bez konta, bez Firebase, bez uprawnienia `INTERNET`.
  Kopia zapasowa tylko przez ręczny eksport (`allowBackup=false`).
- **Repozytorium jest publiczne.** Do gita trafia tylko ogólna treść planu
  (`phone/assets/plan/plan.json`). Dane osobowe i zdrowotne (waga, objawy, wyniki) wpisuje się
  w aplikacji. Test `plan_test.dart` pilnuje, żeby w planie nie było danych osobowych.
- Wagę prowadzi aplikacja [Waga](../waga/README.md). Trening odczyta ją z Health Connect
  (wersja 1.1).
- Na zegarek trafiają zwykłe powiadomienia telefonu przez aplikację Zepp. Osobnej aplikacji
  na zegarek nie ma.

## Treść jako dane

| Plik | Co zawiera | Skąd |
|---|---|---|
| `phone/assets/plan/plan.json` | ćwiczenia z dawkami, sesje, etapy (harmonogram, zadania, spacer, kryteria przejścia), test kierunkowy, teksty bezpieczeństwa | ręcznie, z planu treningowego |
| `phone/assets/plan/atlas.json` | technika ćwiczeń: sekcje opisu, rysunki, uwagi do rysunków | generowany z atlasu ćwiczeń |
| `phone/assets/plan/img/*.jpg` | 29 rysunków z atlasu (Gemini) | kopiowane z atlasu |

- Identyfikator ćwiczenia to kotwica atlasu (`bird-dog`). Wariant rysunku idzie po ukośniku
  (`deska-boczna/kolana`).
- Atlas (`cwiczenia/atlas_cwiczen.md` + `img/`) żyje poza repozytorium, w folderze planu
  treningowego. Po jego zmianie, w `trening/phone`:

  ```bash
  dart run tool/atlas_do_json.dart C:\TMP\My_GIT\Trening\cwiczenia
  ```

- Zmiana treści planu nie wymaga zmian w kodzie: poprawiasz `plan.json`, a testy
  (`plan_test.dart`) sprawdzają format, odwołania do atlasu i rysunków, harmonogramy i flagi.
  Nieznane pole w JSON-ie to błąd (literówka nie przejdzie po cichu).
- Opis formatu: komentarze w `phone/lib/plan/model.dart` i `atlas.dart`.

## Wydanie

Tag `trening-vX.Y.Z` uruchamia [release-trening.yml](../.github/workflows/release-trening.yml):
wspólny workflow Sklepu rodzinnego buduje i podpisuje `trening.apk` i dopisuje wersję do
biblioteki sklepu. Wersja pochodzi z tagu, `pubspec.yaml` zostaje na `1.0.0+1`.

```bash
git tag trening-v0.0.1 && git push origin trening-v0.0.1
```

## Stan

| Wersja | Zakres |
|---|---|
| 0.0.1 | szkielet, ikona, sprawdzenie ścieżki wydań |
| (M1) | `plan.json` etapu 1, atlas jako dane, silnik: kalendarz z etapami według kryteriów, flagi ćwiczeń; bez zmian w interfejsie |
| 0.1 | etap 1: kalendarz, rutyna 15 min, test kierunkowy, ocena bólu, przypomnienia |
| 0.2 | etapy 2–3: sesje A/B/C, kryteria przejścia, dziennik tygodniowy |
| 1.0 | eksport danych, głos (opcja) |
| 1.1 | Health Connect: kroki z Zepp, waga z Wagi |
