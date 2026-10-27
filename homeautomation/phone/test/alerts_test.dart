import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/background/alerts.dart';

import 'support/memory_cloud_store.dart';

void main() {
  const now = 1793000000000;
  const minute = 60000;

  DeviceHealth dev({String id = 'termostat-ab12cd', bool fault = false, int? seen = now}) =>
      DeviceHealth(id: id, name: 'Salon', sensorFault: fault, lastSeenMs: seen);

  test('awaria czujnika: powiadomienie raz, potem cisza, po naprawie znika', () {
    var r = evaluateAlerts([dev(fault: true)], AlertMemory(), now);
    expect(r.newAlerts.single.kind, AlertKind.sensorFault);
    expect(r.newAlerts.single.title, 'Awaria czujnika: Salon');

    r = evaluateAlerts([dev(fault: true, seen: now + 15 * minute)], r.memory, now + 15 * minute);
    expect(r.newAlerts, isEmpty, reason: 'nie powtarzamy co 15 min');

    r = evaluateAlerts([dev(seen: now + 30 * minute)], r.memory, now + 30 * minute);
    expect(r.newAlerts, isEmpty);
    expect(r.resolved, [('termostat-ab12cd', AlertKind.sensorFault)]);
    expect(r.memory.active, isEmpty);
  });

  test('offline po 3 min bez lastSeen; offline zasłania stary stan awarii', () {
    final r = evaluateAlerts([dev(fault: true, seen: now - 10 * minute)], AlertMemory(), now);
    expect(r.newAlerts.map((a) => a.kind), [AlertKind.offline]);
    expect(r.newAlerts.single.body, contains('10 min'));
    expect(evaluateAlerts([dev(seen: now - 2 * minute)], AlertMemory(), now).newAlerts, isEmpty);
    expect(evaluateAlerts([dev(seen: null)], AlertMemory(), now).newAlerts.single.kind, AlertKind.offline);
  });

  test('termostat usunięty z konta - jego alarm się kasuje', () {
    final memory = AlertMemory({'termostat-old|offline'});
    final r = evaluateAlerts([dev()], memory, now);
    expect(r.resolved, [('termostat-old', AlertKind.offline)]);
  });

  test('pamięć alarmów przez JSON', () {
    final m = AlertMemory({'b|offline', 'a|sensorFault'});
    expect(AlertMemory.fromJson(m.toJson()).active, m.active);
    expect(AlertMemory.fromJson(null).active, isEmpty);
  });

  test('numer powiadomienia stały i różny dla rodzajów', () {
    final a = alertNotificationId('termostat-ab12cd', AlertKind.offline);
    expect(alertNotificationId('termostat-ab12cd', AlertKind.offline), a);
    expect(alertNotificationId('termostat-ab12cd', AlertKind.sensorFault), isNot(a));
    expect(a, greaterThanOrEqualTo(0));
    expect(a, lessThan(1 << 31));
  });

  test('collectHealth czyta tylko potrzebne pola z chmury', () async {
    final store = MemoryCloudStore()
      ..set('users/uid-1/homes/h1', true)
      ..set('homes/h1/devices/termostat-ab12cd', {
        'info': {'name': 'Salon'},
        'state': {'sensorFault': true},
        'lastSeen': now,
      })
      ..set('homes/h1/devices/termostat-000001/state', {'sensorFault': false});
    final list = await collectHealth(TestCloudAccess(store));
    final byId = {for (final d in list) d.id: d};
    expect(byId['termostat-ab12cd']!.name, 'Salon');
    expect(byId['termostat-ab12cd']!.sensorFault, isTrue);
    expect(byId['termostat-ab12cd']!.lastSeenMs, now);
    expect(byId['termostat-000001']!.name, 'termostat-000001');
    expect(byId['termostat-000001']!.lastSeenMs, isNull);
  });
}
