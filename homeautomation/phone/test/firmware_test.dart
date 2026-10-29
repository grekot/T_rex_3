// Aktualizacje firmware (pkt 3e): wersje, manifest, katalog z kopią, sprawdzanie w tle, ekran „Aktualizacje”.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/background/update_check.dart';
import 'package:homeautomation/data/dashboard_store.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/firmware_catalog.dart';
import 'package:homeautomation/data/updates.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/firmware.dart';
import 'package:homeautomation/ui/updates_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_cloud_store.dart';

final _sha = 'b' * 64;

Map<String, dynamic> _rel(String fwId, String version, {String? minVersion, String? url}) => {
  'version': version,
  'url': url ?? 'https://ha-firmware.web.app/fw/$fwId-$version.bin',
  'sha256': _sha,
  'size': 1000,
  'minVersion': ?minVersion,
  'notes': 'Poprawki $version',
  'date': '2026-11-02',
};

final _manifestJson = {
  'v': 1,
  'generated': '2026-11-02T10:00:00Z',
  'fw': {
    'thermostat-n16r8': _rel('thermostat-n16r8', '2.2.0'),
    'switch4-s2mini': _rel('switch4-s2mini', '1.4.0', minVersion: '1.2.0'),
    'hub-n16r8': _rel('hub-n16r8', '1.0.0'),
    'switch4-s3zero': {
      ..._rel('switch4-s3zero', '2.0.0', minVersion: '1.5.0'),
      'intermediate': _rel('switch4-s3zero', '1.6.0'),
    },
    'obcy': _rel('obcy', '9.0.0', url: 'https://github.com/x/obcy.bin'),
    'zly': {'version': '1.0.0', 'url': 'https://ha-firmware.web.app/fw/zly.bin', 'sha256': 'xyz'},
  },
};

/// Atrapa źródła danych ekranu.
class _Backend implements UpdateBackend {
  _Backend(this.targetList, this.hubList);

  final List<UpdateTarget> targetList;
  List<HubUpdatesView> hubList;
  final progress = StreamController<UpdateProgress>();
  final started = <(String, String)>[];
  final applied = <(String, List<String>)>[];

  @override
  Future<FirmwareManifest> manifest() async => FirmwareManifest.fromJson(_manifestJson);

  @override
  DateTime? get manifestFetchedAt => DateTime(2026, 11, 2, 12);

  @override
  Future<List<UpdateTarget>> targets() async => targetList;

  @override
  Stream<UpdateProgress> update(UpdateTarget t, FirmwareRelease r) {
    started.add((t.id, r.version));
    return progress.stream;
  }

  int checks = 0;

  @override
  Future<void> checkHub(String hubId) async => checks++;

  @override
  Future<List<HubUpdatesView>> hubs() async => hubList;

  @override
  Future<void> applyHub(String hubId, List<String> ids) async {
    applied.add((hubId, ids));
    hubList = [
      HubUpdatesView(
        hubId: hubId,
        hubName: 'Hub',
        updates: HubUpdates(
          devices: [
            for (final d in hubList.single.updates.devices)
              ids.contains(d.id)
                  ? HubUpdateEntry(
                      id: d.id,
                      current: d.current,
                      available: d.available,
                      next: d.next,
                      ready: true,
                      state: HubUpdateState.queued,
                    )
                  : d,
          ],
        ),
        names: hubList.single.names,
      ),
    ];
  }
}

void main() {
  test('porównanie wersji', () {
    expect(compareVersions('1.4.0', '1.3.10'), 1);
    expect(compareVersions('1.3.10', '1.4'), -1);
    expect(compareVersions('2.1.0-fake', '2.1.0'), 0);
    expect(compareVersions('2.1', '2.1.0'), 0);
  });

  test('manifest: wpisy spoza ha-firmware.web.app/fw/ i bez sumy pominięte, nieznana wersja = błąd', () {
    final m = FirmwareManifest.fromJson(_manifestJson);
    expect(m.releases.keys.toSet(), {'thermostat-n16r8', 'switch4-s2mini', 'hub-n16r8', 'switch4-s3zero'});
    expect(m.releases['thermostat-n16r8']!.setJson, {
      'firmwareUrl': 'https://ha-firmware.web.app/fw/thermostat-n16r8-2.2.0.bin',
      'firmwareSha256': _sha,
    });
    expect(() => FirmwareManifest.fromJson({'v': 2}), throwsFormatException);
  });

  test('stan aktualizacji: bez fwId, brak wydań, aktualna, dostępna, wymaga wersji pośredniej', () {
    final m = FirmwareManifest.fromJson(_manifestJson);
    expect(checkUpdate(m, fw: '2.1.0', fwId: null).status, UpdateStatus.unknown);
    expect(checkUpdate(m, fw: '1.0.0', fwId: 'hub-eth').status, UpdateStatus.noRelease);
    expect(checkUpdate(m, fw: '2.2.0', fwId: 'thermostat-n16r8').status, UpdateStatus.upToDate);
    expect(checkUpdate(m, fw: '2.1.0', fwId: 'thermostat-n16r8').status, UpdateStatus.available);
    expect(checkUpdate(m, fw: '1.3.0', fwId: 'switch4-s2mini').status, UpdateStatus.available);
    expect(checkUpdate(m, fw: '1.1.0', fwId: 'switch4-s2mini').status, UpdateStatus.needsIntermediate);
    // Z plikiem wersji pośredniej - dwa kroki.
    final two = checkUpdate(m, fw: '1.0.0', fwId: 'switch4-s3zero');
    expect(
      (two.status, two.twoSteps, two.step!.version, two.release!.version),
      (UpdateStatus.available, true, '1.6.0', '2.0.0'),
    );
    final one = checkUpdate(m, fw: '1.6.0', fwId: 'switch4-s3zero');
    expect((one.twoSteps, one.step!.version), (false, '2.0.0'));
  });

  test('wpis huba: next, dwa kroki, starszy hub bez next, błędy; zagnieżdżone błędy Set', () {
    final e = HubUpdateEntry.fromJson({
      'id': 'a',
      'current': '1.1.0',
      'available': '1.4.0',
      'next': '1.3.0',
      'ready': true,
    });
    expect((e.hasUpdate, e.twoSteps, e.selectable), (true, true, true));
    final none = HubUpdateEntry.fromJson({'id': 'a', 'current': '1.4.0', 'available': '1.4.0', 'next': null});
    expect(none.hasUpdate, isFalse);
    final old = HubUpdateEntry.fromJson({'id': 'a', 'current': '1.3.0', 'available': '1.4.0'});
    expect((old.next, old.twoSteps), ('1.4.0', false));
    expect(
      HubUpdateEntry.fromJson({'id': 'a', 'error': 'needs_intermediate'}).errorLabel,
      'brak pliku wersji pośredniej',
    );
    final hubMap = HubUpdates.fromJson({
      'devices': {
        'x': {'id': 'x', 'current': '1.0.0', 'next': '1.1.0', 'ready': false, 'state': 'updating'},
      },
    });
    expect((hubMap.devices.single.state, hubMap.devices.single.selectable), (HubUpdateState.updating, false));
  });

  test('katalog: z sieci, kopia bez internetu, bez kopii - błąd', () async {
    final cache = MemoryTextCache();
    var online = true;
    final catalog = FirmwareCatalog(
      cache: cache,
      client: MockClient(
        (_) async => online ? http.Response(jsonEncode(_manifestJson), 200) : throw http.ClientException('brak sieci'),
      ),
      clock: () => DateTime(2026, 11, 2, 12),
    );
    expect((await catalog.load()).releases.length, 4);
    online = false;
    final offline = FirmwareCatalog(cache: cache, client: MockClient((_) async => http.Response('', 503)));
    expect((await offline.load()).generated, '2026-11-02T10:00:00Z');
    expect(offline.fetchedAt, DateTime(2026, 11, 2, 12));
    await expectLater(
      FirmwareCatalog(cache: MemoryTextCache(), client: MockClient((_) async => http.Response('', 404))).load(),
      throwsA(isA<ThermostatException>()),
    );
  });

  test('w tle: domy właściciela, urządzenia z chmurą i węzły huba; powiadomienie tylko o nowych', () async {
    final store = MemoryCloudStore();
    store.set('users/own/homes', {'h1': true, 'h2': true});
    store.set('homes/h1/ownerUid', 'own');
    store.set('homes/h2/ownerUid', 'ktos'); // cudzy dom - pomijany
    store.set('homes/h1/deviceIndex', {
      't1': {'type': 'thermostat', 'name': 'Salon'},
      'hub1': {'type': 'hub', 'name': 'Hub'},
      'sw1': {'type': 'switch', 'name': 'Taras', 'via': 'hub1'},
    });
    store.set('homes/h1/devices/t1/info', {'type': 'thermostat', 'fw': '2.1.0', 'fwId': 'thermostat-n16r8'});
    store.set('homes/h1/devices/hub1/info', {'type': 'hub', 'fw': '1.0.0', 'fwId': 'hub-n16r8'});
    store.set('homes/h1/devices/sw1/info', {'type': 'switch', 'fw': '1.0.0', 'fwId': 'switch4-s2mini', 'via': 'hub1'});
    store.set('homes/h1/devices/hub1/updates', {
      'checked': 1793000000,
      'devices': [
        {'id': 'sw1', 'current': '1.3.0', 'available': '1.4.0', 'ready': true, 'state': 'idle'},
      ],
    });
    store.set('homes/h2/devices/x/info', {'type': 'thermostat', 'fw': '1.0.0', 'fwId': 'thermostat-n16r8'});
    final m = FirmwareManifest.fromJson(_manifestJson);
    final found = await collectUpdates(store, 'own', m);
    expect(found.map((a) => a.key), ['t1@2.2.0', 'sw1@1.4.0']);
    expect(found.map((a) => a.name), ['Salon', 'Taras']);

    final n = updateNotice(found, const {})!;
    expect(n.title, 'Dostępne aktualizacje (2)');
    expect(n.body, startsWith('Salon, Taras'));
    expect(updateNotice(found, {'t1@2.2.0', 'sw1@1.4.0'}), isNull, reason: 'już powiadomione');
    expect(updateNotice(found, {'t1@2.1.0'}), isNotNull, reason: 'nowa wersja');
  });

  testWidgets('ekran: dostępne i aktualne, ostrzeżenie termostatu, postęp, węzły huba do zatwierdzenia', (
    tester,
  ) async {
    final backend = _Backend(
      const [
        UpdateTarget(
          id: 't1',
          name: 'Salon',
          type: DeviceType.thermostat,
          fw: '2.1.0',
          fwId: 'thermostat-n16r8',
          local: true,
          warning: 'Termostat właśnie grzeje - na czas pobierania i restartu (1-2 min) grzanie się zatrzyma.',
        ),
        UpdateTarget(id: 'hub1', name: 'Hub', type: DeviceType.hub, fw: '1.0.0', fwId: 'hub-n16r8', local: true),
        UpdateTarget(id: 'sw9', name: 'Stary', type: DeviceType.onOff, fw: '1.1.0', fwId: 'switch4-s2mini'),
        UpdateTarget(id: 's3', name: 'Garaż', type: DeviceType.onOff, fw: '1.0.0', fwId: 'switch4-s3zero'),
        UpdateTarget(id: 'sw1', name: 'Taras (za hubem)', type: DeviceType.onOff, fw: '1.3.0', fwId: 'switch4-s2mini'),
      ],
      const [
        HubUpdatesView(
          hubId: 'hub1',
          hubName: 'Hub',
          names: {'sw1': 'Taras', 'sw2': 'Schody'},
          updates: HubUpdates(
            checked: 1793000000,
            devices: [
              HubUpdateEntry(id: 'sw1', current: '1.3.0', available: '1.4.0', next: '1.4.0', ready: true),
              HubUpdateEntry(id: 'sw2', current: '1.3.0', available: '1.4.0', next: '1.4.0'),
            ],
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UpdatesScreen(backend: backend, hubRefresh: const Duration(hours: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wersja 2.1.0 → 2.2.0'), findsOneWidget);
    expect(find.text('Wersja 1.0.0 - aktualna'), findsOneWidget);
    expect(find.textContaining('najpierw potrzebna wersja 1.2.0'), findsOneWidget);
    expect(find.byKey(const Key('target-sw1')), findsNothing, reason: 'węzeł za hubem - tylko w sekcji huba');
    expect(find.byKey(const Key('update-hub1')), findsNothing);
    expect(find.byKey(const Key('update-sw9')), findsNothing);
    expect(find.text('Wersja 1.0.0 → 2.0.0 (najpierw 1.6.0)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('update-t1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updateWarning')), findsOneWidget);
    expect(find.text('Poprawki 2.2.0'), findsWidgets);
    await tester.tap(find.byKey(const Key('updateConfirm')));
    // Kręcące się kółko postępu - pumpAndSettle by nie skończył.
    await tester.pump(const Duration(milliseconds: 500));
    expect(backend.started, [('t1', '2.2.0')]);
    backend.progress.add(const UpdateProgress(UpdatePhase.downloading, percent: 40));
    await tester.pump();
    expect(find.text('Pobieranie 40%…'), findsOneWidget);
    backend.progress.add(const UpdateProgress(UpdatePhase.done, message: 'Zaktualizowano do 2.2.0'));
    await tester.pump();
    expect(find.text('Zaktualizowano do 2.2.0'), findsOneWidget);

    // Węzły huba: tylko gotowe (ready) do zaznaczenia.
    await tester.dragUntilVisible(find.byKey(const Key('hubApply-hub1')), find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    expect(find.textContaining('hub jeszcze pobiera plik'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('hubApply-hub1'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('hubUpd-sw1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('hubApply-hub1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aktualizuj').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(backend.applied.single.$1, 'hub1');
    expect(backend.applied.single.$2, ['sw1']);
    expect(find.textContaining('w kolejce'), findsOneWidget);
  });
}
