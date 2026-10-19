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

1. Zainstaluj `phone/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
   (budowanie: `phone/build_apk.cmd`).
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

## Diagnoza

| Objaw | Znaczenie |
|-------|-----------|
| Zegarek: „Most niedostępny”, na telefonie brak zapytań | Zepp nie łączy się z 127.0.0.1 – plan B: pliki w Firebase Storage |
| Na telefonie jest `GET /manifest.json`, ale nie ma `GET /p/...` | lista działa (fetch), a pobieranie plików (downloader) nie |
| „Test sieci” też kończy się błędem | problem z pobieraniem/konwersją/przesyłem w Zepp, nie z mostem |
| Zdjęcia doszły, ale żadna „ścieżka” ich nie pokazuje | IMG nie czyta plików z `data://download` – trzeba innego sposobu wyświetlania |

## Testy

```bash
cd watch && npm test
```

```bash
cd phone && flutter test
```
