// Pulpit (pkt 13 i 13.1): pola rozszerzone, nieznane pola i widoki zapisywane bez zmian, siatka 4, sekcje.

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/models/dashboard.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart';

void main() {
  test('widżet: pola 13.1 czytane getterami, nieznane pola i widok zostają przy zapisie', () {
    final j = {
      'id': 'w1',
      'view': 'gauge',
      'size': '1x1',
      'device': 'termostat-ab12cd',
      'point': 'hum',
      'w': 2,
      'h': 2,
      'section': 's1',
      'color': 'blue',
      'secondary': 'point:temp',
      'iconSize': 'l',
      'iconTap': 'none',
      'tap': 'device',
      'confirm': true,
      'features': [
        {'type': 'trend', 'point': 'hum'},
      ],
      'min': 0,
      'max': 100,
      'zones': [
        [0, 30, 'amber'],
        [30, 60, 'green'],
      ],
      'target': 'point:target',
      'przyszlePole': {'x': 1},
    };
    final w = DashWidget.fromJson(j);
    expect(
      (w.view, w.gridW, w.gridH, w.section, w.color, w.secondary),
      (WidgetView.gauge, 2, 2, 's1', 'blue', 'point:temp'),
    );
    expect(
      (w.iconSize, w.iconTap, w.tap, w.confirm, w.min, w.max, w.target),
      ('l', 'none', 'device', true, 0.0, 100.0, 'point:target'),
    );
    expect(w.features.single.type, 'trend');
    expect(w.zones.map((z) => z.color), ['amber', 'green']);
    expect(w.toJson(), j, reason: 'zapis bez zmian, także nieznane pole');

    final future = DashWidget.fromJson({'id': 'w2', 'view': 'kamera', 'device': 'x'});
    expect(future.view, WidgetView.value, reason: 'nieznany widok - jak wartość');
    expect(future.toJson()['view'], 'kamera', reason: 'ale zapis bez zmian');

    final patched = w.patch({'color': null, 'secondary': 'none'});
    expect((patched.color, patched.secondary, patched.toJson().containsKey('color')), (null, 'none', false));
  });

  test('rozmiary: dawne size → siatka 4, resized ustawia też size dla starszych wersji', () {
    const a = DashWidget(id: 'a', view: WidgetView.toggle);
    const b = DashWidget(id: 'b', view: WidgetView.thermostat, size: WidgetSize.s2x1);
    const c = DashWidget(id: 'c', view: WidgetView.chart, size: WidgetSize.s2x2);
    expect([(a.gridW, a.gridH), (b.gridW, b.gridH), (c.gridW, c.gridH)], [(2, 2), (4, 2), (4, 4)]);
    expect(
      [a.resized(4, 1).size, a.resized(2, 1).size, a.resized(4, 4).size],
      [WidgetSize.s2x1, WidgetSize.s1x1, WidgetSize.s2x2],
    );

    final d = Dashboard(id: 'd', name: 'Dom', scope: DashboardScope.private, widgets: const [a, b, c]);
    final g = d.toGrid4();
    expect(g.grid, 4);
    expect(g.widgets.map((w) => (w.w, w.h)), [(2, 2), (4, 2), (4, 4)]);
    final round = Dashboard.fromJson('d', DashboardScope.private, {
      ...g
          .copyWith(
            sections: const [DashSection(id: 's1', title: 'Salon', room: 'r1')],
          )
          .toJson(),
    });
    expect((round.grid, round.sections.single.title, round.sections.single.room), (4, 'Salon', 'r1'));
    expect(Dashboard.fromJson('d', DashboardScope.private, d.toJson()).toJson().containsKey('grid'), isFalse);
  });

  test('siatka 4: kafelki w pierwszym wolnym miejscu, małe wypełniają luki', () {
    DashWidget t(String id, int w, int h) => DashWidget(id: id, view: WidgetView.value).resized(w, h);
    final placed = packGrid4([t('a', 4, 2), t('b', 2, 2), t('c', 2, 1), t('d', 1, 1), t('e', 4, 1), t('f', 1, 1)]);
    expect(
      [for (final p in placed) '${p.widget.id}:${p.row},${p.col}'],
      ['a:0,0', 'b:2,0', 'c:2,2', 'd:3,2', 'e:4,0', 'f:3,3'],
    );
  });

  test('siatka 4: przypięte kafelki (x, y) na swoim miejscu, reszta wokół; nachodzący - automatycznie', () {
    DashWidget t(String id, int w, int h) => DashWidget(id: id, view: WidgetView.value).resized(w, h);
    final placed = packGrid4([
      t('a', 2, 2),
      t('b', 2, 2),
      t('mid', 1, 1).pinnedAt(1, 2),
      t('c', 2, 1),
      t('zly', 2, 2).pinnedAt(1, 2), // nachodzi na „mid”
    ]);
    expect(
      [for (final p in placed) '${p.widget.id}:${p.row},${p.col}'],
      ['a:0,0', 'b:0,2', 'mid:2,1', 'c:2,2', 'zly:3,0'],
    );
    // Przypięty przy prawej krawędzi po powiększeniu przesuwa się w lewo.
    expect(t('x', 1, 1).pinnedAt(3, 0).resized(2, 1).x, 2);
    expect(t('x', 1, 1).pinnedAt(3, 0).unpinned().pinned, isFalse);
  });
}
