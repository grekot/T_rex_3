# Trening: aplikacja na telefon

Flutter 3.41, tylko Android, pakiet `pl.grekot.trening`, minSdk 26.

## Polecenia

```bash
flutter pub get
flutter analyze
flutter test
```

APK release (wspólny klucz z `android/key.properties`, poza gitem; bez niego klucz debug):
`build_apk.cmd` → `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`.
Na Windows przy błędzie Gradle „Unable to establish loopback connection” ustaw `TEMP`/`TMP`
na zwykły katalog (np. `C:\TMP\jtmp`).

## Kod

| Folder | Co to jest |
|---|---|
| `lib/plan/` | model `plan.json` i `atlas.json` ze ścisłym odczytem (`json.dart`), sprawdzanie odwołań (`sprawdz.dart`) |
| `lib/silnik/` | czysta logika bez Fluttera: kalendarz z etapami według kryteriów (`kalendarz.dart`), flagi ćwiczeń z wyniku testu kierunkowego i zasięgu bólu (`flagi.dart`), daty w UTC (`daty.dart`) |
| `lib/trening/` | rozpiska sesji na fazy (przygotowanie, powtórzenia, trzymanie, oddechy, przerwy), maszyna prowadzenia z wstrzykiwanym zegarem (`przebieg.dart`), sygnały, propozycja wyniku testu kierunkowego |
| `lib/silnik/sygnalizacja.dart` | sygnalizacja świetlna: strefa z bólu, zasięgu, mrowienia i „czy minęło do rana” |
| `lib/przypomnienia/` | ustawienia przypomnień i wyliczanie listy (trening, przerwy, wyprosty) na najbliższe dni |
| `lib/dane/` | `stan.json` (zapis atomowy + `.bak`; oceny, check-iny, dni wolne, ustawienia), stany okienek kalendarza, `DaneAplikacji`: plan + atlas + stan |
| `lib/ui/` | ekrany: powitanie, Dziś, kalendarz, Więcej, prowadzenie treningu (rysunek, skrót, arkusz „Technika”, ocena po treningu), test kierunkowy, bezpieczeństwo |
| `lib/urzadzenie.dart` + `MainActivity.kt` | kanał `pl.grekot.trening/urzadzenie`: dźwięk (ToneGenerator), wibracja, „ekran nie gaśnie”, katalog aplikacji, przypomnienia, zgoda na powiadomienia, bateria, ekran wybierania 112; bez wtyczek |
| `Przypomnienia.kt` | alarmy AlarmManagera (nieprecyzyjne, `setAndAllowWhileIdle`) z listy wyliczonej w Darcie; lista w SharedPreferences, ponowne ustawienie po restarcie telefonu i aktualizacji |
| `tool/` | `atlas_do_json.dart`: atlas ćwiczeń (Markdown) → `assets/plan/atlas.json` + rysunki |
| `assets/plan/` | dane planu: `plan.json`, `atlas.json`, `img/` |

## Ikona

`python tools/ikona.py` rysuje ikonę (kartka kalendarza z kręgosłupem) i zapisuje ją w
`android/app/src/main/res/mipmap-*` (zwykła i adaptacyjna). Podgląd: `tools/ikona_podglad.png`.

## Uprawnienia

Celowo **brak** `INTERNET`: dane zostają na telefonie. `allowBackup=false`: bez automatycznej
kopii Google; kopia przez ręczny eksport (od wersji 1.0).

| Uprawnienie | Po co |
|---|---|
| `VIBRATE` | sygnały podczas treningu |
| `POST_NOTIFICATIONS` | przypomnienia (Android 13+ pyta o zgodę na ekranie powitania) |
| `RECEIVE_BOOT_COMPLETED` | ponowne ustawienie przypomnień po restarcie telefonu |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | przycisk „Zezwól” w „Więcej”: zwolnienie z oszczędzania baterii, bez którego Samsung usypia przypomnienia |

Bez uprawnienia do dokładnych alarmów: przypomnienie minutę później nie ma znaczenia.

## Przypomnienia

Lista jest liczona w Darcie od nowa przy każdym otwarciu aplikacji i każdej zmianie (trening
zrobiony, dzień wolny, ustawienia): trening na 14 dni, przerwy i wyprosty na 7. Jeśli aplikacja
nie była otwierana przez tydzień, przypomnienia o przerwach się kończą (trening jeszcze tydzień).
