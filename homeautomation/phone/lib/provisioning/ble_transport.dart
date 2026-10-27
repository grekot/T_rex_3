import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'messages.dart';
import 'provisioner.dart';

/// Usługa BLE provisioningu Espressif ustawiona w firmware (`wifi_prov_scheme_ble_set_service_uuid`).
final provServiceUuid = Guid('021a9004-0382-4aea-bff4-6b3f1c5adfb4');

/// Prefiks nazwy Bluetooth urządzeń w trybie konfiguracji (kontrakt pkt 9.1).
const provNamePrefix = 'HA_';

/// Deskryptor „Characteristic User Description” - ESP-IDF zapisuje w nim nazwę endpointu.
final _userDescription = Guid('2901');

/// Urządzenie znalezione w trybie konfiguracji.
class ProvCandidate {
  const ProvCandidate(this.name, this.rssi, [this.handle]);

  /// Np. `HA_termostat-ab12cd`.
  final String name;
  final int rssi;

  /// Obiekt transportu (dla BLE: [BluetoothDevice]).
  final Object? handle;

  /// `termostat-ab12cd`.
  String get id => name.startsWith(provNamePrefix) ? name.substring(provNamePrefix.length) : name;
}

/// Skąd brać urządzenia w trybie konfiguracji i jak się z nimi łączyć (BLE albo atrapa w testach).
abstract class ProvisioningBackend {
  bool get supported;

  Stream<List<ProvCandidate>> scan();

  Future<ProvTransport> connect(ProvCandidate candidate);

  /// Czy transport umie skanować sieci (bez tego SSID wpisuje się ręcznie).
  bool canScan(ProvTransport transport) => true;
}

class BleProvisioningBackend extends ProvisioningBackend {
  @override
  bool get supported => bluetoothSupported;

  @override
  Stream<List<ProvCandidate>> scan() => scanProvDevices();

  @override
  Future<ProvTransport> connect(ProvCandidate candidate) =>
      BleProvTransport.connect(candidate.handle! as BluetoothDevice);

  @override
  bool canScan(ProvTransport transport) => transport is! BleProvTransport || transport.canScan;
}

bool get bluetoothSupported =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Skan BLE: urządzenia `HA_*` aktualizowane na bieżąco, dopóki ktoś słucha.
Stream<List<ProvCandidate>> scanProvDevices({Duration timeout = const Duration(seconds: 20)}) {
  late final StreamController<List<ProvCandidate>> controller;
  StreamSubscription<List<ScanResult>>? sub;

  Future<void> start() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw const ProvisioningException('Ten telefon nie obsługuje Bluetooth LE.');
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        await FlutterBluePlus.turnOn().catchError((_) {});
      }
      final adapter = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.unknown);
      if (adapter != BluetoothAdapterState.on) {
        throw const ProvisioningException('Włącz Bluetooth w telefonie.');
      }
      sub = FlutterBluePlus.scanResults.listen((results) {
        final found = <String, ProvCandidate>{};
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
          if (name.startsWith(provNamePrefix)) found[name] = ProvCandidate(name, r.rssi, r.device);
        }
        if (!controller.isClosed) {
          controller.add(found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
        }
      });
      await FlutterBluePlus.startScan(
        withKeywords: const [provNamePrefix],
        timeout: timeout,
        // Android 11 i starsze wymagają lokalizacji do skanu BLE.
        androidUsesFineLocation: await _needsLocationForScan(),
      );
    } on Object catch (e) {
      if (!controller.isClosed) controller.addError(e is ProvisioningException ? e : ProvisioningException('$e'));
    }
  }

  controller = StreamController<List<ProvCandidate>>(
    onListen: start,
    onCancel: () async {
      await sub?.cancel();
      await FlutterBluePlus.stopScan().catchError((_) {});
    },
  );
  return controller.stream;
}

Future<bool> _needsLocationForScan() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt <= 30;
  } on Object {
    return true;
  }
}

/// Transport provisioningu przez GATT: zapis do charakterystyki endpointu, potem odczyt odpowiedzi.
/// Charakterystyki rozpoznajemy po nazwie w deskryptorze 0x2901 (np. `prov-session`, `ha-pair`).
class BleProvTransport implements ProvTransport {
  BleProvTransport._(this.device, this._endpoints);

  final BluetoothDevice device;
  final Map<String, BluetoothCharacteristic> _endpoints;

  static Future<BleProvTransport> connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan().catchError((_) {});
    await device.connect(timeout: const Duration(seconds: 20));
    try {
      final services = await device.discoverServices();
      final service = services.where((s) => s.serviceUuid == provServiceUuid).firstOrNull;
      if (service == null) {
        throw const ProvisioningException('Urządzenie nie ma usługi konfiguracji WiFi.');
      }
      final endpoints = <String, BluetoothCharacteristic>{};
      for (final c in service.characteristics) {
        final desc = c.descriptors.where((d) => d.descriptorUuid == _userDescription).firstOrNull;
        if (desc == null) continue;
        final name = utf8.decode(await desc.read(), allowMalformed: true).trim();
        if (name.isNotEmpty) endpoints[name] = c;
      }
      for (final required in const ['prov-session', 'prov-config', 'ha-pair']) {
        if (!endpoints.containsKey(required)) {
          throw ProvisioningException('Urządzenie nie ma endpointu $required - zaktualizuj firmware.');
        }
      }
      return BleProvTransport._(device, endpoints);
    } on Object {
      await device.disconnect().catchError((_) {});
      rethrow;
    }
  }

  /// Czy urządzenie umie skanować sieci (`prov-scan`); bez tego SSID wpisuje się ręcznie.
  bool get canScan => _endpoints.containsKey('prov-scan');

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List data) async {
    final c = _endpoints[endpoint];
    if (c == null) throw ProvisioningException('Brak endpointu $endpoint.');
    await c.write(data, allowLongWrite: data.length > device.mtuNow - 3);
    return Uint8List.fromList(await c.read());
  }

  @override
  Future<void> close() => device.disconnect().catchError((_) {});
}
