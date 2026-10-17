# Konfiguracja Firebase (jednorazowo, ok. 10 minut)

Wszystko robisz w przeglądarce, zalogowany swoim kontem Google. Darmowy plan
(Spark) w zupełności wystarczy – nie trzeba podawać karty.

## 1. Projekt

1. Otwórz <https://console.firebase.google.com/> → **Utwórz projekt**.
2. Nazwa np. `zakupy`. Google Analytics możesz **wyłączyć** (niepotrzebne).

## 2. Logowanie e-mailem

1. W menu po lewej: **Kompilacja → Authentication → Rozpocznij**.
2. Zakładka **Metoda logowania** → **E-mail/hasło** → włącz **pierwszy** przełącznik
   (E-mail/hasło), drugiego (link w e-mailu) nie trzeba → **Zapisz**.

## 3. Baza danych Firestore

1. **Kompilacja → Firestore Database → Utwórz bazę danych**.
2. Lokalizacja: `europe-central2 (Warszawa)` – albo dowolna europejska.
3. Tryb: **produkcyjny**.
4. Po utworzeniu przejdź do zakładki **Reguły**, usuń całą zawartość, wklej
   zawartość pliku [`firestore.rules`](firestore.rules) z tego folderu → **Opublikuj**.

## 4. Aplikacja Android

1. Kliknij koło zębate obok „Przegląd projektu” → **Ustawienia projektu**.
2. Na dole, w sekcji **Twoje aplikacje**, kliknij ikonę **Android**.
3. Nazwa pakietu Androida: **`pl.grekot.zakupy`** (dokładnie tak). Pseudonim: `Zakupy`.
   SHA-1 nie jest potrzebny → **Zarejestruj aplikację**.
4. **Pobierz `google-services.json`** i zapisz go jako:

   ```
   C:\TMP\My_GIT\T_rex_3\lista-zakupow\phone\android\app\google-services.json
   ```

5. Kolejne kroki kreatora (dodawanie SDK) pomiń – kliknij **Dalej** aż do końca.

Plik `google-services.json` zawiera identyfikatory projektu (m.in. klucz API Firebase).
To nie jest tajne hasło – dostęp do danych chronią reguły z punktu 3 – ale nie publikuj
go niepotrzebnie.

## 5. (Opcjonalnie) Rozpoznawanie zdjęć przez AI – Gemini

1. W menu po lewej: **AI services → AI Logic → Get started**.
2. Wybierz **Gemini Developer API** (bez płatności) i przejdź kreator do końca. Kroków
   z dodawaniem SDK nie trzeba wykonywać – aplikacja ma to już w kodzie.
3. Kreator włącza **App Check** dla AI Logic, którego aplikacja instalowana z pliku APK nie
   przejdzie. Wyłącz wymuszanie: **Security → App Check → zakładka APIs → Firebase AI Logic →
   Unenforce**. Na planie Spark nie grozi to żadnymi kosztami (gdyby projekt kiedyś przeszedł
   na płatny plan Blaze, warto App Check skonfigurować).

## 6. Daj znać

Po zapisaniu `google-services.json` napisz, że gotowe. Skrypt
[`../tools/configure.mjs`](../tools/configure.mjs) przepisze z niego konfigurację do
aplikacji na telefon i na zegarek.
