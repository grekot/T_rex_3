import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapychodzone/dane/katalog.dart';
import 'package:mapychodzone/dane/magazyn.dart';

/// Dwa sąsiednie regiony ze wspólnym plikiem tras E20_N45 (jak Gorce i Tatry).
Katalog _katalog() {
  Map<String, dynamic> plik(String nazwa, int rozmiar) => {'plik': nazwa, 'rozmiar': rozmiar, 'sha256': 'x'};
  Map<String, dynamic> region(String id, List<String> rd5) => {
        'id': id,
        'nazwa': id,
        'bbox': [19.5, 49.0, 20.7, 49.9],
        'mapa': plik('$id.pmtiles', 3),
        'szlaki': plik('$id-szlaki.geojson', 2),
        'punkty': plik('$id-punkty.geojson', 1),
        'rd5': rd5,
      };
  return Katalog.zJson({
    'wersja': 1,
    'format': 2,
    'wydanie': 'dane-test',
    'daneOsm': '2026-11-27',
    'styl': plik('styl.json', 4),
    'rd5Zrodlo': 'https://brouter.de/brouter/segments4/',
    'regiony': [
      region('gorce', ['E15_N45', 'E20_N45']),
      region('tatry', ['E20_N45']),
    ],
  });
}

void main() {
  late Directory katalog;
  late Magazyn m;
  final k = _katalog();
  final gorce = k.region('gorce')!;
  final tatry = k.region('tatry')!;

  void zapisz(String sciezka, int rozmiar) {
    File(sciezka)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(rozmiar, 0));
  }

  void pobierz(RegionPaczki r) {
    zapisz(m.plikStylu, k.styl.rozmiar);
    for (final p in r.pliki) {
      zapisz(m.plikMapy(p.plik), p.rozmiar);
    }
    for (final n in r.rd5) {
      zapisz(m.plikRd5(n), 10);
    }
  }

  setUp(() {
    katalog = Directory.systemTemp.createTempSync('mapychodzone_');
    m = Magazyn(katalog.path.replaceAll(r'\', '/'));
  });
  tearDown(() => katalog.deleteSync(recursive: true));

  test('kilka regionów na telefonie, aktywny otwiera się na starcie', () async {
    expect(m.gotoweRegiony(k), isEmpty);
    pobierz(gorce);
    pobierz(tatry);
    expect(m.gotoweRegiony(k).map((r) => r.id), ['gorce', 'tatry']);
    await File(m.plikKatalogu).writeAsString('''
{"wersja":1,"format":$wymaganyFormatPaczek,"wydanie":"dane-test","daneOsm":"2026-11-27",
 "styl":{"plik":"styl.json","rozmiar":4,"sha256":"x"},"rd5Zrodlo":"https://brouter.de/brouter/segments4/",
 "regiony":[${['gorce', 'tatry'].map((id) => '''
  {"id":"$id","nazwa":"$id","bbox":[19.5,49.0,20.7,49.9],"rd5":["E20_N45"],
   "mapa":{"plik":"$id.pmtiles","rozmiar":3,"sha256":"x"},
   "szlaki":{"plik":"$id-szlaki.geojson","rozmiar":2,"sha256":"x"},
   "punkty":{"plik":"$id-punkty.geojson","rozmiar":1,"sha256":"x"}}''').join(',')}]}''');
    expect(m.gotowyRegion()?.id, 'gorce');
    await m.ustawAktywny('tatry');
    expect(m.gotowyRegion()?.id, 'tatry');
    expect(m.zajeteMiejsce(tatry), 6);
  });

  test('usunięcie regionu zostawia wspólne dane tras', () async {
    pobierz(gorce);
    pobierz(tatry);
    await m.usunRegion(k, gorce);
    expect(m.regionCzesciowo(gorce), isFalse);
    expect(m.gotoweRegiony(k).map((r) => r.id), ['tatry']);
    // E20_N45 potrzebny Tatrom zostaje, E15_N45 był tylko dla Gorców
    expect(File(m.plikRd5('E20_N45')).existsSync(), isTrue);
    expect(File(m.plikRd5('E15_N45')).existsSync(), isFalse);
    await m.usunRegion(k, tatry);
    expect(File(m.plikRd5('E20_N45')).existsSync(), isFalse);
  });

  test('region bez kompletu plików (np. stara wersja) jest „częściowo”, nie gotowy', () {
    pobierz(gorce);
    File(m.plikMapy(gorce.mapa.plik)).writeAsBytesSync([1]);
    expect(m.regionGotowy(k, gorce), isFalse);
    expect(m.regionCzesciowo(gorce), isTrue);
  });
}
