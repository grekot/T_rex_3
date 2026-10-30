import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/device_type.dart';
import '../models/home.dart';
import '../models/json_utils.dart';
import 'local_endpoint.dart';

/// Urządzenie zapamiętane w telefonie (sparowane albo znane z konta w chmurze).
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    this.lastEndpoint,
    this.type = DeviceType.thermostat,
    this.access = AccessLevel.none,
    this.via,
  });

  final String id;
  final String name;
  final DeviceType type;

  /// Poziom tokenu tego telefonu (pkt 2); `none` = nieznany (np. urządzenie tylko z konta).
  final AccessLevel access;

  /// Ostatni adres, pod którym termostat odpowiedział w sieci lokalnej.
  final LocalEndpoint? lastEndpoint;

  /// Hub, przez który urządzenie jest dostępne (pkt 11); nie zapisujemy - przychodzi z huba albo z `deviceIndex`.
  final String? via;

  PairedDevice copyWith({String? name, LocalEndpoint? lastEndpoint, DeviceType? type, AccessLevel? access}) =>
      PairedDevice(
        id: id,
        name: name ?? this.name,
        lastEndpoint: lastEndpoint ?? this.lastEndpoint,
        type: type ?? this.type,
        access: access ?? this.access,
        via: via,
      );

  factory PairedDevice.fromJson(Json j) {
    final host = asStringOrNull(j['host'], 'host');
    return PairedDevice(
      id: asString(j['id'], 'id'),
      name: asString(j['name'], 'name'),
      type: DeviceType.fromWire(asStringOrNull(j['type'], 'type')),
      // Tokeny sprzed v2 były jedne dla urządzenia, z pełnym dostępem.
      access: j.containsKey('access') ? AccessLevel.fromWire(j['access']) : AccessLevel.config,
      lastEndpoint: host == null ? null : LocalEndpoint(host, asInt(j['port'], 'port', 80)),
    );
  }

  Json toJson() => {
    'id': id,
    'name': name,
    'type': type.wire,
    'access': access.wire,
    if (lastEndpoint != null) 'host': lastEndpoint!.host,
    if (lastEndpoint != null) 'port': lastEndpoint!.port,
  };
}

/// Lista sparowanych termostatów i ich tokeny.
abstract class DeviceStore {
  Future<List<PairedDevice>> devices();
  Future<void> saveDevice(PairedDevice device);
  Future<void> removeDevice(String id);
  Future<String?> token(String id);
  Future<void> saveToken(String id, String token);
}

/// Lista urządzeń w SharedPreferences, tokeny w bezpiecznym magazynie
/// (Android Keystore / iOS Keychain).
class SecureDeviceStore implements DeviceStore {
  SecureDeviceStore({FlutterSecureStorage? secure, SharedPreferencesAsync? prefs})
    : _secure = secure ?? const FlutterSecureStorage(),
      _prefs = prefs ?? SharedPreferencesAsync();

  static const _devicesKey = 'devices';

  final FlutterSecureStorage _secure;
  final SharedPreferencesAsync _prefs;

  String _tokenKey(String id) => 'token_$id';

  @override
  Future<List<PairedDevice>> devices() async {
    final raw = await _prefs.getString(_devicesKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [for (final e in list) PairedDevice.fromJson((e as Map).cast<String, dynamic>())];
    } on Object {
      return [];
    }
  }

  Future<void> _write(List<PairedDevice> list) =>
      _prefs.setString(_devicesKey, jsonEncode([for (final d in list) d.toJson()]));

  @override
  Future<void> saveDevice(PairedDevice device) async {
    final list = await devices();
    final i = list.indexWhere((d) => d.id == device.id);
    if (i >= 0) {
      list[i] = device;
    } else {
      list.add(device);
    }
    await _write(list);
  }

  @override
  Future<void> removeDevice(String id) async {
    final list = await devices()
      ..removeWhere((d) => d.id == id);
    await _write(list);
    await _secure.delete(key: _tokenKey(id));
  }

  @override
  Future<String?> token(String id) => _secure.read(key: _tokenKey(id));

  @override
  Future<void> saveToken(String id, String token) => _secure.write(key: _tokenKey(id), value: token);
}

/// Magazyn w pamięci - do testów i podglądu.
class MemoryDeviceStore implements DeviceStore {
  final _devices = <String, PairedDevice>{};
  final _tokens = <String, String>{};

  @override
  Future<List<PairedDevice>> devices() async => _devices.values.toList();

  @override
  Future<void> saveDevice(PairedDevice device) async => _devices[device.id] = device;

  @override
  Future<void> removeDevice(String id) async {
    _devices.remove(id);
    _tokens.remove(id);
  }

  @override
  Future<String?> token(String id) async => _tokens[id];

  @override
  Future<void> saveToken(String id, String token) async => _tokens[id] = token;
}
