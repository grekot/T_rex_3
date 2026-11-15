// Most lokalny: serwer HTTP tylko pod 127.0.0.1 (niewidoczny w Wi-Fi). Side Service aplikacji Zepp
// na tym samym telefonie pobiera z niego listę zdjęć (/manifest.json) i pliki PNG (/p/<id>.png),
// a aplikacja HomeAutomation - JPEG-i w rozmiarze ekranu zegara ESP32 (/p/<id>.jpg?w=320&h=240).
// Zdjęcia bierze przy każdym zapytaniu ze źródła - w usłudze w tle jest nim opublikowana pula w plikach,
// więc nowa pula po odświeżeniu jest od razu widoczna dla zegarka.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'photo_prep.dart';

const int bridgePort = 8765;

/// JPEG kadru o podanym rozmiarze; null = nie da się go zrobić (np. zdjęcia nie ma już w galerii)
typedef JpegReader = Future<List<int>?> Function(int width, int height);

class BridgePhoto {
  BridgePhoto({
    required this.id,
    required Uint8List png,
    required this.taken,
    this.caption = '',
    this.memory = false,
    this.jpeg,
  })  : size = png.length,
        read = (() async => png);

  /// Zdjęcie czytane z pliku dopiero, gdy zegarek o nie poprosi
  BridgePhoto.file({
    required this.id,
    required File file,
    required this.size,
    required this.taken,
    this.caption = '',
    this.memory = false,
    this.jpeg,
  }) : read = file.readAsBytes;

  final String id;
  final int size;
  final DateTime taken;

  /// Podpis od AI (zegarek pokazuje go pod zdjęciem)
  final String caption;

  /// Wspomnienie z historii galerii (zegary HomeAutomation opisują je inaczej niż świeże zdjęcia)
  final bool memory;
  final Future<List<int>> Function() read;

  /// Kadr prostokątny w JPEG (null = most go nie robi)
  final JpegReader? jpeg;
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
            'memory': p.memory,
          },
      ],
    };

/// Bok kadru JPEG z zapytania ([minJpegSide]..[maxJpegSide]); null = brak albo poza zakresem
int? jpegSide(String? value) {
  final v = int.tryParse(value ?? '');
  return v != null && v >= minJpegSide && v <= maxJpegSide ? v : null;
}

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
      } else if (path.startsWith('/p/') && path.endsWith('.jpg')) {
        final id = path.substring(3, path.length - 4);
        final w = jpegSide(req.uri.queryParameters['w']), h = jpegSide(req.uri.queryParameters['h']);
        final photo = (await source()).where((p) => p.id == id).firstOrNull;
        if (w == null || h == null) {
          status = HttpStatus.badRequest;
        } else if (photo == null || photo.jpeg == null) {
          status = HttpStatus.notFound;
        } else {
          final jpg = await photo.jpeg!(w, h);
          if (jpg == null) {
            status = HttpStatus.notFound;
          } else {
            body = jpg;
            type = ContentType('image', 'jpeg');
          }
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
