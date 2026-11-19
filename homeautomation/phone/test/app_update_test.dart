// Aktualizacja aplikacji na komputer: najnowsze wydanie `homeautomation-v*` z plikiem dla Windows z GitHub Release.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/data/app_update.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _rel(String tag, {bool zip = true, bool draft = false, bool pre = false}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': pre,
  'html_url': 'https://github.com/grekot/T_rex_3/releases/tag/$tag',
  'assets': [
    {'name': 'homeautomation.apk', 'browser_download_url': 'https://x/$tag/homeautomation.apk'},
    if (zip)
      {'name': 'homeautomation-windows.zip', 'browser_download_url': 'https://x/$tag/homeautomation-windows.zip'},
  ],
};

final _list = [
  _rel('zakupy-v9.9.9'),
  _rel('homeautomation-v1.40.0', zip: false),
  _rel('homeautomation-v1.39.0', draft: true),
  _rel('homeautomation-v1.38.0', pre: true),
  _rel('homeautomation-v1.35.2'),
  _rel('homeautomation-v1.35.10'),
  _rel('homeautomation-v1.34.1'),
];

void main() {
  test('porównanie wersji', () {
    expect(compareVersions('1.35.10', '1.35.2'), 1);
    expect(compareVersions('1.35', '1.35.0'), 0);
    expect(compareVersions('1.9.0', '1.10.0'), -1);
  });

  test('najnowsze wydanie z zipem: bez innych aplikacji, szkiców, wersji próbnych i wydań bez pliku Windows', () {
    final r = latestWindowsRelease(_list)!;
    expect(r.version, '1.35.10');
    expect(r.download.toString(), 'https://x/homeautomation-v1.35.10/homeautomation-windows.zip');
    expect(latestWindowsRelease({'message': 'rate limit'}), isNull);
  });

  test('sprawdzenie: nowsza wersja albo null; błąd sieci i kompilacja lokalna - bez banera', () async {
    final ok = MockClient((r) async => http.Response(jsonEncode(_list), 200));
    expect((await checkAppUpdate(current: '1.35.2', client: ok))?.version, '1.35.10');
    expect(await checkAppUpdate(current: '1.35.10', client: ok), isNull);
    expect(await checkAppUpdate(current: '', client: ok), isNull);
    final down = MockClient((r) async => http.Response('', 503));
    expect(await checkAppUpdate(current: '1.0.0', client: down), isNull);
    final broken = MockClient((r) async => throw http.ClientException('brak sieci'));
    expect(await checkAppUpdate(current: '1.0.0', client: broken), isNull);
  });
}
