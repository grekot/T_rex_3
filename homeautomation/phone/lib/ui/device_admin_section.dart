import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../data/cloud_access.dart';
import '../data/cloud_connection.dart' show cloudDevicePath;
import '../data/cloud_store.dart' show toJsonObject;
import '../data/device_store.dart';
import '../data/errors.dart';
import '../data/local_api.dart';
import '../models/device_info.dart';
import '../models/device_type.dart';
import '../services.dart';
import 'ble_setup_screen.dart';
import 'cloud_link_screen.dart';
import 'diag_screen.dart';
import 'firmware_screen.dart';
import 'hub_screen.dart' show AssignToHubScreen;
import 'notify_screen.dart';
import 'phones_screen.dart';
import 'wifi_ap_screen.dart';
import 'format.dart';
import 'widgets.dart';

/// Ustawienia wspólne dla każdego typu urządzenia: chmura, aktualizacja firmware,
/// zmiana sieci WiFi (pkt 9.3), identyfikator. Zmiany działają tylko w sieci domowej.
/// Urządzenie za hubem (`via`): chmura = lustro huba (`deviceIndex/{id}/via`, pkt 11), „Do chmury” także spoza domu.
class DeviceAdminSection extends StatefulWidget {
  const DeviceAdminSection({super.key, required this.controller, required this.cloudLinked, this.uptime});

  final DeviceController<Object?, Object?> controller;

  /// `cloud` ze State urządzenia.
  final bool cloudLinked;

  /// `uptime` ze State (s).
  final int? uptime;

  @override
  State<DeviceAdminSection> createState() => _DeviceAdminSectionState();
}

class _DeviceAdminSectionState extends State<DeviceAdminSection> {
  DeviceController<Object?, Object?> get c => widget.controller;

  /// `GET /api/cloud` (tylko lokalnie) - np. ostatni błąd logowania urządzenia.
  Future<CloudLinkStatus?>? _cloudLink;

  /// `GET /api/info` (lokalnie): `prov` (zmiana sieci przez SoftAP) i `cloud: false` (węzeł bez chmury).
  DeviceInfo? _info;

  /// Urządzenie z wyborem punktu sieci mesh (`GET /api/wifi` odpowiada, pkt 9.6) - lokalnie, poziom `config`.
  bool _wifiAp = false;

  /// Za hubem: czy `deviceIndex/{id}/via` wskazuje ten hub (hub prowadzi lustro w chmurze); null = jeszcze nie wiadomo.
  bool? _viaLinked;
  String? _hubName;
  bool _viaLoading = false;

  /// Hub, przez który urządzenie jest dostępne (pkt 11); null = własne połączenie.
  String? get _via => c.device.via;

  /// Urządzenie innej firmy albo czujnik Bluetooth za hubem - bez API węzła (WiFi, telefony, firmware, ntfy).
  bool get _foreign => _via != null && RegExp(r'^(ble|shelly|tasmota|ewelink|sonoff|tuya)-').hasMatch(c.device.id);

  @override
  void initState() {
    super.initState();
    _refreshCloud();
    c.localApi?.info(timeout: const Duration(seconds: 3)).then((i) {
      if (mounted) setState(() => _info = i);
    }, onError: (_) {});
    if (c.canConfig) {
      c.localApi?.wifiAp(timeout: const Duration(seconds: 3)).then((w) {
        if (mounted && w != null) setState(() => _wifiAp = true);
      }, onError: (_) {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_via != null && _viaLinked == null && !_viaLoading) _loadVia();
  }

  Future<void> _loadVia() async {
    final services = Services.of(context);
    final cloud = services.cloud, via = _via!;
    _viaLoading = true;
    final hubName = (await services.store.devices().catchError(
      (_) => const <PairedDevice>[],
    )).where((d) => d.id == via).firstOrNull?.name;
    var linked = false;
    final h = cloud.homeId;
    if (cloud.available && h != null) {
      linked = await cloud.store.read('homes/$h/deviceIndex/${c.device.id}/via').catchError((_) => null) == via;
    }
    if (!mounted) return;
    setState(() {
      _hubName = hubName;
      _viaLinked = linked;
      _viaLoading = false;
    });
  }

  /// Jak „Do chmury” na ekranie huba: właściciel wpisuje `deviceIndex/{id}` z `via`, hub zakłada lustro (do 5 min).
  /// Sam zapis w bazie - działa też spoza domu.
  Future<void> _linkViaHub(CloudAccess cloud) async {
    final messenger = ScaffoldMessenger.of(context);
    final d = c.device;
    try {
      await writeDeviceIndex(cloud.store, cloud.homeId!, d.id, d.type, d.name, via: _via);
      if (mounted) setState(() => _viaLinked = true);
      messenger.showSnackBar(SnackBar(content: Text('Zapisano. Hub połączy „${d.name}” z chmurą w ciągu 5 minut.')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie zapisano: $e')));
    }
  }

  /// „Diagnostyka” (pkt 3c): w domu z urządzenia (także dziennik), poza domem kopia z chmury; poziom `config`.
  Widget _diagTile(CloudAccess cloud) {
    final h = cloud.homeId;
    final viaCloud = !c.isLocal && cloud.available && h != null && _via == null;
    final can = c.canConfig && (c.isLocal || viaCloud);
    return ListTile(
      key: const Key('diag'),
      leading: const Icon(Icons.monitor_heart_outlined),
      title: const Text('Diagnostyka'),
      subtitle: Text(
        !c.canConfig
            ? 'Wymaga pełnego dostępu do urządzenia'
            : c.isLocal
            ? 'Restarty, pamięć, błędy, awarie i dziennik'
            : viaCloud
            ? 'Kopia z chmury (dziennik - w sieci domowej)'
            : 'Tylko w sieci domowej',
      ),
      enabled: can,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DiagScreen(
            name: c.device.name,
            api: c.localApi,
            cloudDiag: viaCloud
                ? () async => toJsonObject(await cloud.store.read('${cloudDevicePath(h, c.device.id)}/diag'))
                : null,
          ),
        ),
      ),
    );
  }

  /// Sekcja „Chmura” urządzenia za hubem: stan lustra przez hub i „Do chmury”.
  List<Widget> _viaCloud(CloudAccess cloud) {
    final linked = _viaLinked;
    final hub = _hubName ?? 'hub';
    final canLink = cloud.available && cloud.isHomeOwner && cloud.homeId != null;
    return [
      const SectionHeader('Chmura'),
      ListTile(
        key: const Key('viaCloud'),
        leading: Icon(linked == true ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
        title: Text(linked == true ? 'W chmurze przez $hub' : 'Tylko w domu'),
        subtitle: Text(
          cloud is NoCloudAccess
              ? cloud.unavailableReason
              : linked == null
              ? 'Sprawdzanie…'
              : linked
              ? 'Hub przesyła stan do chmury - widać go spoza domu i na zegarku.'
              : 'Hub nie przesyła stanu do chmury: spoza domu i na zegarku poza zasięgiem nie będzie widoczne.',
        ),
      ),
      if (linked == false && cloud is! NoCloudAccess)
        ListTile(
          key: const Key('linkViaHub'),
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Do chmury'),
          subtitle: Text(canLink ? 'Hub połączy urządzenie z chmurą w ciągu 5 minut' : 'Łączy właściciel domu'),
          enabled: canLink,
          onTap: () => _linkViaHub(cloud),
        ),
    ];
  }

  void _refreshCloud() => _cloudLink = c.cloudStatus().catchError((_) => null);

  Future<void> _linkCloud(CloudAccess cloud) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudLinkScreen(controller: c, cloud: cloud),
      ),
    );
    if (mounted) setState(_refreshCloud);
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _unlinkCloud(CloudAccess cloud) async {
    if (!await _confirm(
      'Odłączyć od chmury?',
      'Urządzenie zapomni swoje konto w chmurze i przestanie wysyłać stan. '
          'Spoza domu nie będzie można nim sterować. W domu działa dalej normalnie.',
      'Odłącz',
    )) {
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deviceUid = (await c.cloudStatus())?.deviceUid;
      await c.unlinkCloud();
      // Wiązanie konta urządzenia z domem usuwa właściciel (pkt 8.2).
      final h = cloud.homeId;
      if (deviceUid != null && h != null && cloud.isHomeOwner) {
        await bindDeviceAccount(cloud.store, h, deviceUid, null).catchError((_) {});
      }
      messenger.showSnackBar(const SnackBar(content: Text('Odłączono od chmury.')));
      if (mounted) setState(_refreshCloud);
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// `POST /api/wifi/reset`, potem konfiguracja przez Bluetooth tym samym kreatorem co nowe urządzenie.
  Future<void> _changeWifi() async {
    if (!await _confirm(
      'Zmienić sieć WiFi?',
      _info?.prov == ProvScheme.softap
          ? 'Urządzenie zapomni obecną sieć i wystawi własną sieć WiFi HA_… Telefon połączy się z nią '
                'kodem z naklejki. Token, chmura i ustawienia zostają.'
          : 'Urządzenie zapomni obecną sieć i uruchomi się w trybie konfiguracji Bluetooth. Telefon musi być '
                'obok urządzenia, a kod z ekranu będzie potrzebny. Token, chmura i ustawienia zostają.',
      'Zmień sieć',
    )) {
      return;
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.wifiReset();
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final device = await navigator.push<PairedDevice>(
      MaterialPageRoute(
        builder: (_) => BleSetupScreen(expectedId: c.device.id, softAp: _info?.prov == ProvScheme.softap),
      ),
    );
    if (device != null) await c.connect();
  }

  /// Zmiany techniczne: tylko w domu (lokalnie) i z poziomem `config`.
  bool get _canAdmin => c.isLocal && c.canConfig;

  String get _adminHint => !c.canConfig ? 'Wymaga pełnego dostępu do urządzenia' : 'Tylko w sieci domowej';

  @override
  Widget build(BuildContext context) {
    final cloud = Services.of(context).cloud;
    final linked = widget.cloudLinked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_via != null)
          ..._viaCloud(cloud)
        else if (_info?.cloud == false) ...[
          const SectionHeader('Chmura'),
          const ListTile(
            key: Key('noCloud'),
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Urządzenie bez własnej chmury'),
            subtitle: Text('Działa w sieci domowej. Spoza domu będzie dostępne przez hub.'),
          ),
        ] else ...[
          const SectionHeader('Chmura'),
          ListTile(
            leading: Icon(linked ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
            title: const Text('Urządzenie w chmurze'),
            subtitle: Text(
              cloud is NoCloudAccess
                  ? cloud.unavailableReason
                  : !_canAdmin
                  ? (c.canConfig ? 'Łączenie i odłączanie tylko w sieci domowej.' : '$_adminHint.')
                  : linked
                  ? 'Urządzenie odbiera polecenia z chmury.'
                  : 'Urządzenie nie jest połączone z chmurą.',
            ),
            trailing: Text(linked ? 'połączone' : 'niepołączone'),
          ),
          if (_canAdmin)
            FutureBuilder<CloudLinkStatus?>(
              future: _cloudLink,
              builder: (context, snap) {
                final s = snap.data;
                final text = switch (s?.status) {
                  'linked' when !s!.connected => 'Konto zapisane, urządzenie łączy się z bazą…',
                  'linking' => 'Urządzenie zakłada konto w chmurze…',
                  'binding' => 'Konto urządzenia czeka na przypisanie do domu - połącz ponownie.',
                  'error' => 'Ostatnia próba nieudana: ${s!.error ?? 'nieznany błąd'}',
                  _ => null,
                };
                if (text == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: Text(text, style: Theme.of(context).textTheme.bodySmall),
                );
              },
            ),
          if (cloud is! NoCloudAccess && _canAdmin) ...[
            ListTile(
              key: const Key('linkCloud'),
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text(linked ? 'Połącz ponownie' : 'Połącz z chmurą'),
              enabled: cloud.available && cloud.isHomeOwner,
              subtitle: !cloud.available
                  ? Text(cloud.unavailableReason ?? '')
                  : cloud.isHomeOwner
                  ? null
                  : const Text('Łączy właściciel domu'),
              onTap: () => _linkCloud(cloud),
            ),
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Odłącz od chmury'),
              onTap: () => _unlinkCloud(cloud),
            ),
          ],
        ],
        if (_canAdmin && c.device.type != DeviceType.hub)
          ListTile(
            key: const Key('assignHub'),
            leading: const Icon(Icons.device_hub),
            title: const Text('Przypisz do huba'),
            subtitle: Text(
              c.device.type == DeviceType.thermostat
                  ? 'Termostat w automatykach huba (token sterowania)'
                  : 'Hub zbiera stan, prowadzi automatyki i łączy z chmurą',
            ),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => AssignToHubScreen(controller: c))),
          ),
        const SectionHeader('Urządzenie'),
        // Czujnik Bluetooth i urządzenia innych firm za hubem nie mają API węzła (WiFi, ntfy, telefony, firmware).
        if (!_foreign) ...[
          ListTile(
            key: const Key('changeWifi'),
            leading: const Icon(Icons.wifi_find),
            title: const Text('Zmień sieć WiFi'),
            subtitle: Text(_canAdmin ? 'Przez Bluetooth, telefon obok urządzenia' : _adminHint),
            enabled: _canAdmin,
            onTap: _changeWifi,
          ),
          if (_wifiAp)
            ListTile(
              key: const Key('wifiAp'),
              leading: const Icon(Icons.router_outlined),
              title: const Text('Punkt WiFi'),
              subtitle: Text(_canAdmin ? 'Który punkt sieci (np. Deco): najsilniejszy albo wybrany' : _adminHint),
              enabled: _canAdmin,
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WifiApScreen.forController(c))),
            ),
          ListTile(
            key: const Key('notify'),
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Powiadomienia na telefon'),
            subtitle: Text(_canAdmin ? 'Alarm wysyła samo urządzenie przez aplikację ntfy' : _adminHint),
            enabled: _canAdmin,
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NotifyScreen.forController(c))),
          ),
          ListTile(
            key: const Key('phones'),
            leading: const Icon(Icons.phone_android),
            title: const Text('Telefony'),
            subtitle: Text(_canAdmin ? 'Sparowane telefony i ich poziomy dostępu' : _adminHint),
            enabled: _canAdmin,
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PhonesScreen(controller: c))),
          ),
          ListTile(
            key: const Key('firmware'),
            leading: const Icon(Icons.system_update_alt),
            title: const Text('Aktualizacja firmware'),
            subtitle: Text(_canAdmin ? 'Wgraj plik .bin z komputera albo telefonu' : _adminHint),
            enabled: _canAdmin,
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FirmwareScreen(controller: c))),
          ),
        ],
        if (_via != null) ListTile(dense: true, title: const Text('Przez hub'), trailing: Text(_hubName ?? _via!)),
        if (!_foreign) _diagTile(Services.of(context).cloud),
        ListTile(dense: true, title: const Text('Identyfikator'), trailing: Text(c.device.id)),
        ListTile(dense: true, title: const Text('Typ'), trailing: Text(c.device.type.label)),
        ListTile(dense: true, title: const Text('Mój dostęp'), trailing: Text(c.access.label)),
        if (widget.uptime != null)
          ListTile(dense: true, title: const Text('Czas pracy'), trailing: Text(fmtUptime(widget.uptime!))),
      ],
    );
  }
}
