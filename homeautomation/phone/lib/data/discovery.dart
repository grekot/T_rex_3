import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;

import '../models/device_type.dart';
import 'local_endpoint.dart';

/// Usługa mDNS urządzeń HomeAutomation (pkt 1 kontraktu).
const homeServiceType = '_homeauto._tcp';

/// Urządzenie znalezione w sieci lokalnej.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.endpoint,
    this.type = DeviceType.thermostat,
    this.fw,
    this.api,
    this.serviceName,
    this.softAp = false,
    this.channels = 1,
  });

  /// `termostat-XXXXXX` z TXT `id` (albo z nazwy usługi, gdy TXT brak).
  final String id;

  /// TXT `type`.
  final DeviceType type;
  final LocalEndpoint endpoint;
  final String? fw;
  final int? api;
  final String? serviceName;

  /// TXT `prov=softap` (urządzenie bez Bluetooth, pkt 9.4).
  final bool softAp;

  /// TXT `ch` (pkt 10.1).
  final int channels;

  @override
  String toString() => '$id @ ${endpoint.display}';
}

/// Wykrywanie urządzeń w sieci lokalnej.
abstract class ThermostatDiscovery {
  /// Lista aktualnie widocznych termostatów, aktualizowana na bieżąco.
  /// Wykrywanie trwa, dopóki ktoś słucha strumienia.
  Stream<List<DiscoveredDevice>> watch();

  /// Szuka termostatu o danym `id`; null po [timeout].
  Future<DiscoveredDevice?> find(String id, {Duration timeout = const Duration(seconds: 4)}) async {
    try {
      final list = await watch().firstWhere((l) => l.any((d) => d.id == id)).timeout(timeout);
      return list.firstWhere((d) => d.id == id);
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    }
  }
}

/// Wykrywanie przez systemowe DNS-SD: NsdManager (Android), Bonjour (iOS).
class NsdThermostatDiscovery extends ThermostatDiscovery {
  @override
  Stream<List<DiscoveredDevice>> watch() {
    if (kIsWeb) return Stream.value(const []);

    late final StreamController<List<DiscoveredDevice>> controller;
    nsd.Discovery? discovery;
    final found = <String, DiscoveredDevice>{};

    Future<void> start() async {
      try {
        final d = await nsd.startDiscovery(homeServiceType, ipLookupType: nsd.IpLookupType.v4);
        if (controller.isClosed) {
          await nsd.stopDiscovery(d);
          return;
        }
        discovery = d;
        d.addServiceListener((service, status) {
          final key = service.name ?? service.host ?? '';
          if (status == nsd.ServiceStatus.lost) {
            found.remove(key);
          } else {
            final t = _fromService(service);
            if (t != null) found[key] = t;
          }
          if (!controller.isClosed) controller.add(found.values.toList());
        });
        controller.add(found.values.toList());
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller = StreamController<List<DiscoveredDevice>>(
      onListen: start,
      onCancel: () async {
        final d = discovery;
        discovery = null;
        if (d != null) await nsd.stopDiscovery(d).catchError((_) {});
      },
    );
    return controller.stream;
  }

  static DiscoveredDevice? _fromService(nsd.Service s) {
    final port = s.port;
    final address = s.addresses?.where((a) => a.rawAddress.length == 4).firstOrNull ?? s.addresses?.firstOrNull;
    final host = address?.address ?? s.host;
    if (host == null || port == null) return null;

    String? txt(String key) {
      final v = s.txt?[key];
      return v == null ? null : utf8.decode(v, allowMalformed: true);
    }

    final id = txt('id') ?? s.name ?? host;
    return DiscoveredDevice(
      id: id,
      endpoint: LocalEndpoint(host, port),
      type: DeviceType.fromWire(txt('type')),
      fw: txt('fw'),
      api: int.tryParse(txt('api') ?? ''),
      serviceName: s.name,
      softAp: txt('prov') == 'softap',
      channels: int.tryParse(txt('ch') ?? '') ?? 1,
    );
  }
}

/// Stara nazwa (termostat był jedynym typem).
typedef DiscoveredThermostat = DiscoveredDevice;
