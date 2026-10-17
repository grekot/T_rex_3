import 'package:flutter_test/flutter_test.dart';
import 'package:zakupy/models.dart';
import 'package:zakupy/sorting.dart';

// Testy udostępniania są we wspólnej bibliotece: wspolne/test/sharing_test.dart

ShoppingItem item(String id, {bool checked = false, int? created, int? checkedAt}) => ShoppingItem(
      id: id,
      name: id,
      checked: checked,
      createdAt: created == null ? null : DateTime.utc(2026, 10, 16, 10, created),
      checkedAt: checkedAt == null ? null : DateTime.utc(2026, 10, 16, 11, checkedAt),
    );

void main() {
  test('do kupienia w kolejności dodania, kupione na dole (ostatnio odhaczone wyżej)', () {
    final sorted = sortItems([
      item('chleb', created: 2),
      item('mleko', checked: true, created: 1, checkedAt: 5),
      item('masło', created: 1),
      item('jajka', checked: true, created: 3, checkedAt: 9),
      item('nowy', created: null), // jeszcze bez daty z serwera
    ]);
    expect(sorted.map((i) => i.id), ['masło', 'chleb', 'nowy', 'jajka', 'mleko']);
  });

  test('normalizeName ignoruje wielkość liter i spacje', () {
    expect(normalizeName('  Mleko   2%  '), 'mleko 2%');
  });

  test('planAdd: nowy, już na liście, wraca z kupionych', () {
    final current = [item('Mleko'), item('Chleb', checked: true)];
    expect(planAdd('jajka', current).decision, AddDecision.add);
    expect(planAdd(' mleko ', current).decision, AddDecision.alreadyOnList);
    final back = planAdd('CHLEB', current);
    expect(back.decision, AddDecision.uncheckExisting);
    expect(back.existing!.id, 'Chleb');
  });

  test('ShoppingList z danymi udostępnienia', () {
    final list = ShoppingList(
      id: 'L1',
      name: 'Biedronka',
      ownerId: 'me',
      members: ['me', 'zona'],
      memberEmails: {'me': 'ja@x.pl'},
    );
    expect(list.isOwner('me'), isTrue);
    expect(list.isShared, isTrue);
    expect(list.ownerEmail, 'ja@x.pl');
  });
}
