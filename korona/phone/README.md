# Na szczycie – telefon

Aplikacja na Androida (Flutter), która pokazuje szczyty zdobyte z aplikacją
[Na szczycie na zegarku](../README.md): postęp każdej listy, mapę i historię wejść. Loguje się
tym samym kontem co Zakupy i Powrót (pakiet [`wspolne`](../../wspolne)). Dane zapisuje
zegarek – telefon tylko je czyta (kontrakt: [`../SYNC.md`](../SYNC.md)).

## Ekrany

- **Postęp** – karta każdej grupy z `peaks.json` (np. Korona Gór Polski „12 / 28” z paskiem
  i procentem, medal przy zdobytej całej liście, „+ 2 warianty”), karta **Własne szczyty**
  (dodane na zegarku przyciskiem „Dodaj szczyt tutaj”) i kiedy zegarek ostatnio wysłał dane.
- **Lista grupy** – szczyty od najwyższego; zdobyte pogrubione z zieloną kropką, datą i ikoną
  (satelita = zaliczony na szczycie po GPS, kalendarz = dodany ręcznie), niezdobyte szare.
  Filtr *Wszystkie / Zdobyte / Zostało*, sortowanie (wysokość, nazwa, data zdobycia),
  wyszukiwanie bez polskich znaków przy większych grupach („sniezka” → Śnieżka).
  Warianty KGP osobno na dole – nie liczą się do 28. Ikona mapy pokazuje tylko tę grupę.
- **Szczegóły szczytu** – wysokość, pasmo, grupy, data i sposób zdobycia, uwagi (wierzchołek
  graniczny, wariant którego szczytu), mała mapa, współrzędne i linki: szlaki w Mapy.com,
  dojazd w Google Maps, węzeł w OpenStreetMap.
- **Mapa** – wszystkie szczyty: zdobyte zielone, niezdobyte białe z szarą obwódką, własne
  niebieskie; nazwy po przybliżeniu. Filtr grup u góry, legenda z liczbami, przycisk
  podkładu (topograficzny / OpenStreetMap). Stuknięcie w szczyt → karta z datą → szczegóły.
- **Historia** – liczba zdobytych szczytów, w tym roku, najwyższy, ile po GPS, pierwsze
  wejście; słupki „zdobycia w latach”; wszystkie wejścia od najnowszego, pogrupowane po latach.
- **Przykładowe dane** – w menu ⋮ (albo przycisk na ekranie „Brak konfiguracji”): zmyślone
  zdobycia, żeby obejrzeć aplikację bez zegarka. Nic nie zapisuje.

### Dlaczego flutter_map, a nie Google Maps

Mapa to [flutter_map](https://pub.dev/packages/flutter_map) z kafelkami **OpenTopoMap**
(domyślnie – poziomice, szlaki, cieniowanie; w górach czytelniejsze) i **OpenStreetMap**.
Nie trzeba klucza API ani konfiguracji w Google Cloud, szczyty i tak pochodzą z OSM (te same
punkty co na mapie), a przy kilkuset znacznikach wystarczy zwykła warstwa widżetów.
Kafelki pobierają się z internetu (flutter_map trzyma je w pamięci podręcznej); obie usługi
są darmowe przy prywatnym użyciu – aplikacja wysyła swój pakiet jako User-Agent i pokazuje
atrybucję, czego wymagają ich zasady.

## Lista szczytów

`assets/peaks.json` to kopia wspólnego [`../data/peaks.json`](../data/peaks.json) (ten sam
plik zasila zegarek). Po każdej zmianie listy – np. nowe grupy Beskid Wyspowy, Sądecki,
Gorce, Tatry – skopiuj ją i zbuduj APK ponownie:

```bash
node tools/copy_peaks.mjs
```

Skrypt sprawdza plik z kontraktem (unikalne id, znane grupy, `variantOf`) i wypisuje grupy
z liczbą szczytów. Aplikacja nie zakłada stałej liczby grup ani szczytów: każda grupa z
pliku dostaje kartę, filtr na mapie i własną listę. `flutter test` przypomina, gdy kopia
jest nieaktualna.

## Uruchomienie krok po kroku

1. **Reguły Firestore** – blok `korona/{uid}` (czyta i pisze tylko właściciel) jest w
   `App_storage/firebase/firestore.rules` (gałąź `korona-reguly` w repo App_storage). Po
   scaleniu opublikuj ten plik: konsola Firebase → Firestore Database → Rules → wklej →
   Publish. Bez tego aplikacja pokaże „Brak dostępu do zdobyć”.
2. **Aplikacja Android w Firebase** – w projekcie `zakupy-8ec54`: Project settings → Your apps
   → **Add app → Android**, pakiet **`pl.grekot.naszczycie`**, nazwa „Na szczycie”. Pobierz
   `google-services.json` i zapisz w `android/app/`.
3. **Konfiguracja** (w tym folderze):

   ```bash
   node tools/configure.mjs
   ```

   Bez pliku skrypt zapisze zaślepkę `lib/firebase_options.dart` – aplikacja się zbuduje i
   pokaże „Brak konfiguracji” z przyciskiem przykładowych danych.
4. **Instalacja** – ze **Sklepu rodzinnego** (niżej) albo ręcznie: [`build_apk.cmd`](build_apk.cmd)
   (uruchom z Eksploratora albo z własnego okna cmd), wynik:
   `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`. Lokalny `android/key.properties`
   (kopia z Powrotu, poza gitem) podpisuje go wspólnym kluczem sklepu, więc sklep potem go
   zaktualizuje.
5. **Logowanie** – tym samym kontem co Zakupy / Powrót; na zegarku w aplikacji Zepp
   (Urządzenie → Na szczycie → ustawienia), gdy synchronizacja zegarka będzie gotowa.

## Wydanie do Sklepu rodzinnego

Tag `naszczycie-vX.Y.Z` uruchamia [release-naszczycie.yml](../../.github/workflows/release-naszczycie.yml)
(wspólny workflow z `grekot/App_storage`): APK arm64 podpisany wspólnym kluczem trafia do GitHub
Release jako `naszczycie.apk`, a wersja do biblioteki sklepu. Konfigurację Firebase CI odtwarza z
sekretu repozytorium **`FIREBASE_OPTIONS_NASZCZYCIE_B64`** (base64 pliku `lib/firebase_options.dart`
po `node tools/configure.mjs`; bez niego wydanie ma zaślepkę i pokazuje tylko przykładowe dane):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\TMP\My_GIT\T_rex_3\korona\phone\lib\firebase_options.dart")) | Set-Clipboard
```

Do grup przypisuje administrator (w folderze `App_storage`):

```bash
sklep przypisz naszczycie --grupa Rodzina
```

## Dla programisty

```
lib/main.dart              start, Firebase, logowanie (wspolne), ekran braku konfiguracji
lib/data/peaks.dart        PeakCatalog / PeakGroup / Peak z assets/peaks.json
lib/data/climbs.dart       ClimbsDoc z dokumentu korona/{uid} (odporny na złe wpisy)
lib/data/stats.dart        postęp grup, oś czasu, zdobycia w latach, podsumowanie
lib/data/demo.dart         przykładowe zdobycia (stałe ziarno)
lib/data/repository.dart   ClimbsRepository extends AccountRepository: watchClimbs()
lib/ui/home_screen.dart    zakładki Postęp / Mapa / Historia, menu, błędy
lib/ui/groups_tab.dart     karty grup, własne szczyty
lib/ui/group_screen.dart   lista grupy: filtr, sortowanie, wyszukiwanie, warianty
lib/ui/peak_screen.dart    szczegóły szczytu (z listy albo własnego)
lib/ui/peaks_map.dart      mapa flutter_map, podkłady, znaczniki
lib/ui/history_tab.dart    statystyki i historia
tools/copy_peaks.mjs       ../data/peaks.json → assets/ (ze sprawdzeniem)
tools/configure.mjs        google-services.json → lib/firebase_options.dart
```

```bash
flutter analyze
```

```bash
flutter test
```

Wersja 1 tylko czyta. Pomysły na później: edycja dat z telefonu (wymaga zmiany kontraktu –
dziś zegarek nadpisuje cały dokument), „najbliższe niezdobyte” od mojej pozycji,
udostępnianie postępu znajomym.
