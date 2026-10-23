import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/activity.dart';
import '../data/health_source.dart';
import '../data/repository.dart';
import '../data/weights.dart';
import 'activity_tab.dart';
import 'chart_tab.dart';
import 'entries_tab.dart';
import 'entry_dialog.dart';

/// Ile dni wstecz czytamy z Health Connect (bez zgody na historię i tak tylko 30)
const activityDays = 120;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo});

  final WeightRepository repo;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _health = HealthSource();
  late final Stream<WeightDoc> _stream = widget.repo.watch();
  int _tab = 0;
  HealthState _healthState = HealthState.checking;
  ActivityData _activity = ActivityData.empty;
  bool _loadingActivity = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshHealth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Powrót z ekranu zgód Health Connect albo z Zepp (nowe dane)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshHealth();
  }

  Future<void> _refreshHealth() async {
    final s = await _health.state();
    if (!mounted) return;
    setState(() => _healthState = s);
    if (s == HealthState.ready) await _loadActivity();
  }

  Future<void> _loadActivity() async {
    if (_loadingActivity) return;
    _loadingActivity = true;
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: activityDays));
      final data = await _health.load(from, now);
      if (mounted) setState(() => _activity = data);
    } finally {
      _loadingActivity = false;
    }
  }

  Future<void> _connectHealth() async {
    if (_healthState == HealthState.needsInstall) {
      await _health.install();
      return;
    }
    await _health.requestAccess();
    await _refreshHealth();
  }

  Future<void> _addEntry(WeightDoc doc) async {
    final today = DateTime.now();
    final existing = doc.entryFor(dayKey(today));
    final r = await showEntryDialog(
      context,
      day: today,
      initial: existing?.w ?? doc.last?.w ?? 800,
      existing: existing != null,
    );
    if (r != null) await _apply(r);
  }

  Future<void> _apply(EntryResult r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (r.delete) {
        await widget.repo.deleteEntry(r.day);
      } else {
        await widget.repo.setEntry(r.day, r.w);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Nie udało się zapisać: $e')));
    }
  }

  Future<void> _editGoal(WeightDoc doc) async {
    final r = await showGoalDialog(context, current: doc.goal, suggestion: (doc.last?.w ?? 800) - 30);
    if (r == null) return;
    await widget.repo.setGoal(r.$1);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WeightDoc>(
      stream: _stream,
      builder: (context, snap) {
        final doc = snap.data ?? WeightDoc.empty;
        final loading = !snap.hasData && !snap.hasError;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Waga'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'goal') _editGoal(doc);
                  if (v == 'logout') FirebaseAuth.instance.signOut();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text(widget.repo.email)),
                  PopupMenuItem(
                    value: 'goal',
                    child: Text(doc.goal == null ? 'Ustaw cel wagi' : 'Cel: ${formatKg(doc.goal!)} kg'),
                  ),
                  const PopupMenuItem(value: 'logout', child: Text('Wyloguj')),
                ],
              ),
            ],
          ),
          body: snap.hasError
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Błąd odczytu: ${snap.error}')))
              : loading
                  ? const Center(child: CircularProgressIndicator())
                  : IndexedStack(
                      index: _tab,
                      children: [
                        ChartTab(
                          doc: doc,
                          activity: _activity,
                          healthReady: _healthState == HealthState.ready,
                          onSetGoal: () => _editGoal(doc),
                        ),
                        EntriesTab(doc: doc, activity: _activity, onEdit: _apply),
                        ActivityTab(
                          state: _healthState,
                          activity: _activity,
                          doc: doc,
                          onConnect: _connectHealth,
                          onRefresh: _refreshHealth,
                        ),
                      ],
                    ),
          floatingActionButton: _tab < 2 && !loading
              ? FloatingActionButton.extended(
                  onPressed: () => _addEntry(doc),
                  icon: const Icon(Icons.add),
                  label: const Text('Pomiar'),
                )
              : null,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.show_chart), label: 'Wykres'),
              NavigationDestination(icon: Icon(Icons.list_alt), label: 'Pomiary'),
              NavigationDestination(icon: Icon(Icons.local_fire_department_outlined), label: 'Aktywność'),
            ],
          ),
        );
      },
    );
  }
}
