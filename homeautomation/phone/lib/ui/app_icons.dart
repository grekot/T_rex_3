import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import '../models/device_type.dart';

/// Ikona do wyboru dla widżetu pulpitu albo urządzenia. [key] trafia do JSON-u (`"icon"`), więc się nie zmienia.
class AppIcon {
  const AppIcon(this.key, this.label, this.icon, this.group);

  final String key;
  final String label;
  final IconData icon;
  final String group;
}

/// Katalog ikon (Material Icons) w grupach - klucze są stałe, nazwy po polsku.
const appIcons = <AppIcon>[
  // Oświetlenie
  AppIcon('light', 'Żarówka', Icons.lightbulb_outline, 'Oświetlenie'),
  AppIcon('light-on', 'Żarówka (świeci)', Icons.lightbulb, 'Oświetlenie'),
  AppIcon('ceiling', 'Sufit', Icons.light, 'Oświetlenie'),
  AppIcon('lamp', 'Lampka', Icons.wb_incandescent_outlined, 'Oświetlenie'),
  AppIcon('spot', 'Reflektor', Icons.highlight, 'Oświetlenie'),
  AppIcon('led', 'Taśma LED', Icons.linear_scale, 'Oświetlenie'),
  AppIcon('outdoor-light', 'Na zewnątrz', Icons.deck, 'Oświetlenie'),
  AppIcon('night', 'Nocne', Icons.nightlight_outlined, 'Oświetlenie'),
  AppIcon('dimmer', 'Ściemniacz', Icons.light_mode_outlined, 'Oświetlenie'),
  // Ogrzewanie i klimat
  AppIcon('thermostat', 'Termostat', Icons.thermostat, 'Ogrzewanie i klimat'),
  AppIcon('temperature', 'Temperatura', Icons.device_thermostat, 'Ogrzewanie i klimat'),
  AppIcon('heating', 'Grzanie', Icons.local_fire_department_outlined, 'Ogrzewanie i klimat'),
  AppIcon('frost', 'Mróz', Icons.ac_unit, 'Ogrzewanie i klimat'),
  AppIcon('schedule', 'Harmonogram', Icons.calendar_month_outlined, 'Ogrzewanie i klimat'),
  AppIcon('humidity', 'Wilgotność', Icons.water_drop_outlined, 'Ogrzewanie i klimat'),
  AppIcon('fan', 'Wentylator', Icons.air, 'Ogrzewanie i klimat'),
  AppIcon('outdoor', 'Pogoda', Icons.wb_sunny_outlined, 'Ogrzewanie i klimat'),
  // Zasilanie i sprzęty
  AppIcon('power', 'Zasilanie', Icons.power_settings_new, 'Zasilanie i sprzęty'),
  AppIcon('socket', 'Gniazdko', Icons.electrical_services, 'Zasilanie i sprzęty'),
  AppIcon('energy', 'Energia', Icons.bolt, 'Zasilanie i sprzęty'),
  AppIcon('tv', 'Telewizor', Icons.tv, 'Zasilanie i sprzęty'),
  AppIcon('speaker', 'Głośnik', Icons.speaker_outlined, 'Zasilanie i sprzęty'),
  AppIcon('coffee', 'Ekspres', Icons.coffee_outlined, 'Zasilanie i sprzęty'),
  AppIcon('kitchen', 'Kuchnia', Icons.kitchen_outlined, 'Zasilanie i sprzęty'),
  AppIcon('laundry', 'Pralka', Icons.local_laundry_service_outlined, 'Zasilanie i sprzęty'),
  AppIcon('water', 'Woda', Icons.water, 'Zasilanie i sprzęty'),
  // Dom i miejsca
  AppIcon('home', 'Dom', Icons.home_outlined, 'Dom i miejsca'),
  AppIcon('living', 'Salon', Icons.weekend_outlined, 'Dom i miejsca'),
  AppIcon('bedroom', 'Sypialnia', Icons.bed_outlined, 'Dom i miejsca'),
  AppIcon('bathroom', 'Łazienka', Icons.bathtub_outlined, 'Dom i miejsca'),
  AppIcon('stairs', 'Schody', Icons.stairs_outlined, 'Dom i miejsca'),
  AppIcon('door', 'Drzwi', Icons.door_front_door_outlined, 'Dom i miejsca'),
  AppIcon('window', 'Okno', Icons.window_outlined, 'Dom i miejsca'),
  AppIcon('garage', 'Garaż', Icons.garage_outlined, 'Dom i miejsca'),
  AppIcon('garden', 'Ogród', Icons.yard_outlined, 'Dom i miejsca'),
  AppIcon('pool', 'Basen', Icons.pool, 'Dom i miejsca'),
  // Czujniki i wejścia
  AppIcon('sensor', 'Czujnik', Icons.sensors, 'Czujniki i wejścia'),
  AppIcon('motion', 'Ruch', Icons.directions_walk, 'Czujniki i wejścia'),
  AppIcon('door-sensor', 'Kontaktron', Icons.sensor_door_outlined, 'Czujniki i wejścia'),
  AppIcon('button', 'Przycisk', Icons.radio_button_checked, 'Czujniki i wejścia'),
  AppIcon('switch', 'Łącznik', Icons.toggle_on_outlined, 'Czujniki i wejścia'),
  AppIcon('touch', 'Dotyk', Icons.touch_app_outlined, 'Czujniki i wejścia'),
  AppIcon('lock', 'Zamek', Icons.lock_outline, 'Czujniki i wejścia'),
  AppIcon('alarm', 'Alarm', Icons.notifications_active_outlined, 'Czujniki i wejścia'),
  // Sceny
  AppIcon('scene', 'Scena', Icons.auto_awesome, 'Sceny'),
  AppIcon('leave', 'Wychodzę', Icons.logout, 'Sceny'),
  AppIcon('arrive', 'Wracam', Icons.login, 'Sceny'),
  AppIcon('sleep', 'Dobranoc', Icons.bedtime_outlined, 'Sceny'),
  AppIcon('morning', 'Dzień dobry', Icons.wb_twilight, 'Sceny'),
  AppIcon('movie', 'Film', Icons.movie_outlined, 'Sceny'),
  AppIcon('party', 'Impreza', Icons.celebration_outlined, 'Sceny'),
  AppIcon('eco', 'Oszczędzanie', Icons.eco_outlined, 'Sceny'),
  // Urządzenia
  AppIcon('hub', 'Hub', Icons.device_hub, 'Urządzenia'),
  AppIcon('node', 'Węzeł', Icons.developer_board, 'Urządzenia'),
  AppIcon('relay', 'Przekaźniki', Icons.view_module_outlined, 'Urządzenia'),
  AppIcon('router', 'Sieć', Icons.router_outlined, 'Urządzenia'),
  AppIcon('chart', 'Wykres', Icons.show_chart, 'Urządzenia'),
  AppIcon('settings', 'Ustawienia', Icons.tune, 'Urządzenia'),
];

final _byKey = {for (final i in appIcons) i.key: i};

AppIcon? appIcon(String? key) => key == null ? null : _byKey[key];

/// Ikona domyślna dla urządzenia danego typu (kafelki, lista urządzeń).
String deviceIconKey(DeviceType type) => switch (type) {
  DeviceType.thermostat => 'thermostat',
  DeviceType.hub => 'hub',
  DeviceType.dimmer => 'dimmer',
  DeviceType.onOff => 'light',
  _ => 'node',
};

/// Ikona domyślna widżetu: z widoku, punktu danych i typu urządzenia.
String widgetIconKey({required WidgetView view, String? point, DeviceType? type}) {
  if (view == WidgetView.scene) return 'scene';
  if (view == WidgetView.thermostat) return 'thermostat';
  if (view == WidgetView.chart) return 'chart';
  if (view == WidgetView.group) return 'light';
  if (view == WidgetView.weather) return 'outdoor';
  if (view == WidgetView.hub) return 'hub';
  if (view == WidgetView.schedule) return 'schedule';
  final p = point ?? '';
  if (RegExp(r'^on\d*$').hasMatch(p) || p == 'toggle') return 'light';
  if (RegExp(r'^in\d+$').hasMatch(p)) return 'button';
  return switch (p) {
    'temp' => 'temperature',
    'outdoor.temp' => 'outdoor',
    'hum' => 'humidity',
    'target' => 'thermostat',
    'heating' => 'heating',
    'mode' => 'settings',
    'power' => type == DeviceType.thermostat ? 'power' : 'energy',
    'level' => 'dimmer',
    'lux' => 'outdoor',
    _ => type == null ? 'sensor' : deviceIconKey(type),
  };
}

/// Wybór ikony: siatka w grupach, „Domyślna” zwraca pusty klucz (`''`), anulowanie - null.
Future<String?> pickAppIcon(BuildContext context, {String? current, String? defaultKey}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _IconGrid(scroll: scroll, current: current, defaultKey: defaultKey),
      ),
    );

class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.scroll, this.current, this.defaultKey});

  final ScrollController scroll;
  final String? current;
  final String? defaultKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final groups = <String, List<AppIcon>>{};
    for (final i in appIcons) {
      (groups[i.group] ??= []).add(i);
    }
    final def = appIcon(defaultKey);
    Widget tile(AppIcon? i, {required bool selected, required String key, required String label}) => InkWell(
      key: Key('icon-$key'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pop(context, key),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(i?.icon ?? Icons.auto_fix_high, color: selected ? cs.onPrimaryContainer : null),
            const SizedBox(height: 4),
            Text(label, maxLines: 2, textAlign: TextAlign.center, style: t.labelSmall),
          ],
        ),
      ),
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Text('Ikona', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          children: [
            tile(
              def,
              selected: current == null || current!.isEmpty,
              key: '',
              label: 'Domyślna${def == null ? '' : ' (${def.label})'}',
            ),
          ],
        ),
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(g.key, style: t.labelLarge),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final i in g.value) tile(i, selected: current == i.key, key: i.key, label: i.label)],
          ),
        ],
      ],
    );
  }
}
