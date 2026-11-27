import 'package:web/web.dart' as web;

String? odczytajUstawienie(String klucz) {
  try {
    return web.window.localStorage.getItem('mapychodzone.$klucz');
  } on Object {
    return null; // tryb prywatny albo zablokowane dane strony
  }
}

void zapiszUstawienie(String klucz, String wartosc) {
  try {
    web.window.localStorage.setItem('mapychodzone.$klucz', wartosc);
  } on Object {
    // bez zapamiętywania
  }
}
