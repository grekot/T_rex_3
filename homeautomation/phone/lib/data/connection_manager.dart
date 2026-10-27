import 'package:http/http.dart' as http;

import 'cloud_access.dart';
import 'device_store.dart';
import 'discovery.dart';
import 'errors.dart';
import 'local_api.dart';
import 'local_connection.dart';
import 'local_endpoint.dart';
import '../models/device_type.dart';
import '../models/set_values.dart';
import 'thermostat_connection.dart';

/// Wybiera drogę do termostatu (pkt 1 kontraktu):
/// 1. ostatni znany adres (timeout ~1 s),
/// 2. mDNS `_termostat._tcp`,
/// 3. chmura.
class ConnectionManager {
  ConnectionManager({
    required this.store,
    required this.discovery,
    this.probeTimeout = const Duration(seconds: 1),
    this.discoveryTimeout = const Duration(seconds: 4),
    CloudAccess? cloud,
    http.Client Function()? httpClientFactory,
  }) : cloud = cloud ?? NoCloudAccess(),
       _httpClientFactory = httpClientFactory ?? http.Client.new;

  final DeviceStore store;
  final CloudAccess cloud;
  final ThermostatDiscovery discovery;
  final Duration probeTimeout;
  final Duration discoveryTimeout;
  final http.Client Function() _httpClientFactory;

  /// Połączenie z termostatem.
  Future<ThermostatConnection> connect(PairedDevice device, {void Function(String step)? onStep}) =>
      connectWith(device, thermostatCodec, onStep: onStep);

  /// Zwraca otwarte połączenie z urządzeniem danego typu. [onStep] dostaje opis bieżącego kroku do UI.
  Future<DeviceConnection<S, C>> connectWith<S, C>(
    PairedDevice device,
    DeviceCodec<S, C> codec, {
    void Function(String step)? onStep,
  }) async {
    // Urządzenie znane tylko z konta w chmurze nie ma tokenu - wtedy od razu chmura.
    final token = await store.token(device.id);
    final last = device.lastEndpoint;
    if (token != null) {
      // 1. Ostatni znany adres.
      if (last != null) {
        onStep?.call('Łączenie z ${last.display}…');
        if (await _probe(last, device.id)) {
          return _openLocal(device, last, token, codec);
        }
      }

      // 2. mDNS.
      onStep?.call('Szukanie urządzenia w sieci lokalnej…');
      final found = await discovery.find(device.id, timeout: discoveryTimeout).catchError((_) => null);
      if (found != null && found.endpoint != last && await _probe(found.endpoint, device.id)) {
        await store.saveDevice(device.copyWith(lastEndpoint: found.endpoint));
        return _openLocal(device, found.endpoint, token, codec);
      }
    }

    // 3. Chmura.
    if (cloud.available) {
      onStep?.call('Łączenie przez chmurę…');
      final conn = cloud.connection(device.id, codec);
      await conn.open();
      return conn;
    }
    if (token == null) throw const UnauthorizedException();
    throw NoRouteException('Nie znaleziono urządzenia w sieci lokalnej. ${cloud.unavailableReason}');
  }

  /// Czy pod adresem odpowiada właśnie to urządzenie.
  Future<bool> _probe(LocalEndpoint endpoint, String id) async {
    if (!isLocalNetworkHost(endpoint.host)) return false;
    final api = LocalApi(endpoint, client: _httpClientFactory());
    try {
      final info = await api.info(timeout: probeTimeout);
      return info.id == id;
    } on Object {
      return false;
    } finally {
      api.close();
    }
  }

  Future<DeviceConnection<S, C>> _openLocal<S, C>(
    PairedDevice device,
    LocalEndpoint endpoint,
    String token,
    DeviceCodec<S, C> codec,
  ) async {
    final conn = LocalConnection<S, C>(
      deviceId: device.id,
      endpoint: endpoint,
      token: token,
      codec: codec,
      client: _httpClientFactory(),
    );
    try {
      await conn.open();
    } on Object {
      await conn.close();
      rethrow;
    }
    return conn;
  }
}
