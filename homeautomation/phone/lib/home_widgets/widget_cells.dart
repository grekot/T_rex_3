import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/device_icons.dart';
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

WidgetCell _unavailable(String title, String subtitle, String icon, [WidgetItemLook look = const WidgetItemLook()]) =>
    WidgetCell(title: title, subtitle: subtitle, icon: icon, dimmed: true, iconKey: look.icon, color: look.color);

String _noLink(DeviceController<Object?, Object?> c) =>
    c.phase == ConnectPhase.connecting ? 'Łączenie…' : 'Brak kontaktu';

/// Ikona z katalogu aplikacji: wybrana dla pozycji, potem wybrana dla urządzenia (cały włącznik, termostat,
/// czujnik); null = ikona zapasowa Androida.
String? _iconKey(WidgetItemLook look, String? deviceId) =>
    look.icon ?? (deviceId == null ? null : DeviceIcons.instance.of(deviceId));

WidgetCell _output(HomeWidgetItem item, DeviceHub hub) {
  final id = item.device!, point = item.point!;
  final look = item.look;
  final c = hub.controller(id);
  final name = c?.device.name ?? hub.device(id)?.name ?? 'Urządzenie';
  if (c == null) return _unavailable(look.label ?? name, 'Niedostępne', 'lock', look);
  if (hub.accessFor(id) == AccessLevel.none) return _unavailable(look.label ?? name, 'Brak dostępu', 'lock', look);
  final state = c.stateJson;
  final n = channelCount(state);
  final all = point == 'on';
  final title = look.label ?? (all ? name : channelName(c, null, point));
  final iconKey = _iconKey(look, all ? id : null);
  final open = look.tap == 'open' ? id : null;
  if (state == null || !c.live) return _unavailable(title, _noLink(c), 'bulb', look);
  if (all && n > 1) {
    final count = [for (var i = 1; i <= n; i++) state['on$i'] == true].where((x) => x).length;
    return WidgetCell(
      title: title,
      subtitle: '$count z $n włączone',
      icon: 'bulb',
      active: count > 0,
      iconKey: iconKey,
      color: look.color,
      open: open,
    );
  }
  final on = state[point] == true;
  final level = all && on && state['level'] is num ? ' · ${state['level']}%' : '';
  return WidgetCell(
    title: title,
    subtitle: on ? 'Włączone$level' : 'Wyłączone',
    icon: 'bulb',
    active: on,
    iconKey: iconKey,
    color: look.color,
    open: open,
  );
}

WidgetCell _thermostat(HomeWidgetItem item, DeviceHub hub) {
  final id = item.device!;
  final look = item.look;
  final c = hub.controller(id);
  final name = look.label ?? c?.device.name ?? hub.device(id)?.name ?? 'Termostat';
  if (c == null) return _unavailable(name, 'Niedostępne', 'lock', look);
  if (hub.accessFor(id) == AccessLevel.none) return _unavailable(name, 'Brak dostępu', 'lock', look);
  final state = c.stateJson;
  final iconKey = _iconKey(look, id);
  if (state == null || !c.live) {
    return WidgetCell(
      title: name,
      subtitle: _noLink(c),
      icon: 'thermostat',
      dimmed: true,
      open: id,
      iconKey: iconKey,
      color: look.color,
    );
  }
  final heating = state['heating'] == true;
  // Pod temperaturą: nastawa (domyślnie), wilgotność albo nic (`more`: [] ).
  final below = look.more == null ? 'target' : look.more!.firstOrNull;
  final hum = state['hum'];
  final what = switch (below) {
    'hum' => hum is num ? 'Wilgotność ${hum.round()} %' : null,
    'target' => 'Nastawa ${_degrees(state['target'])}',
    _ => null,
  };
  return WidgetCell(
    title: name,
    value: _degrees(state['temp']),
    subtitle: state['sensorFault'] == true
        ? 'Awaria czujnika'
        : [?what, if (heating) what == null ? 'Grzeje' : 'grzeje'].join(' · '),
    icon: heating ? 'flame' : 'thermostat',
    active: heating,
    open: id,
    iconKey: iconKey,
    color: look.color,
  );
}

WidgetCell _scene(HomeWidgetItem item, DeviceHub hub) {
  final look = item.look;
  final scene = hub.scene(item.sceneId!);
  return scene == null
      ? _unavailable(look.label ?? 'Scena', hub.loaded ? 'Niedostępna' : 'Łączenie…', 'scene', look)
      : WidgetCell(
          title: look.label ?? scene.name,
          subtitle: 'Dotknij, aby uruchomić',
          icon: 'scene',
          iconKey: look.icon,
          color: look.color,
        );
}

/// Pola czujnika, gdy urządzenie (jeszcze) nie podało `describe`.
const _sensorKeys = ['temp', 'hum', 'pressure', 'co2', 'illuminance', 'moisture', 'battery'];

const _sensorNames = {
  'temp': 'Temperatura',
  'hum': 'Wilgotność',
  'pressure': 'Ciśnienie',
  'co2': 'CO₂',
  'illuminance': 'Natężenie światła',
  'moisture': 'Wilgotność gleby',
  'battery': 'Bateria',
};

/// Kolejność domyślna: temperatura, wilgotność, ciśnienie, reszta (jak w `describe`), bateria na końcu.
int _rank(String key) => switch (key) {
  'temp' => 0,
  'hum' => 1,
  'pressure' => 2,
  'battery' => 9,
  _ => 3,
};

/// Odczyt czujnika: klucz punktu, nazwa i tekst po polsku (`22,4 °C`).
typedef SensorReading = ({String key, String name, String text});

/// Wszystkie odczyty liczbowe czujnika w kolejności domyślnej: punkty `sensor` z `describe` (bez `rssi`),
/// bez opisu - znane pola State.
List<SensorReading> sensorReadings(DeviceController<Object?, Object?> c) {
  final state = c.stateJson;
  if (state == null) return const [];
  final desc = c.cachedDescription;
  final List<SensorReading> all = desc == null
      ? [
          for (final k in _sensorKeys)
            if (state[k] is num) (key: k, name: _sensorNames[k] ?? k, text: bleValueText(k, state[k])),
        ]
      : [
          for (final p in desc.points)
            if (p.kind == PointKind.sensor && p.key != 'rssi' && p.valueIn(state) is num)
              (
                key: p.key,
                name: p.name,
                text: p.key == 'battery' ? 'bateria ${p.format(p.valueIn(state))}' : p.format(p.valueIn(state)),
              ),
        ];
  // Stabilnie: w obrębie tej samej rangi kolejność z opisu.
  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final r = _rank(a.$2.key).compareTo(_rank(b.$2.key));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
  return [for (final (_, r) in indexed) r];
}

/// Wartości czujnika do kratki: główna ([WidgetItemLook.main] albo pierwsza wg kolejności domyślnej - temperatura),
/// potem [WidgetItemLook.more] (do 2; pusta lista = nic) albo kolejne, razem najwyżej [max].
List<String> sensorValues(
  DeviceController<Object?, Object?> c, {
  WidgetItemLook look = const WidgetItemLook(),
  int max = 3,
}) {
  final all = sensorReadings(c);
  final main = all.where((r) => r.key == look.main).firstOrNull ?? all.firstOrNull;
  if (main == null) return const [];
  final rest = look.more == null
      ? all.where((r) => r.key != main.key).take(max - 1)
      : [for (final k in look.more!.take(2)) ...all.where((r) => r.key == k && r.key != main.key)];
  return [main.text, for (final r in rest) r.text];
}

/// Czy urządzenie da się pokazać jako czujnik: typ `sensor` albo inne z temperaturą / wilgotnością w State.
bool canShowAsSensor(DeviceType type, Json? state) =>
    type == DeviceType.sensor ||
    (type != DeviceType.thermostat && type != DeviceType.hub && (state?['temp'] is num || state?['hum'] is num));

WidgetCell _sensor(HomeWidgetItem item, DeviceHub hub) {
  final id = item.device!;
  final look = item.look;
  final c = hub.controller(id);
  final name = look.label ?? c?.device.name ?? hub.device(id)?.name ?? 'Czujnik';
  if (c == null) return _unavailable(name, 'Niedostępne', 'lock', look);
  if (hub.accessFor(id) == AccessLevel.none) return _unavailable(name, 'Brak dostępu', 'lock', look);
  final state = c.stateJson;
  final iconKey = _iconKey(look, id);
  if (state == null || !c.live) {
    return WidgetCell(
      title: name,
      subtitle: _noLink(c),
      icon: 'sensor',
      dimmed: true,
      open: id,
      iconKey: iconKey,
      color: look.color,
    );
  }
  final values = sensorValues(c, look: look);
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
    iconKey: iconKey,
    color: look.color,
  );
}

/// Stan pozycji widżetu z danych na żywo.
WidgetCell widgetCell(HomeWidgetItem item, DeviceHub hub) => switch (item.kind) {
  HomeWidgetKind.output => _output(item, hub),
  HomeWidgetKind.thermostat => _thermostat(item, hub),
  HomeWidgetKind.scene => _scene(item, hub),
  HomeWidgetKind.sensor => _sensor(item, hub),
};
