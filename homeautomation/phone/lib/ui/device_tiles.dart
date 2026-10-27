import 'package:flutter/material.dart';

import '../controllers/light_controller.dart';
import '../controllers/thermostat_controller.dart';
import '../data/device_store.dart';
import '../data/thermostat_connection.dart';
import '../models/device_type.dart';
import 'format.dart';
import '../controllers/device_hub.dart';
import 'generic_device_screen.dart';
import 'hub_screen.dart';
import 'thermostat_screen.dart';

/// Kafelek urządzenia na ekranie „Dom” - wygląd zależy od typu (kontrakt pkt 0).
class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.device, required this.controller, this.onLongPress, this.hub});

  /// Urządzenia domu (ekran huba).
  final DeviceHub? hub;

  final PairedDevice device;

  /// null = typ, którego aplikacja jeszcze nie obsługuje.
  final DeviceController<Object?, Object?>? controller;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return _UnknownTile(device: device, onLongPress: onLongPress);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => switch (c) {
        final ThermostatController t => _ThermostatTile(controller: t, onLongPress: onLongPress),
        final LightController l => _LightTile(controller: l, onLongPress: onLongPress),
        _ => _GenericTile(controller: c, onLongPress: onLongPress, hub: hub),
      },
    );
  }
}

/// Szczegóły urządzenia: termostat - jego ekran, hub - ekran huba (z [hub]), inne typy - ekran z `describe`.
Future<void> openDevice(BuildContext context, DeviceController<Object?, Object?> c, {DeviceHub? hub}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => c is ThermostatController
            ? ThermostatScreen(controller: c)
            : c.device.type == DeviceType.hub && hub != null
            ? HubScreen(controller: c, hub: hub)
            : GenericDeviceScreen(controller: c),
      ),
    );

/// Stan łącza w jednej linijce kafelka; null = dane płyną.
String? _statusLine(DeviceController<Object?, Object?> c) {
  if (c.needsPairing) return 'Wymaga sparowania';
  return switch (c.phase) {
    ConnectPhase.connecting => 'Łączenie…',
    ConnectPhase.failed => 'Brak połączenia',
    ConnectPhase.connected => switch (c.linkStatus) {
      LinkStatus.offline => 'Offline',
      LinkStatus.reconnecting || LinkStatus.connecting => 'Łączenie ponownie…',
      _ => null,
    },
  };
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.title,
    required this.child,
    this.icon,
    this.status,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
    this.tileKey,
  });

  final String title;
  final Widget child;
  final Widget? icon;
  final String? status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      key: tileKey,
      color: highlighted ? cs.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  ),
                  ?icon,
                ],
              ),
              const SizedBox(height: 8),
              child,
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(status!, style: t.bodySmall?.copyWith(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThermostatTile extends StatelessWidget {
  const _ThermostatTile({required this.controller, this.onLongPress});

  final ThermostatController controller;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.state;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return _TileFrame(
      tileKey: Key('tile-${c.device.id}'),
      title: c.config?.name ?? c.device.name,
      icon: s == null
          ? null
          : s.sensorFault
          ? Icon(Icons.warning_amber_rounded, color: cs.error)
          : Icon(Icons.local_fire_department, color: s.heating ? const Color(0xFFE8590C) : cs.outlineVariant),
      status: _statusLine(c),
      onTap: () => openDevice(context, c),
      onLongPress: onLongPress,
      child: s == null
          ? Text('—', style: t.headlineMedium)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.temp == null ? '—' : fmtTemp(s.temp), style: t.headlineMedium),
                Text('Nastawa ${fmtTemp(c.displayTarget)}', style: t.bodySmall),
              ],
            ),
    );
  }
}

class _LightTile extends StatelessWidget {
  const _LightTile({required this.controller, this.onLongPress});

  final LightController controller;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.state;
    final on = c.displayOn ?? false;
    final dimmable = c.device.type == DeviceType.dimmer || s?.level != null;
    return _TileFrame(
      tileKey: Key('tile-${c.device.id}'),
      title: c.config?.name ?? c.device.name,
      highlighted: on,
      icon: IconButton(
        tooltip: 'Szczegóły',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.tune),
        onPressed: () => openDevice(context, c),
      ),
      status: _statusLine(c),
      onTap: s == null || !c.canControl ? null : c.toggle,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(on ? Icons.lightbulb : Icons.lightbulb_outline, size: 32),
              const Spacer(),
              Switch(key: Key('switch-${c.device.id}'), value: on, onChanged: s == null || !c.canControl ? null : c.setOn),
            ],
          ),
          if (s != null && s.multi)
            Text(
              'Włączone: ${s.onCount} z ${s.channels}',
              key: Key('channels-${c.device.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (dimmable)
            Slider(
              value: (c.displayLevel ?? 0).toDouble(),
              max: 100,
              divisions: 20,
              onChanged: s == null || !c.canControl ? null : (v) => c.setLevel(v.round()),
            ),
        ],
      ),
    );
  }
}

/// Typ bez własnego kafelka: nazwa i pierwszy punkt z `describe`; dotknięcie - szczegóły.
class _GenericTile extends StatelessWidget {
  const _GenericTile({required this.controller, this.onLongPress, this.hub});

  final DeviceController<Object?, Object?> controller;
  final VoidCallback? onLongPress;
  final DeviceHub? hub;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _TileFrame(
      tileKey: Key('tile-${c.device.id}'),
      title: c.device.name,
      icon: Icon(c.device.type == DeviceType.hub ? Icons.device_hub : Icons.developer_board),
      status: _statusLine(c),
      onTap: () => openDevice(context, c, hub: hub),
      onLongPress: onLongPress,
      child: Text(
        c.device.type == DeviceType.hub && c.stateJson != null
            ? 'Hub · ${c.stateJson!['online'] ?? 0}/${c.stateJson!['devices'] ?? 0} urządzeń'
                  '${c.stateJson!['cloud'] == true ? '' : ' · bez chmury'}'
            : c.device.type.label,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _UnknownTile extends StatelessWidget {
  const _UnknownTile({required this.device, this.onLongPress});

  final PairedDevice device;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => _TileFrame(
    tileKey: Key('tile-${device.id}'),
    title: device.name,
    icon: const Icon(Icons.device_unknown),
    onLongPress: onLongPress,
    child: Text(
      device.type == DeviceType.hub ? 'Hub - obsługa w kolejnej wersji' : 'Nieobsługiwany typ urządzenia',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
