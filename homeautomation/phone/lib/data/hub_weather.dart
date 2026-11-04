import 'package:flutter/services.dart';

import '../controllers/device_controller.dart';
import '../models/hub_weather.dart';
import 'cloud_access.dart';
import 'errors.dart';

/// Prognoza huba (pkt 11): w domu `GET /api/weather`, poza domem `homes/{h}/devices/{hubId}/weather`.
/// Pamięć na 15 min (hub i tak pobiera prognozę co godzinę); błędy - null.
class HubForecasts {
  HubForecasts._();

  static final instance = HubForecasts._();

  static const ttl = Duration(minutes: 15);

  final _cache = <String, ({DateTime at, HubForecast? value})>{};
  final _loading = <String, Future<HubForecast?>>{};

  /// Prognoza z pamięci (także starsza niż [ttl]) - do pierwszego rysowania.
  HubForecast? cached(String hubId) => _cache[hubId]?.value;

  /// Prognoza, pobrana na nowo po [ttl].
  Future<HubForecast?> load(DeviceController<Object?, Object?> hub, CloudAccess cloud, String? homeId) {
    final id = hub.device.id;
    final c = _cache[id];
    if (c != null && DateTime.now().difference(c.at) < ttl) return Future.value(c.value);
    return _loading[id] ??= _fetch(hub, cloud, homeId)
        .then((v) {
          _cache[id] = (at: DateTime.now(), value: v ?? c?.value);
          return v ?? c?.value;
        })
        .whenComplete(() => _loading.remove(id));
  }

  Future<HubForecast?> _fetch(DeviceController<Object?, Object?> hub, CloudAccess cloud, String? homeId) async {
    try {
      final local = hub.localApi;
      if (local != null) return HubForecast.fromJson(await local.request('GET', '/api/weather'));
      if (cloud.available && homeId != null) {
        return HubForecast.fromJson(await cloud.store.read('homes/$homeId/devices/${hub.device.id}/weather'));
      }
    } on Object {
      // Brak prognozy - kafelek pokazuje samą bieżącą pogodę.
    }
    return null;
  }

  /// Do testów.
  void clear() {
    _cache.clear();
    _loading.clear();
  }
}

const _location = MethodChannel('pl.grekot.homeautomation/location');

/// Przybliżone położenie telefonu (kanał natywny w MainActivity.kt; system pyta o zgodę przy pierwszym razie).
Future<({double lat, double lon})> phoneLocation() async {
  try {
    final r = await _location.invokeMapMethod<String, Object?>('current');
    final lat = r?['lat'], lon = r?['lon'];
    if (lat is num && lon is num) return (lat: lat.toDouble(), lon: lon.toDouble());
    throw const ThermostatException('Telefon nie podał położenia.');
  } on PlatformException catch (e) {
    throw ThermostatException(switch (e.code) {
      'denied' => 'Brak zgody na lokalizację - zezwól w ustawieniach telefonu albo wpisz ręcznie.',
      'disabled' => 'Lokalizacja w telefonie jest wyłączona - włącz ją albo wpisz ręcznie.',
      _ => 'Telefon nie zna teraz położenia - spróbuj za chwilę albo wpisz ręcznie.',
    });
  } on MissingPluginException {
    throw const ThermostatException('Ten telefon nie poda położenia - wpisz ręcznie.');
  }
}
