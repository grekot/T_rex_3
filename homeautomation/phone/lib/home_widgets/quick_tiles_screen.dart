// Kafelki szybkich ustawień Androida „Dom 1-4” (pasek rozwijany z góry ekranu): pozycja każdego - wyjście, scena,
// termostat, czujnik albo wykres, jak w widżecie. Zapis jako widżet o identyfikatorze -1…-4; stan liczy i dotknięcia
// wykonuje usługa widżetów, kafelki rysuje Android (`QuickTiles.kt`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/device_hub.dart';
import '../controllers/home_session.dart';
import '../data/home_widget_store.dart';
import '../models/dashboard.dart';
import '../models/home_widget.dart';
import 'widget_cells.dart';
import 'widget_config.dart';
import '../ui/widgets.dart' show listPadding;

/// Liczba kafelków (jak `QuickTiles.SLOTS` po stronie Androida).
const quickTileSlots = 4;

/// Identyfikator „widżetu” kafelka [slot] (1-4).
int quickTileId(int slot) => -slot;

const _channel = MethodChannel('pl.grekot.homeautomation/widget_link');

/// Android: nowe ustawienia kafelków - usługa wczytuje listę, kafelki się przerysują; zwraca dodane kafelki.
Future<Set<int>> notifyQuickTiles({String method = 'quickTilesChanged'}) async {
  try {
    final added = await _channel.invokeListMethod<int>(method);
    return {...?added};
  } on Object {
    return const {}; // poza Androidem
  }
}

class QuickTilesScreen extends StatefulWidget {
  const QuickTilesScreen({
    super.key,
    required this.hub,
    this.session,
    this.store,
    this.dashboards = const [],
    this.onChanged,
  });

  final DeviceHub hub;
  final HomeSession? session;

  /// Do testów: magazyn ustawień widżetów.
  final HomeWidgetStore? store;
  final List<Dashboard> dashboards;

  /// Do testów zamiast kanału Androida.
  final Future<Set<int>> Function()? onChanged;

  @override
  State<QuickTilesScreen> createState() => _QuickTilesScreenState();
}

class _QuickTilesScreenState extends State<QuickTilesScreen> {
  late final HomeWidgetStore _store = widget.store ?? HomeWidgetStore();
  Map<int, HomeWidgetConfig> _configs = const {};
  Set<int> _added = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final all = await _store.load();
    final added = widget.onChanged == null ? await notifyQuickTiles(method: 'quickTilesAdded') : _added;
    if (!mounted) return;
    setState(() {
      _configs = {
        for (final c in all)
          if (c.id < 0 && c.id >= -quickTileSlots) -c.id: c,
      };
      _added = added;
      _loaded = true;
    });
  }

  Future<void> _changed() async {
    final added = await (widget.onChanged ?? notifyQuickTiles)();
    if (mounted) setState(() => _added = added);
    await _load();
  }

  Future<void> _edit(int slot) async {
    final current = _configs[slot];
    final home = widget.session?.current;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => HomeWidgetConfigScreen(
          hub: widget.hub,
          multi: false,
          dashboards: widget.dashboards,
          title: 'Kafelek „Dom $slot”',
          saveLabel: 'Zapisz kafelek',
          initial: current != null && current.homeId == (home?.id ?? HomeWidgetConfig.localHome)
              ? current.items
              : const [],
          onSave: (items) async {
            await _store.save(
              HomeWidgetConfig(
                id: quickTileId(slot),
                homeId: home?.id ?? HomeWidgetConfig.localHome,
                homeName: home?.name ?? '',
                ownerUid: home?.ownerUid ?? '',
                items: items.take(1).toList(),
              ),
            );
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
      ),
    );
    await _changed();
  }

  Future<void> _clear(int slot) async {
    await _store.remove(quickTileId(slot));
    await _changed();
  }

  String _describe(HomeWidgetConfig c) {
    final item = c.items.firstOrNull;
    if (item == null) return 'Nie ustawiono';
    final cell = widgetCell(item, widget.hub);
    final kind = switch (item.kind) {
      HomeWidgetKind.output => 'przełącza',
      HomeWidgetKind.scene => 'uruchamia scenę',
      HomeWidgetKind.thermostat || HomeWidgetKind.sensor || HomeWidgetKind.chart => 'pokazuje i otwiera',
    };
    final other = c.homeId != (widget.session?.current?.id ?? HomeWidgetConfig.localHome);
    return '${cell.title} · $kind${other && c.homeName.isNotEmpty ? ' · dom ${c.homeName}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Szybkie ustawienia')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: widget.hub,
              builder: (context, _) => ListView(
                padding: listPadding(context, const EdgeInsets.only(bottom: 24)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Kafelki „Dom 1-4” w pasku rozwijanym z góry ekranu (obok WiFi i latarki) - bez otwierania '
                      'aplikacji. Wybierz, co ma robić każdy, potem dodaj go: rozwiń pasek do końca, dotknij ołówka '
                      '(edycja) i przeciągnij „Dom N” na górę.',
                      style: t.bodyMedium,
                    ),
                  ),
                  for (var slot = 1; slot <= quickTileSlots; slot++)
                    ListTile(
                      key: Key('quickTile-$slot'),
                      leading: CircleAvatar(child: Text('$slot')),
                      title: Text('Dom $slot'),
                      subtitle: Text(
                        [
                          _configs[slot] == null ? 'Nie ustawiono' : _describe(_configs[slot]!),
                          if (_added.contains(slot)) 'w pasku',
                        ].join(' · '),
                      ),
                      trailing: _configs[slot] == null
                          ? const Icon(Icons.chevron_right)
                          : IconButton(
                              key: Key('quickTileClear-$slot'),
                              tooltip: 'Wyczyść',
                              icon: const Icon(Icons.close),
                              onPressed: () => _clear(slot),
                            ),
                      onTap: () => _edit(slot),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      'Wyjście przełącza się od razu, także przy zablokowanym telefonie; termostat, czujnik i wykres '
                      'pokazują wartość, a dotknięcie otwiera urządzenie. Stan odświeża ta sama usługa co widżety.',
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
