import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/cloud_access.dart';
import '../data/connection_manager.dart';
import '../data/device_store.dart';
import '../data/home_repository.dart';
import '../data/scene_store.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/scene.dart';
import 'light_controller.dart';
import 'thermostat_controller.dart';

/// Urządzenia bieżącego domu i ich kontrolery - wspólne dla zakładek „Urządzenia” i „Pulpit”.
/// Łączy urządzenia sparowane w telefonie z tymi z domu w chmurze i nakłada moje uprawnienia (pkt 12).
class DeviceHub extends ChangeNotifier {
  DeviceHub({
    required this.store,
    required this.manager,
    required this.cloud,
    this.home,
    this.repo,
    this.sceneStore,
  });

  final DeviceStore store;
  final ConnectionManager manager;
  final CloudAccess cloud;

  /// Bieżący dom (null bez konta).
  final Home? home;
  final HomeRepository? repo;

  /// Sceny domu (`homes/{h}/scenes`, bez konta - w telefonie).
  final SceneStore? sceneStore;

  /// Dom w magazynach (pulpity, sceny); bez konta - jeden dom „w telefonie”.
  String get homeId => home?.id ?? 'local';
  List<Scene> _scenes = const [];
  StreamSubscription<List<Scene>>? _scenesSub;

  /// Nazwy urządzeń zapisane w `deviceIndex` (właściciel uzupełnia przy zmianie nazwy).
  final _indexed = <String, String>{};

  List<PairedDevice> _local = const [];
  List<CloudDeviceSummary> _cloud = const [];
  bool _loaded = false;
  bool _cloudLoading = false;
  String? _cloudError;
  HomeAccess? _myAccess;
  StreamSubscription<HomeAccess>? _accessSub;
  StreamSubscription<Object?>? _membersSub;
  final _controllers = <String, DeviceController<Object?, Object?>>{};
  bool _disposed = false;

  bool get loaded => _loaded;
  bool get cloudLoading => _cloudLoading;
  String? get cloudError => _cloudError;

  /// Moje uprawnienia w domu; null = bez konta (wszystko wg tokenów telefonu).
  HomeAccess? get myAccess => _myAccess;

  bool get isOwner => home?.isOwner(cloud.uid) ?? false;

  /// Sceny i pulpity wspólne zmienia właściciel (bez konta - każdy).
  bool get canEditShared => home == null || isOwner;

  List<Scene> get scenes => _scenes;

  Scene? scene(String id) => _scenes.where((s) => s.id == id).firstOrNull;

  /// Urządzenia sparowane w tym telefonie.
  List<PairedDevice> get paired => _local;

  /// Wszystkie znane urządzenia domu (bez powtórzeń). Urządzenia lokalne bez dostępu w domu
  /// (np. cudze) i tak są pokazane - dostęp sprawdza urządzenie.
  List<PairedDevice> get devices {
    final localIds = {for (final d in _local) d.id};
    return [
      ..._local,
      for (final c in _cloud)
        if (!localIds.contains(c.id)) PairedDevice(id: c.id, name: c.name ?? c.id, type: c.type),
    ];
  }

  PairedDevice? device(String id) => devices.where((d) => d.id == id).firstOrNull;

  DeviceController<Object?, Object?>? controller(String id) => _controllers[id];

  /// Mój poziom dostępu do urządzenia (do ukrywania elementów; urządzenie i tak pilnuje).
  AccessLevel accessFor(String id) =>
      _controllers[id]?.access ?? _myAccess?.levelFor(id) ?? device(id)?.access ?? AccessLevel.config;

  void start() {
    final h = home, r = repo, uid = cloud.uid;
    if (h != null && r != null && uid != null) {
      _accessSub = r.accessOf(h, uid).listen((a) {
        _myAccess = a;
        for (final c in _controllers.values) {
          c.homeAccess = a;
        }
        _notify();
      }, onError: (_) {});
    }
    // Właściciel dopisuje wyjątki z zaproszeń, gdy zobaczy nowego domownika (pkt 12).
    if (h != null && r != null && isOwner) {
      _membersSub = r.members(h.id).asyncMap((m) => r.applyInviteExceptions(h.id, m)).listen((_) {}, onError: (_) {});
    }
    _scenesSub = sceneStore?.watch(homeId).listen((s) {
      _scenes = s;
      _notify();
    }, onError: (_) {});
    unawaited(load());
  }

  /// Uruchamia scenę (pkt 4.6): z hubem - polecenie `runScene` do huba (wykonuje ją hub), bez huba -
  /// aplikacja wysyła akcje po kolei, każde urządzenie sprawdza moje uprawnienia. Zwraca problemy.
  Future<List<String>> runScene(Scene scene, {Duration maxDelay = const Duration(seconds: 60)}) async {
    final hubDevice = devices
        .where((d) => d.type == DeviceType.hub && accessFor(d.id).canControl && _controllers[d.id] != null)
        .firstOrNull;
    if (hubDevice != null) {
      final r = await _controllers[hubDevice.id]!.sendJson({'runScene': scene.id});
      return r.errors.isEmpty ? const [] : ['Hub: ${describeErrors(r.errors)}'];
    }
    return _runLocally(scene, maxDelay, 0);
  }

  Future<List<String>> _runLocally(Scene scene, Duration maxDelay, int depth) async {
    final problems = <String>[];
    for (final a in scene.actions) {
      if (a.isSet) {
        final c = _controllers[a.device!];
        final name = device(a.device!)?.name ?? a.device!;
        if (c == null) {
          problems.add('$name: niedostępne');
          continue;
        }
        final r = await c.sendJson(a.set!);
        if (r.errors.isNotEmpty) problems.add('$name: ${describeErrors(r.errors)}');
      } else if (a.delay != null) {
        if (Duration(seconds: a.delay!) > maxDelay) {
          problems.add('Opóźnienie ${a.delay} s wykona tylko hub - dalsze kroki pominięte.');
          break;
        }
        await Future<void>.delayed(Duration(seconds: a.delay!));
      } else if (a.scene != null) {
        final inner = this.scene(a.scene!);
        if (inner == null || depth >= 3) {
          problems.add('Scena ${a.scene}: niedostępna');
        } else {
          problems.addAll(await _runLocally(inner, maxDelay, depth + 1));
        }
      }
    }
    return problems;
  }

  Future<void> load() async {
    _local = await store.devices();
    _loaded = true;
    _sync();
    _notify();
    if (cloud.available && cloud.homeId != null) {
      _cloudLoading = true;
      _cloudError = null;
      _notify();
      try {
        _cloud = await cloud.devices().timeout(const Duration(seconds: 10));
        _sync();
      } on Object {
        _cloudError = 'Nie udało się pobrać urządzeń z chmury.';
      } finally {
        _cloudLoading = false;
        _notify();
      }
    }
  }

  /// Nowe dane urządzenia (np. po parowaniu) - kontroler od nowa.
  Future<void> reloadDevice(String id) async {
    _controllers.remove(id)?.dispose();
    await load();
  }

  Future<void> removeLocal(String id) async {
    await store.removeDevice(id);
    _controllers.remove(id)?.dispose();
    await load();
  }

  void refreshRoutes() {
    for (final c in _controllers.values) {
      c.refreshRoute();
    }
  }

  void _sync() {
    final byId = {for (final d in devices) d.id: d};
    for (final id in _controllers.keys.where((id) => !byId.containsKey(id)).toList()) {
      _controllers.remove(id)?.dispose();
    }
    for (final d in byId.values) {
      if (_controllers.containsKey(d.id)) continue;
      final DeviceController<Object?, Object?> c = switch (d.type) {
        DeviceType.thermostat => ThermostatController(device: d, manager: manager),
        DeviceType.onOff || DeviceType.dimmer => LightController(device: d, manager: manager),
        _ => DeviceController(device: d, manager: manager, codec: rawCodec),
      };
      c.homeAccess = _myAccess;
      c.addListener(_notify);
      _controllers[d.id] = c;
      unawaited(c.connect());
    }
  }

  void _notify() {
    if (_disposed) return;
    _syncIndex();
    notifyListeners();
  }

  /// Właściciel: nowa nazwa urządzenia trafia do `homes/{h}/deviceIndex` (lista dla domowników, pkt 12).
  void _syncIndex() {
    final h = home;
    if (h == null || !isOwner || !cloud.available) return;
    for (final c in _controllers.values) {
      final d = c.device;
      if (c.state == null) continue; // dopiero po połączeniu (nazwa z Config)
      final name = d.name;
      if (_indexed[d.id] == name) continue;
      _indexed[d.id] = name;
      unawaited(writeDeviceIndex(cloud.store, h.id, d.id, d.type, name).catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _accessSub?.cancel();
    _scenesSub?.cancel();
    _membersSub?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
