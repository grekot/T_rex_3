import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/home_repository.dart';
import '../data/home_widget_store.dart';
import '../models/home_widget.dart';
import '../services.dart';
import 'dashboard_screen.dart';
import 'device_tiles.dart';
import 'devices_tab.dart';
import 'members_screen.dart';
import 'onboarding_screen.dart';

/// Po zalogowaniu: domy konta. Brak domu → załóż albo dołącz kodem; jest dom → [MainScreen].
class HomeGate extends StatefulWidget {
  const HomeGate({super.key});

  @override
  State<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends State<HomeGate> {
  HomeSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    final cloud = Services.of(context).cloud;
    _session = HomeSession(
      repo: HomeRepository(
        store: cloud.store,
        uid: cloud.uid!,
        email: cloud.email ?? '',
        name: cloud.displayName ?? '',
      ),
      cloud: cloud,
    )..load();
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session!;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (s.error != null && s.homes.isEmpty) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: s.load, child: const Text('Ponów')),
                  ],
                ),
              ),
            ),
          );
        }
        final home = s.current;
        if (home == null) return OnboardingScreen(session: s);
        return MainScreen(key: ValueKey(home.id), session: s);
      },
    );
  }
}

/// Ekran główny domu: zakładki Pulpit, Urządzenia i (dla właściciela) Domownicy.
/// Bez konta [session] jest null - jeden lokalny dom w telefonie.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.session});

  final HomeSession? session;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  DeviceHub? _hub;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hub != null) return;
    final services = Services.of(context);
    _hub = DeviceHub(
      store: services.store,
      manager: services.manager,
      cloud: services.cloud,
      home: widget.session?.current,
      repo: widget.session?.repo,
      sceneStore: services.scenes,
    )..start();
    _openFromWidget();
  }

  /// Dotknięcie widżetu termostatu na ekranie telefonu: otwiera jego ekran (także w innym domu konta).
  Future<void> _openFromWidget() async {
    final link = await HomeWidgetLink.take();
    if (link == null || !mounted) return;
    final s = widget.session;
    if (s != null && link.homeId != HomeWidgetConfig.localHome && s.current?.id != link.homeId) {
      final home = s.homes.where((h) => h.id == link.homeId).firstOrNull;
      if (home == null) return;
      // Nowy dom to nowy MainScreen - to on otworzy urządzenie.
      HomeWidgetLink.pending = link;
      await s.switchTo(home);
      return;
    }
    for (var i = 0; i < 50; i++) {
      if (!mounted) return;
      final c = _hub?.controller(link.deviceId);
      if (c != null) {
        await openDevice(context, c, hub: _hub);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hub?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hub?.refreshRoutes();
      _openFromWidget();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hub!;
    final s = widget.session;
    final owner = s?.isOwner ?? false;
    final pages = [
      DashboardScreen(hub: hub, session: s),
      DevicesTab(hub: hub, session: s),
      if (owner) MembersScreen(hub: hub, session: s!),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Pulpit'),
          const NavigationDestination(icon: Icon(Icons.devices_other_outlined), selectedIcon: Icon(Icons.devices_other), label: 'Urządzenia'),
          if (owner)
            const NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Domownicy'),
        ],
      ),
    );
  }
}
