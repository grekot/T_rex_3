import 'package:flutter/widgets.dart';

import 'data/cloud_access.dart';
import 'data/connection_manager.dart';
import 'data/dashboard_store.dart';
import 'data/device_store.dart';
import 'data/discovery.dart';
import 'data/pairing.dart';
import 'data/room_store.dart';
import 'data/scene_store.dart';
import 'provisioning/ble_transport.dart';
import 'provisioning/softap_transport.dart';

/// Zależności aplikacji dostępne z drzewa widżetów.
class Services extends InheritedWidget {
  Services({
    super.key,
    required this.store,
    required this.discovery,
    required this.manager,
    required this.pairing,
    required this.cloud,
    required this.provisioning,
    required this.rooms,
    DashboardStore? dashboards,
    SceneStore? scenes,
    SoftApProvisioning? softAp,
    required super.child,
  }) : dashboards = dashboards ?? LocalDashboardStore(cache: MemoryTextCache()),
       scenes = scenes ?? LocalSceneStore(cache: MemoryTextCache()),
       softAp = softAp ?? SoftApProvisioning();

  factory Services.production({required CloudAccess cloud, required Widget child}) {
    final store = SecureDeviceStore();
    final discovery = NsdThermostatDiscovery();
    return Services(
      store: store,
      discovery: discovery,
      manager: ConnectionManager(store: store, discovery: discovery, cloud: cloud),
      pairing: PairingService(store: store, idToken: cloud.idToken),
      cloud: cloud,
      provisioning: BleProvisioningBackend(),
      rooms: AccountRoomStore(cloud),
      dashboards: AccountDashboardStore(cloud),
      scenes: AccountSceneStore(cloud),
      child: child,
    );
  }

  final DeviceStore store;
  final CloudAccess cloud;

  /// Konfiguracja WiFi nowych urządzeń (Bluetooth).
  final ProvisioningBackend provisioning;

  /// Konfiguracja WiFi urządzeń bez Bluetooth - przez ich sieć `HA_*` (pkt 9.4).
  final SoftApProvisioning softAp;

  /// Pokoje: w chmurze z kontem, lokalnie bez Firebase.
  final RoomStore rooms;

  /// Pulpity (pkt 13): w chmurze z kontem i domem, inaczej w telefonie.
  final DashboardStore dashboards;

  /// Sceny domu (`homes/{h}/scenes`).
  final SceneStore scenes;
  final ThermostatDiscovery discovery;
  final ConnectionManager manager;
  final PairingService pairing;

  static Services of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<Services>();
    assert(s != null, 'Brak Services w drzewie widżetów');
    return s!;
  }

  @override
  bool updateShouldNotify(Services oldWidget) =>
      store != oldWidget.store || manager != oldWidget.manager || pairing != oldWidget.pairing;
}
