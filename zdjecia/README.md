# Zdjęcia

Najciekawsze zdjęcia z galerii telefonu losowo pokazywane na zegarku.

Teraz jest tu **etap 0 – próba**. Sprawdza dwie rzeczy, od których zależy cały pomysł:

1. czy aplikacja Zepp na telefonie może pobierać pliki z **mostu lokalnego** (`http://127.0.0.1:8765`),
   czyli z aplikacji „Zdjęcia” na tym samym telefonie – bez chmury i bez konta,
2. ile waży zdjęcie po konwersji do formatu zegarka i ile trwa jego przesłanie przez Bluetooth
   (od tego zależy, ile zdjęć zmieści się w puli na zegarku).

## Jak to działa

```
Telefon: aplikacja „Zdjęcia” (Flutter)
  ostatnie zdjęcia z galerii → kwadrat ze środka → PNG 480×480 (czarne narożniki)
  serwer tylko pod 127.0.0.1:8765:  /manifest.json  i  /p/<id>.png
        ↓  ten sam telefon
Side Service w aplikacji Zepp: lista → pobranie PNG → image.convert → TransferFile
        ↓  Bluetooth
Zegarek: odbiór do data://download/zd_<id>.png → IMG na cały ekran
```

Zdjęcia Google nie wchodzą w grę: od 31.03.2025 Google Photos API nie daje dostępu do biblioteki
(tylko ręczny wybór w Pickerze), a Ambient API jest wyłącznie dla firm partnerskich.
Dlatego źródłem jest galeria telefonu (te same zdjęcia, które Google Photos kopiuje do chmury).

| Folder   | Co to                                                          |
|----------|----------------------------------------------------------------|
| `watch/` | aplikacja na zegarek (zeus, appId 1087163, API 3.0)             |
| `phone/` | aplikacja na telefon (Flutter, `pl.grekot.zdjecia`)             |

## Test etapu 0

**Telefon**

1. Zainstaluj „Zdjęcia” ze **Sklepu rodzinnego** albo ręcznie
   `phone/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (budowanie: `phone/build_apk.cmd`).
2. Otwórz „Zdjęcia” → **Weź ostatnie** (domyślnie 3) → zezwól na dostęp do zdjęć.
   Przy każdym zdjęciu widać rozmiar PNG.
3. Włącz **Udostępnij zegarkowi** → **Sprawdź serwer** powinno pokazać „OK”.
   Zostaw aplikację otwartą – ekran telefonu nie zgaśnie, dopóki serwer działa.

**Zegarek**

1. W folderze `watch/`: `zeus preview` → Amazfit T-Rex 3 → kod QR w aplikacji Zepp.
2. Na zegarku otwórz **Zdjęcia** i naciśnij **Test sieci** – pobiera obrazek z internetu
   i przechodzi cały łańcuch (pobranie → konwersja → przesłanie) bez mostu.
3. Naciśnij **Pobierz z telefonu**. Status pokazuje kolejne kroki, a po każdym zdjęciu:
   rozmiar na zegarku, czas konwersji i czas przesłania (BT).
4. **Pokaż zdjęcia** – stuknięcie w zdjęcie = następne. Jeśli zamiast zdjęcia jest czarny ekran,
   naciskaj **ścieżka** (różne zapisy ścieżki pliku), aż zdjęcie się pojawi – wybór się zapamiętuje.
   **Wyczyść** usuwa zdjęcia z zegarka, żeby powtórzyć próbę.

**Co zgłosić**: linie z panelu zegarka (średni rozmiar i czas BT), która „ścieżka” zadziałała,
i czy w aplikacji na telefonie w „Zapytania z aplikacji Zepp” pojawiły się wpisy.

## Próba 0b: powiadomienie „Zobacz to”

Docelowo zegarek sam, o losowych porach, pokazuje powiadomienie, a „Pokaż” otwiera ciekawe zdjęcie.
Łańcuch: budzik systemowy (`@zos/alarm`) → usługa w tle `app-service/notify` (600 ms, bez ekranu)
→ powiadomienie (`@zos/notification`) z przyciskiem „Pokaż” → ekran `page/gt/photo`.
Dokumentacja mówi, że przycisk powiadomienia uruchamia usługę, a nie ekran, więc próbujemy trzech sposobów:

| Sposób | Przycisk „Pokaż” uruchamia | Ekran zdjęcia otwiera |
|--------|----------------------------|-----------------------|
| A | wprost ekran `page/gt/photo/index.page` | system (o ile pozwoli) |
| B | usługę `app-service/open_b` | `launchApp` z usługi |
| C | usługę `app-service/open_c` | budzik za 1 s z adresem ekranu (opisana w dokumentacji droga) |

Na zegarku: **Powiadomienia** → **Sposób A (za 30 s)** → wyjdź z aplikacji (przesunięcie w prawo) →
po 30 s powiadomienie → **Pokaż**. Ekran zdjęcia pokazuje na dole „Sposób A”, jeśli zadziałało.
To samo dla B i C. Po wejściu w Powiadomienia widać wyniki: „A: otwarto 13:05:09” albo „jeszcze nie”.
**Od razu (C)** wysyła powiadomienie bez budzika – oddziela problem z budzikiem od problemu z powiadomieniem.
Błędy usług przychodzą jako osobne powiadomienia „Zdjęcia: …”.

**Wynik 0b:** działają wszystkie trzy sposoby (przed zdjęciem na chwilę mignie tarcza). Bez powiadomienia
ma działać **sposób D**: budzik otwiera wprost ekran zdjęcia, zegarek krótko wibruje, a po 15 s sam
wraca do tarczy. Pierwsze stuknięcie zatrzymuje zamykanie, kolejne pokazują następne zdjęcia.

## Diagnoza

| Objaw | Znaczenie |
|-------|-----------|
| Zegarek: „Most niedostępny”, na telefonie brak zapytań | Zepp nie łączy się z 127.0.0.1 – plan B: pliki w Firebase Storage |
| Na telefonie jest `GET /manifest.json`, ale nie ma `GET /p/...` | lista działa (fetch), a pobieranie plików (downloader) nie |
| „Test sieci” też kończy się błędem | problem z pobieraniem/konwersją/przesyłem w Zepp, nie z mostem |
| Zdjęcia doszły, ale żadna „ścieżka” ich nie pokazuje | IMG nie czyta plików z `data://download` – trzeba innego sposobu wyświetlania |

## Etap 1: telefon wybiera najciekawsze zdjęcia

Wszystko na telefonie, bez internetu (`phone/lib/select/` – czysta logika z testami, `phone/lib/media/` – galeria i ML Kit):

1. **Kandydaci**: zdjęcia z aparatu (folder `DCIM`, bez zrzutów ekranu i komunikatorów) z ostatnich 30 dni
   plus ulubione z innych folderów.
2. **Jakość** na miniaturze 256 px: ostrość (wariancja laplasjanu), jasność, prześwietlenia, kolorowość,
   odcisk dHash. Ostrość i kolorowość liczone względem pozostałych zdjęć z okresu (centyl) – 12% najmniej
   ostrych odpada.
3. **Treść** (ML Kit na miniaturze 512 px): twarze z uśmiechem i otwartymi oczami, etykiety (zwierzę, święto,
   krajobraz, zachód słońca…), a gdy nie ma twarzy – ilość tekstu. Paragony, kartki, dokumenty i zrzuty odpadają.
4. **Pula 20 zdjęć**: punkty + premia za ulubione i świeżość; z serii podobnych ujęć tylko najlepsze;
   najwyżej 2 zdjęcia z dnia, z różnych wydarzeń (≥ 2 h odstępu); gdy brakuje zdjęć, zasady łagodnieją.
5. **Kadr pod koło**: twarze z ramionami mieszczą się w kole (nie tylko w kwadracie), bez twarzy – najciekawszy
   pas zdjęcia; PNG z miniatury 1600 px, więc przybliżenie jest ostre. Kadr da się poprawić palcami.

Wyniki analizy są zapamiętywane (`analysis.json`), więc kolejne odświeżenia analizują tylko nowe zdjęcia.

**Ocena przez AI (od 0.3.0).** Sama punktacja z telefonu wybierała słabo (nie odróżnia wspomnień od zdjęć
„praktycznych”), więc decyduje Gemini – tak jak w EscapeRoom: klucz z Google AI Studio wpisany w aplikacji
(ikona ✨), trzymany w zaszyfrowanym magazynie Androida (`flutter_secure_storage`), zapytania wprost do
`generativelanguage.googleapis.com` (`phone/lib/ai/`). Telefon najpierw odsiewa nieostre zdjęcia, dokumenty
i serie, potem Gemini ocenia miniatury 512 px po 12 w zapytaniu (przerwa 4 s, ponawianie przy limicie)
i zwraca ocenę 1–10, „nadaje się / nie”, kategorię, polski podpis i prostokąt głównego motywu (kadr).
Preferencje właściciela („co lubię / czego nie chcę”) są dopisywane do polecenia; ich zmiana albo zmiana
modelu = ocena od nowa. Oceny w `ratings.json`. Bez klucza zostaje punktacja z telefonu.
Przy kluczu bez płatności w AI Studio obowiązują warunki darmowego Gemini API (Google może używać treści
do ulepszania usług).
Na ekranie: pula w okrągłych podglądach z powodem wyboru, przypinanie, usuwanie, poprawa kadru,
ręczne dodawanie zdjęć z galerii i ustawienia (dni, wielkość puli).

## Wydanie do Sklepu rodzinnego

Tag `zdjecia-vX.Y.Z` uruchamia [release-zdjecia.yml](../.github/workflows/release-zdjecia.yml)
(wspólny workflow z `grekot/App_storage`): APK arm64 podpisany wspólnym kluczem trafia do GitHub Release
jako `zdjecia.apk`, a wersja do biblioteki sklepu. Do grup przypisuje administrator:
`sklep przypisz zdjecia --grupa Ja`.

## Testy

```bash
cd watch && npm test
```

```bash
cd phone && flutter test
```
