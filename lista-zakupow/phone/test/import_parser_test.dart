import 'package:flutter_test/flutter_test.dart';
import 'package:zakupy/import/parser.dart';
import 'package:zakupy/import/products_pl.dart';
import 'package:zakupy/models.dart';

ShoppingItem item(String name, {bool checked = false}) => ShoppingItem(id: name, name: name, checked: checked);

void main() {
  test('stripDiacritics i matchKey', () {
    expect(stripDiacritics('Żółć Łąka'), 'Zolc Laka');
    expect(matchKey('  Masło  Ekstra '), 'maslo ekstra');
  });

  test('editDistance', () {
    expect(editDistance('mleko', 'mleko'), 0);
    expect(editDistance('mieko', 'mleko'), 1);
    expect(editDistance('chlep', 'chleb'), 1);
    expect(editDistance('', 'abc'), 3);
  });

  test('cleanLine usuwa punktory, numerację i śmieci', () {
    expect(cleanLine('- mleko'), 'Mleko');
    expect(cleanLine('• chleb razowy.'), 'Chleb razowy');
    expect(cleanLine('1. masło'), 'Masło');
    expect(cleanLine('2) jajka 10 szt'), 'Jajka 10 szt');
    expect(cleanLine('[ ] ser'), 'Ser');
    expect(cleanLine('[x] woda'), 'Woda');
    expect(cleanLine('a) cukier'), 'Cukier');
    expect(cleanLine('2 mleka'), '2 mleka', reason: 'liczba bez kropki to ilość - zostaje');
    expect(cleanLine('   '), isNull);
    expect(cleanLine('123'), isNull);
    expect(cleanLine('-'), isNull);
    expect(cleanLine('x'), isNull);
  });

  test('splitCandidates: linie, przecinki, średniki, ale nie "2,5 kg"', () {
    expect(splitCandidates('mleko, chleb; masło\n- ser 2,5 kg\n\n3. woda'), ['Mleko', 'Chleb', 'Masło', 'Ser 2,5 kg', 'Woda']);
    expect(splitCandidates('ziemniaki\r\ncebula'), ['Ziemniaki', 'Cebula']);
  });

  group('autokorekta', () {
    final vocab = Vocabulary(['Mleko 2%', 'Pomidory koktajlowe'], commonProducts);

    test('brak ogonków i wielkość liter', () {
      expect(vocab.correct('maslo'), 'Masło');
      expect(vocab.correct('SMIETANA'), 'Śmietana');
    });

    test('pomylone litery', () {
      expect(vocab.correct('Mieko'), 'Mleko');
      expect(vocab.correct('Chlep'), 'Chleb');
      expect(vocab.correct('Ziemniakl'), 'Ziemniaki');
      expect(vocab.correct('Papler toaletowy'), 'Papier toaletowy');
    });

    test('historia ma pierwszeństwo', () {
      expect(vocab.correct('mleko 2%'), 'Mleko 2%');
      expect(vocab.correct('Pomidory koktajIowe'), 'Pomidory koktajlowe');
    });

    test('słowo po słowie z zachowaniem reszty', () {
      expect(vocab.correct('Mieko 3,2%'), 'Mleko 3,2%');
    });

    test('nieznane zostaje bez zmian, krótkich słów nie "poprawiamy" na siłę', () {
      expect(vocab.correct('Klej do tapet'), 'Klej do tapet');
      expect(vocab.correct('Klej'), 'Klej');
      expect(vocab.correct('Xyz'), 'Xyz');
      expect(vocab.correct('sol'), 'Sól', reason: 'same ogonki - także w krótkich słowach');
    });
  });

  test('planImport: poprawia, usuwa powtórki, oznacza stan względem listy', () {
    final vocab = Vocabulary(const [], commonProducts);
    final current = [item('Mleko'), item('Chleb', checked: true)];
    final plan = planImport(['1. Mieko\n- chlep\n- maslo\n- Masło\n- klej do tapet'], current, vocab);
    expect(plan.map((c) => c.text), ['Mleko', 'Chleb', 'Masło', 'Klej do tapet']);
    expect(plan.map((c) => c.status), [ImportStatus.onList, ImportStatus.restore, ImportStatus.add, ImportStatus.add]);
    expect(plan.map((c) => c.selected), [false, true, true, true]);
    expect(plan[0].corrected, isTrue);
    expect(plan[0].original, 'Mieko');
    expect(plan[3].corrected, isFalse);
  });

  test('splitSpoken: dzieli dyktowanie po przecinkach i spójnikach', () {
    expect(splitSpoken('mleko, chleb i masło'), ['Mleko', 'Chleb', 'Masło']);
    expect(splitSpoken('ser żółty oraz 2 litry soku przecinek jajka'), ['Ser żółty', '2 litry soku', 'Jajka']);
    expect(splitSpoken('I pomidory'), ['Pomidory']);
    expect(splitSpoken('chleb z masłem'), ['Chleb z masłem']);
    expect(splitSpoken('mąka 2,5 kg'), ['Mąka 2,5 kg']);
    expect(splitSpoken('  '), isEmpty);
  });
}
