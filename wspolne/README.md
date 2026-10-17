# wspolne – kod wspólny aplikacji Zakupy i Powrót (Flutter)

Obie aplikacje na telefon korzystają z tego samego projektu Firebase, więc konto i znajomi są
wspólne. Ten pakiet trzyma to, co w obu wygląda tak samo:

| Plik | Co robi |
|---|---|
| `lib/src/account_repository.dart` | `AccountRepository`: znajomi, książka adresowa `emails`, udostępnianie i opuszczanie (`applySharing`, `leave`) dla dowolnej kolekcji |
| `lib/src/models.dart` | `Shared` (wspólna część listy i miejsca), `Friend`, parsowanie pól |
| `lib/src/sharing.dart` | `planSharing`, `suggestedFriends` – logika bez Firebase (testowana) |
| `lib/src/login_screen.dart` | ekran logowania / zakładania konta |
| `lib/src/friends_screen.dart` | ekran Znajomi z „Proponowanymi” |
| `lib/src/share_sheet.dart` | okno „Udostępnij” (`collection: 'lists'` albo `'places'`) |

Aplikacje dołączają go ścieżką w `pubspec.yaml`:

```yaml
wspolne:
  path: ../../wspolne
```

Testy:

```bash
flutter test
```
