// Ostrzeżenia IMGW, alerty pogodowe i dzień liturgiczny w hubie (kontrakt pkt 11, hub 0.3.44+): podgląd ze State huba
// (`warnings`, `alerts`, `today`) na ekranie huba i ustawienia w Config (`warnings {enabled, teryt}`,
// `alerts {frost, frostBelow, rain, rainMm, rainDryH}`, `today {enabled}`). Działa lokalnie i przez chmurę (State
// i Config huba są w lustrze).

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/field_errors.dart';
import '../models/hub_warnings.dart';
import '../models/json_utils.dart';
import 'format.dart';
import 'widgets.dart';

/// Kolor stopnia ostrzeżenia: 1 żółty, 2 pomarańczowy, 3 czerwony.
Color warningColor(int level) => switch (level) {
  >= 3 => const Color(0xFFE03131),
  2 => const Color(0xFFFF922B),
  _ => const Color(0xFFFCC419),
};

const _dayNames = ['pn', 'wt', 'śr', 'cz', 'pt', 'so', 'nd'];

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// „18:00” dziś, „jutro 06:00”, „pt 21.11 06:00” dalej.
String warningTime(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day), today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return _hm(t);
  if (diff == 1) return 'jutro ${_hm(t)}';
  return '${_dayNames[t.weekday - 1]} ${t.day}.${t.month.toString().padLeft(2, '0')} ${_hm(t)}';
}

/// „do 18:00” (trwa) albo „od jutro 06:00 do …” (zapowiedź).
String warningWhen(HubWarning w, DateTime now) {
  final to = w.to == null ? '' : 'do ${warningTime(w.to!, now)}';
  if (w.active || w.from == null) return to;
  return ['od ${warningTime(w.from!, now)}', to].where((s) => s.isNotEmpty).join(' ');
}

/// Bieżące ostrzeżenia, alerty i dzień liturgiczny ze State huba (ekran huba i ekran ustawień).
class HubWarningsStatus extends StatelessWidget {
  const HubWarningsStatus({super.key, required this.state, this.now});

  final Json state;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final at = (now ?? DateTime.now)();
    final warnings = hubWarnings(state['warnings']) ?? const <HubWarning>[];
    final alerts = hubAlerts(state['alerts']) ?? const <HubAlert>[];
    final today = HubToday.fromJson(state['today']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in warnings)
          Card(
            key: Key('warning-${w.id}'),
            color: warningColor(w.level).withValues(alpha: 0.18),
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: warningColor(w.level), size: 32),
              title: Text('${w.event} - stopień ${w.level}'),
              subtitle: Text(
                [
                  [
                    warningWhen(w, at),
                    if (!w.active) 'zapowiedź',
                    if (w.prob != null) 'prawdopodobieństwo ${w.prob} %',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  ?w.text,
                ].join('\n'),
              ),
              isThreeLine: w.text != null,
            ),
          ),
        for (final a in alerts)
          Card(
            key: Key('alert-${a.id}'),
            child: ListTile(
              leading: Icon(a.kind == 'frost' ? Icons.ac_unit : Icons.water_drop_outlined),
              title: Text(a.text),
              subtitle: Text(
                [
                  if (a.kind == 'frost' && a.t != null) 'minimum ${fmtTemp(a.t)}',
                  if (a.kind == 'rain' && a.mm != null) 'opad ${fmtNumber(a.mm!)} mm',
                  if (a.until != null) 'do ${warningTime(a.until!, at)}',
                ].join(' · '),
              ),
            ),
          ),
        if (today != null && (today.saint != null || today.day != null || today.readings.isNotEmpty))
          Card(
            key: const Key('hubToday'),
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(today.saint ?? today.day ?? 'Dzień liturgiczny'),
              subtitle: Text(
                [
                  if (today.saint != null) ?today.day,
                  if (today.readings.isNotEmpty) today.readings.join(' · '),
                ].join('\n'),
                style: t.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }
}

/// Opis na liście ekranu huba.
String hubWarningsSummary(Json cfg, Json state) {
  final w = cfg['warnings'] is Map ? cfg['warnings'] as Map : null;
  final a = alertSettings(cfg['alerts']);
  final list = hubWarnings(state['warnings']);
  return [
    if (w != null)
      w['enabled'] != true
          ? 'IMGW wyłączone'
          : list == null
          ? 'IMGW: ${cfg['countyName'] ?? 'powiat nieustalony'}'
          : list.isEmpty
          ? 'IMGW: brak ostrzeżeń'
          : 'IMGW: ${list.length} ${list.length == 1 ? 'ostrzeżenie' : 'ostrzeżenia'}',
    if (cfg.containsKey('alerts'))
      [
        if (a.frost) 'przymrozek < ${fmtNumber(a.frostBelow)} °C',
        if (a.rain) 'deszcz',
      ].join(', ').ifEmpty('alerty wył.'),
    if (cfg['today'] is Map && (cfg['today'] as Map)['enabled'] == true) 'dzień liturgiczny',
  ].join(' · ');
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Wartości `rainMm` do wyboru suwakiem (0,05…5 mm w 15 min).
const _rainSteps = [0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 5.0];

/// Ustawienia i podgląd: ostrzeżenia IMGW (powiat), alerty przymrozku i deszczu, dzień liturgiczny.
class HubWarningsScreen extends StatefulWidget {
  const HubWarningsScreen({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<HubWarningsScreen> createState() => _HubWarningsScreenState();
}

class _HubWarningsScreenState extends State<HubWarningsScreen> {
  DeviceController<Object?, Object?> get c => widget.controller;
  late final _teryt = TextEditingController(text: _obj('warnings')['teryt'] as String? ?? '');

  // Wartości suwaków w trakcie przeciągania (zapis po puszczeniu).
  double? _frostBelow;
  double? _rainIndex;
  double? _rainDryH;

  Json get _cfg => c.config is Map ? (c.config! as Map).cast<String, dynamic>() : const {};
  Json get _state => c.stateJson ?? const {};
  Json _obj(String key) => _cfg[key] is Map ? (_cfg[key] as Map).cast<String, dynamic>() : const {};

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _teryt.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _set(String key, Json changes) async {
    final r = await c.sendJson({
      key: {..._obj(key), ...changes},
    });
    if (mounted) showSaveResult(context, r.errors, describeErrors);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final can = c.canConfig;
    final t = Theme.of(context).textTheme;
    final w = _obj('warnings');
    final a = alertSettings(cfg['alerts']);
    final teryt = _teryt.text.trim();
    final rainIndex = _rainIndex ?? _rainSteps.indexWhere((s) => s >= a.rainMm - 1e-9).clamp(0, _rainSteps.length - 1);
    return Scaffold(
      appBar: AppBar(title: const Text('Ostrzeżenia i alerty')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          HubWarningsStatus(state: _state),
          if (cfg.containsKey('warnings')) ...[
            const SectionHeader('Ostrzeżenia IMGW'),
            SwitchListTile(
              key: const Key('warningsEnabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Ostrzeżenia meteorologiczne'),
              subtitle: const Text('IMGW-PIB co 15 min - dla powiatu domu (zegary: pasek w kolorze stopnia)'),
              value: w['enabled'] == true,
              onChanged: can ? (v) => _set('warnings', {'enabled': v}) : null,
            ),
            ListTile(
              key: const Key('warningsCounty'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.map_outlined),
              title: Text(
                cfg['countyName'] is String
                    ? '${cfg['countyName']}${cfg['county'] is String ? ' (${cfg['county']})' : ''}'
                    : 'Powiat jeszcze nieustalony',
              ),
              subtitle: Text(
                (w['teryt'] as String? ?? '').isEmpty
                    ? 'Z położenia domu (hub pyta GUGiK po zmianie położenia)'
                    : 'Wpisany ręcznie: ${w['teryt']}',
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('warningsTeryt'),
                    controller: _teryt,
                    enabled: can,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(
                      labelText: 'Kod TERYT powiatu (4 cyfry)',
                      helperText: 'Puste = sam z położenia domu, np. 1261 Kraków, 1206 powiat krakowski',
                      helperMaxLines: 2,
                      errorText: validTeryt(teryt) ? null : 'Cztery cyfry albo puste',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    key: const Key('warningsTerytSave'),
                    onPressed: can && validTeryt(teryt) && teryt != (w['teryt'] as String? ?? '')
                        ? () => _set('warnings', {'teryt': teryt})
                        : null,
                    child: const Text('Zapisz'),
                  ),
                ),
              ],
            ),
          ],
          if (cfg.containsKey('alerts')) ...[
            const SectionHeader('Alerty pogodowe'),
            Text(
              'Hub liczy je z prognozy wybranego źródła; zegar pokazuje dymek raz, potem mały znaczek.',
              style: t.bodySmall,
            ),
            SwitchListTile(
              key: const Key('alertsFrost'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Przymrozek w nocy'),
              subtitle: Text('Gdy w nocy (18-9) spadnie poniżej ${fmtNumber(_frostBelow ?? a.frostBelow)} °C'),
              value: a.frost,
              onChanged: can ? (v) => _set('alerts', {'frost': v}) : null,
            ),
            Slider(
              key: const Key('alertsFrostBelow'),
              min: frostBelowMin,
              max: frostBelowMax,
              divisions: ((frostBelowMax - frostBelowMin) * 2).round(),
              label: '${fmtNumber(_frostBelow ?? a.frostBelow)} °C',
              value: (_frostBelow ?? a.frostBelow).clamp(frostBelowMin, frostBelowMax),
              onChanged: can && a.frost ? (v) => setState(() => _frostBelow = v) : null,
              onChangeEnd: (v) async {
                await _set('alerts', {'frostBelow': v});
                if (mounted) setState(() => _frostBelow = null);
              },
            ),
            SwitchListTile(
              key: const Key('alertsRain'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Deszcz za chwilę'),
              subtitle: Text(
                'Gdy w ciągu godziny zacznie padać po ${(_rainDryH ?? a.rainDryH).round()} h bez deszczu '
                '(od ${fmtNumber(_rainSteps[rainIndex.round()], decimals: 2)} mm w 15 min) - „zamknij okna”',
              ),
              value: a.rain,
              onChanged: can ? (v) => _set('alerts', {'rain': v}) : null,
            ),
            Text('Ile musi padać', style: t.labelMedium),
            Slider(
              key: const Key('alertsRainMm'),
              min: 0,
              max: _rainSteps.length - 1.0,
              divisions: _rainSteps.length - 1,
              label: '${fmtNumber(_rainSteps[rainIndex.round()], decimals: 2)} mm',
              value: rainIndex.toDouble(),
              onChanged: can && a.rain ? (v) => setState(() => _rainIndex = v) : null,
              onChangeEnd: (v) async {
                await _set('alerts', {'rainMm': _rainSteps[v.round()]});
                if (mounted) setState(() => _rainIndex = null);
              },
            ),
            Text('Ile godzin sucho przed deszczem', style: t.labelMedium),
            Slider(
              key: const Key('alertsRainDryH'),
              min: 0,
              max: rainDryHMax.toDouble(),
              divisions: rainDryHMax,
              label: '${(_rainDryH ?? a.rainDryH).round()} h',
              value: (_rainDryH ?? a.rainDryH.toDouble()).clamp(0, rainDryHMax.toDouble()),
              onChanged: can && a.rain ? (v) => setState(() => _rainDryH = v) : null,
              onChangeEnd: (v) async {
                await _set('alerts', {'rainDryH': v.round()});
                if (mounted) setState(() => _rainDryH = null);
              },
            ),
          ],
          if (cfg.containsKey('today')) ...[
            const SectionHeader('Dzień liturgiczny'),
            SwitchListTile(
              key: const Key('todayEnabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Święty i czytania dnia'),
              subtitle: const Text('Evangelizo raz na dobę - nazwy i sigla czytań, bez tekstów'),
              value: _obj('today')['enabled'] == true,
              onChanged: can ? (v) => _set('today', {'enabled': v}) : null,
            ),
          ],
        ],
      ),
    );
  }
}
