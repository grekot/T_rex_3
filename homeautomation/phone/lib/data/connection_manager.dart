import 'package:http/http.dart' as http;

import 'cloud_access.dart';
import 'device_store.dart';
import 'discovery.dart';
import 'errors.dart';
import 'hub_child_connection.dart';
import 'local_api.dart';
import 'local_connection.dart';
import 'local_endpoint.dart';
import '../models/device_type.dart';
import '../models/set_values.dart';
import 'thermostat_connection.dart';

typedef _OpenHubLink = ({HubLink link, String host});

/// Wybiera drogę do termostatu (pkt 1 kontraktu):
/// 1. ostatni znany adres (timeout ~1 s),
/// 2. mDNS `_homeauto._tcp`,
/// 3. urządzenie podrzędne: przez hub w sieci lokalnej,
/// 4. chmura.
class ConnectionManager {
  ConnectionManager({
    required this.store,
    required this.discovery,
    this.probeTimeout = const Duration(seconds: 1),
    this.discoveryTimeout = const Duration(seconds: 4),
    this.hubPollInterval = const Duration(seconds: 3),
    CloudAccess? cloud,
    http.Client Function()? httpClientFactory,
  }) : cloud = cloud ?? NoCloudAccess(),
       _httpClientFactory = httpClientFactory ?? http.Client.new;

  final DeviceStore store;
  final CloudAccess cloud;
  final ThermostatDiscovery discovery;
  final Duration probeTimeout;
  final Duration discoveryTimeout;
  final Duration hubPollInterval;
  final http.Client Function() _httpClientFactory;
  final _hubLinks = <String, Future<_OpenHubLink?>>{};

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
    if (token != null) {
      final endpoint = await _findLocal(device, onStep: onStep, save: true);
      if (endpoint != null) return _openLocal(device, endpoint, token, codec);
    }

    // 3. Przez hub.
    final via = device.via;
    if (via != null) {
      onStep?.call('Łączenie przez hub…');
      final conn = await _openViaHub(device, via, codec);
      if (conn != null) return conn;
    }

    // 4. Chmura.
    if (cloud.available) {
      onStep?.call('Łączenie przez chmurę…');
      final conn = cloud.connection(device.id, codec);
      await conn.open();
      return conn;
    }
    if (token == null) throw const UnauthorizedException();
    throw NoRouteException('Nie znaleziono urządzenia w sieci lokalnej. ${cloud.unavailableReason}');
  }

  /// Ostatni znany adres, potem mDNS; null = nie ma go w sieci lokalnej.
  Future<LocalEndpoint?> _findLocal(
    PairedDevice device, {
    void Function(String step)? onStep,
    required bool save,
  }) async {
    final last = device.lastEndpoint;
    if (last != null) {
      onStep?.call('Łączenie z ${last.display}…');
      if (await _probe(last, device.id)) return last;
    }
    onStep?.call('Szukanie urządzenia w sieci lokalnej…');
    final found = await discovery.find(device.id, timeout: discoveryTimeout).catchError((_) => null);
    if (found == null || found.endpoint == last || !await _probe(found.endpoint, device.id)) return null;
    if (save) await store.saveDevice(device.copyWith(lastEndpoint: found.endpoint));
    return found.endpoint;
  }

  /// Łącze do huba, wspólne dla jego urządzeń; null = telefon nie ma tokenu huba albo hub jest poza zasięgiem.
  Future<_OpenHubLink?> _hubLink(String hubId) async {
    final open = await (_hubLinks[hubId] ??= _openHubLink(hubId));
    if (open == null) _hubLinks.remove(hubId);
    return open;
  }

  Future<_OpenHubLink?> _openHubLink(String hubId) async {
    final token = await store.token(hubId);
    final hub = (await store.devices()).where((d) => d.id == hubId).firstOrNull;
    if (token == null || hub == null) return null;
    // Adres zapisuje połączenie samego huba; tu wiele urządzeń naraz nadpisywałoby listę.
    final endpoint = await _findLocal(hub, save: false);
    if (endpoint == null) return null;
    final link = HubLink(
      hubId: hubId,
      api: LocalApi(endpoint, token: token, client: _httpClientFactory()),
      interval: hubPollInterval,
      onIdle: () => _hubLinks.remove(hubId),
    );
    return (link: link, host: endpoint.host);
  }

  Future<DeviceConnection<S, C>?> _openViaHub<S, C>(PairedDevice device, String hubId, DeviceCodec<S, C> codec) async {
    final open = await _hubLink(hubId);
    if (open == null) return null;
    final conn = HubChildConnection<S, C>(deviceId: device.id, link: open.link, codec: codec, hubHost: open.host);
    try {
      await conn.open();
      return conn;
    } on Object {
      // Hub nie zna urządzenia, ma starsze firmware albo zniknął - zostaje chmura.
      await conn.close();
      return null;
    }
  }

  /// Urządzenia podrzędne sparowanych hubów w zasięgu - pokazywane także bez konta i bez internetu.
  Future<List<PairedDevice>> hubChildren() async {
    final out = <PairedDevice>[];
    for (final hub in (await store.devices()).where((d) => d.type == DeviceType.hub)) {
      final open = await _hubLink(hub.id);
      if (open == null) continue;
      open.link.retain();
      try {
        for (final c in await open.link.api.devices()) {
          if (!c.mirror || c.type == null || c.type == 'unknown') continue;
          out.add(
            PairedDevice(id: c.id, name: c.label, type: DeviceType.fromWire(c.type), access: hub.access, via: hub.id),
          );
        }
      } on Object {
        // Hub zniknął - jego urządzenia zostają znane z chmury.
      } finally {
        open.link.release();
      }
    }
    return out;
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
