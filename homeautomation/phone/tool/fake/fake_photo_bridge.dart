// Atrapa mostu aplikacji „Zdjęcia” (127.0.0.1:8765 na telefonie): `GET /manifest.json` i `GET /p/<id>.jpg?w=&h=`
// (kadr W×H jako JPEG baseline). Do testów synchronizacji zdjęć z zegarami (lib/data/photo_sync.dart).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

class FakePhotoBridge {
  /// Pula: `{id, taken (ms), caption?, memory}` - jak w manifeście.
  final photos = <Map<String, dynamic>>[];

  /// Własna treść kadru dla id (np. za duży albo progresywny JPEG).
  final override = <String, List<int>>{};

  /// Żądania: `manifest`, `jpg <id> <w>x<h>`.
  final requests = <String>[];

  HttpServer? _server;

  int get port => _server!.port;
  Uri get uri => Uri.parse('http://127.0.0.1:$port');

  void add(String id, DateTime taken, {String? caption, bool memory = false}) => photos.add({
    'id': id,
    'size': 1000,
    'taken': taken.millisecondsSinceEpoch,
    'caption': ?caption,
    'memory': memory,
  });

  Future<void> start() async {
    _server = await shelf_io.serve(_handle, InternetAddress.loopbackIPv4, 0);
  }

  Future<void> stop() async => _server?.close(force: true);

  Response _handle(Request req) {
    final path = '/${req.url.path}';
    if (path == '/manifest.json') {
      requests.add('manifest');
      return Response.ok(jsonEncode({'version': 1, 'photos': photos}), headers: {'Content-Type': 'application/json'});
    }
    final m = RegExp(r'^/p/([^/]+)\.jpg$').firstMatch(path);
    if (m == null) return Response.notFound('');
    final id = m.group(1)!;
    final w = int.tryParse(req.url.queryParameters['w'] ?? ''), h = int.tryParse(req.url.queryParameters['h'] ?? '');
    requests.add('jpg $id ${w}x$h');
    if (w == null || h == null || w < 64 || w > 800 || h < 64 || h > 800) return Response.badRequest();
    if (!photos.any((p) => p['id'] == id)) return Response.notFound('');
    return Response.ok(override[id] ?? fakeJpeg(w, h), headers: {'Content-Type': 'image/jpeg'});
  }
}

/// Najmniejszy „JPEG baseline” z nagłówkiem SOF0 W×H (bez obrazu - zegar-atrapa czyta tylko nagłówek).
/// [sof] 0xC2 = progresywny; [size] - dopełnienie komentarzem do tylu bajtów.
Uint8List fakeJpeg(int w, int h, {int sof = 0xC0, int size = 2000}) {
  final b = BytesBuilder()
    ..add([0xFF, 0xD8])
    ..add([0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0, 0])
    ..add([0xFF, sof, 0x00, 0x11, 0x08, h >> 8, h & 0xFF, w >> 8, w & 0xFF, 0x03])
    ..add([0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]);
  var left = size - b.length - 2;
  while (left > 4) {
    final n = left - 4 > 60000 ? 60000 : left - 4;
    b
      ..add([0xFF, 0xFE, (n + 2) >> 8, (n + 2) & 0xFF])
      ..add(List.filled(n, 0x20));
    left -= n + 4;
  }
  b.add([0xFF, 0xD9]);
  return b.toBytes();
}
