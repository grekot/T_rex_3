/// Błędy warstwy połączenia. `message` jest po polsku i nadaje się do UI.
class ThermostatException implements Exception {
  const ThermostatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 401 - token nie pasuje (np. po resecie fabrycznym termostatu). Trzeba sparować ponownie.
class UnauthorizedException extends ThermostatException {
  const UnauthorizedException() : super('Urządzenie odrzuciło token. Sparuj telefon ponownie.');
}

/// 403 `forbidden` - telefon (token) albo domownik ma za niski poziom dostępu (pkt 12).
class ForbiddenException extends ThermostatException {
  const ForbiddenException()
    : super(
        'Brak uprawnień: do tej zmiany potrzebny jest wyższy poziom dostępu do urządzenia. Poproś właściciela domu.',
      );
}

/// Urządzenie nie odpowiada pod danym adresem.
class UnreachableException extends ThermostatException {
  const UnreachableException([super.message = 'Urządzenie nie odpowiada.']);
}

/// Żadna droga połączenia (lokalna, chmura) nie zadziałała.
class NoRouteException extends ThermostatException {
  const NoRouteException(super.message);
}

/// Błąd parowania; `code` to pole `error` z odpowiedzi termostatu.
class PairingException extends ThermostatException {
  const PairingException(this.code, super.message, {this.attemptsLeft, this.retryIn});

  final String? code;

  /// Przy `locked` (429): po ilu sekundach można zacząć parowanie od nowa.
  final int? retryIn;

  /// Przy `bad_code`: ile prób zostało; 0 = parowanie przerwane.
  final int? attemptsLeft;

  /// Czy parowanie trzeba zacząć od nowa (nowy kod na ekranie urządzenia).
  bool get mustRestart => code != 'bad_code' || attemptsLeft == 0;

  factory PairingException.fromCode(String? code, {int? attemptsLeft, int? retryIn}) {
    final message = switch (code) {
      'locked' when retryIn != null => 'Parowanie zablokowane po 3 złych kodach. Spróbuj za $retryIn s.',
      'locked' => 'Parowanie chwilowo zablokowane po 3 złych kodach. Spróbuj za minutę.',
      'bad_code' when attemptsLeft == 0 => 'Za dużo błędnych prób. Rozpocznij parowanie od nowa.',
      'bad_code' when attemptsLeft != null =>
        'Nieprawidłowy kod. ${attemptsLeft == 1 ? 'Została 1 próba' : 'Zostały $attemptsLeft próby'}.',
      'bad_code' => 'Nieprawidłowy kod.',
      'not_pairing' => 'Kod wygasł albo parowanie nie jest aktywne. Rozpocznij je od nowa.',
      'json' => 'Urządzenie nie zrozumiało żądania.',
      'busy' => 'Urządzenie jest zajęte, spróbuj za chwilę.',
      'too_many_clients' => 'Urządzenie ma już 16 telefonów. Usuń któryś w jego ustawieniach → Telefony.',
      null || '' => 'Parowanie nie powiodło się.',
      _ => 'Parowanie nie powiodło się ($code).',
    };
    return PairingException(code, message, attemptsLeft: attemptsLeft, retryIn: retryIn);
  }
}

/// Pole `error` odpowiedzi termostatu (`{"ok":false,"error":...}`) → tekst po polsku.
String describeApiError(String? code) => switch (code) {
  'busy' => 'Urządzenie jest zajęte, spróbuj za chwilę.',
  'timeout' => 'Urządzenie nie potwierdziło polecenia. Jeśli odezwie się w ciągu 10 minut, wykona je z opóźnieniem.',
  'forbidden' => 'Brak uprawnień do tej zmiany - poproś właściciela domu o wyższy poziom dostępu.',
  'too_many_clients' => 'Urządzenie ma już 16 telefonów. Usuń któryś w ustawieniach → Telefony.',
  'auth' => 'Urządzenie nie mogło zalogować się do chmury.',
  'expired' => 'Polecenie wygasło: urządzenie nie odebrało go w ciągu 10 minut.',
  'not_implemented' => 'Urządzenie jeszcze tego nie obsługuje (zaktualizuj oprogramowanie).',
  'not_found' => 'Urządzenie nie zna tego polecenia - może ma za starą wersję oprogramowania.',
  'json' => 'Urządzenie nie zrozumiało żądania.',
  'unauthorized' => 'Urządzenie odrzuciło token. Sparuj telefon ponownie.',
  null || '' => 'Urządzenie zgłosiło błąd.',
  _ => 'Urządzenie zgłosiło błąd ($code).',
};
