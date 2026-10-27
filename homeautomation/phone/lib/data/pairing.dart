import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/device_info.dart';
import '../models/home.dart';
import 'device_store.dart';
import 'errors.dart';
import 'local_api.dart';
import 'local_endpoint.dart';

/// Parowanie w sieci lokalnej (pkt 2 kontraktu): kod z OLED-a → token w bezpiecznym magazynie.
class PairingService {
  PairingService({
    required this.store,
    http.Client Function()? httpClientFactory,
    this.clientName,
    this.idToken,
    this.mePoll = const Duration(seconds: 1),
    this.meWait = const Duration(seconds: 15),
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new;

  /// Token logowania Firebase (null bez konta) - urządzenie nada z niego poziom domownika.
  final Future<String?> Function()? idToken;
  final Duration mePoll;
  final Duration meWait;

  final DeviceStore store;
  final http.Client Function() _httpClientFactory;

  /// Nazwa telefonu wysyłana jako `client`; domyślnie z device_info_plus.
  final Future<String> Function()? clientName;

  LocalApi _api(LocalEndpoint e) => LocalApi(e, client: _httpClientFactory());

  /// `GET /api/info` - sprawdza, czy pod adresem jest urządzenie w obsługiwanej wersji API.
  Future<DeviceInfo> probe(LocalEndpoint endpoint) async {
    final api = _api(endpoint);
    try {
      final info = await api.info(timeout: const Duration(seconds: 3));
      if (!info.apiSupported) {
        throw ThermostatException(
          'Urządzenie ma API w wersji ${info.api}, a aplikacja obsługuje ${supportedApiVersions.join(' i ')}. '
          'Zaktualizuj aplikację albo oprogramowanie urządzenia.',
        );
      }
      return info;
    } finally {
      api.close();
    }
  }

  /// Urządzenie pokazuje kod; zwraca czas jego ważności.
  Future<Duration> start(LocalEndpoint endpoint) async {
    final api = _api(endpoint);
    try {
      return Duration(seconds: await api.pairStart());
    } finally {
      api.close();
    }
  }

  /// Potwierdza kod, zapisuje token i urządzenie.
  /// Potwierdza kod i zapisuje token. Z kontem urządzenie dostaje `idToken`, nadaje najpierw `view`,
  /// a po sprawdzeniu tożsamości poziom domownika - wtedy czekamy na zmianę w `GET /api/me`
  /// ([onAccess] dostaje kolejne poziomy).
  Future<PairedDevice> confirm(
    LocalEndpoint endpoint,
    DeviceInfo info,
    String code, {
    void Function(AccessLevel access)? onAccess,
  }) async {
    final api = _api(endpoint);
    try {
      String? token;
      try {
        token = await idToken?.call();
      } on Object {
        token = null;
      }
      final result = await api.pairConfirm(code, await (clientName ?? defaultClientName)(), idToken: token);
      await store.saveToken(result.id, result.token);
      var device = PairedDevice(
        id: result.id,
        name: info.name.isNotEmpty ? info.name : result.id,
        type: info.type,
        lastEndpoint: endpoint,
        access: result.access,
      );
      await store.saveDevice(device);
      onAccess?.call(result.access);
      if (result.pending) {
        final level = await waitForAccess(
          LocalApi(endpoint, token: result.token, client: _httpClientFactory()),
          result.access,
        );
        if (level != result.access) {
          device = device.copyWith(access: level);
          await store.saveDevice(device);
          onAccess?.call(level);
        }
      }
      return device;
    } finally {
      api.close();
    }
  }

  /// Odpytuje `GET /api/me`, aż poziom zmieni się z [initial] (albo minie [meWait]).
  Future<AccessLevel> waitForAccess(LocalApi api, AccessLevel initial) async {
    final deadline = DateTime.now().add(meWait);
    try {
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(mePoll);
        try {
          final me = await api.me(timeout: const Duration(seconds: 3));
          if (me.access != initial) return me.access;
        } on ThermostatException {
          // Urządzenie zajęte sprawdzaniem - próbujemy dalej.
        }
      }
      return initial;
    } finally {
      api.close();
    }
  }
}

/// Np. „Google Pixel 8” albo „iPhone Kasi”.
Future<String> defaultClientName() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) return 'Przeglądarka';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final a = await plugin.androidInfo;
        final brand = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
        return '$brand${a.model}'.trim();
      case TargetPlatform.iOS:
        return (await plugin.iosInfo).name;
      default:
        return 'Telefon';
    }
  } on Object {
    return 'Telefon';
  }
}
