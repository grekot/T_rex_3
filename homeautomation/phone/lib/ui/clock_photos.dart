// Zdjęcia na zegarze (pkt 10.2 „Zdjęcia”, lib/data/photo_sync.dart): stan synchronizacji z aplikacją „Zdjęcia”,
// przebieg przy otwarciu ekranu zegara (w sieci domowej) i kafelek w ustawieniach zegara.

import 'dart:async';

import 'package:flutter/material.dart';

import '../background/photo_worker.dart';
import '../controllers/device_controller.dart';
import '../data/local_connection.dart';
import '../data/photo_sync.dart';
import '../models/clock.dart';
import '../models/json_utils.dart';
import 'clock_section.dart' show clockScreenList;
import 'clock_settings.dart' show ClockPhotosPage;

/// Stan synchronizacji zdjęć jednego zegara do UI: odczyt z [PhotoSyncLog], przebieg na żądanie.
class ClockPhotoSync extends ChangeNotifier {
  ClockPhotoSync(this.c) : log = logFactory();

  /// Testy podstawiają magazyn w pamięci i synchronizację z atrapą mostu.
  static PhotoSyncLog Function() logFactory = PrefsPhotoSyncLog.new;
  static PhotoSync Function(DeviceController<Object?, Object?> c, PhotoSyncLog log) syncFactory = (c, log) =>
      PhotoSync(store: c.manager.store, log: log);

  final DeviceController<Object?, Object?> c;
  final PhotoSyncLog log;

  BridgeSeen? bridge;
  PhotoSyncStatus? status;
  bool running = false;
  bool? _notedOn;
  bool _disposed = false;

  Json? get _cfg => c.config is Map ? (c.config! as Map).cast<String, dynamic>() : null;

  /// Ekran `photo` jest w pokazie (i zegar zna zdjęcia).
  bool get photoOn => clockHasPhotos(_cfg) && clockScreenList(_cfg).contains('photo');

  /// Przebieg tylko w sieci domowej, z własnym tokenem ≥ `control`.
  bool get canRun => c.canControl && c.connection is LocalConnection;

  Future<void> load() async {
    bridge = await log.bridge();
    status = await log.clock(c.device.id);
    _notify();
  }

  /// Config zegara się zmienił: zapamiętuje, czy ekran `photo` jest w pokazie (od tego zależy zadanie w tle).
  Future<void> noteConfig() async {
    if (_cfg == null) return;
    final on = photoOn;
    if (_notedOn == on) return;
    _notedOn = on;
    await log.notePhotoOn(c.device.id, on);
    await PhotoSyncScheduler.update(store: c.manager.store, log: log);
  }

  /// Przebieg dla tego zegara; [minInterval] - pomija, gdy sprawdzany niedawno.
  Future<void> run({Duration minInterval = Duration.zero}) async {
    final conn = c.connection;
    if (running || !canRun || conn is! LocalConnection) return;
    running = true;
    _notify();
    try {
      await syncFactory(c, log).run(deviceId: c.device.id, endpoint: conn.endpoint, minInterval: minInterval);
    } on Object catch (e) {
      debugPrint('Zdjęcia na zegarze: $e');
    } finally {
      running = false;
    }
    await load();
  }

  /// „5 zdjęć na zegarze · ostatnio 14:05” (liczba z State `photos`, gdy zegar ją podaje).
  String get text {
    final n = c.stateJson?['photos'];
    return photoSyncText(bridge: bridge, status: status, onClock: n is num ? n.toInt() : null);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Kafelek „Zdjęcia” w ustawieniach zegara. Przy otwarciu ekranu zegara (w sieci domowej, ekran `photo` w pokazie)
/// uruchamia synchronizację - także bez kafelka ([showTile] = false, telefon bez poziomu `config`).
class ClockPhotosTile extends StatefulWidget {
  const ClockPhotosTile({super.key, required this.controller, this.showTile = true});

  final DeviceController<Object?, Object?> controller;
  final bool showTile;

  @override
  State<ClockPhotosTile> createState() => _ClockPhotosTileState();
}

class _ClockPhotosTileState extends State<ClockPhotosTile> {
  late final ClockPhotoSync _sync = ClockPhotoSync(widget.controller);
  bool _triggered = false;

  DeviceController<Object?, Object?> get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_rebuild);
    c.addListener(_onController);
    unawaited(_sync.load());
    _onController();
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    _sync.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onController() {
    unawaited(_sync.noteConfig());
    if (!_triggered && _sync.photoOn && _sync.canRun) {
      _triggered = true;
      unawaited(_sync.run(minInterval: const Duration(minutes: 1)));
    }
    _rebuild();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = c.config is Map ? (c.config! as Map).cast<String, dynamic>() : null;
    if (!widget.showTile || !clockHasPhotos(cfg)) return const SizedBox.shrink();
    return ListTile(
      key: const Key('clockPhotos'),
      leading: const Icon(Icons.photo_library_outlined),
      title: const Text('Zdjęcia'),
      subtitle: Text(_sync.photoOn ? _sync.text : 'Ekran „Zdjęcia” wyłączony - włącz go w pokazie'),
      trailing: _sync.running
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ClockPhotosPage(controller: c)));
        await _sync.load();
      },
    );
  }
}
