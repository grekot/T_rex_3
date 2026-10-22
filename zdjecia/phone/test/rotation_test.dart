import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zdjecia/select/pool.dart';
import 'package:zdjecia/select/rotation.dart';
import 'package:zdjecia/select/scoring.dart';

import 'select_test.dart' show scored;

final start = DateTime(2026, 10, 22, 12);

/// [n] zdjęć, każde z innego dnia (zasady dnia nie przeszkadzają), lepsze = nowsze
List<ScoredPhoto> photos(int n) => [
      for (var i = 0; i < n; i++)
        scored('p$i', 10.0 - i * 0.05, start.subtract(Duration(days: 4 + i)), hash: i.toRadixString(16).padLeft(16, '0')),
    ];

Set<String> ids(List<ScoredPhoto> list) => {for (final p in list) p.id};

void main() {
  const rules = PoolRules(size: 10);

  test('pula zmienia się po trochu, wygasłe odpoczywają', () {
    final all = photos(80);
    final state = FreshRotation();
    final random = math.Random(7);
    final shown = <String>{};
    final left = <String, DateTime>{};
    var previous = <String>{};
    for (var h = 0; h <= 30 * 24; h += 8) {
      final now = start.add(Duration(hours: h));
      final pool = ids(rotateFresh(all, rules, state, now, random));
      expect(pool.length, 10);
      if (previous.isNotEmpty) {
        // Nigdy cała pula naraz
        expect(pool.difference(previous).length, lessThanOrEqualTo(5));
      }
      for (final id in previous.difference(pool)) {
        left[id] = now;
      }
      for (final id in pool.difference(previous)) {
        final gone = left[id];
        if (gone != null) expect(now.difference(gone), greaterThanOrEqualTo(freshRest));
      }
      shown.addAll(pool);
      previous = pool;
    }
    // W miesiąc przewija się większość dobrych zdjęć, nie ta sama dziesiątka
    expect(shown.length, greaterThan(50));
  });

  test('zdjęcie zostaje w puli co najmniej 2 dni', () {
    final all = photos(80);
    final state = FreshRotation();
    final random = math.Random(3);
    final first = ids(rotateFresh(all, rules, state, start, random));
    final later = ids(rotateFresh(all, rules, state, start.add(freshStayMin - const Duration(hours: 1)), random));
    expect(later, first);
  });

  test('„Odśwież” wymienia od razu kilka zdjęć', () {
    final all = photos(80);
    final state = FreshRotation();
    final random = math.Random(5);
    final first = ids(rotateFresh(all, rules, state, start, random));
    final now = start.add(const Duration(minutes: 1));
    final after = ids(rotateFresh(all, rules, state, now, random, swap: freshSwapOnRefresh));
    expect(after.length, 10);
    expect(first.difference(after).length, freshSwapOnRefresh);
  });

  test('nowe dobre zdjęcie wchodzi od razu, słabe czeka na swoją kolej', () {
    final all = photos(80);
    final state = FreshRotation();
    final random = math.Random(9);
    rotateFresh(all, rules, state, start, random);
    final now = start.add(const Duration(hours: 1));
    final withNew = [
      ...all,
      scored('nowe', 9.9, now.subtract(const Duration(minutes: 30)), hash: 'aaaaaaaaaaaaaaaa'),
      scored('nowe-slabe', 0.1, now.subtract(const Duration(minutes: 20)), hash: 'bbbbbbbbbbbbbbbb'),
    ];
    final pool = ids(rotateFresh(withNew, rules, state, now, random));
    expect(pool, contains('nowe'));
    expect(pool, isNot(contains('nowe-slabe')));
    expect(pool.length, 10);
  });

  test('przypięte zawsze, usunięte i odrzucone nigdy', () {
    final all = [...photos(40), scored('zle', 99, start, rejected: 'nieostre')];
    final state = FreshRotation();
    final random = math.Random(11);
    final r = PoolRules(size: 10, pinned: const {'p39'}, removed: const {'p0', 'p1'});
    for (var h = 0; h <= 20 * 24; h += 12) {
      final pool = ids(rotateFresh(all, r, state, start.add(Duration(hours: h)), random));
      expect(pool, contains('p39'));
      expect(pool.intersection({'p0', 'p1', 'zle'}), isEmpty);
      expect(pool.length, 10);
    }
    expect(state.slots.map((s) => s.photoId), isNot(contains('p39')));
  });

  test('przy małej liczbie zdjęć odpoczywające wracają, pula pełna', () {
    final all = photos(12);
    final state = FreshRotation();
    final random = math.Random(13);
    for (var h = 0; h <= 20 * 24; h += 8) {
      expect(rotateFresh(all, rules, state, start.add(Duration(hours: h)), random).length, 10);
    }
  });

  test('stan rotacji przez JSON', () {
    final state = FreshRotation();
    rotateFresh(photos(30), rules, state, start, math.Random(1));
    rotateFresh(photos(30), rules, state, start.add(const Duration(days: 5)), math.Random(2));
    final back = FreshRotation.fromJson(state.toJson());
    expect(back.slots.map((s) => (s.photoId, s.expiresAt)).toList(),
        state.slots.map((s) => (s.photoId, s.expiresAt)).toList());
    expect(back.resting, state.resting);
  });
}
