import 'package:flutter_test/flutter_test.dart';
import 'package:trening/przypomnienia/harmonogram.dart';

void main() {
  // wtorek 24.11.2026, 10:05 (czas lokalny)
  final teraz = DateTime(2026, 11, 24, 10, 5);

  List<Przypomnienie> plan({
    UstawieniaPrzypomnien? u,
    DateTime? kiedy,
    bool Function(DateTime)? bez,
    bool pali = false,
    bool wyprosty = false,
  }) =>
      harmonogramPrzypomnien(
        u: u ?? UstawieniaPrzypomnien(),
        teraz: kiedy ?? teraz,
        bezTreningu: bez ?? (_) => false,
        opisTreningu: (_) => 'Kręgosłup 15 min (ok. 15 min)',
        paliDzis: pali,
        wyprostyDozwolone: wyprosty,
      );

  test('trening codziennie o 19:00 przez 14 dni, od dziś', () {
    final t = plan().where((p) => p.kanal == 'trening').toList();
    expect(t, hasLength(dniTreningu));
    expect(t.first.kiedy, DateTime(2026, 11, 24, 19));
    expect(t.last.kiedy, DateTime(2026, 12, 7, 19));
    expect(t.first.tytul, 'Trening');
    expect(t.first.tresc, 'Kręgosłup 15 min (ok. 15 min)');
  });

  test('dzień z treningiem albo wolny: bez przypomnienia; po 19:00 dzisiejsze już nie przychodzi', () {
    final zrobione = plan(bez: (d) => d.day == 24).where((p) => p.kanal == 'trening');
    expect(zrobione.first.kiedy, DateTime(2026, 11, 25, 19));
    final wieczor = plan(kiedy: DateTime(2026, 11, 24, 19, 30)).where((p) => p.kanal == 'trening');
    expect(wieczor.first.kiedy.day, 25);
  });

  test('drugie przypomnienie o 20:30', () {
    final t = plan(u: UstawieniaPrzypomnien(drugie: true)).where((p) => p.kanal == 'trening').toList();
    expect(t, hasLength(2 * dniTreningu));
    expect(t[1].kiedy, DateTime(2026, 11, 24, 20, 30));
  });

  test('przerwy Pn–Pt 8–16 co 40 min, w weekend żadnych, dzisiejsze od teraz', () {
    final p = plan().where((p) => p.kanal == 'przerwy').toList();
    final dzis = p.where((x) => x.kiedy.day == 24).map((x) => x.kiedy).toList();
    expect(dzis.first, DateTime(2026, 11, 24, 10, 40));
    expect(dzis.last, DateTime(2026, 11, 24, 16));
    final sroda = p.where((x) => x.kiedy.day == 25).map((x) => x.kiedy).toList();
    expect(sroda.first, DateTime(2026, 11, 25, 8, 40));
    expect(sroda, hasLength(12));
    expect(p.where((x) => x.kiedy.weekday >= 6), isEmpty);
    // 7 dni naprzód: wt–pt w tym tygodniu i pn w następnym
    expect(p.map((x) => x.kiedy.day).toSet(), {24, 25, 26, 27, 30});
  });

  test('„pali dziś w krzyżu”: dziś przerwy co 25 min od teraz, jutro zwykle', () {
    final p = plan(pali: true).where((p) => p.kanal == 'przerwy').toList();
    final dzis = p.where((x) => x.kiedy.day == 24).map((x) => x.kiedy).toList();
    expect(dzis.take(2), [DateTime(2026, 11, 24, 10, 30), DateTime(2026, 11, 24, 10, 55)]);
    expect(p.firstWhere((x) => x.kiedy.day == 25).kiedy, DateTime(2026, 11, 25, 8, 40));
  });

  test('wyprosty tylko po dobrym teście kierunkowym i gdy włączone', () {
    final u = UstawieniaPrzypomnien(wyprosty: true);
    expect(plan(u: u).where((p) => p.kanal == 'wyprosty'), isEmpty);
    final w = plan(u: u, wyprosty: true).where((p) => p.kanal == 'wyprosty').toList();
    expect(w.where((x) => x.kiedy.day == 24).map((x) => x.kiedy.hour), [11, 14, 17, 20]);
    expect(plan(wyprosty: true).where((p) => p.kanal == 'wyprosty'), isEmpty);
    // po dobrym teście przerwy przypominają też o wyprostach w staniu
    expect(plan(wyprosty: true).firstWhere((p) => p.kanal == 'przerwy').tresc, contains('wyprostów'));
  });

  test('identyfikatory są unikalne, a lista posortowana po czasie', () {
    final p = plan(u: UstawieniaPrzypomnien(drugie: true, wyprosty: true), wyprosty: true, pali: true);
    expect(p.map((x) => x.id).toSet(), hasLength(p.length));
    expect(p.map((x) => x.id), isNot(contains(idTestowe)));
    for (var i = 1; i < p.length; i++) {
      expect(p[i].kiedy.isBefore(p[i - 1].kiedy), isFalse);
    }
    expect(p.length, lessThan(250)); // system pozwala na ok. 500 alarmów na aplikację
  });

  test('wyłączone przypomnienia: pusta lista', () {
    expect(plan(u: UstawieniaPrzypomnien(trening: false, przerwy: false)), isEmpty);
  });

  test('ustawienia: zapis i odczyt, brakujące pola z wartości domyślnych', () {
    final u = UstawieniaPrzypomnien(treningMin: 19 * 60 + 30, przerwyCo: 45, przerwyDni: {1, 3, 5}, wyprosty: true);
    final z = UstawieniaPrzypomnien.zJson(u.toJson());
    expect(z.toJson(), u.toJson());
    expect(z.toJson()['trening'], {'wl': true, 'godz': '19:30', 'drugie': false});
    final d = UstawieniaPrzypomnien.zJson(const {});
    expect(d.toJson(), UstawieniaPrzypomnien().toJson());
  });
}
