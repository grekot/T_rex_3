// Diagnostyka urządzenia (pkt 3c): model, ekran „Stan” (restarty, strażnik łącza, pamięć, błędy, awarie),
// dziennik z wyszukiwaniem, usunięcie zrzutu, kopia z chmury bez dziennika.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/models/diag.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/ui/diag_screen.dart';

const _diag = {
  'fw': '0.3.17',
  'elf': 'aea2f8a71e2aad92',
  'resetReason': 'task_wdt',
  'boots': 42,
  'wdtResets': 2,
  'panics': 0,
  'brownouts': 1,
  'heapFree': 180000,
  'heapMin': 150000,
  'heapMaxBlock': 110000,
  'psramFree': 8000000,
  'uptime': 7200,
  'ota': {'partition': 'ota_1', 'trial': false, 'rollbacks': 1, 'rolledBackFrom': 'ota_0'},
  'errors': [
    {'t': 3600, 'msg': 'Chmura: zapis nieudany (timeout)', 'n': 12},
    {'t': 7000, 'msg': 'OTA: zła suma'},
  ],
  'guard': {'n': 3, 'last': '1793990000 DNS martwe 180 s'},
  'crashes': [
    {'boot': 41, 'reason': 'task_wdt', 'task': 'IDLE0', 'pc': '0x403781b2', 'elf': '9c07e145f2818464', 'size': 11364},
  ],
  'coreDump': true,
};

class _Api extends LocalApi {
  _Api() : super(LocalEndpoint('127.0.0.1', 1));

  int deletes = 0;
  Json diagJson = _diag;

  @override
  Future<Json> diag() async => diagJson;

  @override
  Future<String> log({Duration? timeout}) async =>
      '12:00:01 WiFi: połączono\n12:00:05 Chmura: zapis nieudany\n12:01:00 Hub: 4 urządzenia\n';

  @override
  Future<void> deleteCoreDump() async {
    deletes++;
    diagJson = {...diagJson, 'crashes': <Object>[], 'coreDump': false};
  }
}

void main() {
  test('model: liczniki, strażnik łącza z czasem i powodem, błędy, awarie; powody po polsku', () {
    final d = DeviceDiag.fromJson(_diag);
    expect((d.boots, d.wdtResets, d.brownouts, d.rollbacks, d.rolledBackFrom), (42, 2, 1, 1, 'ota_0'));
    expect(
      (d.guardRestarts, d.guard!.why, d.guard!.at),
      (3, 'DNS martwe 180 s', DateTime.fromMillisecondsSinceEpoch(1793990000000)),
    );
    expect(d.errors.first, (t: 3600, msg: 'Chmura: zapis nieudany (timeout)', n: 12));
    expect(d.errors.last.n, 1);
    expect((d.crashes.single.task, d.coreDump), ('IDLE0', true));
    expect(
      (resetReasonText('task_wdt'), resetIsFault('task_wdt'), resetIsFault('poweron')),
      ('watchdog zadań (zawieszenie)', true, false),
    );
    expect(DeviceDiag.fromJson(const {}).guard, isNull);
  });

  testWidgets('ekran w domu: stan, błędy, awarie, usunięcie zrzutu; dziennik z wyszukiwaniem', (tester) async {
    final api = _Api();
    await tester.pumpWidget(
      MaterialApp(
        home: DiagScreen(name: 'Hub', api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 h 0 min'), findsOneWidget);
    expect(find.text('watchdog zadań (zawieszenie)'), findsOneWidget);
    expect(find.byKey(const Key('diagGuard')), findsOneWidget);
    expect(find.textContaining('DNS martwe 180 s'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Chmura: zapis nieudany (timeout)'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.textContaining('12× pod rząd'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('diagDeleteDump')),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.textContaining('zadanie IDLE0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('diagDeleteDump')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('diagDeleteOk')));
    await tester.pumpAndSettle();
    expect(api.deletes, 1);
    expect(find.byKey(const Key('diagDeleteDump')), findsNothing);

    await tester.tap(find.byKey(const Key('diagTabLog')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 wierszy'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('diagLogFilter')), 'chmura');
    await tester.pump();
    expect(find.text('1 z 3 wierszy'), findsOneWidget);
    expect(find.text('12:00:05 Chmura: zapis nieudany'), findsOneWidget);
  });

  testWidgets('poza domem: kopia z chmury, bez zakładki dziennika i bez usuwania zrzutu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DiagScreen(name: 'Hub', cloudDiag: () async => _diag),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Kopia z chmury'), findsOneWidget);
    expect(find.byKey(const Key('diagTabLog')), findsNothing);
    await tester.dragUntilVisible(
      find.textContaining('zadanie IDLE0'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.byKey(const Key('diagDeleteDump')), findsNothing);
  });
}
