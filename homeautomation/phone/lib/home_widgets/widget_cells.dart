import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../models/describe.dart';
import '../models/device_type.dart';
import '../models/home.dart';
import '../models/home_widget.dart';
import '../models/json_utils.dart';
import '../ui/dashboard_tiles.dart' show channelName;
import '../ui/hub_ble_screen.dart' show bleValueText;

/// Kanały `on1..N` węzła wielokanałowego; 1 = zwykły włącznik.
int channelCount(Json? state) => state?['channels'] is int ? state!['channels'] as int : 1;

String _degrees(Object? v) => v is num ? '${v.toStringAsFixed(1).replaceAll('.', ',')}°' : '—';

/// Set dla dotknięcia wyjścia - tak jak ikona kafelka pulpitu: wszystkie kanały jednym `on`.
Json outputToggle(String point, Json? state) {
  final n = channelCount(state);
  if (point == 'on' && n > 1) {
    final any = [for (var i = 1; i <= n; i++) state?['on$i'] == true].contains(true);
    return {'on': !any};
  }
  return {point: state?[point] != true};
}

/// Czy po przełączeniu wyjście będzie włączone.
bool outputActiveAfter(Json set) => set.values.first == true;

WidgetCell _unavailable(String title, String subtitle, String icon) =>
    WidgetCell(title: title, subtitle: subtitle, icon: icon, dimmed: true);

String _noLink(DeviceController<Object?, Object?> c) =>
    c.phase == ConnectPhase.connecting ? 'Łączenie…' : 'Brak kontaktu';

WidgetCell _output(HomeWidgetItem item, DeviceHub hub) {
  final id = item.device!, point = item.point!;
  final c = hub.controller(id);
  final name = c?.device.name ?? hub.device(id)?.name ?? 'Urządzenie';
  if (c == null) return _unavailable(name, 'Niedostępne', 'lock');
  if (hub.accessFor(id) == AccessLevel.none) return _unavailable(name, 'Brak dostępu', 'lock');
  final state = c.stateJson;
  final n = channelCount(state);
  final all = point == 'on';
  final title = all ? name : channelName(c, null, point);
  if (state == null || !c.live) return _unavailable(title, _noLink(c), 'bulb');
  if (all && n > 1) {
    final count = [for (var i = 1; i <= n; i++) state['on$i'] == true].where((x) => x).length;
    return WidgetCell(title: title, subtitle: '$count z $n włączone', icon: 'bulb', active: count > 0);
  }
  final on = state[point] == true;
  final level = all && on && state['level'] is num ? ' · ${state['level']}%' : '';
  return WidgetCell(title: title, subtitle: on ? 'Włączone$level' : 'Wyłączone', icon: 'bulb', active: on);
}

WidgetCell _thermostat(HomeWidgetItem item, DeviceHub hub) {
  final id = item.device!;
  final c = hub.controller(id);
  final name = c?.device.name ?? hub.device(id)?.name ?? 'Termostat';
  if (c == null) return _unavailable(name, 'Niedostępne', 'lock');
  if (hub.accessFor(id) == AccessLevel.none) return _unavailable(name, 'Brak dostępu', 'lock');
  final state = c.stateJson;
  if (state == null || !c.live) {
    return WidgetCell(title: name, subtitle: _noLink(c), icon: 'thermostat', dimmed: true, open: id);
  }
  final heating = state['heating'] == true;
  return WidgetCell(
    title: name,
    value: _degrees(state['temp']),
    subtitle: state['sensorFault'] == true
        ? 'Awaria czujnika'
        : 'Nastawa ${_degrees(state['target'])}${heating ? ' · grzeje' : ''}',
    icon: heating ? 'flame' : 'thermostat',
    active: heating,
    open: id,
  );
}

WidgetCell _scene(HomeWidgetItem item, DeviceHub hub) {
  final scene = hub.scene(item.sceneId!);
  return scene == null
      ? _unavailable('Scena', hub.loaded ? 'Niedostępna' : 'Łączenie…', 'scene')
      : WidgetCell(title: scene.name, subtitle: 'Dotknij, aby uruchomić', icon: 'scene');
}

/// Pola czujnika, gdy urządzenie (jeszcze) nie podało `describe`.
const _sensorKeys = ['temp', 'hum', 'pressure', 'co2', 'illuminance', 'moisture', 'battery'];

/// Do [max] wartości czujnika po polsku: punkty `sensor` z `describe` po kolei (bez `rssi`, bateria na końcu),
/// bez opisu - znane pola State. Np. `22,4 °C`, `58 %`, `997,8 hPa`.
List<String> sensorValues(DeviceController<Object?, Object?> c, {int max = 3}) {
  final state = c.stateJson;
  if (state == null) return const [];
  final desc = c.cachedDescription;
  final List<(String, Object?, DataPoint?)> all = desc == null
      ? [
          for (final k in _sensorKeys)
            if (state[k] is num) (k, state[k], null),
        ]
      : [
          for (final p in desc.points)
            if (p.kind == PointKind.sensor && p.key != 'rssi' && p.valueIn(state) is num) (p.key, p.valueIn(state), p),
        ];
  final ordered = [...all.where((e) => e.$1 != 'battery'), ...all.where((e) => e.$1 == 'battery')];
  return [
    for (final (key, v, p) in ordered.take(max))
      p == null ? bleValueText(key, v) : (key == 'battery' ? 'bateria ${p.format(v)}' : p.format(v)),
  ];
}

/// Czy urządzenie da się pokazać jako czujnik: typ `sensor` albo inne z temperaturą / wilgotnością w State.
bool canShowAsSensor(DeviceType type, Json? state) =>
    type == DeviceType.sensor ||
    (type != DeviceType.thermostat && type != DeviceType.hub && (state?['temp'] is num || state?['hum'] is num));

WidgetCell _sensor(HomeWidgetItem item, DeviceHub hub) {
  final id = item.device!;
  final c = hub.controller(id);
  final name = c?.device.name ?? hub.device(id)?.name ?? 'Czujnik';
  if (c == null) return _unavailable(name, 'Niedostępne', 'lock');
  if (hub.accessFor(id) == AccessLevel.none) return _unavailable(name, 'Brak dostępu', 'lock');
  final state = c.stateJson;
  if (state == null || !c.live) {
    return WidgetCell(title: name, subtitle: _noLink(c), icon: 'sensor', dimmed: true, open: id);
  }
  final values = sensorValues(c);
  final offline = state['online'] == false;
  return WidgetCell(
    title: name,
    value: values.firstOrNull,
    subtitle: offline
        ? 'Niedostępny${values.isEmpty ? '' : ' · ostatni odczyt'}'
        : values.isEmpty
        ? 'Brak odczytów'
        : values.skip(1).join(' · '),
    icon: 'sensor',
    dimmed: offline,
    open: id,
  );
}

/// Stan pozycji widżetu z danych na żywo.
WidgetCell widgetCell(HomeWidgetItem item, DeviceHub hub) => switch (item.kind) {
  HomeWidgetKind.output => _output(item, hub),
  HomeWidgetKind.thermostat => _thermostat(item, hub),
  HomeWidgetKind.scene => _scene(item, hub),
  HomeWidgetKind.sensor => _sensor(item, hub),
};
