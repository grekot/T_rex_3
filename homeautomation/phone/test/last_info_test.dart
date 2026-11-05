// Ostatnia informacja od urządzenia: `seenAt` od huba (pkt 11), napis pod paskiem połączenia na ekranie urządzenia.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/ui/widgets.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() => const Stream.empty();
}

/// Urządzenie huba widziane przez hub (bez WebSocketu do samego urządzenia).
class _Conn implements DeviceConnection<Json, Json> {
  _Conn(this.state);

  @override
  final Json state;
  @override
  String get deviceId => 'ble-b8f862d84911';
  @override
  ConnectionKind get kind => ConnectionKind.local;
  @override
  String get routeDescription => 'przez hub 192.168.68.125';
  @override
  Json get config => const {'name': 'Czujnik BT'};
  @override
  LinkStatus get status => LinkStatus.online;
  @override
  Stream<Json> get states => const Stream.empty();
  @override
  Stream<Json> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<Json?> describeJson() async => null;
  @override
  Future<SetResult> sendSet(Json values) async => const SetResult(ok: true);
  @override
  Future<void> close() async {}
}

class _Manager extends ConnectionManager {
  _Manager(this.conn) : super(store: MemoryDeviceStore(), discovery: _NoDiscovery());

  final _Conn conn;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async => conn as DeviceConnection<S, C>;
}

void main() {
  test('napis: dziś z „N min temu”, wczoraj, starsze z datą', () {
    final now = DateTime(2026, 11, 5, 12, 34);
    expect(lastInfoText(DateTime(2026, 11, 5, 12, 31), now), '12:31 · 3 min temu');
    expect(
      lastInfoText(DateTime(2026, 11, 5, 12, 34, 10), now.add(const Duration(seconds: 20))),
      '12:34 · przed chwilą',
    );
    expect(lastInfoText(DateTime(2026, 11, 5, 9, 5), now), '09:05 · 3 h temu');
    expect(lastInfoText(DateTime(2026, 11, 4, 23, 5), now), 'wczoraj 23:05');
    expect(lastInfoText(DateTime(2026, 11, 1, 8, 15), now), '01.11 08:15');
  });

  testWidgets('urządzenie huba: `seenAt` pod paskiem połączenia; bez niego - nic', (tester) async {
    final seen = DateTime.now().subtract(const Duration(minutes: 3));
    Future<void> show(Json state) async {
      final c = DeviceController<Json, Json>(
        device: const PairedDevice(id: 'ble-b8f862d84911', name: 'Czujnik BT', type: DeviceType.sensor, via: 'hub1'),
        manager: _Manager(_Conn(state)),
        codec: rawCodec,
      );
      await c.connect();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RouteChip(controller: c)),
        ),
      );
    }

    await show({'temp': 24.8, 'seenAt': seen.millisecondsSinceEpoch ~/ 1000});
    expect(find.textContaining('Ostatni odczyt: '), findsOneWidget);
    expect(find.textContaining('3 min temu'), findsOneWidget);
    await show({'temp': 24.8});
    expect(find.byKey(const Key('lastInfo')), findsNothing, reason: 'hub bez seenAt - czas odpytania nic nie mówi');
  });
}
