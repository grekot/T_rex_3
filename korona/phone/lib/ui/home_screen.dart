import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/climbs.dart';
import '../data/demo.dart';
import '../data/korona_data.dart';
import '../data/peaks.dart';
import '../data/repository.dart';
import 'groups_tab.dart';
import 'history_tab.dart';
import 'peaks_map.dart';

/// Trzy zakładki: Postęp, Mapa, Historia. Dane z Firestore ([repo]) albo przykładowe
/// (bez [repo] - np. gdy Firebase nie jest skonfigurowany).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.catalog, this.repo});

  final PeakCatalog catalog;
  final KoronaRepository? repo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<ClimbsDoc>? _sub;
  ClimbsDoc? _doc;
  Object? _error;
  late bool _demo = widget.repo == null;
  late final ClimbsDoc _demoDoc = demoClimbs(widget.catalog);
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    final repo = widget.repo;
    if (repo != null) {
      _sub = repo.watchClimbs().listen(
            (doc) => setState(() {
              _doc = doc;
              _error = null;
            }),
            onError: (Object e) => setState(() => _error = e),
          );
      // Wpis w książce adresowej - jak w Zakupach i Powrocie (znajomi po e-mailu)
      repo.registerEmail().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final doc = _demo ? _demoDoc : _doc;
    final data = doc == null ? null : KoronaData(catalog: widget.catalog, doc: doc, demo: _demo);

    Widget body;
    if (data == null && _error != null) {
      body = _ErrorView(error: _error!);
    } else if (data == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = IndexedStack(
        index: _tab,
        children: [
          GroupsTab(data: data),
          PeaksMap(data: data),
          HistoryTab(data: data),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Korona'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'demo') setState(() => _demo = !_demo);
              if (v == 'logout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => [
              if (repo != null) PopupMenuItem(enabled: false, child: Text(repo.email)),
              if (repo != null)
                CheckedPopupMenuItem(value: 'demo', checked: _demo, child: const Text('Przykładowe dane')),
              if (repo != null) const PopupMenuItem(value: 'logout', child: Text('Wyloguj')),
              if (repo == null) const PopupMenuItem(enabled: false, child: Text('Tryb przykładu - bez konta')),
            ],
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Postęp'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historia'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final denied = '$error'.contains('permission-denied');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          denied
              ? 'Brak dostępu do zdobyć w Firestore.\n\nOpublikuj reguły z blokiem „korona” '
                  '(App_storage/firebase/firestore.rules) w konsoli Firebase.'
              : 'Nie udało się wczytać zdobyć:\n$error',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
