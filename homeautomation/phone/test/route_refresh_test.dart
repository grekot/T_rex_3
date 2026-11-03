// Powrót aplikacji z tła (DeviceController.refreshRoute): nowa droga szukana w tle, stare połączenie
// pokazuje stan do chwili przełączenia; chmura zamiast działającej chmury nic nie zmienia.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/device_controller.dart';
import 'package:homeautomation/data/connection_manager.dart';
import 'package:homeautomation/data/device_store.dart';
import 'package:homeautomation/data/discovery.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/thermostat_connection.dart';
import 'package:homeautomation/models/device_type.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/set_values.dart';

class _NoDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredThermostat>> watch() => const Stream.empty();
}

class _Conn implements DeviceConnection<Json, Json> {
  _Conn(this.kind, this.status, this.state);

  @override
  final ConnectionKind kind;
  @override
  LinkStatus status;
  @override
  final Json state;
  bool closed = false;

  @override
  String get deviceId => 'sw-1';
  @override
  String get routeDescription => kind.label;
  @override
  Json get config => const {'name': 'Światło'};
  @override
  Stream<Json> get states => const Stream.empty();
  @override
  Stream<Json> get configs => const Stream.empty();
  @override
  Stream<LinkStatus> get statuses => const Stream.empty();
  @override
  Future<void> open() async {}
  @override
  Future<SetResult> sendSet(Json values) async => const SetResult(ok: true);
  @override
  Future<Json?> describeJson() async => null;
  @override
  Future<void> close() async => closed = true;
}

/// Kolejne wywołania connectWith czekają na [next] (test decyduje, kiedy i czym się skończą).
class _Manager extends ConnectionManager {
  _Manager(DeviceStore store) : super(store: store, discovery: _NoDiscovery());

  final calls = <Completer<DeviceConnection<Json, Json>>>[];

  Completer<DeviceConnection<Json, Json>> get next => calls.last;

  @override
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async {
    final c = Completer<DeviceConnection<Json, Json>>();
    calls.add(c);
    return await c.future as DeviceConnection<S, C>;
  }
}

void main() {
  late _Manager manager;
  late DeviceController<Json, Json> c;

  Future<_Conn> start(ConnectionKind kind, LinkStatus status) async {
    manager = _Manager(MemoryDeviceStore());
    c = DeviceController<Json, Json>(
      device: const PairedDevice(id: 'sw-1', name: 'Światło', type: DeviceType.onOff),
      manager: manager,
      codec: rawCodec,
    );
    final connecting = c.connect();
    await Future<void>.delayed(Duration.zero); // connect() najpierw zamyka poprzednie połączenie
    final first = _Conn(kind, status, const {'on': true});
    manager.next.complete(first);
    await connecting;
    return first;
  }

  tearDown(() => c.dispose());

  test('chmura → lokalnie: stan widoczny w trakcie, potem przełączenie i zamknięcie starego', () async {
    final cloud = await start(ConnectionKind.cloud, LinkStatus.online);
    final refreshing = c.refreshRoute();
    expect((c.phase, c.connection), (ConnectPhase.connected, cloud));
    expect(c.stateJson, {'on': true});
    expect(c.live, isTrue, reason: 'bez ekranu „łączenie” po powrocie z tła');
    c.refreshRoute();
    expect(manager.calls.length, 2, reason: 'drugi powrót w trakcie nie zaczyna kolejnego szukania');

    final local = _Conn(ConnectionKind.local, LinkStatus.online, const {'on': false});
    manager.next.complete(local);
    await refreshing;
    expect((c.connection, c.kind, cloud.closed), (local, ConnectionKind.local, true));
    expect(c.stateJson, {'on': false});
  });

  test('poza domem: nowa chmura zamiast działającej - zostaje stare połączenie', () async {
    final cloud = await start(ConnectionKind.cloud, LinkStatus.online);
    final refreshing = c.refreshRoute();
    final again = _Conn(ConnectionKind.cloud, LinkStatus.online, const {'on': true});
    manager.next.complete(again);
    await refreshing;
    expect((c.connection, cloud.closed, again.closed), (cloud, false, true));
  });

  test('brak nowej drogi: działające połączenie zostaje, zerwane - błąd', () async {
    final cloud = await start(ConnectionKind.cloud, LinkStatus.online);
    var refreshing = c.refreshRoute();
    manager.next.completeError(const NoRouteException('brak'));
    await refreshing;
    expect((c.phase, c.connection), (ConnectPhase.connected, cloud));

    c.dispose();
    final local = await start(ConnectionKind.local, LinkStatus.offline);
    refreshing = c.refreshRoute();
    expect(c.connection, local);
    manager.next.completeError(const NoRouteException('Nie znaleziono urządzenia.'));
    await refreshing;
    expect(
      (c.phase, c.error, c.connection, local.closed),
      (ConnectPhase.failed, 'Nie znaleziono urządzenia.', null, true),
    );
  });

  test('lokalne działające połączenie: bez szukania drogi', () async {
    await start(ConnectionKind.local, LinkStatus.online);
    await c.refreshRoute();
    expect(manager.calls.length, 1);
  });
}
