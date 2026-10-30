# HomeAutomation – aplikacja na telefon

Aplikacja Flutter dla urządzeń domowych: termostat SmartTermostatOLED (ESP32-S3), a w kolejnych fazach światła
(`switch` / `dimmer`) i hub do urządzeń innych firm. Zastępuje ESP RainMaker i aplikację „ESP BLE Provisioning”.
Format danych opisuje kontrakt v2 [`docs/API.md`](https://github.com/grekot/SmartTermostatOLED/blob/main/docs/API.md)
w repozytorium firmware `grekot/SmartTermostatOLED` (lokalnie `C:\TMP\My_GIT\Termostat\SmartTermostatOLED\docs\API.md`).
To on jest źródłem prawdy.

- **Domy i domownicy** (pkt 12): właściciel zakłada dom, domownicy dołączają kodem zaproszenia; uprawnienia
  `view` / `control` / `config` na każde urządzenie.
- **Pulpity** (pkt 13): prywatne i wspólne, widżety z punktów danych `describe` (pkt 14), sceny.
- **Urządzenia**: kafelki ze stanem pogrupowane w pokoje, szczegóły i ustawienia techniczne.
- **W domu**: HTTP i WebSocket `/ws` bezpośrednio do urządzenia, wykrywanie przez mDNS `_homeauto._tcp` (TXT `type`).
- **Spoza domu**: Firebase Realtime Database w projekcie `zakupy-8ec54`, logowanie wspólnym kontem (pakiet `wspolne`).
- **Nowe urządzenie przez Bluetooth**: konfiguracja WiFi i parowanie w jednym kroku (kontrakt pkt 9).
- **Powiadomienia** o awarii czujnika i braku kontaktu: WorkManager co ~15 min.
- Pakiet Androida `pl.grekot.homeautomation`. UI jest po polsku. Podstawową platformą jest Android,
  a kod buduje się też na iOS (powiadomienia w tle na razie tylko na Androidzie).

## Wymagania

- Flutter 3.41+ (Dart 3.11), Android SDK (compileSdk 36), Node.js (do `tools/configure.mjs`).
- Pakiet [`wspolne`](../../wspolne/README.md) z tego repozytorium (`pubspec.yaml`: `path: ../../wspolne`).
- Telefon z Androidem 7+ i Bluetooth LE. Na iOS potrzebny jest Mac z Xcode.

## Uruchomienie

```bash
cd homeautomation/phone
node tools/configure.mjs    # lib/firebase_options.dart (bez google-services.json - zaślepka)
flutter pub get
flutter run                 # telefon podłączony przez USB/ADB
```

`lib/firebase_options.dart` i `android/app/google-services.json` są w `.gitignore`, więc po sklonowaniu
repozytorium trzeba najpierw uruchomić `node tools/configure.mjs`.

- **Bez konfiguracji Firebase** (zaślepka) aplikacja startuje od razu ekranem głównym i działa tylko w sieci domowej.
  Jest wtedy jeden „dom w telefonie”: pokoje i pulpity są zapisane lokalnie, bez domowników.
- **Z konfiguracją** najpierw pokazuje logowanie wspólnym kontem. Konto bez domu widzi ekran „Załóż dom /
  Dołącz kodem”; pokoje, pulpity i uprawnienia są w chmurze.

## Dom, domownicy i uprawnienia (pkt 12)

- **Dom** `homes/{homeId}` `{name, ownerUid}`. Pierwsze uruchomienie z kontem: **Załóż dom** (zostajesz właścicielem)
  albo **Dołącz do domu** kodem. Menu konta (ikona osoby w pasku): przełączanie domów, zmiana nazwy (właściciel),
  nowy dom / dołączenie, powiadomienia, wylogowanie. Wybrany dom telefon pamięta.
- **Wyjście z domu** (domownik): menu konta → „Opuść ten dom” (usuwa swój `access` i `members`).
- **Zakładka „Domownicy”** (tylko właściciel):
  - lista z `members`; dotknięcie domownika → poziom domyślny `_all` (także dla nowych urządzeń) i wyjątki dla
    urządzeń (`view` / `control` / `config`, a przy ogólnym poziomie także „brak dostępu” = `"none"`, które odbiera
    jedno urządzenie), **Zapisz** → `homes/{h}/access/{uid}`; **Usuń z domu**;
  - **Zaproś**: poziomy dla nowej osoby → kod 8 znaków (`invites/{kod}` `{"homeId","createdBy","expiresAt","level"}`,
    ważny 24 h) do skopiowania. Zaproszenie niesie tylko poziom domyślny; wyjątki dla urządzeń aplikacja właściciela
    trzyma w `users/{uid}/inviteAccess/{h}/{kod}` i dopisuje do `access/{uid}`, gdy zobaczy nowego domownika
    (podpowiedź: niższy poziom domyślny, wyjątki w górę).
    Dołączający zapisuje **jedną operacją** (update wielu ścieżek) `members/{uid}` z kodem, `usedInvites/{kod}` i
    `access/{uid}/_all` = `level` (liść; przy `none` nic), potem `users/{uid}/homes/{h}`.
    Kod jest jednorazowy; zaproszenie kasuje właściciel.
- **Poziomy w aplikacji**: `view` - tylko podgląd (kontrolki wyszarzone, pasek „Masz tylko podgląd”); `control` -
  sterowanie (`power`, `target`, `mode`, `on`, `level`, `toggle`); `config` - także harmonogram, ustawienia, nazwa,
  WiFi, chmura, OTA, telefony. Aplikacja tylko ukrywa; **urządzenie pilnuje samo**, a jego odmowę
  (403 `forbidden`, `errors.<pole> = "forbidden"`, `lastCommand.errors`) aplikacja pokazuje jako „brak uprawnień”.
  Przez chmurę poziom bierze z `access` domu, w domu z poziomu tokenu telefonu (`GET /api/me`).
- Każde polecenie do chmury ma `"by": uid` (`homes/{h}/devices/{id}/commands`).

## Pulpity (pkt 13)

- Prywatne `users/{uid}/dashboards/{homeId}/{id}` i wspólne `homes/{homeId}/dashboards/{id}` (zmienia tylko
  właściciel). Wybór pulpitu z tytułu paska, menu: nowy (wspólny - właściciel), zmiana nazwy, **Otwieraj na starcie**
  (`users/{uid}/prefs/{homeId}.defaultDashboard`), **Kopiuj do moich** (wspólny → prywatny), usunięcie.
  Ostatnia lista pulpitów jest w telefonie, więc bez internetu pulpit od razu się pokazuje.
- Pusty dom: **Utwórz z moich urządzeń** (termostaty jako widżet „termostat”, światła jako przełączniki) albo pusty pulpit.
- **Widżety**: siatka 2 kolumn, rozmiary `1x1`, `2x1`, `2x2`. Widoki: `value`, `toggle`, `slider`, `stepper`, `status`,
  `chart` (historia z `history` w chmurze, ostatnie 24 h), `thermostat` (temperatura, nastawa − / +, grzanie), `scene`.
  Widżet urządzenia bez dostępu jest wyszarzony z kłódką, kontrolki ponad mój poziom są nieaktywne.
- **Wygląd kafelka** (`TileShell` w `lib/ui/dashboard_tiles.dart`): ikona-przycisk w kółku, nazwa, druga linia stanu,
  tło w kolorze akcentu (pomarańcz z motywu), gdy włączone / grzeje / zwarte; plakietki GRZEJE, MRÓZ, AWARIA,
  USTERKA. Kafelek bez treści na dole: ikona u góry, nazwa i stan na dole. Na dwa wiersze - większa ikona.
- **Dwie strefy dotyku**: ikona wykonuje akcję główną (przełącz, wszystkie kanały, scena), reszta kafelka otwiera
  arkusz szczegółów (pełna kontrolka punktu, wykres 24 h, przejście do urządzenia); termostat i węzeł
  wielokanałowy - od razu ekran urządzenia. Zmiana widoczna od razu (zanim urządzenie odpowie), z wibracją.
- **Rodzaje** (z punktów `describe`, bez nowych pól w kontrakcie): jedno wyjście (`toggle` + `onN`), wszystkie wyjścia
  węzła (`toggle` + `on` na urządzeniu z `channels` > 1: przycisk na kanał z nazwą, „2 z 4”, ikona wł./wył.
  wszystkie, plakietka usterki wejścia; 1×1 - same numery), stan wejścia (`status` + `inN`: zwarte / rozwarte,
  usterka z `inNFault`), wartość z ikoną (`value`), suwak (ikona przełącza `on` ściemniacza), plus / minus,
  wykres (pole pod linią), termostat, scena.
- **Rozszerzony układ (pkt 13.1)**: siatka 4 kolumn × 64 px (`"grid": 4`; nowe pulpity od razu, stare - menu
  „Nowy układ” albo karta w edycji: `toGrid4()` przelicza dawne rozmiary), rozmiary 1×1…4×4 (`w`, `h`), kafelki
  w pierwszym wolnym miejscu (`packGrid4`). Pasek 4×1: wszystko w jednej linii, suwak obok nazwy. **Sekcje** z
  nagłówkami (pulpit startowy - sekcja na pokój; w edycji: nowa sekcja, zmiana nazwy, kolejność, usunięcie;
  przeciągnięty kafelek przechodzi do sekcji kafelka docelowego). **Podsumowanie** nad pulpitem
  (`lib/ui/dashboard_summary.dart`): pigułki świateł („Wyłącz wszystkie”), grzania i alarmów (awaria czujnika,
  usterka wejścia, brak kontaktu).
- **Ustawienia kafelka 13.1** (arkusz, części rozwijane): kolor (`color`, z tego samego wzoru co motyw), rozmiar
  ikony, druga linia (stan / ostatnia zmiana / inny punkt / nic), dotyk ikony i kafelka, pytanie przed akcją,
  szybkie sterowanie (`features`: suwak, − / +, tryby, kanały, trend), wybrane kanały węzła (`points`), napisy
  stanu (`labels`), wskaźnik (min / max, strefy, znacznik celu), wykres (zakres, przełącznik zakresu, do 3 serii -
  gładka / schodkowa / pasy stanu, linia odniesienia). Pola nieznane tej wersji (także `view`) zostają w JSON-ie.
- **Pokrętło** (`dial`, `lib/ui/tile_charts.dart`): półokrągły suwak do `setpoint`, przeciąganie po łuku z krokiem
  z `describe`, polecenie po puszczeniu palca, kropka z wartością bieżącą (dla `target` - temperatura).
  **Wskaźnik** (`gauge`): łuk tylko do odczytu ze strefami. **Wykres**: `TileChart` - kilka serii, zakres 6 h -
  30 dni (historia z `hours`).
- **Grupa, pogoda, hub (pkt 13.1)**: `group` - kilka wyjść (`members`) jednym kafelkiem: „2 z 5”, ikona wyłącza
  wszystko, gdy coś świeci (inaczej włącza), dotyk - lista z przełącznikami; członkowie bez `control` albo bez
  połączenia pomijani. `weather` - `outdoor` termostatu: temperatura, ikona i opis (numer ikony termostatu 1-9
  albo kod OpenWeatherMap), „sprzed N min”, na kafelku 4×3 wykres z historii `out`. `hub` - urządzenia dostępne /
  wszystkie, automatyki, trwające sceny, ostatnie wykonanie, plakietka BEZ CHMURY; dotyk - ekran huba.
- **Termostat na pulpicie**: dotyk kafelka termostatu otwiera arkusz (`lib/ui/thermostat_sheet.dart`) z zakładkami
  Sterowanie (jak ekran termostatu), Harmonogram i Ustawienia (te same ekrany, wymagają `config`). Kafelek
  **Harmonogram** (`schedule`, pkt 13.1): „Komfort do 22:30, potem eko 18°”, „Ręcznie · nastawa”, „Wyłączony”,
  „nadpisane”; od 4×2 pasek dzisiejszego planu z bieżącą godziną; dotyk - arkusz na zakładce Harmonogram.
- **Nazwy kanałów i wejść** na kafelkach, w kreatorze i w grupach: najpierw z Config modułu (`chN.name`,
  `inputK.name`), potem z `describe`, na końcu „Kanał N”. Opis urządzenia jest pobierany na nowo po każdej zmianie
  Config (`descriptionVersion`), więc zmiana nazwy w ustawieniach modułu od razu widać na pulpicie.
- **Gotowe kafelki** (kreator, po wyborze urządzenia, `tilePresets`): termostat (duży, pokrętło, temperatura
  z wilgotnością, wskaźnik wilgotności, wykres 24 h, pogoda), węzeł (wszystkie wyjścia, każdy kanał, każde wejście),
  światło (przełącznik, pasek i pokrętło jasności), hub (stan). Pod nimi - wybór punktu jak dotąd.
  **Grupa wyjść** - osobna pozycja na liście urządzeń (`GroupPickerScreen`); członków zmienia arkusz kafelka.
- **Edycja na siatce** (ołówek): te same kafelki co na pulpicie, z obrysem. Dotyk - arkusz ustawień z podglądem na
  żywo (`lib/ui/tile_settings.dart`): podpis, ikona, rozmiar, wygląd (z pasujących do punktu z `describe`),
  Wcześniej / Później, Duplikuj, Edytuj scenę, Usuń. Przytrzymanie i przeciągnięcie - kafelek zajmuje miejsce tego,
  na który go upuszczono. Uchwyt w rogu - kolejny rozmiar (1×1 → 2×1 → 2×2).
- Podgląd pulpitu do obrazka (prawdziwe czcionki, jasny i ciemny motyw):
  `flutter test tool/preview/dashboard_preview_test.dart --update-goldens` → `tool/preview/pulpit_*.png`,
  `edycja_*.png`, `siatka4_*.png`.
- **Ikony**: każdy widżet ma ikonę przed nazwą - domyślną z punktu danych i typu urządzenia (np. kanał `on2` -
  żarówka, `in3` - przycisk, `temp` - termometr, scena - gwiazdki) albo wybraną z katalogu (~60 ikon w grupach:
  oświetlenie, ogrzewanie, sprzęty, miejsca, czujniki, sceny, urządzenia; `lib/ui/app_icons.dart`). Wybór: krok
  „wygląd” przy dodawaniu albo menu widżetu → **Ikona**; zapis w JSON-ie widżetu jako `"icon":"<klucz>"`.
  Urządzenia (węzły) mają ikonę na kafelku - domyślną dla typu albo wybraną (przytrzymanie kafelka → **Ikona**).
  W domu w chmurze ikona urządzenia jest w `homes/{h}/deviceIndex/{id}/icon` - wspólna dla domowników i zegarka,
  zmienia ją tylko właściciel (domownik nie ma opcji **Ikona**); bez konta - w telefonie. Widżety całego
  urządzenia (termostat, `on`) biorą ikonę urządzenia; kolejność: ikona widżetu → urządzenia → domyślna.
- **Tryb edycji** (ołówek): przeciąganie za uchwyt, menu widżetu (rozmiar, podpis, usunięcie), **+ Widżet** w 3 krokach:
  urządzenie → punkt danych z `GET /api/describe` (w chmurze `devices/{id}/describe`; gdy urządzenie milczy - znane
  pola wg typu) → wygląd, rozmiar i podpis.
- **Sceny** (`homes/{h}/scenes/{id}` `{"name","actions":[…]}`, ARCHITEKTURA pkt 4.6): układa właściciel (bez konta -
  każdy), domownicy wybierają gotowe; widżet wskazuje `sceneId`. Akcje: ustawienie urządzenia (`device` + `set`),
  przerwa (`delay`), inna scena. **Uruchom**: gdy w domu jest hub z moim `control` - polecenie `{"runScene": id}`
  do huba; bez huba telefon wysyła akcje po kolei z moimi uprawnieniami (przerwy do 60 s, dłuższe tylko hub).
  Błędy (np. brak uprawnień) wracają w komunikacie.

## Pulpit zegarka (pkt 13a)

Ikona zegarka na pasku pulpitu (tylko z kontem). Osobny od pulpitów telefonu, dla każdego domu i zegarka:
`users/{uid}/watchDashboards/{homeId}/{watchId}`.
- **Zegarek**: lista z `users/{uid}/watches` (zgłasza się sam przy uruchomieniu aplikacji „Dom”); gdy żadnego nie ma -
  model z wbudowanej listy Amazfit (T-Rex 3, Balance, Cheetah Pro, GTR 4, Active 2, T-Rex Ultra, GTS 4, Active,
  GTS 4 Mini, Bip 5; rozdzielczości w `lib/models/watch.dart`).
- **Strony** z tytułem, kafelki `half` / `full` / `big`, widoki `value`, `toggle`, `stepper`, `status`, `thermostat`,
  `scene`. Kafelek dodaje się jak widżet pulpitu (urządzenie → punkt z `describe` → wygląd), potem menu: rozmiar,
  podpis, przeniesienie na inną stronę, usunięcie; przeciąganie za uchwyt. **Zapisz** zapisuje cały pulpit
  (`watch` = ekran, dla którego układano, `updatedAt`); „Usuń pulpit zegarka” - zegarek wraca do listy urządzeń.
- **Podgląd** w kształcie i rozdzielczości zegarka, przeskalowany i przewijany palcem, z wartościami na żywo.
  Układ to port 1:1 `watch/utils/layout.js` (wiersze 88/186 px, odstęp 10, nagłówek 40, start 92; na okrągłym
  szerokość wiersza = cięciwa w miejscu, gdzie wiersz da się przewinąć najbliżej środka, minus 14 px, 220-400 px).
  Test `watch_test.dart` porównuje wynik z `layout.js`.
- **Konto dla zegarka** (Domownicy, właściciel; `PRZEGLAD.md` #9): aplikacja Dom w Zepp trzyma refresh token konta,
  a główne konto otwiera też Zakupy, Wagę itd. Ekran zakłada osobne konto e-mail (podpowiedź `ja+zegarek@…`) w drugiej
  instancji Firebase - telefon zostaje zalogowany głównym kontem - i dołącza je do domu jednorazowym kodem (10 min,
  `_all: control`, potem kod skasowany). Pulpit zegarka jest prywatny (`users/{uid}/watchDashboards`), więc kopia
  idzie pod konto zegarka; po zmianach pulpitu wystarczy powtórzyć zapis (ten sam e-mail i hasło - konto już jest
  domownikiem, odświeża się poziom i pulpit). Hasła telefon nie zapamiętuje. Bez zmian w regułach bazy.

## Urządzenia i pokoje

- **Urządzenia**: sparowane w tym telefonie oraz te z domu w chmurze (`homes/{h}/devices`, typ w `info/type`).
  Domownik nie może wylistować `homes/{h}/devices` (reguły), więc bierze listę z `homes/{h}/deviceIndex`
  (`{"type","name","via"?}`), którą aplikacja właściciela zapisuje przy dodaniu urządzenia, zmianie nazwy i uzupełnia
  z `devices` (typ huba i `via` przenosi z `info`). Reguły biorą typ huba i przynależność do huba właśnie stąd.
  Urządzenie znane tylko z chmury jest sterowane przez chmurę, a do sterowania w domu trzeba je sparować.
- **Kafelki**:
  - termostat: temperatura, nastawa, płomień przy grzaniu, ostrzeżenie o awarii; dotknięcie otwiera ekran termostatu;
  - włącznik / ściemniacz: przełącznik i suwak jasności; dotknięcie kafelka przełącza, ikona ⚙ otwiera szczegóły;
  - przełącznik wielokanałowy z wejściami (pkt 10.1, np. węzeł `switch4`: 4 kanały, 8 wejść zwieranych do masy):
    kafelek steruje wszystkimi kanałami (`on` / `toggle`) i pokazuje „Włączone: 2 z 4”; w szczegółach przełącznik
    na każdy kanał i stany wejść (z `describe`), a w sekcjach **Kanały** (nazwa, stan po zaniku zasilania) i
    **Wejścia** (nazwa, tryb: przycisk / łącznik - każda zmiana / łącznik - położenie, steruje kanałem: brak / 1-N);
    usterka wejścia (`inNFault`: ponad 30 zmian w 5 s, wejście zablokowane, samo wraca po 60 s) - ostrzeżenie na
    kafelku („Usterka wejścia 2”), baner na ekranie urządzenia i oznaczone wejście; atrapa: klawisze `x1`…`x8`;
  - inne typy: szczegóły zbudowane z `describe` (lista punktów z kontrolkami wg rodzaju i poziomu dostępu);
  - typ nieobsługiwany (np. hub): kafelek informacyjny.
- **Pokoje** (`homes/{h}/rooms/{roomId}` `{"name","order","devices":[…]}`, pkt 8.3), zmienia je właściciel domu:
  - ikona domu z „+” w pasku tworzy pokój;
  - przytrzymanie kafelka: przeniesienie do pokoju albo do nowego pokoju, wyjęcie z pokoju, kolejność (wcześniej/dalej),
    usunięcie z telefonu;
  - menu pokoju: zmiana nazwy, wyżej/niżej, usunięcie;
  - urządzenia spoza pokoi są w sekcji „Bez pokoju”.

  Ten sam układ widzi zegarek (`../watch`).

## Hub (pkt 11, ARCHITEKTURA pkt 4.4-4.6)

Kafelek huba pokazuje „Hub · 3/4 urządzeń”; dotknięcie otwiera **ekran huba**:
- stan (urządzenia dostępne, sceny, automatyki, łącze, chmura, ostatnie wykonanie); gdy hub nie zna czasu -
  „Z telefonu” (`POST /api/time`);
- **Urządzenia huba** (w domu): `GET /api/devices` (dostępność, błąd, „w chmurze” / „tylko w domu”), przełącznik
  (`POST /api/devices/{id}/set`, `202 pending` = urządzenie odpowie za chwilę), „Do chmury” (właściciel wpisuje
  `deviceIndex/{id}` z `via`), usuwanie (z wpisami w bazie); **Szukaj w sieci**: `GET /api/discover` co 1 s, aż
  `scanning: false`, dodanie z nazwą, hasłem (Shelly, Tasmota) i kanałem; Tuya - komunikat (faza 4);
- **Automatyki**: w domu wprost w hubie (`/api/automations`: diagnostyka - pominięte reguły, wschód/zachód, czas;
  „Uruchom teraz”; dziennik), poza domem `homes/{h}/automations/{id}` z `updatedAt` i Set `{"reload":true}`.
  Edytor: kiedy (godzina z dniami, wschód/zachód z przesunięciem, stan urządzenia z „przez N s”, przycisk / wejście
  węzła krótko / podwójnie / długo, po scenie), tylko jeśli (pora, dni, dzień / noc, stan), wtedy (ustaw urządzenie,
  przerwa, scena, powiadomienie z wagą, wpis w dzienniku); błędną regułę hub odrzuca z listą problemów;
- **Sceny** (wykonuje je hub; akcja „Powiadomienie” tylko z hubem); po zapisie w chmurze `updatedAt` i `reload`;
- **Położenie domu** (Set `location`, podpowiedź z ustawień pogody termostatu) - wschód i zachód w automatykach;
- ustawienia wspólne (chmura - łączenie zapisuje też `deviceIndex/{hubId}` `{"type":"hub"}`, telefony, firmware, WiFi).

**Przypisz do huba** (ustawienia węzła albo termostatu, w domu, poziom `config`): węzeł wystawia hubowi token
(`POST /api/clients`), aplikacja przekazuje go hubowi (`POST /api/devices` `ownNode`) i wpisuje `deviceIndex/{id}`
z `via`. Termostat dostaje token `control` i `"mirror": false` - tylko do automatyk.

**Powiadomienia z domu** (`homes/{h}/notifications`, akcja `notify`): dzwonek z liczbą nieprzeczytanych na pulpicie
i powiadomienia telefonu z zadania w tle (co ~15 min, nowe od ostatniego sprawdzenia).

Atrapa: `dart run tool/fake_device.dart --type hub --port 8084` (urządzenia, wykrywanie Shelly / Tasmota,
automatyki i sceny z `updatedAt`, dziennik, czas; host `.98` = urządzenie odpowiada z opóźnieniem).

## Dodawanie urządzeń

**Dodaj urządzenie** daje dwie drogi.

### Nowe urządzenie – Bluetooth (kontrakt pkt 9.2)

Urządzenie w trybie konfiguracji (pierwsze uruchomienie, reset fabryczny albo po `wifi/reset`) rozgłasza
`HA_<id>` i pokazuje 8-znakowy kod PoP. Kroki w aplikacji:
1. Skan BLE z filtrem `HA_` i wybór urządzenia.
2. Kod PoP. Sesja **security 1** Espressif Unified Provisioning: X25519, klucz XOR SHA-256(PoP),
   jeden ciągły strumień AES-256-CTR.
3. **`ha-pair`** `{"client":…,"uid":…}` → `{"id","type","token","api","access":"config"}`: token telefonu
   (przypisany do konta) zapisany od razu, urządzenie sparowane, ten telefon ma pełny dostęp.
4. Skan sieci (`prov-scan`), wybór sieci (albo ukryta), hasło → `prov-config` set + apply →
   odpytywanie stanu aż `connected` (z adresem IP) albo `auth_error` / `ap_not_found`.
5. Urządzenie wyłącza Bluetooth. Aplikacja znajduje je przez mDNS (albo pod IP ze stanu) i zapisuje adres.

Protokół jest w `lib/provisioning/`, w Dart na `flutter_blue_plus` (1.x, licencja BSD). Gotowy pakiet
`flutter_esp_ble_prov` nie obsługuje własnych endpointów, a `ha-pair` jest własny. Endpointy rozpoznaje po
deskryptorze 0x2901 charakterystyk usługi `021a9004-0382-4aea-bff4-6b3f1c5adfb4`. Protobuf jest kodowany
ręcznie: numery pól z `.proto` ESP-IDF 5.1.

### Kod QR z naklejki (pkt 9.1)

**Dodaj urządzenie → Skanuj kod QR**: kod w formacie Espressif
`{"ver":"v1","name":"HA_<id>","pop":"<PoP>","transport":"ble|softap","security":1}`.
- `ble` - aplikacja szuka przez Bluetooth urządzenia o nazwie `name` i od razu łączy się kodem `pop`
  (bez listy i przepisywania kodu); `softap` - łączy telefon z siecią `name` (hasło = `pop`), dalej jak niżej.
- Nieznane pola są pomijane, `ver` inne niż `v1` - „Nieobsługiwany kod QR”. Treść kodu można też wkleić
  (ikona klawiatury, np. z logu urządzenia `WiFi: QR {...}`).
- Skaner: [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) (BSD-3), na Androidzie ML Kit z Google Play
  Services (`dev.steenbakker.mobile_scanner.useUnbundled=true` w `android/gradle.properties`, APK większy tylko
  o ~600 KB); uprawnienie aparatu: Android z wtyczki, iOS `NSCameraUsageDescription`.

### Nowe urządzenie bez Bluetootha – SoftAP (pkt 9.4)

Np. węzeł `switch4` (ESP32-S2). **Dodaj urządzenie → Nowe urządzenie bez Bluetootha**:
1. Kod z naklejki (PoP, 8 znaków hex; aplikacja zamienia na małe litery).
2. Telefon łączy się z siecią urządzenia `HA_<id>` (WPA2, hasło = PoP): Android 10+ `WifiNetworkSpecifier`
   (system pokazuje sieci `HA_*` do wyboru) + `requestNetwork` + `bindProcessToNetwork`, iOS `NEHotspotConfiguration`
   (prefiks `HA_`, uprawnienie Hotspot Configuration w `Runner.entitlements`). Kod natywny: `MainActivity.kt`,
   `AppDelegate.swift`, kanał `pl.grekot.homeautomation/wifi`. Starszy telefon: „Jestem już połączony” po ręcznym
   połączeniu z siecią w ustawieniach.
3. Ten sam protokół co Bluetooth (security 1, `ha-pair`, skan, `prov-config`), tylko przez
   `POST http://192.168.4.1/<endpoint>` (`lib/provisioning/softap_transport.dart`), z ciasteczkiem `session=`;
   status czytany z ponowieniami.
4. Po `connected` aplikacja zwalnia sieć `HA_*`, czeka na restart urządzenia (~3 s) i szuka go przez mDNS.

**Zmiana sieci WiFi** urządzenia z `"prov":"softap"` prowadzi tą samą ścieżką (sieć `HA_<id>`).
Węzeł bez chmury (`"cloud":false` w `/api/info`) nie ma sekcji „Połącz z chmurą” - do chmury przez hub.

### Urządzenie już w sieci – kod z ekranu (pkt 2)

Dla kolejnych telefonów: wybór z listy mDNS albo adres ręcznie, `POST /api/pair/start`, 6 cyfr z ekranu.
Urządzenie bez ekranu (`"pair":"pop"` w `/api/info`): kodem jest PoP z naklejki (8 znaków hex, wielkość liter
bez znaczenia); węzeł bez chmury daje nowemu telefonowi `control`, poziom zmienia właściciel w „Telefony”.
Każdy telefon dostaje **własny token**. Z kontem aplikacja wysyła w `pair/confirm` także `idToken` Firebase:
urządzenie daje najpierw `view`, sprawdza konto i nadaje poziom z `access` domu - aplikacja czeka na to,
odpytując `GET /api/me` (komunikat „Sprawdzanie uprawnień konta…”).

### Token dla komputera (pkt 2a)

Ikona komputera na zakładce „Urządzenia” → **Wyślij token do komputera**: na PC `python tools/pair_pc.py` pokazuje
kod QR `{"ver":"v1","kind":"pc-token","url","secret","name"}` (ważny 5 min; inny kod - „to nie ten kod”; adres musi
być w sieci domowej). Aplikacja pokazuje urządzenia, w których telefon ma `config` i zna adres; dla każdego wybranego
`POST /api/clients {"name":"komputer <nazwa>","access":"config"}`, potem jedno `POST <url>`
`{"secret","devices":[{"id","type","name","host","token"}]}` (`403` zły sekret, `410` po 5 min). Komputer zapisuje
`tokens.json` dla `tools/ota.py`; token komputera widać i usuwa się w „Telefony”.

### Zmiana sieci WiFi (pkt 9.3)

W ustawieniach urządzenia (sekcja „Urządzenie”, tylko w sieci domowej): **Zmień sieć WiFi** wysyła
`POST /api/wifi/reset`, a potem prowadzi ten sam kreator Bluetooth, ograniczony do tego urządzenia.
`ha-pair` zwraca ten sam token.

## Ustawienia wspólne dla każdego urządzenia

`DeviceAdminSection`:
- chmura: połącz / odłącz, stan z `GET /api/cloud`;
- zmiana sieci WiFi;
- aktualizacja firmware (OTA);
- **Telefony** (`/api/clients`, wymaga `config`, w domu): lista sparowanych telefonów z poziomem i kontem;
  dotknięcie - ręczna zmiana poziomu (`PATCH`, np. bez chmury; przy chmurze urządzenie bierze poziom domownika
  z `access`); usunięcie unieważnia token; **Token** - nowy token bez parowania dla huba albo skryptu (`POST`),
  pokazany raz;
- **Powiadomienia na telefon** (pkt 3d, `config`, w domu): urządzenie samo wysyła alarm przez ntfy (awaria czujnika,
  mróz, nieudana aktualizacja, akcje automatyk huba) - od razu, bez czekania na WorkManager. Ekran: włącz/wyłącz,
  temat (kopiuj adres), **Subskrybuj w ntfy** (`ntfy://<serwer>/<temat>`, bez aplikacji ntfy - strona tematu, potem
  adres do schowka), **Wyślij próbne**, nowy losowy temat, własny serwer i token (tokenu urządzenie nie zwraca).
  Linki otwiera kanał natywny `pl.grekot.homeautomation/links` (MainActivity.kt, AppDelegate.swift) - bez wtyczki.
  Starszy firmware bez `notify` w Config - komunikat o aktualizacji;
- identyfikator, typ, czas pracy, mój dostęp.

Administracja (chmura, WiFi, OTA, telefony) wymaga poziomu `config` i połączenia w sieci domowej.

Termostat ma do tego harmonogram i własne ustawienia, w tym **ochronę przed zamarzaniem** (`frost`, pkt 6):
najniższa temperatura pilnowana zawsze, także przy OFF (0 = wył., 4-12 °C), i grzanie cykliczne przy awarii czujnika
(0 albo 5-20 min/h, tylko w mróz). Ekran termostatu pokazuje, kiedy ochrona działa (`protect` w State). Światło ma nazwę i zachowanie po zaniku zasilania (`defaultOn`).

## Aktualizacje firmware (pkt 3e)

Urządzenia → ikona aktualizacji (właściciel; bez konta - każdy z tokenem `config`). Każdą aktualizację zatwierdza
się tutaj.
- **Manifest** `https://ha-firmware.web.app/manifest.json` (`lib/data/firmware_catalog.dart`), ostatnia kopia
  w telefonie na czas bez internetu. Wpisy spoza `https://ha-firmware.web.app/fw/` albo bez SHA-256 są pomijane
  (urządzenie i tak odrzuci je z chmury).
- **Termostat, hub, urządzenia z chmurą**: wersja i wariant z `/api/info` (`fw`, `fwId`) albo z chmury
  (`devices/{id}/info`). „Aktualizuj” → Set `{"firmwareUrl","firmwareSha256"}` lokalnie albo poleceniem z chmury
  (z chmury tylko właściciel). Lokalnie postęp z `GET /api/ota`, potem `/api/info` z nową wersją; z chmury -
  `homes/{h}/devices/{id}/ota` (`running` z procentami, `failed`, `done`, `rolledBack` z `crash`/`boot`; stary wpis
  sprzed polecenia pomijany), a przy starszym firmware nowe `info.fw` (do 10 min). Termostat: ostrzeżenie przed
  zatwierdzeniem, gdy grzeje albo ma awarię czujnika. Obecna wersja poniżej `minVersion` - dwa kroki: najpierw
  `intermediate` z manifestu, po nim lista od nowa i drugie zatwierdzenie (bez `intermediate` - tylko informacja).
- **Węzły huba**: `GET hub/api/updates` (tablica) albo `homes/{h}/devices/{hubId}/updates` (mapa po id),
  `next` = co zainstaluje najbliższe zatwierdzenie (po wersji pośredniej - drugie zatwierdzenie); zaznaczenie
  gotowych (`ready`) i `POST hub/api/updates/apply` (`409` z błędem po id: `unknown|busy|not_ready`) albo Set huba
  `applyUpdates` (błąd po id w `applyUpdates.<id>`); **Sprawdź teraz** - `POST hub/api/updates/check` / Set
  `checkUpdates`. Stany `queued/updating/observing/done/failed` odświeżane co 15 s, dopóki hub coś aktualizuje.
  Węzły z listy huba nie pojawiają się drugi raz wśród urządzeń.
- **W tle** (WorkManager, raz na dobę, domy, których jestem właścicielem): lokalne powiadomienie „Dostępna
  aktualizacja” tylko o wersjach, o których jeszcze nie było (`lib/background/update_check.dart`).
- Atrapy: `fwId` w `/api/info`, Set `firmwareUrl` udaje pobieranie i restart z wersją z nazwy pliku
  (`firmwareSha256Mismatch` - błąd sumy); atrapa huba ma `nodeUpdates`, `/api/updates`, `/api/updates/apply`,
  `applyUpdates` i kolejkę (`advanceUpdates`, `updateStep`, `failUpdateOf`).

## Firebase (chmura)

1. W konsoli: aplikacja Android **`pl.grekot.homeautomation`** w projekcie `zakupy-8ec54` i reguły bazy
   (`homes/`, `users/`, `invites/`) według `docs/firebase/KONFIGURACJA.md` (repozytorium firmware). Pobierz `google-services.json`
   do `homeautomation/phone/android/app/`.
2. `node tools/configure.mjs` przepisze z niego `apiKey`, `appId`, `projectId` i **`databaseURL`**
   (wtyczka Gradle `google-services` nie jest używana).
3. W konsoli: **Authentication → Sign-in method → Anonymous: włącz**. Urządzenia zakładają sobie anonimowe konta.
4. W sieci domowej (właściciel domu): ustawienia urządzenia → **Chmura → Połącz z chmurą** (bez hasła, pkt 8.2):
   - `POST /api/cloud {"apiKey","dbUrl","homeId"}` → `202 linking` (urządzenie zakłada konto);
   - odpytywanie `GET /api/cloud` co 1 s → `binding` z `deviceUid`; aplikacja zapisuje
     `homes/{h}/deviceAccounts/{deviceUid} = deviceId` (i `deviceIndex`);
   - urządzenie widzi przypisanie → `linked`;
   - **Odłącz**: `{"disconnect":true}` i usunięcie wpisu w `deviceAccounts`.

Dane w bazie (pkt 8.1): `homes/{h}/devices/{id}/{info,state,config,describe,lastSeen,lastCommand}` (aplikacja nasłuchuje
tylko tych gałęzi), polecenia `commands/{h}/{id}/{push}` `{"values","ts","by"}`, historia `history/{h}/{id}/{dzień}/{HHMM}`.

### Powiadomienia

Po zalogowaniu zadanie WorkManagera (co ~15 min, gdy jest sieć) czyta `info/name`, `state/sensorFault` i `lastSeen`
każdego urządzenia we wszystkich domach konta. Powiadamia tylko przy przejściu w **awarię czujnika** albo **brak kontaktu**
(`lastSeen` starsze niż 3 min) i chowa powiadomienie, gdy problem minie. Wyłączenie: menu konta → „Powiadomienia o awariach”.

## Wydanie do Sklepu rodzinnego

Tag `homeautomation-vX.Y.Z` uruchamia [release-homeautomation.yml](../../.github/workflows/release-homeautomation.yml)
(wspólny workflow z `grekot/App_storage`). Wynik:
- APK arm64 podpisany wspólnym kluczem trafia do GitHub Release jako `homeautomation.apk`;
- wersja trafia do biblioteki sklepu.

Konfigurację Firebase CI odtwarza z sekretu repozytorium **`FIREBASE_OPTIONS_HOMEAUTOMATION_B64`**:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\TMP\My_GIT\T_rex_3\homeautomation\phone\lib\firebase_options.dart")) | Set-Clipboard
```

Do grup przypisuje administrator (w folderze `App_storage`):

```bash
sklep przypisz homeautomation --grupa Rodzina
```

Lokalnie [`build_apk.cmd`](build_apk.cmd) buduje `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
Podpisuje go kluczem z `android/key.properties` (poza gitem).

## Atrapy urządzeń (bez sprzętu)

`tool/fake_device.dart` uruchamia serwer zgodny z kontraktem v2.
- **Wspólne endpointy** (`tool/fake/fake_device.dart`):
  - `/api/info` z `type` i `api: 2` (opcjonalnie `prov`, `pair`, `cloud`, `channels`);
  - parowanie kodem (`403 bad_code`, `409 not_pairing`, `429 locked` przez 60 s po 3 złych kodach); z `--pop` kodem jest PoP;
  - `/api/state|config|set` (`400` z `errors` + stan, `503 busy`) i `/ws`;
  - `/api/wifi/reset`: po 1 s zamyka połączenia (BLE nie ma);
  - `/api/cloud` (bez prawdziwego Firebase: `linking` → `binding` → `linked`, `apiKey` `zly` = błąd) i `/api/ota`
    (obraz od `0xE9`).
- **mDNS** `_homeauto._tcp` z TXT `id`, `type`, `api`, `fw` (i `prov=softap`, `ch=N`).
- **Typy**:
  - `thermostat` (`fake_thermostat_server.dart`): temperatura, grzanie z histerezą, AUTO wg harmonogramu, walidacja jak w firmware;
  - `switch` / `dimmer` (`fake_light.dart`): `on`, `level`, `toggle`, `name`, `defaultOn`; z `--channels N`
    przełącznik wielokanałowy jak `switch4` (`on1..N`, `ch1..N`, wejścia `in1..M` / `input1..M`, domyślnie M = 2N).

```bash
cd homeautomation/phone
dart run tool/fake_device.dart                                  # termostat, port 8080
dart run tool/fake_device.dart --type dimmer --port 8081        # ściemniacz swiatlo-0c4f21
dart run tool/fake_device.dart --type switch --port 8082 --id swiatlo-000002 --name Korytarz
dart run tool/fake_device.dart --type switch --channels 4 --prov softap --pop ab12cd34 --no-cloud --port 8083   # jak switch4
```

Klawisze (Enter po każdym):
- termostat: `k`/`j` gałka ±0,5 °C, `f` awaria czujnika;
- światło: `w` przycisk na ścianie, `w1`…`w8` wejście węzła wielokanałowego;
- zawsze: `b` zajęty, `p` kod parowania, `s` stan, `t` token, `q` koniec.

Jak się połączyć:

| Skąd | Adres |
|---|---|
| Telefon w tej samej sieci Wi-Fi | mDNS albo `IP-komputera:8080` |
| Emulator Androida | `10.0.2.2:8080` |
| Firmware w Wokwi | `10.0.2.2:8180` z emulatora (pkt 1a) |

Konfiguracji Bluetooth atrapa nie udaje. Ten przepływ testuje `test/support/fake_prov_device.dart`.

## Testy

```bash
flutter test
```

- `provisioning_test.dart`:
  - AES-CTR na wektorach NIST SP 800-38A, z przeniesieniem przez 128 bitów;
  - cała sesja security 1 porównana z referencją z OpenSSL (Node) na kluczach z RFC 7748;
  - zły PoP, `ha-pair`, skan sieci, zapis sieci, `connected`/`auth_error`/`ap_not_found`.
- `home_v2_test.dart`:
  - typy urządzeń, światło na atrapie (wł./wył., jasność, błąd pola, przycisk na żywo), `/api/wifi/reset`;
  - pokoje: układ, przenoszenie, kolejność, zapis w `homes/{h}/rooms`.
- `dashboard_model_test.dart`: pola 13.1, nieznane pola i widok bez zmian, rozmiary siatki 4, sekcje, układanie.
- `dashboard_tiles_test.dart`: kafelki pulpitu - ikona przełącza od razu, kolor wg stanu, arkusz szczegółów, wszystkie
  wyjścia węzła, stan wejścia z usterką, termostat z plakietką, każdy rodzaj w kafelku 1×1 bez przepełnień.
- `firmware_test.dart` / `updates_device_test.dart`: aktualizacje firmware - wersje, manifest, katalog z kopią,
  sprawdzanie w tle, ekran (ostrzeżenie, postęp, węzły huba) i na atrapach: Set `firmwareUrl` z postępem
  i restartem, zła suma, kolejka huba.
- `notify_test.dart` / `notify_device_test.dart`: powiadomienia ntfy - model, ekran (włączenie, próbne, subskrypcja
  z zapasową stroną, nowy temat, starszy firmware) i Set `notify` na atrapie (błędy pól, poziom `config`).
- `watch_account_test.dart`: konto zegarka - dołączenie z `control`, sprzątnięty kod, kopia pulpitu, powtórka,
  e-mail głównego konta i złe hasło, ekran.
- `watch_test.dart`: układ kafelków zegarka porównany z `watch/utils/layout.js` (okrągły 480 i 466, prostokątny),
  JSON i zapis pulpitu zegarka, ekran „Zegarek” (model z listy, kafelek, zapis).
- `softap_switch_test.dart`: SoftAP przez HTTP na serwerze z atrapą provisioningu (ciasteczko sesji, cały przebieg),
  węzeł `switch4` na atrapie (`/api/info`, parowanie kodem PoP → `control`, kanały, wejścia, błędy pól, poziomy);
  `softap_ui_test.dart`: kreator „Urządzenie bez Bluetootha”.
- `hub_test.dart`: API huba na atrapie (wykrywanie, dodawanie, sterowanie, `202 pending`, Tuya, automatyki i sceny
  z `updatedAt`, błędna reguła, dziennik, czas), automatyki w domu i przez chmurę (`reload`), przypisanie węzła,
  powiadomienia; `automations_ui_test.dart`: edytor automatyki (słońce → powiadomienie, odrzucona reguła).
- `pc_token_test.dart`: kod komputera i wysyłka tokenów na atrapę `pair_pc.py` (403, 410).
- `homes_test.dart`: dom, zaproszenie, dołączenie jedną operacją (klucze jak w regułach), wygasły kod, wyjście z domu,
  `deviceIndex` (właściciel / domownik), zmiana i odebranie uprawnień; `_all` i wyjątki; `describe` (klucze z kropką, Set); pulpity (JSON z kontraktu, chmura + kopia
  lokalna, preferencje); historia do wykresu.
- `ui_v2_test.dart`: kreator Bluetooth od skanu do „Gotowe” na atrapie urządzenia; ekran przełącznika 4-kanałowego
  (kanał z `describe`, ustawienia kanału i wejścia); zakładka „Urządzenia” (kafelki,
  przełącznik, nowy pokój, przeniesienie); pulpit (startowy z urządzeń, sterowanie z widżetów, widżet w 3 krokach,
  scena).
- `local_connection_test.dart`: parowanie (własny token, `idToken` → `view` → poziom z `/api/me`), tokeny `view`
  i `config` (`forbidden`, `/api/clients` GET/PATCH/POST/DELETE, `describe`), OTA, chmura `/api/cloud` (konto
  urządzenia: linking → binding → linked), ochrona przed zamarzaniem, stan na żywo, set przez WS i HTTP,
  wybór drogi.
- `cloud_connection_test.dart`: chmura na RTDB w pamięci (`homes/{h}/devices`, `commands/{h}/{id}` z `by`), offline,
  lista z typami.
- `alerts_test.dart`, `models_test.dart`, `schedule_test.dart`, `widget_test.dart` (termostat, ustawienia, OTA).

## Struktura

```
lib/
  main.dart, app.dart          start, Firebase, AuthGate (LoginScreen z `wspolne`) → HomeGate, motyw, lokalizacja
  services.dart                zależności: magazyn, mDNS, ConnectionManager, parowanie, chmura, BLE, pokoje, pulpity
  models/                      czysty Dart (używa go też atrapa)
    device_type.dart           typy z pkt 0 + DeviceCodec (State/Config danego typu)
    thermostat_*.dart, set_values.dart, schedule.dart   termostat (pkt 5-7)
    light.dart                 switch / dimmer (pkt 10)
    room.dart                  pokoje i ich układ (czyste funkcje)
    home.dart                  poziomy dostępu, dom, domownik, uprawnienia (`_all`), zaproszenie
    describe.dart              punkty danych (pkt 14)
    dashboard.dart             pulpity, widżety, preferencje (pkt 13)
    scene.dart                 sceny i ich akcje
    watch.dart                 zegarki, pulpit zegarka i jego układ (pkt 13a, port layout.js)
    device_info.dart           /api/info
  data/
    thermostat_connection.dart DeviceConnection<S, C> (alias ThermostatConnection), ConnectionKind, LinkStatus
    local_connection.dart      HTTP (Bearer) + WebSocket /ws?token=, ponawianie, ack z timeoutem → HTTP
    cloud_connection.dart      RTDB homes/{h}/devices/{id}: state/config na żywo, commands (by) → lastCommand
    connection_manager.dart    wybór drogi: ostatni IP (1 s) → mDNS → chmura
    local_api.dart             klient HTTP (info, pair, me, describe, clients, state/config/set, wifi/reset, cloud, ota)
    discovery.dart             mDNS _homeauto._tcp (pakiet nsd)
    room_store.dart            pokoje: chmura z kontem, lokalnie bez
    home_repository.dart       domy, domownicy, zaproszenia, uprawnienia
    dashboard_store.dart       pulpity: chmura (z kopią lokalną) albo telefon
    history.dart               historia do wykresów
    scene_store.dart           sceny: chmura (z kopią lokalną) albo telefon
    watch_store.dart           zegarki i pulpity zegarka
    cloud_store.dart, cloud_access.dart, device_store.dart, pairing.dart, local_endpoint.dart, errors.dart
  provisioning/                Bluetooth: protobuf, messages (ESP .proto), aes_ctr_stream, security1,
                               provisioner (przepływ), ble_transport (flutter_blue_plus + backend),
                               softap_transport (HTTP w sieci HA_*, łączenie z siecią przez kanał natywny)
  controllers/                 DeviceController (wspólny, poziom dostępu) → ThermostatController, LightController;
                               DeviceHub (urządzenia domu), HomeSession (bieżący dom), field_errors
  background/                  alarmy (alerts.dart) i WorkManager (alert_worker.dart)
  ui/                          main_screen (HomeGate, zakładki), onboarding_screen, account_menu,
                               dashboard_screen, dashboard_tiles, widget_editor, members_screen, devices_tab,
                               device_tiles, generic_device_screen, point_controls, phones_screen,
                               add_device_screen, ble_setup_screen, pairing_screen, thermostat_screen,
                               schedule_screen, settings_screen, device_admin_section, cloud_link_screen,
                               firmware_screen, watch_screen, widgets
tools/configure.mjs            google-services.json → lib/firebase_options.dart
tool/fake_device.dart          atrapa (CLI); tool/fake/: baza, termostat, światło, mDNS
```

## Bezpieczeństwo

- **Token** (64 hex) leży w `flutter_secure_storage` (Android Keystore / iOS Keychain). `android:allowBackup="false"`.
- **Bluetooth**: przez BLE idą tylko dane szyfrowane sesją z kluczem z PoP, także token z `ha-pair` i hasło WiFi.
  Hasła WiFi aplikacja nie zapisuje.
- **Cleartext HTTP** tylko w sieci lokalnej. `LocalApi` odmawia połączenia z adresem publicznym (`isLocalNetworkHost()`),
  bo `dart:io` nie stosuje `network_security_config`.
- **Baza**: dostęp według domu i `access` (`docs/firebase/database.rules.json`); aplikacja tylko ukrywa
  niedozwolone elementy, uprawnień pilnują reguły i urządzenie.
- **Tokeny telefonów**: każdy telefon ma własny token z poziomem; zgubiony telefon usuwa się w „Telefony”.
- **Uprawnienia Androida**: `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT`; na Androidzie 11 i starszych
  lokalizacja do skanu BLE.
- **iOS** (`Info.plist`): `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices`
  (`_homeauto._tcp`).

## Problemy

- **Gradle: `Unable to establish loopback connection`** (Windows, JDK 17):
  `$env:JAVA_TOOL_OPTIONS='-Djdk.net.unixdomain.tmpdir=C:\TMP\jtmp'` (katalog musi istnieć).
- **Nie widać urządzenia przez Bluetooth**:
  - urządzenie musi być w trybie konfiguracji (na ekranie DODAJ W APLIKACJI);
  - Bluetooth w telefonie musi być włączony;
  - na Androidzie 11 i starszych potrzebna jest też lokalizacja.
- **Nie widać urządzenia w sieci**:
  - ta sama sieć (nie gościnna);
  - router nie może blokować multicastu;
  - zawsze można wpisać adres ręcznie.
