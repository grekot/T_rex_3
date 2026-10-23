# Waga – kontrakt danych zegarek ↔ telefon

Pomiary wagi żyją w dwóch miejscach: w pliku `waga.json` na zegarku i w Firestore.
Zmiany formatu tylko tu, w obu aplikacjach naraz.

Projekt Firebase ten sam co Zakupy, Powrót i Na szczycie (`zakupy-8ec54`), to samo konto
(zegarek loguje się przez ustawienia w aplikacji Zepp, telefon przez `wspolne`).

## Dokument `waga/{uid}`

```
waga/{uid}
  e:         map { "RRRR-MM-DD": { w: int, t: int } }
  goal:      int        (opcjonalnie; cel w dziesiątych kg, ustawia telefon)
  updatedAt: timestamp
  v:         1
```

- `w` – waga w **dziesiątych częściach kilograma** (823 = 82,3 kg), zakres 300–2500.
  **`w: 0` = pomiar usunięty** („nagrobek” – zostaje, żeby druga strona go nie przywróciła).
- `t` – kiedy wpis zmieniono (ms od 1970, zegar urządzenia, które zmieniało).
- Dzień `RRRR-MM-DD` w czasie lokalnym. Jeden pomiar na dzień.

## Scalanie

Obie strony mogą dodawać, poprawiać i usuwać. Dla każdego dnia **wygrywa wpis z większym `t`**
(nagrobek też). Nikt nie nadpisuje całej mapy – zapisuje się tylko zmienione dni:

- **Zegarek** (Side Service): `batchGet` dokumentu → scalenie z plikiem → `commit` z `update`
  i `updateMask.fieldPaths` = `` e.`2026-10-23` `` (dla każdego dnia, w którym zegarek ma nowszy
  wpis) + `updatedAt` + `v`. Scalony stan (z nagrobkami) wraca do pliku na zegarku.
  Synchronizacja przy otwarciu aplikacji i po każdym zapisie, gdy zalogowano.
- **Telefon**: `set({e: {dzień: {w, t}}, updatedAt, v: 1}, merge: true)` – zmienia tylko ten dzień.
  Cel: `set({goal}, merge: true)`.

## Reguły

Czytać i pisać może tylko właściciel (`request.auth.uid == uid`); `e` musi być mapą, `v` liczbą,
`goal` liczbą. Blok `waga` jest w `App_storage/firebase/firestore.rules` (jeden zestaw reguł na
cały projekt).

## Czego tu nie ma

Kalorie, kroki i treningi telefon czyta lokalnie z Health Connect (zapisuje je tam aplikacja
Zepp) – nie trafiają do Firestore ani na zegarek.
