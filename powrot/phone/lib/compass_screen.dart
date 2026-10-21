import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'geo.dart';
import 'models.dart';

/// Nawigacja na azymut do zapisanego miejsca - do marszu w terenie bez dróg.
/// Strzałka zawsze wskazuje cel z bieżącej pozycji, więc można omijać przeszkody.
/// Kierunek telefonu: flutter_compass (sam uwzględnia obrót ekranu) + deklinacja z geo.dart.
class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key, required this.place});

  final Place place;

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

enum _GpsState { searching, ok, serviceOff, denied, deniedForever, error }

class _CompassScreenState extends State<CompassScreen> {
  // ok. 30 odczytów kompasu na sekundę -> wygładzenie do ok. 0,2 s
  static const _smoothing = 0.15;

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _compassTimeout;

  Position? _pos;
  _GpsState _gps = _GpsState.searching;
  double? _heading; // wygładzony kierunek góry telefonu (geograficzny, gdy znamy deklinację)
  double? _accuracy;
  bool _compassMissing = false;
  bool _gotCompass = false;
  final _arrival = ArrivalTracker();

  Place get place => widget.place;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable().catchError((_) {});
    // Pionowo: strzałka i napisy się nie przestawiają, gdy telefon leży płasko w dłoni
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _startCompass();
    _startGps();
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _gpsSub?.cancel();
    _compassTimeout?.cancel();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _startCompass() {
    final events = FlutterCompass.events;
    if (events == null) {
      _compassMissing = true;
      return;
    }
    _compassSub = events.listen((e) {
      final raw = e.heading;
      if (raw == null || !mounted) return; // null = brak czujnika
      _gotCompass = true;
      final decl = _declination;
      final h = decl == null ? normalize(raw) : trueHeading(raw, decl);
      setState(() {
        _compassMissing = false;
        _accuracy = e.accuracy;
        _heading = smoothAngle(_heading, h, _smoothing);
      });
    }, onError: (_) {
      if (mounted) setState(() => _compassMissing = true);
    });
    // Telefon bez magnetometru po prostu nic nie przysyła
    _compassTimeout = Timer(const Duration(seconds: 3), () {
      if (!_gotCompass && mounted) setState(() => _compassMissing = true);
    });
  }

  Future<void> _startGps() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    setState(() => _gps = _GpsState.searching);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _gps = _GpsState.serviceOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _gps = _GpsState.deniedForever);
        return;
      }
      if (perm == LocationPermission.denied) {
        if (mounted) setState(() => _gps = _GpsState.denied);
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _pos == null) _onPosition(last, fresh: false);
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0),
      ).listen(_onPosition, onError: (Object e) {
        if (!mounted) return;
        setState(() => _gps = e is LocationServiceDisabledException ? _GpsState.serviceOff : _GpsState.error);
      });
    } catch (_) {
      if (mounted) setState(() => _gps = _GpsState.error);
    }
  }

  void _onPosition(Position p, {bool fresh = true}) {
    if (!mounted) return;
    setState(() {
      _pos = p;
      if (fresh) _gps = _GpsState.ok;
    });
    // Ostatnia znana pozycja może być sprzed godziny - alarm tylko na świeżym odczycie
    if (fresh && _arrival.update(_distance!)) _buzz();
  }

  Future<void> _buzz() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: [0, 400, 150, 400]);
        return;
      }
    } catch (_) {}
    HapticFeedback.heavyImpact();
  }

  double? get _declination {
    final p = _pos;
    return declination(p?.latitude ?? place.lat, p?.longitude ?? place.lon, DateTime.now());
  }

  double? get _distance {
    final p = _pos;
    return p == null ? null : distanceMeters(p.latitude, p.longitude, place.lat, place.lon);
  }

  double? get _bearing {
    final p = _pos;
    return p == null ? null : bearing(p.latitude, p.longitude, place.lat, place.lon);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = _distance;
    final brg = _bearing;
    final heading = _heading;
    final here = _arrival.here;
    final hasFix = _pos != null;
    final stale = hasFix && _gps != _GpsState.ok;

    return Scaffold(
      appBar: AppBar(title: Text(place.name, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!hasFix || stale) _GpsBanner(state: _gps, stale: stale, onRetry: _startGps),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1,
              child: _Dial(
                heading: heading,
                bearing: brg,
                here: here,
                active: hasFix && heading != null && !_compassMissing,
                color: theme.colorScheme.primary,
                ringColor: theme.colorScheme.outlineVariant,
                northColor: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              here ? 'Na miejscu!' : (dist == null ? '–' : formatDistance(dist)),
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              brg == null ? 'Azymut: czekam na GPS' : 'Azymut ${formatBearing(brg)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              _details(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            ..._compassHints(theme),
          ],
        ),
      ),
    );
  }

  String _details() {
    final parts = <String>[];
    final p = _pos;
    if (p != null && p.accuracy > 0) parts.add('GPS ±${p.accuracy.round()} m');
    final heading = _heading;
    if (heading != null && !_compassMissing) parts.add('telefon: ${formatBearing(heading)}');
    final decl = _declination;
    parts.add(decl == null
        ? 'kierunek magnetyczny (brak poprawki deklinacji w tym rejonie)'
        : 'deklinacja ${decl >= 0 ? '+' : ''}${decl.toStringAsFixed(1).replaceAll('.', ',')}°');
    return parts.join(' · ');
  }

  List<Widget> _compassHints(ThemeData theme) {
    if (_compassMissing) {
      final brg = _bearing;
      return [
        _Hint(
          icon: Icons.explore_off_outlined,
          text: 'Brak kompasu w telefonie (albo nie odpowiada). '
              '${brg == null ? '' : 'Idź na azymut ${formatBearing(brg)} – sprawdź go zwykłym kompasem lub zegarkiem.'}',
          color: theme.colorScheme.errorContainer,
        ),
      ];
    }
    final q = compassQuality(_accuracy);
    return [
      if (q == CompassQuality.poor || (q == CompassQuality.unknown && _gotCompass))
        _Hint(
          icon: Icons.screen_rotation_alt,
          text: q == CompassQuality.poor
              ? 'Kompas jest niedokładny – zatocz telefonem kilka razy ósemkę w powietrzu. '
                  'Odsuń się od metalu, auta i magnesów (np. w etui).'
              : 'Dokładność kompasu nieznana. Jeśli strzałka nie zgadza się z terenem, '
                  'zatocz telefonem kilka razy ósemkę w powietrzu.',
          color: q == CompassQuality.poor ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHigh,
        ),
      _Hint(
        icon: Icons.stay_current_portrait,
        text: 'Trzymaj telefon płasko, górą przed siebie. Strzałka zawsze wskazuje cel z miejsca, '
            'w którym jesteś – możesz obchodzić przeszkody.',
        color: theme.colorScheme.surfaceContainerHigh,
      ),
    ];
  }
}

/// Tarcza: duża strzałka do celu i znacznik północy na obwodzie
class _Dial extends StatelessWidget {
  const _Dial({
    required this.heading,
    required this.bearing,
    required this.here,
    required this.active,
    required this.color,
    required this.ringColor,
    required this.northColor,
  });

  final double? heading;
  final double? bearing;
  final bool here;
  final bool active;
  final Color color;
  final Color ringColor;
  final Color northColor;

  @override
  Widget build(BuildContext context) {
    if (here) {
      return Icon(Icons.check_circle, size: 220, color: color);
    }
    final h = heading, b = bearing;
    final arrow = active && h != null && b != null ? relativeAngle(b, h) : null;
    return CustomPaint(
      painter: _DialPainter(
        arrowDeg: arrow,
        northDeg: h == null ? null : normalize(-h),
        color: color,
        ringColor: ringColor,
        northColor: northColor,
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.arrowDeg,
    required this.northDeg,
    required this.color,
    required this.ringColor,
    required this.northColor,
  });

  final double? arrowDeg;
  final double? northDeg;
  final Color color;
  final Color ringColor;
  final Color northColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r - 4, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = ringColor);

    final n = northDeg;
    if (n != null) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(n * pi / 180);
      final tp = TextPainter(
        text: TextSpan(text: 'N', style: TextStyle(color: northColor, fontSize: r * 0.13, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -r + 10));
      canvas.restore();
    }

    final a = arrowDeg;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate((a ?? 0) * pi / 180);
    final s = r * 0.72;
    final path = Path()
      ..moveTo(0, -s)
      ..lineTo(s * 0.55, s * 0.55)
      ..lineTo(0, s * 0.28)
      ..lineTo(-s * 0.55, s * 0.55)
      ..close();
    canvas.drawPath(path, Paint()..color = a == null ? ringColor : color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.arrowDeg != arrowDeg || old.northDeg != northDeg || old.color != color || old.ringColor != ringColor;
}

class _GpsBanner extends StatelessWidget {
  const _GpsBanner({required this.state, required this.stale, required this.onRetry});

  final _GpsState state;
  final bool stale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String text, String? action, VoidCallback? onAction) = switch (state) {
      _GpsState.searching => (
          stale ? 'Szukam sygnału GPS… (na razie ostatnia znana pozycja)' : 'Szukam sygnału GPS… Wyjdź pod gołe niebo.',
          null,
          null
        ),
      _GpsState.ok => ('', null, null),
      _GpsState.serviceOff => ('Lokalizacja w telefonie jest wyłączona.', 'Włącz', () async {
          await Geolocator.openLocationSettings();
          onRetry();
        }),
      _GpsState.denied => ('Bez zgody na lokalizację nie wiem, gdzie jesteś.', 'Zezwól', onRetry),
      _GpsState.deniedForever => ('Zgoda na lokalizację jest zablokowana.', 'Ustawienia', () async {
          await Geolocator.openAppSettings();
          onRetry();
        }),
      _GpsState.error => ('Brak sygnału GPS.', 'Ponów', onRetry),
    };
    return _Hint(
      icon: state == _GpsState.searching ? Icons.gps_not_fixed : Icons.gps_off,
      text: text,
      color: state == _GpsState.searching ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.errorContainer,
      action: action == null ? null : TextButton(onPressed: onAction, child: Text(action)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, required this.color, this.action});

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            ?action,
          ],
        ),
      ),
    );
  }
}
