/// Zapis `stan.json` w prywatnym katalogu aplikacji: najpierw plik tymczasowy,
/// potem podmiana; poprzednia wersja zostaje jako `stan.json.bak`.
/// Uszkodzony plik główny → odczyt kopii zapasowej.
library;

import 'dart:convert';
import 'dart:io';

import 'stan.dart';

class Magazyn {
  Magazyn(this.katalog);

  final Directory katalog;

  File get _plik => File('${katalog.path}/stan.json');
  File get _kopia => File('${katalog.path}/stan.json.bak');
  File get _tymczasowy => File('${katalog.path}/stan.json.tmp');

  Future<Stan> wczytaj() async {
    for (final plik in [_plik, _kopia]) {
      if (!await plik.exists()) continue;
      try {
        final json = jsonDecode(await plik.readAsString());
        return Stan.zJson((json as Map).cast<String, Object?>());
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return Stan();
  }

  Future<void> zapisz(Stan stan) async {
    await katalog.create(recursive: true);
    const enkoder = JsonEncoder.withIndent(' ');
    await _tymczasowy.writeAsString(enkoder.convert(stan.toJson()), flush: true);
    if (await _plik.exists()) await _plik.copy(_kopia.path);
    await _tymczasowy.rename(_plik.path);
  }
}
