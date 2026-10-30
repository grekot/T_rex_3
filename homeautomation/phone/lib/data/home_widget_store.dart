import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_widget.dart';

/// Ustawienia widżetów na ekranie telefonu; zapisuje ekran konfiguracji, czyta usługa w tle.
class HomeWidgetStore {
  HomeWidgetStore({SharedPreferencesAsync? prefs}) : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'home_widgets';

  final SharedPreferencesAsync _prefs;

  Future<List<HomeWidgetConfig>> load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          if (e is Map) HomeWidgetConfig.fromJson(e.cast<String, dynamic>()),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> save(HomeWidgetConfig config) async {
    final all = [
      ...(await load()).where((c) => c.id != config.id),
      config,
    ];
    await _prefs.setString(_key, jsonEncode([for (final c in all) c.toJson()]));
  }

  /// Usuwa wpisy widżetów, których nie ma już na ekranie.
  Future<void> retain(Set<int> ids) async {
    final all = await load();
    final kept = all.where((c) => ids.contains(c.id)).toList();
    if (kept.length == all.length) return;
    await _prefs.setString(_key, jsonEncode([for (final c in kept) c.toJson()]));
  }
}

/// Widżet termostatu otwiera aplikację na tym urządzeniu.
class HomeWidgetLink {
  const HomeWidgetLink(this.homeId, this.deviceId);

  final String homeId;
  final String deviceId;

  /// Odłożone na czas przełączania domu.
  static HomeWidgetLink? pending;

  static const _channel = MethodChannel('pl.grekot.homeautomation/widget_link');

  /// Zwraca adres z dotknięcia widżetu (raz) albo null.
  static Future<HomeWidgetLink?> take() async {
    final p = pending;
    if (p != null) {
      pending = null;
      return p;
    }
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('take');
      final device = m?['device'];
      if (device is! String) return null;
      final configs = await HomeWidgetStore().load();
      final config = configs.where((c) => c.id == m?['widget']).firstOrNull;
      return config == null ? null : HomeWidgetLink(config.homeId, device);
    } on Object {
      return null; // poza Androidem
    }
  }
}
