import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/thermostat_controller.dart';
import 'package:homeautomation/data/errors.dart';
import 'package:homeautomation/data/local_api.dart';
import 'package:homeautomation/data/local_endpoint.dart';
import 'package:homeautomation/ui/firmware_screen.dart';
import 'package:homeautomation/models/device_info.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/models/thermostat_config.dart';
import 'package:homeautomation/models/thermostat_state.dart';

// Przykłady z docs/API.md (pkt 5 i 6) bez komentarzy.
const stateJson = '''
{
  "id": "termostat-ab12cd",
  "ts": 1793000000,
  "temp": 21.4,
  "hum": 45.0,
  "press": 1013.0,
  "lux": 120.0,
  "target": 21.0,
  "heating": true,
  "sensorFault": false,
  "power": true,
  "mode": "auto",
  "override": false,
  "comfortNow": true,
  "nextChange": "22:30",
  "timeKnown": true,
  "night": false,
  "protect": null,
  "outdoor": { "temp": 4.2, "icon": 69, "age": 600 },
  "wifiRssi": -58,
  "cloud": true,
  "uptime": 86400
}
''';

const configJson = '''
{
  "name": "Salon",
  "comfort": 21.0, "eco": 18.0,
  "hystLow": 0.5, "hystHigh": 0.2,
  "schedule": {
    "weekday": "06:00-08:00,15:00-22:00",
    "saturday": "07:00-23:00",
    "sunday": "07:00-22:00"
  },
  "screen": { "mode": "always", "night": "23:00-06:00", "timeoutMin": 2 },
  "light": { "darkLux": 5 },
  "frost": { "temp": 7.0, "faultDutyMin": 0 },
  "weather": { "lat": "49.894", "lon": "20.609", "apiKeySet": true }
}
''';

Map<String, dynamic> _j(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  group('State', () {
    test('parsuje przykład z kontraktu', () {
      final s = ThermostatState.fromJson(_j(stateJson));
      expect(s.id, 'termostat-ab12cd');
      expect(s.ts, 1793000000);
      expect(s.temp, 21.4);
      expect(s.hum, 45.0);
      expect(s.press, 1013.0);
      expect(s.lux, 120.0);
      expect(s.target, 21.0);
      expect(s.heating, isTrue);
      expect(s.sensorFault, isFalse);
      expect(s.power, isTrue);
      expect(s.mode, ThermostatMode.auto);
      expect(s.override, isFalse);
      expect(s.comfortNow, isTrue);
      expect(s.nextChange, '22:30');
      expect(s.timeKnown, isTrue);
      expect(s.night, isFalse);
      expect(s.outdoor!.temp, 4.2);
      expect(s.outdoor!.icon, 69);
      expect(s.outdoor!.age, 600);
      expect(s.wifiRssi, -58);
      expect(s.cloud, isTrue);
      expect(s.uptime, 86400);
    });

    test('przyjmuje null tam, gdzie kontrakt pozwala', () {
      final j = _j(stateJson)
        ..['temp'] = null
        ..['press'] = null
        ..['lux'] = null
        ..['nextChange'] = null
        ..['outdoor'] = null
        ..['sensorFault'] = true
        ..['mode'] = 'manual';
      final s = ThermostatState.fromJson(j);
      expect(s.temp, isNull);
      expect(s.press, isNull);
      expect(s.lux, isNull);
      expect(s.nextChange, isNull);
      expect(s.outdoor, isNull);
      expect(s.sensorFault, isTrue);
      expect(s.mode, ThermostatMode.manual);
    });

    test('liczby całkowite w miejscu ułamków (np. "target": 21)', () {
      final s = ThermostatState.fromJson(
        _j(stateJson)
          ..['target'] = 21
          ..['temp'] = 20,
      );
      expect(s.target, 21.0);
      expect(s.temp, 20.0);
    });

    test('zły typ pola to FormatException', () {
      expect(() => ThermostatState.fromJson(_j(stateJson)..['temp'] = 'ciepło'), throwsFormatException);
    });

    test('toJson ↔ fromJson', () {
      final s = ThermostatState.fromJson(_j(stateJson));
      expect(ThermostatState.fromJson(s.toJson()).toJson(), s.toJson());
      expect(s.toJson(), _j(stateJson));
    });
  });

  group('Config', () {
    test('parsuje przykład z kontraktu', () {
      final c = ThermostatConfig.fromJson(_j(configJson));
      expect(c.name, 'Salon');
      expect(c.comfort, 21.0);
      expect(c.eco, 18.0);
      expect(c.hystLow, 0.5);
      expect(c.hystHigh, 0.2);
      expect(c.schedule.weekday, '06:00-08:00,15:00-22:00');
      expect(c.schedule.saturday, '07:00-23:00');
      expect(c.schedule.sunday, '07:00-22:00');
      expect(c.screen.mode, ScreenMode.always);
      expect(c.screen.night, '23:00-06:00');
      expect(c.screen.timeoutMin, 2);
      expect(c.light.darkLux, 5);
      expect(c.weather.lat, '49.894');
      expect(c.weather.lon, '20.609');
      expect(c.weather.apiKeySet, isTrue);
    });

    test('toJson odtwarza przykład', () {
      expect(ThermostatConfig.fromJson(_j(configJson)).toJson(), _j(configJson));
    });

    test('tryb ekranu motion', () {
      final j = _j(configJson);
      (j['screen'] as Map)['mode'] = 'motion';
      expect(ThermostatConfig.fromJson(j).screen.mode, ScreenMode.motion);
    });
  });

  group('Set', () {
    test('wysyła tylko ustawione pola', () {
      expect(const SetValues(target: 21.5).toJson(), {'target': 21.5});
      expect(const SetValues().isEmpty, isTrue);
      expect(
        const SetValues(
          power: true,
          mode: ThermostatMode.auto,
          schedule: SchedulePatch(weekday: '06:00-08:00'),
          screen: ScreenPatch(mode: ScreenMode.motion, night: '-', timeoutMin: 5),
          darkLux: 8,
          weather: WeatherPatch(lat: '50.06', lon: '19.94'),
        ).toJson(),
        {
          'power': true,
          'mode': 'auto',
          'schedule': {'weekday': '06:00-08:00'},
          'screen': {'mode': 'motion', 'night': '-', 'timeoutMin': 5},
          'light': {'darkLux': 8},
          'weather': {'lat': '50.06', 'lon': '19.94'},
        },
      );
    });

    test('puste pod-obiekty są pomijane', () {
      expect(
        const SetValues(schedule: SchedulePatch(), screen: ScreenPatch(), weather: WeatherPatch()).toJson(),
        isEmpty,
      );
    });

    test('fromJson ↔ toJson dla przykładu z kontraktu (pkt 7)', () {
      final j = {
        'power': true,
        'target': 21.5,
        'mode': 'auto',
        'name': 'Salon',
        'comfort': 21.0,
        'eco': 18.0,
        'hystLow': 0.5,
        'hystHigh': 0.2,
        'schedule': {'weekday': '06:00-08:00'},
        'screen': {'mode': 'motion', 'night': '-', 'timeoutMin': 5},
        'light': {'darkLux': 8},
        'weather': {'apiKey': '...', 'lat': '50.06', 'lon': '19.94'},
      };
      expect(SetValues.fromJson(j).toJson(), j);
    });

    test('wynik z błędami pól', () {
      final r = SetResult.fromJson(_j('{"ok":false,"errors":{"schedule.weekday":"format"}}'));
      expect(r.ok, isFalse);
      expect(r.errors, {'schedule.weekday': 'format'});
      expect(r.state, isNull);
    });

    test('wynik ze stanem i konfiguracją', () {
      final r = SetResult.fromJson({'ok': true, 'state': _j(stateJson), 'config': _j(configJson)});
      expect(r.ok, isTrue);
      expect(r.errors, isEmpty);
      expect(r.state!.target, 21.0);
      expect(r.config!.name, 'Salon');
    });

    test('ack z WebSocketu', () {
      final r = SetResult.fromJson(_j('{"type":"ack","id":7,"ok":false,"errors":{"target":"range"}}'));
      expect(r.ok, isFalse);
      expect(r.errors, {'target': 'range'});
      expect(r.error, isNull);
    });

    test('ack przy zajętym termostacie', () {
      final r = SetResult.fromJson(_j('{"type":"ack","id":7,"ok":false,"error":"busy"}'));
      expect(r.ok, isFalse);
      expect(r.errors, isEmpty);
      expect(r.error, 'busy');
    });

    test('opisy kodów błędów z kontraktu', () {
      expect(
        describeErrors({'name': 'length', 'mode': 'value', '_': 'json'}),
        'Nazwa: zła długość\nTryb: niedozwolona wartość\nurządzenie nie zrozumiało danych',
      );
      expect(describeApiError('busy'), contains('zajęte'));
    });
  });

  test('Set.firmwareUrl', () {
    expect(const SetValues(firmwareUrl: 'https://x/firmware.bin').toJson(), {'firmwareUrl': 'https://x/firmware.bin'});
    expect(SetValues.fromJson({'firmwareUrl': 'https://x'}).firmwareUrl, 'https://x');
  });

  test('kontrola pliku firmware przed wysłaniem', () {
    final ok = Uint8List(4096)..[0] = 0xE9;
    expect(validateFirmwareImage('firmware.bin', ok), isNull);
    expect(validateFirmwareImage('firmware.elf', ok), contains('.bin'));
    expect(validateFirmwareImage('firmware.bin', Uint8List(4096)), contains('0xE9'));
    expect(validateFirmwareImage('firmware.bin', Uint8List(10)..[0] = 0xE9), contains('mały'));
  });

  test('błędy OTA po polsku', () {
    expect(describeOtaError('busy'), contains('inna aktualizacja'));
    expect(describeOtaError('Wrong Magic Byte'), contains('nagłówek'));
    expect(describeOtaError('Not Enough Space'), contains('za duży'));
    expect(OtaStatus.fromJson({'state': 'running', 'progress': 140}).progress, 100);
  });

  test('/api/info', () {
    final i = DeviceInfo.fromJson(_j('{"id":"termostat-ab12cd","name":"Salon","fw":"2.0.0","api":1,"paired":true}'));
    expect(i.id, 'termostat-ab12cd');
    expect(i.apiSupported, isTrue);
    expect(i.paired, isTrue);
  });

  group('adresy lokalne', () {
    test('prywatne i .local są lokalne', () {
      for (final h in [
        '192.168.1.20',
        '10.0.2.2',
        '172.16.0.1',
        '172.31.255.255',
        '169.254.1.1',
        '127.0.0.1',
        'localhost',
        'termostat-ab12cd.local',
        'fd00::1',
        'fe80::1',
      ]) {
        expect(isLocalNetworkHost(h), isTrue, reason: h);
      }
    });

    test('publiczne nie są lokalne', () {
      for (final h in ['8.8.8.8', '172.32.0.1', '192.169.0.1', 'example.com', '2001:db8::1', '300.1.1.1']) {
        expect(isLocalNetworkHost(h), isFalse, reason: h);
      }
    });

    test('parsowanie wpisanego adresu', () {
      expect(LocalEndpoint.tryParse('192.168.1.20'), const LocalEndpoint('192.168.1.20'));
      expect(LocalEndpoint.tryParse(' http://192.168.1.20:8080/ '), const LocalEndpoint('192.168.1.20', 8080));
      expect(LocalEndpoint.tryParse('termostat-ab12cd.local').toString(), 'termostat-ab12cd.local');
      expect(LocalEndpoint.tryParse(''), isNull);
      expect(const LocalEndpoint('fe80::1', 8080).display, '[fe80::1]:8080');
    });
  });
}
