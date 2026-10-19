import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zdjecia/bridge/bridge_server.dart';

void main() {
  late BridgeServer server;
  late HttpClient client;

  setUp(() async {
    server = BridgeServer(port: 0);
    server.photos = [
      BridgePhoto(id: 'a_1', png: Uint8List.fromList([1, 2, 3, 4]), taken: DateTime.utc(2026, 10, 19, 8)),
    ];
    await server.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.dispose();
  });

  Future<(int, List<int>, String?)> get(String path) async {
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}$path'));
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    return (res.statusCode, bytes, res.headers.contentType?.mimeType);
  }

  test('lista zdjęć', () async {
    final (status, body, type) = await get('/manifest.json');
    expect(status, 200);
    expect(type, 'application/json');
    expect(jsonDecode(utf8.decode(body)), {
      'version': 1,
      'photos': [
        {'id': 'a_1', 'size': 4, 'taken': DateTime.utc(2026, 10, 19, 8).millisecondsSinceEpoch},
      ],
    });
  });

  test('plik PNG i nieznane adresy', () async {
    final (status, body, type) = await get('/p/a_1.png');
    expect(status, 200);
    expect(type, 'image/png');
    expect(body, [1, 2, 3, 4]);
    expect((await get('/p/inne.png')).$1, 404);
    expect((await get('/')).$1, 404);
  });

  test('każde zapytanie trafia do dziennika', () async {
    final logged = server.requests.first;
    await get('/manifest.json');
    final r = await logged;
    expect(r.path, '/manifest.json');
    expect(r.status, 200);
    expect(r.bytes, greaterThan(0));
  });

  test('zatrzymanie serwera', () async {
    expect(server.running, isTrue);
    await server.stop();
    expect(server.running, isFalse);
  });
}
