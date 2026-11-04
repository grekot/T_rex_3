// Wygląd pozycji widżetu na ekranie telefonu: podpis, ikona, kolor, główna wartość czujnika i co pod nią,
// co pod temperaturą termostatu, co robi dotknięcie wyjścia. Pozycja może też powstać z kafelka pulpitu.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../models/dashboard.dart';
import '../models/home_widget.dart';
import '../ui/app_icons.dart';
import '../ui/tile_charts.dart' show namedColor;
import 'widget_cells.dart';

/// Nazwane kolory pozycji (jak kafelki pulpitu, pkt 13.1); null = akcent (pomarańczowy).
const widgetColors = [
  (null, 'Auto'),
  ('amber', 'Bursztyn'),
  ('blue', 'Niebieski'),
  ('green', 'Zielony'),
  ('red', 'Czerwony'),
  ('purple', 'Fioletowy'),
  ('grey', 'Szary'),
];

/// Pozycja widżetu z kafelka pulpitu: rodzaj z widoku i punktu, podpis, ikona, kolor (i wartości czujnika) jak na
/// kafelku. Kopia w chwili wyboru - późniejsza zmiana kafelka nie zmienia widżetu. null = kafelek bez odpowiednika.
HomeWidgetItem? itemFromTile(DashWidget w, DeviceHub hub) {
  WidgetItemLook look({String? main, List<String>? more}) =>
      WidgetItemLook(label: w.label, icon: w.icon, color: w.color, main: main, more: more);
  final device = w.device, point = w.point;
  if (w.isScene) return w.sceneId == null ? null : HomeWidgetItem.scene(w.sceneId!, look: look());
  if (w.view == WidgetView.valueList) {
    final same = [
      for (final i in w.items)
        if (i.device == w.items.firstOrNull?.device) i.point,
    ];
    if (same.isEmpty) return null;
    return HomeWidgetItem.sensor(
      w.items.first.device,
      look: look(main: same.first, more: same.skip(1).take(2).toList()),
    );
  }
  if (device == null || hub.device(device) == null) return null;
  if (w.view == WidgetView.thermostat && point == null) return HomeWidgetItem.thermostat(device, look: look());
  if (point != null &&
      RegExp(r'^on\d*$').hasMatch(point) &&
      (w.view == WidgetView.toggle || w.view == WidgetView.status)) {
    return HomeWidgetItem.output(device, point, look: look());
  }
  if (point != null &&
      const [
        WidgetView.value,
        WidgetView.gauge,
        WidgetView.level,
        WidgetView.chart,
        WidgetView.dial,
      ].contains(w.view)) {
    final second = w.secondary != null && w.secondary!.startsWith('point:') ? w.secondary!.substring(6) : null;
    return HomeWidgetItem.sensor(
      device,
      look: look(main: point, more: second == null ? null : [second]),
    );
  }
  return null;
}

/// Nazwa kafelka pulpitu na liście „Z pulpitu”.
String tileTitle(DashWidget w, DeviceHub hub) =>
    w.label ??
    (w.isScene ? hub.scene(w.sceneId ?? '')?.name : null) ??
    (w.device == null ? null : hub.device(w.device!)?.name) ??
    w.view.label;

/// Ekran „Wygląd” pozycji: podgląd kratki na żywo i ustawienia; zwraca pozycję z nowym wyglądem.
class WidgetLookScreen extends StatefulWidget {
  const WidgetLookScreen({super.key, required this.item, required this.hub});

  final HomeWidgetItem item;
  final DeviceHub hub;

  @override
  State<WidgetLookScreen> createState() => _WidgetLookScreenState();
}

class _WidgetLookScreenState extends State<WidgetLookScreen> {
  late WidgetItemLook _look = widget.item.look;
  late final _label = TextEditingController(text: widget.item.look.label ?? '');

  HomeWidgetItem get _item => widget.item.withLook(_look);

  @override
  void initState() {
    super.initState();
    // Czujnik: nazwy i kolejność punktów z `describe`.
    final c = widget.item.device == null ? null : widget.hub.controller(widget.item.device!);
    if (c != null && c.cachedDescription == null) {
      unawaited(c.description().then((_) => mounted ? setState(() {}) : null));
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _set(WidgetItemLook l) => setState(() => _look = l);

  WidgetItemLook _copy({
    Object? label = _keep,
    Object? icon = _keep,
    Object? color = _keep,
    Object? main = _keep,
    Object? more = _keep,
    Object? tap = _keep,
  }) => WidgetItemLook(
    label: label == _keep ? _look.label : label as String?,
    icon: icon == _keep ? _look.icon : icon as String?,
    color: color == _keep ? _look.color : color as String?,
    main: main == _keep ? _look.main : main as String?,
    more: more == _keep ? _look.more : more as List<String>?,
    tap: tap == _keep ? _look.tap : tap as String?,
  );

  /// Domyślna ikona (bez wyboru) - ta, którą pokaże podgląd.
  String get _defaultIcon => switch (widget.item.kind) {
    HomeWidgetKind.output => 'light',
    HomeWidgetKind.thermostat => 'thermostat',
    HomeWidgetKind.scene => 'scene',
    HomeWidgetKind.sensor => switch (_look.main ?? _readings.firstOrNull?.key) {
      'temp' => 'temperature',
      'hum' => 'humidity',
      _ => 'sensor',
    },
  };

  List<SensorReading> get _readings {
    final c = widget.item.device == null ? null : widget.hub.controller(widget.item.device!);
    return c == null ? const [] : sensorReadings(c);
  }

  Future<void> _pickIcon() async {
    final key = await pickAppIcon(context, current: _look.icon, defaultKey: _defaultIcon);
    if (key == null) return;
    _set(_copy(icon: key.isEmpty ? null : key));
  }

  Widget _chips<T>(String keyPrefix, List<(T, String)> options, T selected, ValueChanged<T> onPick) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final (v, l) in options)
        ChoiceChip(
          key: Key('$keyPrefix-${v ?? 'auto'}'),
          label: Text(l),
          selected: v == selected,
          onSelected: (_) => onPick(v),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kind = widget.item.kind;
    final readings = _readings;
    return Scaffold(
      appBar: AppBar(title: const Text('Wygląd pozycji')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListenableBuilder(
            listenable: widget.hub,
            builder: (context, _) =>
                WidgetCellPreview(cell: widgetCell(_item, widget.hub), iconKey: _look.icon ?? _defaultIcon),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('look-label'),
            controller: _label,
            maxLength: 24,
            decoration: InputDecoration(
              labelText: 'Podpis',
              hintText: widgetCell(widget.item.withLook(_copy(label: null)), widget.hub).title,
            ),
            onChanged: (v) => _set(_copy(label: v.trim().isEmpty ? null : v.trim())),
          ),
          ListTile(
            key: const Key('look-icon'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(appIcon(_look.icon ?? _defaultIcon)?.icon),
            title: const Text('Ikona'),
            subtitle: Text(appIcon(_look.icon)?.label ?? 'domyślna'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickIcon,
          ),
          const SizedBox(height: 8),
          Text('Kolor', style: t.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final (c, l) in widgetColors)
                ChoiceChip(
                  key: Key('look-color-${c ?? 'auto'}'),
                  avatar: c == null
                      ? null
                      : CircleAvatar(backgroundColor: namedColor(c, Theme.of(context).colorScheme), radius: 8),
                  label: Text(l),
                  selected: _look.color == c,
                  onSelected: (_) => _set(_copy(color: c)),
                ),
            ],
          ),
          if (kind == HomeWidgetKind.sensor && readings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Główna wartość', style: t.titleSmall),
            const SizedBox(height: 6),
            _chips<String?>(
              'look-main',
              [for (final r in readings) (r.key, r.name)],
              _look.main ?? readings.first.key,
              (k) => _set(_copy(main: k == readings.first.key && _look.main == null ? null : k)),
            ),
            const SizedBox(height: 12),
            Text('Pod nią (do 2)', style: t.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const Key('look-more-auto'),
                  label: const Text('Kolejne'),
                  selected: _look.more == null,
                  onSelected: (_) => _set(_copy(more: null)),
                ),
                ChoiceChip(
                  key: const Key('look-more-none'),
                  label: const Text('Nic'),
                  selected: _look.more != null && _look.more!.isEmpty,
                  onSelected: (_) => _set(_copy(more: const <String>[])),
                ),
                for (final r in readings)
                  if (r.key != (_look.main ?? readings.first.key))
                    FilterChip(
                      key: Key('look-more-${r.key}'),
                      label: Text(r.name),
                      selected: _look.more?.contains(r.key) ?? false,
                      onSelected: (on) {
                        final list = [...?_look.more];
                        if (on) {
                          list.add(r.key);
                          if (list.length > 2) list.removeAt(0);
                        } else {
                          list.remove(r.key);
                        }
                        _set(_copy(more: list));
                      },
                    ),
              ],
            ),
          ],
          if (kind == HomeWidgetKind.thermostat) ...[
            const SizedBox(height: 16),
            Text('Pod temperaturą', style: t.titleSmall),
            const SizedBox(height: 6),
            _chips<String>(
              'look-below',
              const [('target', 'Nastawa'), ('hum', 'Wilgotność'), ('none', 'Nic')],
              _look.more == null ? 'target' : (_look.more!.firstOrNull ?? 'none'),
              (k) => _set(_copy(more: k == 'target' ? null : (k == 'none' ? const <String>[] : [k]))),
            ),
          ],
          if (kind == HomeWidgetKind.output) ...[
            const SizedBox(height: 16),
            Text('Dotknięcie', style: t.titleSmall),
            const SizedBox(height: 6),
            _chips<String?>(
              'look-tap',
              const [(null, 'Przełącza'), ('open', 'Otwiera urządzenie')],
              _look.tap,
              (v) => _set(_copy(tap: v)),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            key: const Key('look-done'),
            onPressed: () => Navigator.of(context).pop(_item),
            child: const Text('Gotowe'),
          ),
        ),
      ),
    );
  }
}

const Object _keep = Object();

/// Podgląd kratki widżetu (jak na ekranie telefonu): ikona, nazwa, wartość, druga linia, kolor włączonej.
class WidgetCellPreview extends StatelessWidget {
  const WidgetCellPreview({super.key, required this.cell, required this.iconKey});

  final WidgetCell cell;
  final String iconKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final named = cell.color == null ? null : namedColor(cell.color, cs);
    final bg = cell.active ? (named ?? const Color(0xFFE8590C)) : cs.surfaceContainerHigh;
    final fg = cell.active ? Colors.white : cs.onSurface;
    return Opacity(
      key: const Key('look-preview'),
      opacity: cell.dimmed ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(appIcon(iconKey)?.icon ?? Icons.sensors, color: cell.active ? fg : (named ?? fg), size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cell.title,
                    style: t.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  ),
                  if (cell.value != null) Text(cell.value!, style: t.headlineSmall?.copyWith(color: fg)),
                  if (cell.subtitle.isNotEmpty) Text(cell.subtitle, style: t.bodySmall?.copyWith(color: fg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
