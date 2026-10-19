// Most lokalny: serwer HTTP tylko pod 127.0.0.1 (niewidoczny w Wi-Fi). Side Service aplikacji Zepp
// na tym samym telefonie pobiera z niego listę zdjęć (/manifest.json) i pliki PNG (/p/<id>.png).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int bridgePort = 8765;

class BridgePhoto {
  const BridgePhoto({required this.id, required this.png, required this.taken});

  final String id;
  final Uint8List png;
  final DateTime taken;
}

class BridgeRequest {
  const BridgeRequest({
    required this.at,
    required this.method,
    required this.path,
    required this.status,
    required this.bytes,
    required this.took,
  });

  final DateTime at;
  final String method;
  final String path;
  final int status;
  final int bytes;
  final Duration took;
}

class BridgeServer {
  BridgeServer({this.port = bridgePort});

  final int port;
  HttpServer? _server;
  List<BridgePhoto> _photos = const [];
  final _requests = StreamController<BridgeRequest>.broadcast();

  Stream<BridgeRequest> get requests => _requests.stream;
  bool get running => _server != null;

  /// Port, na którym naprawdę słucha (w testach `port: 0` = dowolny wolny).
  int? get boundPort => _server?.port;

  set photos(List<BridgePhoto> photos) => _photos = List.unmodifiable(photos);

  Map<String, Object> manifest() => {
        'version': 1,
        'photos': [
          for (final p in _photos)
            {'id': p.id, 'size': p.png.length, 'taken': p.taken.millisecondsSinceEpoch},
        ],
      };

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> dispose() async {
    await stop();
    await _requests.close();
  }

  Future<void> _handle(HttpRequest req) async {
    final watch = Stopwatch()..start();
    final path = req.uri.path;
    final res = req.response;
    var status = HttpStatus.ok;
    List<int> body = const [];
    ContentType? type;

    if (req.method != 'GET') {
      status = HttpStatus.methodNotAllowed;
    } else if (path == '/manifest.json') {
      body = utf8.encode(jsonEncode(manifest()));
      type = ContentType.json;
    } else if (path.startsWith('/p/') && path.endsWith('.png')) {
      final id = path.substring(3, path.length - 4);
      final photo = _photos.where((p) => p.id == id).firstOrNull;
      if (photo == null) {
        status = HttpStatus.notFound;
      } else {
        body = photo.png;
        type = ContentType('image', 'png');
      }
    } else {
      status = HttpStatus.notFound;
    }

    try {
      res.statusCode = status;
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (type != null) res.headers.contentType = type;
      res.contentLength = body.length;
      if (body.isNotEmpty) res.add(body);
      await res.close();
    } catch (_) {
      // Klient (Zepp) mógł zerwać połączenie - zapisujemy próbę i tak
    }
    if (!_requests.isClosed) {
      _requests.add(BridgeRequest(
        at: DateTime.now(),
        method: req.method,
        path: path,
        status: status,
        bytes: body.length,
        took: watch.elapsed,
      ));
    }
  }
}
