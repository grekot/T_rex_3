// Most lokalny: serwer HTTP tylko pod 127.0.0.1 (niewidoczny w Wi-Fi). Side Service aplikacji Zepp
// na tym samym telefonie pobiera z niego listę zdjęć (/manifest.json) i pliki PNG (/p/<id>.png).
// Zdjęcia bierze przy każdym zapytaniu ze źródła - w usłudze w tle jest nim opublikowana pula w plikach,
// więc nowa pula po odświeżeniu jest od razu widoczna dla zegarka.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int bridgePort = 8765;

class BridgePhoto {
  BridgePhoto({required this.id, required Uint8List png, required this.taken, this.caption = ''})
      : size = png.length,
        read = (() async => png);

  /// Zdjęcie czytane z pliku dopiero, gdy zegarek o nie poprosi
  BridgePhoto.file({required this.id, required File file, required this.size, required this.taken, this.caption = ''})
      : read = file.readAsBytes;

  final String id;
  final int size;
  final DateTime taken;

  /// Podpis od AI (zegarek pokazuje go pod zdjęciem)
  final String caption;
  final Future<List<int>> Function() read;
}

typedef PhotoSource = Future<List<BridgePhoto>> Function();

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

  Map<String, Object> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'method': method,
        'path': path,
        'status': status,
        'bytes': bytes,
        'took': took.inMilliseconds,
      };

  factory BridgeRequest.fromJson(Map<dynamic, dynamic> j) => BridgeRequest(
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        method: j['method'] as String,
        path: j['path'] as String,
        status: j['status'] as int,
        bytes: j['bytes'] as int,
        took: Duration(milliseconds: j['took'] as int),
      );
}

Map<String, Object> manifestOf(List<BridgePhoto> photos) => {
      'version': 1,
      'photos': [
        for (final p in photos)
          {
            'id': p.id,
            'size': p.size,
            'taken': p.taken.millisecondsSinceEpoch,
            if (p.caption.isNotEmpty) 'caption': p.caption,
          },
      ],
    };

class BridgeServer {
  BridgeServer({required this.source, this.port = bridgePort});

  final PhotoSource source;
  final int port;
  HttpServer? _server;
  final _requests = StreamController<BridgeRequest>.broadcast();

  Stream<BridgeRequest> get requests => _requests.stream;
  bool get running => _server != null;

  /// Port, na którym naprawdę słucha (w testach `port: 0` = dowolny wolny).
  int? get boundPort => _server?.port;

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

    try {
      if (req.method != 'GET') {
        status = HttpStatus.methodNotAllowed;
      } else if (path == '/manifest.json') {
        body = utf8.encode(jsonEncode(manifestOf(await source())));
        type = ContentType.json;
      } else if (path.startsWith('/p/') && path.endsWith('.png')) {
        final id = path.substring(3, path.length - 4);
        final photo = (await source()).where((p) => p.id == id).firstOrNull;
        if (photo == null) {
          status = HttpStatus.notFound;
        } else {
          body = await photo.read();
          type = ContentType('image', 'png');
        }
      } else {
        status = HttpStatus.notFound;
      }
    } catch (_) {
      status = HttpStatus.internalServerError;
      body = const [];
      type = null;
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
