import 'package:flutter_test/flutter_test.dart';
import 'package:trening/silnik/flagi.dart';
import 'package:trening/trening/test_kierunkowy.dart';

void main() {
  WynikTestu w(int bp, Zasieg zp, int bpo, Zasieg zpo, {bool mrowienie = false}) =>
      proponujWynik(bolPrzed: bp, zasiegPrzed: zp, bolPo: bpo, zasiegPo: zpo, mrowienie: mrowienie);

  test('palenie zmalało → lepiej', () => expect(w(4, Zasieg.brak, 2, Zasieg.brak), WynikTestu.lepiej));

  test('ból z pośladka cofnął się do krzyża → lepiej, nawet gdy krzyż boli tak samo',
      () => expect(w(3, Zasieg.posladek, 4, Zasieg.brak), WynikTestu.lepiej));

  test('bez zmian → bez zmian', () => expect(w(3, Zasieg.brak, 3, Zasieg.brak), WynikTestu.bezZmian));

  test('o 1 punkt więcej to jeszcze nie „wyraźnie” → bez zmian',
      () => expect(w(3, Zasieg.brak, 4, Zasieg.brak), WynikTestu.bezZmian));

  test('wyraźnie mocniej → gorzej', () => expect(w(3, Zasieg.brak, 5, Zasieg.brak), WynikTestu.gorzej));

  test('zeszło do pośladka → gorzej, nawet gdy krzyż boli mniej',
      () => expect(w(5, Zasieg.brak, 2, Zasieg.posladek), WynikTestu.gorzej));

  test('mrowienie → gorzej', () => expect(w(4, Zasieg.brak, 2, Zasieg.brak, mrowienie: true), WynikTestu.gorzej));
}
