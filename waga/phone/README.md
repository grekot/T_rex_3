# Waga – aplikacja na telefon

Flutter (Android), pakiet `pl.grekot.waga`. Czyta pomiary z Firestore `waga/{uid}` (zapisuje je
zegarek przez Side Service, format w [../SYNC.md](../SYNC.md)) i kalorie, kroki oraz treningi
z Health Connect (zapisuje je tam aplikacja Zepp).

## Ekrany

- **Wykres** – ostatni pomiar, trend (średnia wykładnicza 10%, jak w „The Hacker's Diet”), tempo
  w kg/tydzień z 4 tygodni, średnia 7 dni vs poprzedni tydzień, cel z prognozą daty. Wykres wagi
  (kropki = pomiary, linia = trend, przerywana = cel) dla 30 / 90 dni / roku / całości, pod nim
  słupki spalonych kalorii (do 120 dni).
- **Pomiary** – lista od najnowszego z różnicą do poprzedniego i kaloriami tego dnia; stuknięcie
  = poprawka (−/+ 0,1 kg albo wpisanie) lub usunięcie. Przycisk **Pomiar** dodaje wpis (także
  z innym dniem).
- **Aktywność** – średnio z 7 dni: kalorie spalone i aktywne, kroki; dzień po dniu z wagą; treningi
  (typ, czas, dystans, kalorie).
- Menu: cel wagi, wylogowanie. Konto to samo co w Zakupach / Powrocie / Na szczycie (`wspolne`).

## Konfiguracja (raz)

1. Konsola Firebase, projekt `zakupy-8ec54` → Ustawienia projektu → Dodaj aplikację → Android,
   pakiet `pl.grekot.waga` (bez SHA – logowanie e-mailem). Pobierz `google-services.json`
   do `android/app/`.
2. `node tools/configure.mjs` → `lib/firebase_options.dart` (oba pliki poza gitem).
3. Opublikuj reguły z `App_storage/firebase/firestore.rules` (blok `waga`).
4. W aplikacji Zepp: Profil → Połącz z innymi aplikacjami → Health Connect – zgoda na kalorie,
   kroki i treningi.

## Budowanie

`build_apk.cmd` (z Eksploratora – w piaskownicy Claude Gradle nie startuje) →
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Testy: `flutter test`.

Health Connect wymaga Androida 8+ (minSdk 26); bez zgody na historię daje dane z ostatnich 30 dni.
