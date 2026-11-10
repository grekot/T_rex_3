// Zegar-termometr `clock` (pkt 10.2) na ekranie urządzenia: pokój (temp., wilg., ciśn., rozgrzewanie, awaria
// czujnika, komfort), pogoda teraz, „Pokaż ekran”, „Pokaż, który to” i ustawienia (PLAN zegara pkt 9).

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../controllers/field_errors.dart';
import '../models/clock.dart';
import '../models/json_utils.dart';
import 'clock_buttons.dart';
import 'clock_pages.dart';
import 'clock_settings.dart';
import 'dashboard_tiles.dart' show weatherIconAt, weatherLabel;
import 'format.dart';
import 'widgets.dart';

/// Jedna linijka na kafelek listy: `21,4 °C · 46 % · rozgrzewanie`.
String clockSummary(Json s) {
  if (s['sensorFault'] == true) return 'Awaria czujnika';
  return [
    if (s['warmup'] == true) 'rozgrzewanie' else if (s['temp'] is num) fmtTemp((s['temp'] as num).toDouble()),
    if (s['hum'] is num) '${(s['hum'] as num).round()} %',
    if (s['outTemp'] is num) 'na zewnątrz ${fmtTemp((s['outTemp'] as num).toDouble())}',
  ].join(' · ');
}

/// `screens.list` z Config (domyślnie główny i pogoda).
List<String> clockScreenList(Json? cfg) {
  final s = cfg?['screens'];
  final l = s is Map && s['list'] is List ? [for (final x in s['list'] as List) '$x'] : null;
  return l ?? const ['main', 'hours', 'days', 'chart'];
}

class ClockSection extends StatelessWidget {
  const ClockSection({super.key, required this.controller, this.hub});

  final DeviceController<Object?, Object?> controller;
  final DeviceHub? hub;

  DeviceController<Object?, Object?> get c => controller;

  Json? get _cfg => c.config is Map ? (c.config! as Map).cast<String, dynamic>() : null;

  Future<void> _send(BuildContext context, Json values) async {
    final r = await c.sendJson(values);
    if (context.mounted) showSaveResult(context, r.errors, describeErrors);
  }

  /// „Pokaż ekran”: polecenia i ekrany z `screens.list` (Set `showScreen`, poziom `control`).
  Future<void> _showScreen(BuildContext context) async {
    final pages = ClockPage.listFrom(_cfg);
    final key = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final k in clockScreenList(_cfg))
              ListTile(
                key: Key('clockShow-$k'),
                leading: const Icon(Icons.tv_outlined),
                title: Text(clockScreenName(k, pages)),
                onTap: () => Navigator.pop(ctx, k),
              ),
            const Divider(),
            for (final MapEntry(key: k, value: label) in clockCommands.entries)
              ListTile(
                key: Key('clockShow-$k'),
                leading: const Icon(Icons.skip_next_outlined),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    );
    if (key != null && context.mounted) await _send(context, {'showScreen': key});
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = c.stateJson ?? const <String, dynamic>{};
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final o = s['outdoor'];
    final warm = s['warmup'] == true, fault = s['sensorFault'] == true;
    final temp = s['temp'] is num ? (s['temp'] as num).toDouble() : null;
    final cfg = _cfg;
    final pages = ClockPage.listFrom(cfg);
    final viaHub = c.device.via;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warm || fault)
          Card(
            key: const Key('clockWarn'),
            color: fault ? cs.errorContainer : cs.tertiaryContainer,
            child: ListTile(
              leading: Icon(fault ? Icons.error_outline : Icons.hourglass_top),
              title: Text(fault ? 'Awaria czujnika' : 'Rozgrzewanie czujnika'),
              subtitle: Text(
                fault
                    ? 'Zegar nie odczytuje temperatury - sprawdź czujnik w obudowie.'
                    : 'Do 30 min po włączeniu zasilania temperatura jest ukryta (płytka i ekran grzeją czujnik).',
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      temp == null ? '–' : fmtTemp(temp),
                      key: const Key('clockTemp'),
                      style: t.displaySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    if (s['hum'] is num) Text('${(s['hum'] as num).round()} %', style: t.titleLarge),
                    const Spacer(),
                    if (s['comfort'] is String) Chip(label: Text(s['comfort'] as String)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (s['press'] is num) '${(s['press'] as num).round()} hPa',
                    if (s['lux'] is num) '${(s['lux'] as num).round()} lx',
                    if (s['night'] == true) 'tryb nocny',
                    if (s['screen'] is String) 'ekran: ${clockScreenName(s['screen'] as String, pages)}',
                  ].join(' · '),
                  style: t.bodyMedium,
                ),
                if (o is Map) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(weatherIconAt(o['icon'], day: o['day'] != false), size: 32),
                      const SizedBox(width: 12),
                      Text(o['temp'] is num ? fmtTemp((o['temp'] as num).toDouble()) : '–', style: t.titleLarge),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${weatherLabel(o['icon'])}'
                          '${o['age'] is num && (o['age'] as num) > 2700 ? ' · sprzed ${(o['age'] as num) ~/ 60} min' : ''}',
                          style: t.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (c.canControl)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('clockShowScreen'),
                icon: const Icon(Icons.tv_outlined),
                label: const Text('Pokaż ekran'),
                onPressed: () => _showScreen(context),
              ),
              OutlinedButton.icon(
                key: const Key('clockIdentify'),
                icon: const Icon(Icons.highlight),
                label: const Text('Pokaż, który to'),
                onPressed: () => _send(context, {'identify': true}),
              ),
            ],
          ),
        if (c.canConfig) ...[
          const SectionHeader('Ustawienia zegara'),
          ListTile(
            key: const Key('clockScreens'),
            leading: const Icon(Icons.view_carousel_outlined),
            title: const Text('Ekrany'),
            subtitle: Text(
              '${clockScreenList(cfg).map((k) => clockScreenName(k, pages)).join(', ')}'
              ' · ${clockTransitions[_screens(cfg)['transition']] ?? clockTransitions['cards']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _open(context, ClockScreensPage(controller: c)),
          ),
          ListTile(
            key: const Key('clockPages'),
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: const Text('Strony z widżetami'),
            subtitle: Text(
              viaHub == null
                  ? 'Najpierw dodaj zegar do huba - to hub przysyła odczyty'
                  : pages.isEmpty
                  ? 'Stan urządzeń domu na ekranie zegara (do $clockMaxPages stron)'
                  : pages.map((p) => '${p.title} (${p.widgets.length})').join(', '),
            ),
            enabled: viaHub != null && hub != null,
            onTap: () => _open(context, ClockPagesScreen(controller: c, hub: hub!)),
          ),
          ListTile(
            key: const Key('clockDisplay'),
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Jasność i noc'),
            subtitle: Text(_displayText(cfg)),
            onTap: () => _open(context, ClockDisplayPage(controller: c)),
          ),
          ListTile(
            key: const Key('clockWeather'),
            leading: const Icon(Icons.wb_cloudy_outlined),
            title: const Text('Pogoda i jednostki'),
            subtitle: Text(
              viaHub == null
                  ? 'Własna lokalizacja zegara'
                  : cfg?['outdoor'] is Map
                  ? 'Z huba; temperatura z czujnika na zewnątrz'
                  : 'Z huba; czujnik na zewnątrz do wyboru',
            ),
            onTap: () => _open(context, ClockWeatherPage(controller: c, hub: hub)),
          ),
          ListTile(
            key: const Key('clockSensor'),
            leading: const Icon(Icons.thermostat_outlined),
            title: const Text('Czujnik'),
            subtitle: const Text('Korekta temperatury i wilgotności, kompensacja nagrzewania'),
            onTap: () => _open(context, ClockSensorPage(controller: c)),
          ),
          ListTile(
            key: const Key('clockTheme'),
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Motyw'),
            subtitle: Text(_themeText(cfg)),
            onTap: () => _open(context, ClockThemePage(controller: c)),
          ),
          ListTile(
            key: const Key('clockTime'),
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Zegar'),
            subtitle: const Text('Sekundy, format daty'),
            onTap: () => _open(context, ClockTimePage(controller: c)),
          ),
          ListTile(
            key: const Key('clockButtons'),
            leading: const Icon(Icons.smart_button_outlined),
            title: const Text('Przyciski zdalne'),
            subtitle: Text(
              viaHub == null
                  ? 'Najpierw dodaj zegar do huba - przyciski to automatyki huba'
                  : 'Pilot, przycisk węzła albo czujnika przełącza ekrany',
            ),
            enabled: viaHub != null && hub != null,
            onTap: () => _open(context, ClockButtonsScreen(controller: c, hub: hub!)),
          ),
        ],
      ],
    );
  }

  static Json _screens(Json? cfg) => cfg?['screens'] is Map ? (cfg!['screens'] as Map).cast<String, dynamic>() : {};

  static String _themeText(Json? cfg) {
    final t = cfg?['theme'] is Map ? cfg!['theme'] as Map : const {};
    final name = clockThemes[t['name']]?.label ?? clockThemes['pastel']!.label;
    return t['seasonal'] == true ? 'Według pory roku' : name;
  }

  static String _displayText(Json? cfg) {
    final d = cfg?['display'] is Map ? cfg!['display'] as Map : const {};
    final n = cfg?['night'] is Map ? cfg!['night'] as Map : const {};
    return [
      'jasność ${d['brightness'] ?? 80} %${d['auto'] == true ? ' (auto)' : ''}',
      if (n['mode'] != null && n['mode'] != 'off') 'noc ${n['window'] ?? ''}'.trim() else 'bez trybu nocnego',
    ].join(' · ');
  }
}
