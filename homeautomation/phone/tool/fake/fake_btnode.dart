part of 'fake_thermostat_server.dart';

/// Bramka Bluetooth (type `btnode`, `nodes/btnode`): stan obu układów; czujniki i zegarki zna tylko hub.
class FakeBtNode extends FakeDevice {
  FakeBtNode({
    super.id = 'bt-a1b2c3',
    String name = 'Bramka Bluetooth',
    super.fw = '0.4.0-fake',
    super.token,
    super.statePeriod,
    super.clock,
    super.log,
    super.random,
  }) : _name = name;

  String _name;
  bool bleOk = true;
  int bleConns = 0;
  bool scanAll = false;
  int advPerMin = 240;
  int bleFw = 6;
  int linkCrcErrors = 0;

  @override
  String get typeWire => 'btnode';

  @override
  String get deviceName => _name;

  @override
  Map<String, Object?> get extraInfo => {'bleFw': bleFw};

  @override
  Map<String, dynamic> stateJson() => {
    'id': id,
    'bleOk': bleOk,
    'bleConns': bleConns,
    'scanAll': scanAll,
    'advPerMin': advPerMin,
    'bleFw': bleFw,
    'bleUptime': 3600,
    'linkCrcErrors': linkCrcErrors,
  };

  @override
  Map<String, dynamic> configJson() => {'name': _name, 'scanAll': scanAll};

  @override
  Map<String, String> applySet(Map<String, dynamic> v) {
    final errors = <String, String>{};
    if (v['name'] case final String n) _name = n;
    if (v.containsKey('scanAll')) {
      if (v['scanAll'] is bool) {
        scanAll = v['scanAll'] as bool;
      } else {
        errors['scanAll'] = 'type';
      }
    }
    _broadcastState();
    return errors;
  }

  /// Jak `describeJson()` w `nodes/btnode/src/wifi/main.cpp`.
  @override
  Map<String, dynamic> describeJson() => {
    'type': 'btnode',
    'points': [
      {'key': 'bleOk', 'name': 'Układ Bluetooth', 'kind': 'status'},
      {'key': 'bleConns', 'name': 'Połączenia Bluetooth', 'kind': 'sensor'},
      {'key': 'advPerMin', 'name': 'Rozgłoszenia na minutę', 'kind': 'sensor'},
      {'key': 'scanAll', 'name': 'Szukaj nowych czujników', 'kind': 'switch', 'access': 'control'},
    ],
  };

  /// Klawisz `c`: zegarek łączy się / rozłącza; `u`: układ Bluetooth przestaje odpowiadać.
  void toggleConn() {
    bleConns = bleConns == 0 ? 1 : 0;
    _broadcastState();
  }

  void toggleBle() {
    bleOk = !bleOk;
    _broadcastState();
  }
}
