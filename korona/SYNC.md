# Korona – kontrakt danych zegarek ↔ telefon

Dwa elementy łączą aplikację na zegarek (`watch/`) z aplikacją na telefon (`phone/`):
lista szczytów (plik w repo) i zdobycia (Firestore). Zmiany formatu tylko tu, w obu
aplikacjach naraz.

## 1. Lista szczytów: `data/peaks.json`

Jedno źródło prawdy, generowane narzędziem w `tools/` (zegarek dostaje z niego
`watch/utils/peaks.js`, telefon kopiuje plik do swoich assetów). Nie edytuj ręcznie.

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
  (`rysy`, `babia`…), pozostałe `o<id węzła OSM>`, np. `o1236685520`.
- `groups` – do których list należy szczyt (jeden szczyt może być w kilku, np. Turbacz:
  `kgp` + `gorce`). Planowane grupy: `kgp`, `wyspowy`, `sadecki`, `gorce`, `tatry`.
- `counted` w grupie – ile szczytów liczy się do „X / N” (dla KGP 28; warianty nie).
- `variantOf` – tylko KGP: wariant szczytu z listy (rozpoznawany, nie liczy się do 28).
- Opcjonalne: `border`, `note`, `osm`.
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
