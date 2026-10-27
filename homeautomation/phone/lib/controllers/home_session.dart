import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cloud_access.dart';
import '../data/home_repository.dart';
import '../models/home.dart';

/// Domy zalogowanego użytkownika i bieżący dom (kontrakt pkt 12).
class HomeSession extends ChangeNotifier {
  HomeSession({required this.repo, required this.cloud, SharedPreferencesAsync? prefs}) : _prefs = prefs;

  final HomeRepository repo;
  final CloudAccess cloud;
  final SharedPreferencesAsync? _prefs;

  List<Home> _homes = const [];
  Home? _current;
  bool _loading = true;
  String? _error;

  List<Home> get homes => _homes;
  Home? get current => _current;
  bool get loading => _loading;
  String? get error => _error;
  bool get isOwner => _current?.isOwner(repo.uid) ?? false;

  String get _prefKey => 'currentHome_${repo.uid}';

  Future<String?> _readPref() async {
    try {
      return await (_prefs ?? SharedPreferencesAsync()).getString(_prefKey);
    } on Object {
      return null;
    }
  }

  Future<void> _writePref(String id) async {
    try {
      await (_prefs ?? SharedPreferencesAsync()).setString(_prefKey, id);
    } on Object {
      // Zapamiętanie domu jest tylko wygodą.
    }
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _homes = await repo.myHomes();
      final saved = await _readPref();
      _select(_homes.where((h) => h.id == saved).firstOrNull ?? _homes.firstOrNull);
    } on Object {
      _error = 'Nie udało się pobrać domów. Sprawdź połączenie z internetem.';
    }
    _loading = false;
    notifyListeners();
  }

  void _select(Home? home) {
    _current = home;
    cloud.homeId = home?.id;
    cloud.homeOwnerUid = home?.ownerUid;
  }

  Future<void> switchTo(Home home) async {
    _select(home);
    await _writePref(home.id);
    notifyListeners();
  }

  Future<Home> create(String name) async {
    final home = await repo.createHome(name);
    _homes = [..._homes, home];
    await switchTo(home);
    return home;
  }

  Future<Home> join(String code) async {
    final home = await repo.joinByCode(code);
    _homes = [..._homes.where((h) => h.id != home.id), home];
    await switchTo(home);
    return home;
  }

  /// Domownik wychodzi z bieżącego domu.
  Future<void> leave() async {
    final h = _current;
    if (h == null || h.isOwner(repo.uid)) return;
    await repo.leaveHome(h.id);
    _homes = [..._homes.where((x) => x.id != h.id)];
    _select(_homes.firstOrNull);
    await _writePref(_current?.id ?? '');
    notifyListeners();
  }

  Future<void> rename(String name) async {
    final h = _current;
    if (h == null) return;
    await repo.renameHome(h.id, name);
    final renamed = Home(id: h.id, name: name, ownerUid: h.ownerUid);
    _homes = [for (final x in _homes) x.id == h.id ? renamed : x];
    _current = renamed;
    notifyListeners();
  }
}
