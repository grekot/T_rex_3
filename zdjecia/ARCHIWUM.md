# Archiwum zdjęć w Firestore

Najciekawsze zdjęcia z całej biblioteki Zdjęć Google (eksport Takeout), wybrane na PC
i trzymane w Firestore (projekt `zakupy-8ec54`). Telefon („Zdjęcia”) bierze z nich wspomnienia
dla zegarka i strumień dla zegarów HomeAutomation, ściągając tylko te zdjęcia, których akurat potrzebuje.

```
Takeout (ZIP-y na PC) → tools/archiwum (skan, odsiew, arkusze do przeglądu, eksport ≤ 800×600)
        ↓ wysyłka kontem właściciela (REST, logowanie e-mail + hasło wpisane przez właściciela)
Firestore archiwum/{uid}  +  archiwum/{uid}/zdjecia/{id}
        ↓ telefon: spis raz na odświeżenie, pojedyncze zdjęcia na żądanie (pamięć podręczna w plikach)
Pula zegarka (wspomnienia)  +  strumień zegarów biurkowych (/clocks.json)
```

## Dokumenty

`archiwum/{uid}` - spis (jeden odczyt na sprawdzenie):

| Pole        | Typ       | Opis                                                        |
|-------------|-----------|-------------------------------------------------------------|
| `v`         | number    | wersja formatu, teraz `1`                                   |
| `count`     | number    | liczba zdjęć w spisie                                       |
| `updatedAt` | timestamp | ostatnia wysyłka (telefon pobiera spis od nowa, gdy się zmieni) |
| `items`     | string    | JSON - lista wpisów (niżej); jako tekst, żeby Firestore nie indeksował tysięcy pól |

Wpis w `items`:

```json
{"id": "3f9a0c1d2e4b", "t": 1404390000000, "c": "Nad Morskim Okiem", "s": 8, "w": 800, "h": 600,
 "f": [0.30, 0.20, 0.40, 0.50], "m": [0.10, 0.15, 0.80, 0.70]}
```

| Klucz | Opis |
|-------|------|
| `id`  | 12 znaków `[0-9a-f]` - skrót z daty, nazwy pliku i rozmiaru w Takeout (stały przy ponownym skanie) |
| `t`   | kiedy zrobione (ms od 1970, z `photoTakenTime` w JSON-ie Takeoutu) |
| `c`   | krótki podpis po polsku (≤ 28 znaków; zegarek dopisuje „ · rok”), może być pusty |
| `s`   | ocena 1-10 (jak ocena AI w telefonie) |
| `w`, `h` | wymiary JPEG-a po zmniejszeniu |
| `f`   | opcjonalnie: najciekawszy fragment - left, top, width, height (ułamki zdjęcia) - jak `focus` od Gemini |
| `m`   | opcjonalnie: główny motyw - jak `subject` od Gemini |

`archiwum/{uid}/zdjecia/{id}`:

| Pole   | Typ    | Opis |
|--------|--------|------|
| `jpeg` | bytes  | JPEG baseline, dłuższy bok ≤ 800 px, krótszy ≤ 600 px, bez EXIF (bez GPS), ≤ 300 KB |
| `t`    | number | jak w spisie |

Reguły (`App_storage/firebase/firestore.rules`): czyta, zapisuje i usuwa tylko właściciel (`uid`),
`items` musi być tekstem, `jpeg` bajtami do 300 KB.

## Limity planu Spark

1000 zdjęć po ~100 KB = ~100 MB z 1 GiB na cały projekt. Wysyłka = ~1000 zapisów (limit 20 000 dziennie).
Telefon: 1 odczyt spisu na odświeżenie + 1 odczyt na każde nowe zdjęcie (kilkadziesiąt dziennie).

## Telefon

- Id zdjęcia w puli: `a_<id>`, w galerii (`assetId`): `archiwum:<id>`.
- Zdjęcie z archiwum przechodzi tę samą analizę na telefonie (twarze, pasy ciekawości - do kadrów),
  ale **nie idzie do Gemini**: ocena, podpis i fragment są ze spisu.
- Wspomnienia biorą się z archiwum, gdy jest spis; bez konta / bez spisu - jak dotąd z historii galerii.
- Zdjęcie wraca do puli najwcześniej po `archiveRest` (pokazane dawno - pierwsze w kolejce).
