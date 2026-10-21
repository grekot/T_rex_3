# Na szczycie (folder korona) – kontrakt danych zegarek ↔ telefon

Dwa elementy łączą aplikację na zegarek (`watch/`) z aplikacją na telefon (`phone/`):
lista szczytów (plik w repo) i zdobycia (Firestore). Zmiany formatu tylko tu, w obu
aplikacjach naraz.

## 1. Lista szczytów: `data/peaks.json`

Jedno źródło prawdy, generowane przez `tools/fetch_peaks.mjs` (KGP z `watch/utils/kgp.js`
+ kategorie Wikipedii + współrzędne OSM). Zegarek dostaje z niego `watch/utils/peaks-data.js`
(`tools/build_watch_data.mjs`), telefon kopiuje plik do swoich assetów. Nie edytuj ręcznie.

```json
{
  "version": 1,
  "generated": "2026-10-20",
  "sources": ["..."],
  "groups": [
    { "id": "kgp", "name": "Korona Gór Polski", "short": "KGP", "counted": 28 }
  ],
  "peaks": [
    { "id": "rysy", "name": "Rysy", "h": 2499, "lat": 49.1795756, "lon": 20.0881081,
      "range": "Tatry", "groups": ["kgp", "tatry"], "osm": 4366169405, "border": true }
  ]
}
```

- `id` – stały identyfikator szczytu (klucz zdobycia). 34 szczyty KGP mają nazwy
  (`rysy`, `babia`…), pozostałe `o<id węzła OSM>`, np. `o1843836472` (Ćwilin), a 57 bez
  węzła OSM – `w<id strony Wikipedii>`.
- `groups` – do których list należy szczyt (jeden szczyt może być w kilku, np. Turbacz:
  `kgp` + `gorce`). Grupy: `kgp`, `wyspowy`, `sadecki`, `gorce`, `tatry`; na zegarku
  dochodzi `moje` (własne szczyty z `custom`, nie ma ich w pliku).
- `counted` w grupie – ile szczytów liczy się do „X / N” (dla KGP 28; warianty nie).
- `variantOf` – tylko KGP: wariant szczytu z listy (rozpoznawany, nie liczy się do 28).
- Opcjonalne: `border`, `note`, `osm` (id węzła OSM), `wiki` (tytuł strony w pl.wikipedii,
  nawias rozróżnia powtarzające się nazwy, np. „Kiczora (806 m)”), `r` (promień rozpoznania
  w metrach, gdy mniejszy niż domyślne 120 – tylko dla zegarka).
- `h` – metry n.p.m. (liczba całkowita, może brakować przy szczytach bez wysokości w OSM).

## 2. Zdobycia: Firestore, dokument `korona/{uid}`

Projekt Firebase ten sam co Zakupy i Powrót (`zakupy-8ec54`), to samo konto
(logowanie na zegarku przez ustawienia w aplikacji Zepp, na telefonie przez `wspolne`).

```
korona/{uid}
  climbs:    map  { "<peakId>": { d: "RRRR-MM-DD", gps: bool } }
  custom:    map  { "<customId>": { name: string, lat: number, lon: number,
                                    d: "RRRR-MM-DD", gps: bool } }
  updatedAt: timestamp
  v:         1
```

- **Zegarek jest źródłem prawdy** (wersja 1): Side Service po każdej zmianie zapisuje
  cały dokument (pełny stan `climbs` + `custom`). Telefon tylko czyta.
- `custom` – szczyty dodane ręcznie na zegarku („Dodaj szczyt tutaj”), id `c<ms>`.
- Daty bez stref czasowych: `RRRR-MM-DD` w czasie lokalnym zegarka.
- Reguły: czytać i pisać może tylko właściciel (`request.auth.uid == uid`).
  Firestore ma jeden zestaw reguł na bazę – publikuje się je z
  `App_storage/firebase/firestore.rules` (patrz nagłówek
  `lista-zakupow/firebase/firestore.rules`), blok `korona` trzeba dopisać tam.
