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
- **Repozytorium jest publiczne.** Do gita trafia tylko ogólna treść planu (od wersji 0.1:
  `plan/plan.json`). Dane osobowe i zdrowotne (waga, objawy, wyniki) wpisuje się w aplikacji.
- Wagę prowadzi aplikacja [Waga](../waga/README.md). Trening odczyta ją z Health Connect
  (wersja 1.1).
- Na zegarek trafiają zwykłe powiadomienia telefonu przez aplikację Zepp. Osobnej aplikacji
  na zegarek nie ma.

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
| 0.1 | etap 1: kalendarz, rutyna 15 min, test kierunkowy, ocena bólu, przypomnienia |
| 0.2 | etapy 2–3: sesje A/B/C, kryteria przejścia, dziennik tygodniowy |
| 1.0 | eksport danych, głos (opcja) |
| 1.1 | Health Connect: kroki z Zepp, waga z Wagi |
