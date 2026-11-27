import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Postęp pobierania: pobrane bajty i całość (null, gdy serwer nie podał długości).
typedef Postep = void Function(int pobrane, int? calosc);

class BladPobierania implements Exception {
  BladPobierania(this.komunikat);
  final String komunikat;
  @override
  String toString() => komunikat;
}

HttpClient nowyKlient() => HttpClient()
  ..userAgent = 'MapyChodzone (Android)'
  ..connectionTimeout = const Duration(seconds: 20);

/// Rozmiar pliku pod adresem (HEAD), null gdy serwer go nie podaje.
Future<int?> rozmiarPliku(String url, {HttpClient? klient}) async {
  final k = klient ?? nowyKlient();
  try {
    final req = await k.headUrl(Uri.parse(url));
    final res = await req.close();
    await res.drain<void>();
    if (res.statusCode != 200) return null;
    return res.contentLength >= 0 ? res.contentLength : null;
  } finally {
    if (klient == null) k.close();
  }
}

/// Pobiera tekst (np. katalog.json).
Future<String> pobierzTekst(String url, {HttpClient? klient}) async {
  final k = klient ?? nowyKlient();
  try {
    final req = await k.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw BladPobierania('Serwer odpowiedział ${res.statusCode} dla $url');
    }
    return await res.transform(utf8.decoder).join();
  } finally {
    if (klient == null) k.close();
  }
}

/// Pobiera plik do `cel` przez plik tymczasowy `cel.part`. Gdy podano [rozmiar] albo [sha256],
/// sprawdza je przed podmianą. Przy błędzie plik docelowy zostaje nietknięty.
Future<void> pobierzPlik(
  String url,
  String cel, {
  int? rozmiar,
  String? sha256,
  Postep? postep,
  HttpClient? klient,
}) async {
  final k = klient ?? nowyKlient();
  final tymczasowy = File('$cel.part');
  await tymczasowy.parent.create(recursive: true);
  IOSink? zapis;
  try {
    final req = await k.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw BladPobierania('Serwer odpowiedział ${res.statusCode} dla $url');
    }
    final calosc = res.contentLength >= 0 ? res.contentLength : rozmiar;
    final zbieracz = _Zbieracz();
    final hasz = crypto.sha256.startChunkedConversion(zbieracz);
    zapis = tymczasowy.openWrite();
    var pobrane = 0;
    var ostatniPostep = DateTime.fromMillisecondsSinceEpoch(0);
    await for (final kawalek in res) {
      zapis.add(kawalek);
      hasz.add(kawalek);
      pobrane += kawalek.length;
      final teraz = DateTime.now();
      if (postep != null && teraz.difference(ostatniPostep).inMilliseconds >= 200) {
        ostatniPostep = teraz;
        postep(pobrane, calosc);
      }
    }
    await zapis.flush();
    await zapis.close();
    zapis = null;
    hasz.close();
    postep?.call(pobrane, calosc);

    if (rozmiar != null && pobrane != rozmiar) {
      throw BladPobierania('Niepełny plik ${_nazwa(cel)}: $pobrane z $rozmiar bajtów');
    }
    if (sha256 != null && zbieracz.wynik.toString() != sha256) {
      throw BladPobierania('Uszkodzony plik ${_nazwa(cel)} (suma SHA-256 się nie zgadza)');
    }
    await tymczasowy.rename(cel);
  } catch (_) {
    await zapis?.close();
    if (tymczasowy.existsSync()) await tymczasowy.delete();
    rethrow;
  } finally {
    if (klient == null) k.close();
  }
}

String _nazwa(String sciezka) => sciezka.split('/').last;

class _Zbieracz implements Sink<crypto.Digest> {
  crypto.Digest? wynik;
  @override
  void add(crypto.Digest data) => wynik = data;
  @override
  void close() {}
}

/// „69,8 MB”
String megabajty(int bajty) {
  final mb = bajty / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} MB';
}
