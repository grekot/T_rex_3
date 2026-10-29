import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/device_store.dart';
import '../data/updates.dart';
import '../models/room.dart';
import '../services.dart';
import 'account_menu.dart';
import 'add_device_screen.dart';
import '../data/device_icons.dart';
import 'app_icons.dart';
import 'device_tiles.dart';
import 'pc_token_screen.dart';
import 'updates_screen.dart';
import 'widgets.dart';

/// Zakładka „Urządzenia”: kafelki ze stanem pogrupowane w pokoje (pkt 8.3). Dotknięcie otwiera
/// szczegóły (termostat - jego ekran, inne typy - ekran z `describe`). Pokoje zmienia właściciel domu
/// (bez konta - każdy, bo są w telefonie).
class DevicesTab extends StatefulWidget {
  const DevicesTab({super.key, required this.hub, this.session});

  final DeviceHub hub;
  final HomeSession? session;

  @override
  State<DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<DevicesTab> {
  DeviceHub get hub => widget.hub;
  List<Room> _rooms = const [];
  StreamSubscription<List<Room>>? _roomsSub;

  bool get _canEditRooms => widget.session == null || widget.session!.isOwner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(DeviceIcons.instance.load());
    _roomsSub ??= Services.of(context).rooms.watch().listen((r) {
      if (mounted) setState(() => _rooms = r);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _roomsSub?.cancel();
    super.dispose();
  }

  Future<void> _add() async {
    final device = await Navigator.of(
      context,
    ).push<PairedDevice>(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
    if (device != null) await hub.reloadDevice(device.id);
  }

  Future<String?> _askName(String title, {String initial = ''}) =>
      showTextInputDialog(context, title: title, initial: initial, hint: 'np. Salon', fieldKey: const Key('roomName'));

  Future<Room?> _newRoom({List<String> devices = const []}) async {
    final name = await _askName('Nowy pokój');
    if (name == null || !mounted) return null;
    final order = _rooms.isEmpty ? 0 : sortRooms(_rooms).last.order + 1;
    final room = Room(id: newRoomId(), name: name, order: order, devices: devices);
    await Services.of(context).rooms.save(room);
    return room;
  }

  Future<void> _roomMenu(Room room, String action) async {
    final store = Services.of(context).rooms;
    switch (action) {
      case 'rename':
        final name = await _askName('Nazwa pokoju', initial: room.name);
        if (name != null) await store.save(room.copyWith(name: name));
      case 'up' || 'down':
        await store.saveAll(shiftRoom(_rooms, room.id, action == 'up' ? -1 : 1));
      case 'delete':
        await store.remove(room.id);
    }
  }

  Future<void> _deviceMenu(PairedDevice d, Room? room) async {
    final paired = hub.paired.any((x) => x.id == d.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(d.name), subtitle: Text('${d.type.label} · ${d.id} · ${hub.accessFor(d.id).label}')),
              const Divider(height: 1),
              if (DeviceIcons.instance.canEdit)
                ListTile(
                  key: const Key('deviceIcon'),
                  leading: Icon(deviceIcon(d)),
                  title: const Text('Ikona'),
                  onTap: () => Navigator.pop(ctx, 'icon'),
                ),
              if (_canEditRooms) ...[
                for (final r in sortRooms(_rooms))
                  if (r.id != room?.id)
                    ListTile(
                      leading: const Icon(Icons.meeting_room_outlined),
                      title: Text('Przenieś do: ${r.name}'),
                      onTap: () => Navigator.pop(ctx, 'move:${r.id}'),
                    ),
                ListTile(
                  leading: const Icon(Icons.add_home_outlined),
                  title: const Text('Przenieś do nowego pokoju…'),
                  onTap: () => Navigator.pop(ctx, 'new'),
                ),
                if (room != null) ...[
                  ListTile(
                    leading: const Icon(Icons.output),
                    title: const Text('Wyjmij z pokoju'),
                    onTap: () => Navigator.pop(ctx, 'move:'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: const Text('Przesuń wcześniej'),
                    onTap: () => Navigator.pop(ctx, 'left'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.arrow_forward),
                    title: const Text('Przesuń dalej'),
                    onTap: () => Navigator.pop(ctx, 'right'),
                  ),
                ],
              ],
              if (paired)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Usuń z telefonu'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'icon') {
      final key = await pickAppIcon(context, current: DeviceIcons.instance.of(d.id), defaultKey: deviceIconKey(d.type));
      if (key != null) await DeviceIcons.instance.set(d, key);
      return;
    }
    final store = Services.of(context).rooms;
    if (action.startsWith('move:')) {
      final target = action.substring(5);
      await store.saveAll(moveDevice(_rooms, d.id, target.isEmpty ? null : target));
    } else if (action == 'new') {
      await store.saveAll(moveDevice(_rooms, d.id, null));
      await _newRoom(devices: [d.id]);
    } else if (action == 'left' || action == 'right') {
      final shifted = shiftDevice(room!, d.id, action == 'left' ? -1 : 1);
      if (shifted != null) await store.save(shifted);
    } else if (action == 'remove') {
      await hub.removeLocal(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final devices = hub.devices;
        final byId = {for (final d in devices) d.id: d};
        final sections = layoutRooms(_rooms, [for (final d in devices) d.id]);
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.session?.current?.name ?? 'Urządzenia'),
            actions: [
              if (_canEditRooms)
                IconButton(
                  key: const Key('addRoom'),
                  tooltip: 'Nowy pokój',
                  icon: const Icon(Icons.add_home_outlined),
                  onPressed: _newRoom,
                ),
              if (_canEditRooms)
                IconButton(
                  key: const Key('updates'),
                  tooltip: 'Aktualizacje firmware',
                  icon: const Icon(Icons.system_update_alt),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => UpdatesScreen(backend: DeviceHubUpdates(hub)))),
                ),
              IconButton(
                key: const Key('pcToken'),
                tooltip: 'Wyślij token do komputera',
                icon: const Icon(Icons.computer_outlined),
                onPressed: () => sendTokenToComputer(context),
              ),
              AccountMenu(session: widget.session),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            key: const Key('addDevice'),
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj urządzenie'),
          ),
          body: !hub.loaded
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: hub.load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                    children: [
                      if (hub.cloudLoading) const LinearProgressIndicator(),
                      if (devices.isEmpty && !hub.cloudLoading) _Empty(onAdd: _add),
                      for (final s in sections)
                        if (s.room != null || s.deviceIds.isNotEmpty) ...[
                          _RoomHeader(
                            room: s.room,
                            onAction: s.room == null || !_canEditRooms ? null : (a) => _roomMenu(s.room!, a),
                          ),
                          if (s.deviceIds.isEmpty && _canEditRooms)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                              child: Text(
                                'Pusty pokój - przytrzymaj kafelek urządzenia, aby go tu przenieść.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          TileGrid(
                            children: [
                              for (final id in s.deviceIds)
                                DeviceTile(
                                  device: byId[id]!,
                                  controller: hub.controller(id),
                                  hub: hub,
                                  onLongPress: () => _deviceMenu(byId[id]!, s.room),
                                ),
                            ],
                          ),
                        ],
                      if (hub.cloudError != null)
                        ListTile(
                          leading: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
                          title: Text(hub.cloudError!),
                          subtitle: const Text('Pociągnij w dół, aby spróbować ponownie.'),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room, this.onAction});

  final Room? room;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 4),
      child: Row(
        children: [
          Expanded(child: Text(room?.name ?? 'Bez pokoju', style: t.titleMedium)),
          if (onAction != null)
            PopupMenuButton<String>(
              tooltip: 'Pokój',
              onSelected: onAction,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                PopupMenuItem(value: 'up', child: Text('Przesuń wyżej')),
                PopupMenuItem(value: 'down', child: Text('Przesuń niżej')),
                PopupMenuItem(value: 'delete', child: Text('Usuń pokój')),
              ],
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
      child: Column(
        children: [
          Icon(Icons.home_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Brak urządzeń', style: t.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Dodaj termostat albo inne urządzenie: nowe przez Bluetooth, '
            'a już działające w sieci domowej kodem z jego ekranu.',
            style: t.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Dodaj urządzenie')),
        ],
      ),
    );
  }
}
