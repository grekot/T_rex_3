import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cloud_store.dart';
import 'dashboard_store.dart';
import 'device_store.dart';

/// Ikony wybrane dla urządzeń (id → klucz z katalogu aplikacji). W domu w chmurze - `homes/{h}/deviceIndex/{id}/icon`
/// (pkt 12-13: wspólne dla domowników i zegarka, zmienia tylko właściciel); kopia w telefonie na czas bez internetu.
/// Bez konta - tylko w telefonie.
class DeviceIcons {
  DeviceIcons({TextCache? cache}) : _cacheOverride = cache;

  static DeviceIcons instance = DeviceIcons();

  static const _localKey = 'device_icons';

  final TextCache? _cacheOverride;

  /// Leniwie - [DeviceHub] podłącza się też tam, gdzie nie ma SharedPreferences (testy).
  late final TextCache _cache = _cacheOverride ?? PrefsTextCache();
  final icons = ValueNotifier<Map<String, String>>(const {});

  CloudStore? _store;
  String? _homeId;
  Object? _attachedBy;
  StreamSubscription<Object?>? _sub;

  /// Urządzenia z wpisem w `deviceIndex` (ikonę dopisuje się do istniejącego wpisu).
  Set<String> _indexed = const {};
  bool _cloudData = false;
  bool _loaded = false;

  /// Bez konta - każdy; w domu w chmurze - tylko właściciel (jak nazwy w `deviceIndex`).
  bool canEdit = true;

  String get _cacheKey => _homeId == null ? _localKey : '${_localKey}_$_homeId';

  /// Tryb bez konta: ikony z telefonu.
  Future<void> load() async {
    if (_loaded || _store != null) return;
    _loaded = true;
    final cached = await _readCache();
    if (cached != null && _store == null) icons.value = cached;
  }

  /// Dom w chmurze: nasłuch `deviceIndex` ([owner] - [DeviceHub], który podłączył; tylko on odłącza).
  void attach(CloudStore store, String homeId, {required bool canEdit, required Object owner}) {
    _attachedBy = owner;
    this.canEdit = canEdit;
    if (_store == store && _homeId == homeId) return;
    _sub?.cancel();
    _store = store;
    _homeId = homeId;
    _cloudData = false;
    _loaded = false;
    _indexed = const {};
    icons.value = const {};
    unawaited(
      _readCache().then((cached) {
        if (cached != null && !_cloudData && _homeId == homeId) icons.value = cached;
      }),
    );
    _sub = store.watch('homes/$homeId/deviceIndex').listen((v) {
      final j = toJsonObject(v) ?? const {};
      _cloudData = true;
      _indexed = j.keys.toSet();
      final map = {
        for (final e in j.entries)
          if (e.value is Map && (e.value as Map)['icon'] is String) e.key: (e.value as Map)['icon'] as String,
      };
      icons.value = map;
      unawaited(_writeCache(map));
    }, onError: (_) {});
  }

  void detach(Object owner) {
    if (_attachedBy != owner) return;
    _sub?.cancel();
    _sub = null;
    _store = null;
    _homeId = null;
    _attachedBy = null;
    _indexed = const {};
    _loaded = false;
    canEdit = true;
    icons.value = const {};
  }

  String? of(String deviceId) => icons.value[deviceId];

  /// null albo pusty klucz = ikona domyślna dla typu.
  Future<void> set(PairedDevice device, String? key) async {
    final icon = key == null || key.isEmpty ? null : key;
    final map = {...icons.value};
    if (icon == null) {
      map.remove(device.id);
    } else {
      map[device.id] = icon;
    }
    final store = _store, h = _homeId;
    if (store == null || h == null) {
      icons.value = map;
      await _writeCache(map);
      return;
    }
    if (!canEdit || (icon == null && !_indexed.contains(device.id))) return;
    icons.value = map;
    final path = 'homes/$h/deviceIndex/${device.id}';
    // Bez wpisu w indeksie sama ikona zrobiłaby urządzenie bez typu i nazwy.
    await (_indexed.contains(device.id)
        ? store.write('$path/icon', icon)
        : store.update(path, {'type': device.type.wire, 'name': device.name, 'icon': icon}));
  }

  Future<void> _writeCache(Map<String, String> map) async {
    try {
      await _cache.set(_cacheKey, jsonEncode(map));
    } on Object {
      // kopia tylko na czas bez internetu
    }
  }

  Future<Map<String, String>?> _readCache() async {
    try {
      final raw = await _cache.get(_cacheKey);
      return raw == null ? null : (jsonDecode(raw) as Map).cast<String, String>();
    } on Object {
      return null; // bez zapisanych ikon - domyślne
    }
  }
}
