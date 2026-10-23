# Aplikacje Zepp OS na Amazfit T-Rex 3

Każda aplikacja ma własny folder i buduje się niezależnie.

| Folder                              | Aplikacja                         |
|-------------------------------------|-----------------------------------|
| [grekot](grekot/README.md)          | GREKOT – napis z efektem 3D        |
| [kolko-krzyzyk](kolko-krzyzyk/README.md) | Kółko i krzyżyk – gra z zegarkiem |
| [saper](saper/README.md)            | Saper – klasyczna gra na okrągłej planszy, 3 poziomy, rekordy |
| [labirynt](labirynt/README.md)      | Labirynt – kulka sterowana przechylaniem zegarka (akcelerometr), dziury, coraz większe plansze |
| [kosci](kosci/README.md)            | Kości – 1–6 kości do planszówek (K6 z oczkami, K4–K20), rzut przyciskiem albo potrząśnięciem, zatrzymywanie kości |
| [szczyty](szczyty/README.md)        | Szczyty – co to za szczyt? Skieruj godzinę 12 na górę: nazwa, wysokość, odległość, sąsiedzi (GPS + kompas, offline, baza OSM) |
| [youtube-subs](youtube-subs/README.md) | YouTube Subs – licznik subskrybentów (zegarek + telefon) |
| [retro-lcd](retro-lcd/README.md)    | Retro LCD – tarcza w stylu starego zegarka cyfrowego |
| [retro-lcd-negatyw](retro-lcd-negatyw/README.md) | Retro LCD Negatyw – ta sama tarcza w negatywie (folder generowany z retro-lcd) |
| [lista-zakupow](lista-zakupow/README.md) | Zakupy – lista zakupów: aplikacja Flutter na telefon + odhaczanie na zegarku (Firebase) |
| [powrot](powrot/README.md)          | Powrót – zapisz miejsce (np. parking) i wróć do niego ze strzałką kompasu (GPS, offline) + aplikacja na telefon (Google Maps, trasa GPX) |
| [korona](korona/README.md)          | Na szczycie – zdobyte szczyty: Korona Gór Polski, Beskid Wyspowy, Sądecki, Gorce, Tatry (652); zegarek rozpoznaje szczyt po GPS i zapisuje datę, własne szczyty, najbliższe ze strzałką + aplikacja na telefon |
| [waga](waga/README.md)              | Waga – poranne ważenie: start od ostatniego pomiaru, −/+ 0,1 kg, wykres 14 dni, historia (offline; telefon z wykresem i Health Connect w planie) |
| [zdjecia](zdjecia/README.md)        | Zdjęcia – najciekawsze zdjęcia z galerii telefonu na zegarku (etap próbny: most 127.0.0.1, pomiar przesyłu) |
| [wspolne](wspolne/README.md)        | kod Fluttera wspólny dla Zakupów i Powrotu (konto, znajomi, udostępnianie) – nie jest osobną aplikacją |

## Zegarek

| Parametr      | Wartość                            |
|---------------|------------------------------------|
| Model         | Amazfit T-Rex 3                    |
| Ekran         | okrągły AMOLED, 480 × 480 px       |
| deviceSource  | 8716545, 8716547 (8716544 – Chiny) |

Aplikacje używają API 3.0 (działa na Zepp OS 3, 4, 5 i 6) i celują we wszystkie
okrągłe zegarki (`"st": "r"` w `app.json`).

## Wymagania

1. [Node.js LTS](https://nodejs.org/)
2. Zeus CLI: `npm i @zeppos/zeus-cli -g`
3. Konto Zepp z ustawionym hasłem (logowanie przez Google nie działa w narzędziach
   deweloperskich; w aplikacji Zepp powiąż e‑mail i ustaw hasło przez „Nie pamiętam hasła”).

## Instalacja na zegarku

W folderze wybranej aplikacji:

```bash
zeus preview
```

Wybierz z listy **Amazfit T-Rex 3** (lista jest długa, przewijaj strzałką w dół),
a potem w aplikacji Zepp na telefonie: **Urządzenie → Ogólne → Tryb dewelopera →
„+” w prawym górnym rogu → Skanuj** i zeskanuj kod QR z terminala.

Tryb dewelopera włącza się raz: **Profil → Ustawienia → O aplikacji** i 7 stuknięć w logo Zepp.
