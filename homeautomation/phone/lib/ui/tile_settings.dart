import 'package:flutter/material.dart';

import '../controllers/device_hub.dart';
import '../models/dashboard.dart';
import '../models/describe.dart';
import '../models/json_utils.dart';
import 'app_icons.dart';
import 'dashboard_tiles.dart';
import 'tile_charts.dart';

/// Co zrobić z kafelkiem po zamknięciu arkusza ustawień.
sealed class TileEdit {
  const TileEdit();
}

/// Zapis zmian.
class TileUpdated extends TileEdit {
  const TileUpdated(this.widget);

  final DashWidget widget;
}

class TileDeleted extends TileEdit {
  const TileDeleted();
}

class TileDuplicated extends TileEdit {
  const TileDuplicated();
}

/// Przesunięcie o [by] miejsc (−1 wcześniej, +1 później) - także bez przeciągania.
class TileMoved extends TileEdit {
  const TileMoved(this.by);

  final int by;
}

class TileEditScene extends TileEdit {
  const TileEditScene();
}

/// Rozmiary w siatce 4 kolumn (szerokość × wysokość) do wyboru.
const grid4Sizes = [(1, 1), (2, 1), (2, 2), (4, 1), (4, 2), (4, 3), (4, 4)];

/// Arkusz ustawień kafelka z podglądem na żywo (pkt 13 i 13.1). [points] - punkty urządzenia z `describe`
/// (szybkie sterowanie, druga linia, serie wykresu), [channels] - liczba kanałów węzła. Null przy anulowaniu.
Future<TileEdit?> showTileSettings(
  BuildContext context, {
  required DashWidget widget,
  required DeviceHub hub,
  required List<WidgetView> views,
  required String defaultTitle,
  HistorySource? history,
  bool canEditScene = false,
  bool first = false,
  bool last = false,
  int grid = 2,
  List<DashSection> sections = const [],
  List<DataPoint> points = const [],
  int channels = 1,
  List<({String device, String point, String name})> groupOptions = const [],
}) => showModalBottomSheet<TileEdit>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => _TileSettings(
    initial: widget,
    hub: hub,
    views: views,
    defaultTitle: defaultTitle,
    history: history,
    canEditScene: canEditScene,
    first: first,
    last: last,
    grid: grid,
    sections: sections,
    points: points,
    channels: channels,
    groupOptions: groupOptions,
  ),
);

class _TileSettings extends StatefulWidget {
  const _TileSettings({
    required this.initial,
    required this.hub,
    required this.views,
    required this.defaultTitle,
    required this.history,
    required this.canEditScene,
    required this.first,
    required this.last,
    required this.grid,
    required this.sections,
    required this.points,
    required this.channels,
    required this.groupOptions,
  });

  final DashWidget initial;
  final DeviceHub hub;
  final List<WidgetView> views;
  final String defaultTitle;
  final HistorySource? history;
  final bool canEditScene;
  final bool first;
  final bool last;
  final int grid;
  final List<DashSection> sections;
  final List<DataPoint> points;
  final int channels;
  final List<({String device, String point, String name})> groupOptions;

  @override
  State<_TileSettings> createState() => _TileSettingsState();
}

class _TileSettingsState extends State<_TileSettings> {
  late DashWidget _w = widget.initial;
  late final _label = TextEditingController(text: widget.initial.label ?? '');
  late final _off = TextEditingController(text: widget.initial.labels?[0] ?? '');
  late final _on = TextEditingController(text: widget.initial.labels?[1] ?? '');
  late final _min = TextEditingController(text: _fmt(widget.initial.min));
  late final _max = TextEditingController(text: _fmt(widget.initial.max));
  late final _ref = TextEditingController(text: _fmt(widget.initial.ref));

  static String _fmt(double? v) => v == null ? '' : (v % 1 == 0 ? '${v.round()}' : '$v').replaceAll('.', ',');
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    for (final c in [_label, _off, _on, _min, _max, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  void _patch(Json changes) => setState(() => _w = _w.patch(changes));

  void _setLabel(String v) =>
      setState(() => _w = v.trim().isEmpty ? _w.copyWith(clearLabel: true) : _w.copyWith(label: v.trim()));

  void _setLabels() {
    final off = _off.text.trim(), on = _on.text.trim();
    _patch({
      'labels': off.isEmpty && on.isEmpty ? null : [off.isEmpty ? 'Nie' : off, on.isEmpty ? 'Tak' : on],
    });
  }

  Future<void> _pickIcon() async {
    final key = await pickAppIcon(
      context,
      current: _w.icon,
      defaultKey: widgetIconKey(view: _w.view, point: _w.point, type: widget.hub.device(_w.device ?? '')?.type),
    );
    if (key == null || !mounted) return;
    setState(() => _w = key.isEmpty ? _w.copyWith(clearIcon: true) : _w.copyWith(icon: key));
  }

  DataPoint? get _point => _w.point == null ? null : widget.points.where((p) => p.key == _w.point).firstOrNull;

  bool get _isOutputs => _w.view == WidgetView.toggle && _w.point == 'on' && widget.channels > 1;

  /// Szybkie sterowanie możliwe dla punktów urządzenia.
  List<TileFeature> get _possibleFeatures => [
    for (final p in widget.points)
      if (p.kind == PointKind.setpoint) ...[
        TileFeature('slider', p.key),
        TileFeature('stepper', p.key),
      ] else if (p.kind == PointKind.select && p.options.isNotEmpty)
        TileFeature('modes', p.key),
    if (widget.channels > 1) const TileFeature('channels'),
    for (final p in widget.points)
      if (p.history != null) TileFeature('trend', p.key),
  ];

  String _featureLabel(TileFeature f) {
    final p = f.point == null ? null : widget.points.where((x) => x.key == f.point).firstOrNull;
    final what = switch (f.type) {
      'slider' => 'suwak',
      'stepper' => '− / +',
      'modes' => 'tryby',
      'channels' => 'kanały',
      _ => 'trend',
    };
    return p == null ? what.substring(0, 1).toUpperCase() + what.substring(1) : '${p.name}: $what';
  }

  void _toggleFeature(TileFeature f, bool on) {
    final list = [
      for (final x in _w.features)
        if (!(x.type == f.type && x.point == f.point)) x,
      if (on) f,
    ];
    _patch({
      'features': list.isEmpty ? null : [for (final x in list) x.toJson()],
    });
  }

  /// Linia serii wykresu wg rodzaju punktu: stan - pasy, nastawa - schodki, odczyt - gładka.
  static String _lineFor(DataPoint p) => switch (p.kind) {
    PointKind.status || PointKind.switchKind => 'band',
    PointKind.setpoint => 'step',
    _ => 'smooth',
  };

  void _toggleSeries(DataPoint p, bool on) {
    final device = _w.device!;
    var list = _w.series.isEmpty && _w.point != null
        ? [(device: device, point: _w.point!, line: 'smooth')]
        : [..._w.series];
    list = [
      for (final s in list)
        if (!(s.device == device && s.point == p.key)) s,
      if (on) (device: device, point: p.key, line: _lineFor(p)),
    ];
    _patch({
      'series': list.length <= 1 && (list.isEmpty || list.single.point == _w.point)
          ? null
          : [
              for (final s in list.take(3)) {'device': s.device, 'point': s.point, 'line': s.line},
            ],
    });
  }

  bool _hasSeries(String key) =>
      _w.series.isEmpty ? key == _w.point : _w.series.any((s) => s.device == _w.device && s.point == key);

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l))],
      onChanged: (v) => onChanged(v as T),
    ),
  );

  Widget _group(String key, String title, List<Widget> children) => ExpansionTile(
    key: Key(key),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: 8),
    title: Text(title, style: Theme.of(context).textTheme.labelLarge),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width - 56;
    final tile = dashTileSize(_w, widget.grid, width);
    final p = _point;
    final tapItems = [
      (null as String?, 'Domyślnie'),
      ('toggle', 'Przełącz / wykonaj'),
      ('details', 'Szczegóły'),
      ('device', 'Ekran urządzenia'),
      ('none', 'Nic'),
    ];
    final features = _possibleFeatures;
    final historyPoints = [
      for (final x in widget.points)
        if (x.history != null) x,
    ];
    final zonesKind = switch (_w.zones.length) {
      3 => 'lowgoodhigh',
      2 => 'goodhigh',
      _ => 'none',
    };
    void setZones(String kind) {
      final lo = _parse(_min.text) ?? p?.min ?? 0, hi = _parse(_max.text) ?? p?.max ?? 100;
      final d = hi - lo;
      _patch({
        'zones': switch (kind) {
          'lowgoodhigh' => [
            [lo, lo + d / 3, 'amber'],
            [lo + d / 3, lo + 2 * d / 3, 'green'],
            [lo + 2 * d / 3, hi, 'blue'],
          ],
          'goodhigh' => [
            [lo, lo + 0.75 * d, 'green'],
            [lo + 0.75 * d, hi, 'red'],
          ],
          _ => null,
        },
      });
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kafelek', style: t.titleMedium),
              const SizedBox(height: 12),
              // Podgląd: ten sam kafelek co na pulpicie, bez dotyku.
              Container(
                key: const Key('tilePreview'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cs.surfaceContainerLowest, borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.centerLeft,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 150),
                  child: SizedBox.fromSize(
                    size: tile,
                    child: IgnorePointer(
                      child: DashTile(widget: _w, hub: widget.hub, history: widget.history),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('tileLabel'),
                controller: _label,
                maxLength: 24,
                decoration: InputDecoration(labelText: 'Podpis', hintText: widget.defaultTitle),
                onChanged: _setLabel,
              ),
              ListTile(
                key: const Key('tileIcon'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(dashWidgetIcon(_w, widget.hub)),
                title: const Text('Ikona'),
                subtitle: Text(appIcon(_w.icon)?.label ?? 'domyślna'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickIcon,
              ),
              const SizedBox(height: 8),
              Text('Rozmiar', style: t.labelLarge),
              const SizedBox(height: 6),
              if (widget.grid == 4)
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (gw, gh) in grid4Sizes)
                      ChoiceChip(
                        key: Key('tileSize4-${gw}x$gh'),
                        label: Text('$gw×$gh'),
                        selected: _w.gridW == gw && _w.gridH == gh,
                        onSelected: (_) => setState(() => _w = _w.resized(gw, gh)),
                      ),
                  ],
                )
              else
                SegmentedButton<WidgetSize>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in WidgetSize.values)
                      ButtonSegment(
                        value: s,
                        label: Text(s.wire.replaceAll('x', '×'), key: Key('tileSize-${s.wire}')),
                      ),
                  ],
                  selected: {_w.size},
                  onSelectionChanged: (v) => setState(() => _w = _w.copyWith(size: v.single)),
                ),
              if (widget.views.length > 1) ...[
                const SizedBox(height: 16),
                Text('Rodzaj', style: t.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final v in widget.views)
                      ChoiceChip(
                        key: Key('tileView-${v.wire}'),
                        label: Text(v.label),
                        selected: _w.view == v,
                        onSelected: (_) => setState(() => _w = _w.copyWith(view: v)),
                      ),
                  ],
                ),
              ],
              if (widget.grid == 4 && _w.pinned) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.push_pin_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Przypięty: kolumna ${_w.x! + 1}, wiersz ${_w.y! + 1}')),
                    ActionChip(
                      key: const Key('tilePosAuto'),
                      label: const Text('Położenie automatyczne'),
                      onPressed: () => setState(() => _w = _w.unpinned()),
                    ),
                  ],
                ),
              ],
              if (widget.sections.isNotEmpty) ...[
                const SizedBox(height: 12),
                _dropdown<String?>(
                  key: const Key('tileSection'),
                  label: 'Sekcja',
                  value: widget.sections.any((x) => x.id == _w.section) ? _w.section : null,
                  items: [(null, 'Bez sekcji'), for (final x in widget.sections) (x.id, x.title)],
                  onChanged: (v) => _patch({'section': v}),
                ),
              ],
              const SizedBox(height: 8),
              _group('tileMoreLook', 'Wygląd: kolor, ikona, druga linia', [
                Text('Kolor po włączeniu', style: t.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in const [null, 'amber', 'blue', 'green', 'red', 'purple', 'grey'])
                      InkWell(
                        key: Key('tileColor-${c ?? 'auto'}'),
                        customBorder: const CircleBorder(),
                        onTap: () => _patch({'color': c}),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: TileShell.schemeFor(c, Theme.of(context)).primaryContainer,
                            border: Border.all(
                              color: _w.color == c ? cs.onSurface : cs.outlineVariant,
                              width: _w.color == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Rozmiar ikony', style: t.bodySmall),
                const SizedBox(height: 6),
                SegmentedButton<String?>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: null, label: Text('Auto', key: Key('tileIconSize-auto'))),
                    ButtonSegment(
                      value: 's',
                      label: Text('Mała', key: Key('tileIconSize-s')),
                    ),
                    ButtonSegment(
                      value: 'm',
                      label: Text('Średnia', key: Key('tileIconSize-m')),
                    ),
                    ButtonSegment(
                      value: 'l',
                      label: Text('Duża', key: Key('tileIconSize-l')),
                    ),
                  ],
                  selected: {_w.iconSize},
                  onSelectionChanged: (v) => _patch({'iconSize': v.single}),
                ),
                const SizedBox(height: 12),
                _dropdown<String?>(
                  key: const Key('tileSecondary'),
                  label: 'Druga linia',
                  value: _w.secondary,
                  items: [
                    (null, 'Stan'),
                    ('lastChanged', 'Ostatnia zmiana'),
                    for (final x in widget.points)
                      if (x.key != _w.point && x.kind != PointKind.action) ('point:${x.key}', x.name),
                    ('none', 'Nic'),
                  ],
                  onChanged: (v) => _patch({'secondary': v}),
                ),
              ]),
              _group('tileMoreAction', 'Działanie dotyku', [
                _dropdown<String?>(
                  key: const Key('tileIconTap'),
                  label: 'Dotyk ikony',
                  value: _w.iconTap,
                  items: tapItems,
                  onChanged: (v) => _patch({'iconTap': v}),
                ),
                _dropdown<String?>(
                  key: const Key('tileTap'),
                  label: 'Dotyk kafelka',
                  value: _w.tap,
                  items: tapItems,
                  onChanged: (v) => _patch({'tap': v}),
                ),
                SwitchListTile(
                  key: const Key('tileConfirmSwitch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pytaj przed wykonaniem'),
                  subtitle: const Text('Np. brama, piec'),
                  value: _w.confirm,
                  onChanged: (v) => _patch({'confirm': v ? true : null}),
                ),
              ]),
              if (_isOutputs)
                _group('tileMoreChannels', 'Kanały na kafelku', [
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var i = 1; i <= widget.channels; i++)
                        FilterChip(
                          key: Key('tileChannel-on$i'),
                          label: Text(widget.points.where((x) => x.key == 'on$i').firstOrNull?.name ?? 'Kanał $i'),
                          selected: _w.points?.contains('on$i') ?? true,
                          onSelected: (on) {
                            final cur = _w.points ?? [for (var k = 1; k <= widget.channels; k++) 'on$k'];
                            final next = [
                              for (var k = 1; k <= widget.channels; k++)
                                if (k == i ? on : cur.contains('on$k')) 'on$k',
                            ];
                            if (next.isEmpty) return;
                            _patch({'points': next.length == widget.channels ? null : next});
                          },
                        ),
                    ],
                  ),
                ]),
              if (_w.view == WidgetView.group && widget.groupOptions.isNotEmpty)
                _group('tileMoreMembers', 'Wyjścia w grupie', [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final o in widget.groupOptions)
                        FilterChip(
                          key: Key('tileMember-${o.device}-${o.point}'),
                          label: Text(o.name),
                          selected: _w.members.any((m) => m.device == o.device && m.point == o.point),
                          onSelected: (on) {
                            final next = [
                              for (final m in _w.members)
                                if (!(m.device == o.device && m.point == o.point)) m,
                              if (on) (device: o.device, point: o.point),
                            ];
                            if (next.isEmpty) return;
                            _patch({
                              'members': [
                                for (final m in next) {'device': m.device, 'point': m.point},
                              ],
                            });
                          },
                        ),
                    ],
                  ),
                ]),
              if (_w.view == WidgetView.status)
                _group('tileMoreLabels', 'Napisy stanu', [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('tileLabelOff'),
                          controller: _off,
                          decoration: const InputDecoration(labelText: 'Gdy nie / rozwarte', hintText: 'Rozwarte'),
                          onChanged: (_) => _setLabels(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const Key('tileLabelOn'),
                          controller: _on,
                          decoration: const InputDecoration(labelText: 'Gdy tak / zwarte', hintText: 'Zwarte'),
                          onChanged: (_) => _setLabels(),
                        ),
                      ),
                    ],
                  ),
                ]),
              if (features.isNotEmpty &&
                  !const [WidgetView.chart, WidgetView.gauge, WidgetView.dial, WidgetView.thermostat].contains(_w.view))
                _group('tileMoreFeatures', 'Szybkie sterowanie w kafelku', [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final f in features)
                        FilterChip(
                          key: Key('tileFeature-${f.type}-${f.point ?? ''}'),
                          label: Text(_featureLabel(f)),
                          selected: _w.features.any((x) => x.type == f.type && x.point == f.point),
                          onSelected: (on) => _toggleFeature(f, on),
                        ),
                    ],
                  ),
                ]),
              if (_w.view == WidgetView.gauge)
                _group('tileMoreGauge', 'Wskaźnik', [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('tileMin'),
                          controller: _min,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: InputDecoration(labelText: 'Od', hintText: _fmt(p?.min ?? 0)),
                          onChanged: (v) => _patch({'min': _parse(v)}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const Key('tileMax'),
                          controller: _max,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: InputDecoration(labelText: 'Do', hintText: _fmt(p?.max ?? 100)),
                          onChanged: (v) => _patch({'max': _parse(v)}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _dropdown<String>(
                    key: const Key('tileZones'),
                    label: 'Strefy kolorów',
                    value: zonesKind,
                    items: const [
                      ('none', 'Bez stref'),
                      ('lowgoodhigh', 'Za mało / dobrze / za dużo'),
                      ('goodhigh', 'Dobrze / za dużo'),
                    ],
                    onChanged: setZones,
                  ),
                  _dropdown<String?>(
                    key: const Key('tileTarget'),
                    label: 'Znacznik celu',
                    value: _w.target,
                    items: [
                      (null, 'Brak'),
                      for (final x in widget.points)
                        if (x.key != _w.point && (x.kind == PointKind.setpoint || x.kind == PointKind.sensor))
                          ('point:${x.key}', x.name),
                    ],
                    onChanged: (v) => _patch({'target': v}),
                  ),
                ]),
              if (_w.view == WidgetView.chart)
                _group('tileMoreChart', 'Wykres', [
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final r in chartRanges)
                        ChoiceChip(
                          key: Key('tileRange-$r'),
                          label: Text(rangeLabel(r)),
                          selected: (_w.range ?? '24h') == r,
                          onSelected: (_) => _patch({'range': r == '24h' ? null : r}),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    key: const Key('tileRangeSwitch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Przełącznik zakresu w kafelku'),
                    value: _w.rangeSwitch,
                    onChanged: (v) => _patch({'rangeSwitch': v ? true : null}),
                  ),
                  if (historyPoints.length > 1) ...[
                    Text('Serie (do 3)', style: t.bodySmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final x in historyPoints)
                          FilterChip(
                            key: Key('tileSeries-${x.key}'),
                            label: Text(x.name),
                            selected: _hasSeries(x.key),
                            onSelected: (on) => _toggleSeries(x, on),
                          ),
                      ],
                    ),
                  ],
                  TextField(
                    key: const Key('tileRef'),
                    controller: _ref,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Linia odniesienia (opcjonalnie)', hintText: 'np. 21'),
                    onChanged: (v) => _patch({'ref': _parse(v)}),
                  ),
                ]),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    key: const Key('tileMoveUp'),
                    avatar: const Icon(Icons.arrow_upward, size: 18),
                    label: const Text('Wcześniej'),
                    onPressed: widget.first ? null : () => Navigator.pop(context, const TileMoved(-1)),
                  ),
                  ActionChip(
                    key: const Key('tileMoveDown'),
                    avatar: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Później'),
                    onPressed: widget.last ? null : () => Navigator.pop(context, const TileMoved(1)),
                  ),
                  ActionChip(
                    key: const Key('tileDuplicate'),
                    avatar: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Duplikuj'),
                    onPressed: () => Navigator.pop(context, const TileDuplicated()),
                  ),
                  if (widget.canEditScene)
                    ActionChip(
                      key: const Key('tileEditScene'),
                      avatar: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Edytuj scenę'),
                      onPressed: () => Navigator.pop(context, const TileEditScene()),
                    ),
                  ActionChip(
                    key: const Key('tileDelete'),
                    avatar: Icon(Icons.delete_outline, size: 18, color: cs.error),
                    label: Text('Usuń', style: TextStyle(color: cs.error)),
                    onPressed: () => Navigator.pop(context, const TileDeleted()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('tileSave'),
                      onPressed: () => Navigator.pop(context, TileUpdated(_w)),
                      child: const Text('Zapisz'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kafelek w trybie edycji: obrys, przycisk rozmiaru w rogu, przeciąganie po przytrzymaniu i miejsce upuszczenia
/// (podświetlone, gdy nad nim jest inny kafelek). Sam kafelek nie reaguje na dotyk.
class EditableTile extends StatelessWidget {
  const EditableTile({
    super.key,
    required this.id,
    required this.child,
    required this.onTap,
    required this.onResize,
    required this.onDrop,
  });

  final String id;
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback onResize;

  /// Upuszczono tu kafelek o tym id.
  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);
    return LayoutBuilder(
      builder: (context, box) {
        Widget framed(bool hover) => Stack(
          children: [
            Positioned.fill(child: IgnorePointer(child: child)),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: Key('editTile-$id'),
                  borderRadius: radius,
                  onTap: onTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: hover ? cs.primary : cs.outline, width: hover ? 3 : 1.5),
                    ),
                  ),
                ),
              ),
            ),
            // Mały uchwyt w samym rogu - zasłania jak najmniej treści kafelka.
            Positioned(
              right: 2,
              bottom: 2,
              child: Tooltip(
                message: 'Zmień rozmiar',
                child: Material(
                  key: Key('tileResize-$id'),
                  shape: const CircleBorder(),
                  color: cs.secondaryContainer,
                  elevation: 1,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onResize,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.open_in_full, size: 16, color: cs.onSecondaryContainer),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        return DragTarget<String>(
          onWillAcceptWithDetails: (d) => d.data != id,
          onAcceptWithDetails: (d) => onDrop(d.data),
          builder: (context, candidates, _) => LongPressDraggable<String>(
            data: id,
            feedback: Material(
              color: Colors.transparent,
              elevation: 8,
              borderRadius: radius,
              child: SizedBox(
                width: box.maxWidth,
                height: box.maxHeight,
                child: IgnorePointer(child: Opacity(opacity: 0.92, child: child)),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: framed(false)),
            child: framed(candidates.isNotEmpty),
          ),
        );
      },
    );
  }
}

/// Wolne pole siatki 4 w edycji: miejsce do upuszczenia kafelka (podświetlone, gdy nad nim jest kafelek).
class EmptyCell extends StatelessWidget {
  const EmptyCell({super.key, required this.onDrop});

  final ValueChanged<String> onDrop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: hover ? cs.primaryContainer.withValues(alpha: 0.6) : cs.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hover ? cs.primary : cs.outlineVariant, width: hover ? 2 : 1),
          ),
          child: hover ? Icon(Icons.add, color: cs.primary) : null,
        );
      },
    );
  }
}
