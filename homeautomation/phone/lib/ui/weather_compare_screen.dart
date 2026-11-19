// „Porównanie prognoz” (kontrakt pkt 11, hub 0.3.43+): Open-Meteo i MET Norway obok siebie - teraz, 24 h (wykres
// i tabela temperatury i opadu) i 7 dni (min / max, opad, ikona). Ma pomóc ocenić, które źródło lepiej trafia.
// Dane surowe z `GET /api/weather/compare` (MET bez uzupełnień z Open-Meteo - porywów i szansy opadu nie ma).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/errors.dart';
import '../models/hub_weather.dart';
import '../models/weather_compare.dart';
import 'dashboard_tiles.dart' show weatherIconAt, weatherLabel;
import 'format.dart';
import 'wide_layout.dart' show wideMinWidth;

/// Kolory źródeł na wykresie i w nagłówkach tabel.
const _colors = {weatherSourceOpenMeteo: Color(0xFFE8590C), weatherSourceMetNo: Color(0xFF1C7ED6)};

const _dayNames = ['pn', 'wt', 'śr', 'cz', 'pt', 'so', 'nd'];

String _hh(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:00';
String _mm(double? v) => v == null ? '—' : '${fmtNumber(v)} mm';
String _short(String s) => s == weatherSourceMetNo ? 'MET' : 'Open-Meteo';

class WeatherCompareScreen extends StatefulWidget {
  const WeatherCompareScreen({super.key, required this.load, this.now});

  /// Pobranie porównania (w aplikacji `HubApi.weatherCompare`).
  final Future<WeatherCompare> Function() load;

  /// Do testów: „teraz”.
  final DateTime Function()? now;

  @override
  State<WeatherCompareScreen> createState() => _WeatherCompareScreenState();
}

class _WeatherCompareScreenState extends State<WeatherCompareScreen> {
  WeatherCompare? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (mounted) setState(() => _data = d);
    } on ThermostatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Porównanie prognoz'),
        actions: [
          IconButton(
            key: const Key('compareReload'),
            tooltip: 'Odśwież',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: _loading && d == null
          ? const Center(child: CircularProgressIndicator())
          : d == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error ?? 'Brak danych.', key: const Key('compareError'), textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: LayoutBuilder(builder: (context, box) => _content(context, d, box.maxWidth >= wideMinWidth)),
            ),
    );
  }

  Widget _content(BuildContext context, WeatherCompare d, bool wide) {
    final now = (widget.now ?? DateTime.now)();
    final head = [
      _Summary(data: d, now: now),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 8),
      _Now(data: d),
    ];
    final hours = [
      const _Header('Najbliższe 24 h'),
      _HoursChart(data: d),
      const SizedBox(height: 8),
      _HoursTable(data: d),
    ];
    final days = [const _Header('7 dni'), _DaysTable(data: d)];
    if (!wide) {
      return ListView(padding: const EdgeInsets.all(16), children: [...head, ...hours, ...days]);
    }
    // Szerokie okno: godziny i dni w dwóch kolumnach obok siebie.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...head,
        Row(
          key: const Key('compareColumns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hours),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: days),
            ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Wybrane i użyte źródło, wiek danych, różnica temperatur i suma opadu w 24 h.
class _Summary extends StatelessWidget {
  const _Summary({required this.data, required this.now});

  final WeatherCompare data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final om = data.sources[weatherSourceOpenMeteo], met = data.sources[weatherSourceMetNo];
    final diff = om != null && met != null ? compareHourlyTemp(om, met) : null;
    final fallback = data.active != null && data.source != null && data.active != data.source;
    String age(CompareSource? s) =>
        s?.at == null ? 'brak danych' : 'pobrane ${fmtAge(now.difference(s!.at!).inSeconds)} temu';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Zegary i kafelki: ${weatherSourceName(data.active ?? data.source)}', style: t.titleSmall),
            if (fallback)
              Padding(
                key: const Key('compareFallback'),
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Wybrane ${weatherSourceName(data.source)} nie ma teraz świeżych danych - hub używa zapasowego źródła.',
                  style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            for (final s in weatherSources)
              Row(
                children: [
                  Icon(Icons.circle, size: 10, color: _colors[s]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${weatherSourceName(s)}: ${age(data.sources[s])}'
                      '${data.sources[s] == null ? '' : ' · opad 24 h ${_mm(data.sources[s]!.rain24h)}'}',
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            if (diff != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  key: const Key('compareDiff'),
                  'Różnica temperatur w 24 h: średnio ${fmtNumber(diff.mean)} °C, najwyżej ${fmtNumber(diff.max)} °C.',
                  style: t.bodyMedium,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'MET Norway nie podaje porywów ani szansy opadu - tu są puste. Źródło zmienisz w ustawieniach pogody huba.',
                style: t.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bieżąca pogoda obu źródeł.
class _Now extends StatelessWidget {
  const _Now({required this.data});

  final WeatherCompare data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget col(String s) {
      final c = data.sources[s]?.current;
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(weatherSourceName(s), style: t.labelLarge?.copyWith(color: _colors[s])),
                const SizedBox(height: 4),
                if (c == null)
                  const Text('Brak danych')
                else ...[
                  Row(
                    children: [
                      Icon(weatherIconAt(c.icon, day: c.day), size: 28),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(fmtTemp(c.temp), key: Key('compareNow-$s'), style: t.titleLarge),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    [
                      weatherLabel(c.icon),
                      if (c.feels != null) 'odczuwalna ${fmtTemp(c.feels)}',
                      if (c.hum != null) 'wilgotność ${c.hum} %',
                      if (c.wind != null) 'wiatr ${c.wind!.round()} km/h',
                      if (c.gust != null) 'porywy ${c.gust!.round()} km/h',
                      if (c.mm != null) 'opad ${_mm(c.mm)}',
                    ].join(' · '),
                    style: t.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final s in weatherSources) col(s)]);
  }
}

/// Temperatura obu źródeł (linie) i opad (słupki) na 24 h.
class _HoursChart extends StatelessWidget {
  const _HoursChart({required this.data});

  final WeatherCompare data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          key: const Key('compareChart'),
          height: 180,
          child: CustomPaint(
            painter: _ChartPainter(
              series: {for (final s in weatherSources) s: data.sources[s]?.hourly ?? const []},
              grid: cs.outlineVariant,
              text: cs.onSurfaceVariant,
            ),
            size: Size.infinite,
          ),
        ),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final s in weatherSources)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 16, height: 3, color: _colors[s]),
                  const SizedBox(width: 4),
                  Text(_short(s), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            Text('linie - temperatura, słupki - opad', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.series, required this.grid, required this.text});

  final Map<String, List<HourForecast>> series;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final l in series.values) ...l];
    final temps = [for (final h in all) ?h.t];
    if (all.isEmpty || temps.isEmpty) return;
    final t0 = all.map((h) => h.ts.millisecondsSinceEpoch).reduce(math.min).toDouble();
    final t1 = all.map((h) => h.ts.millisecondsSinceEpoch).reduce(math.max).toDouble();
    final lo = temps.reduce(math.min).floorToDouble() - 1, hi = temps.reduce(math.max).ceilToDouble() + 1;
    final mmMax = math.max(2.0, all.map((h) => h.mm ?? 0).reduce(math.max));
    const left = 30.0, bottom = 18.0;
    final w = size.width - left, h = size.height - bottom;
    double x(DateTime ts) => left + (t1 == t0 ? 0 : (ts.millisecondsSinceEpoch - t0) / (t1 - t0) * w);
    double y(double t) => h - (t - lo) / (hi - lo) * h;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    void label(String s, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: text, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    for (final t in [lo, (lo + hi) / 2, hi]) {
      canvas.drawLine(Offset(left, y(t)), Offset(size.width, y(t)), gridPaint);
      label('${t.round()}°', Offset(0, y(t) - 6));
    }
    // Opad: słupki obok siebie (każde źródło połowa szerokości godziny).
    final hourW = all.length < 2 ? w : w / math.max(1, (t1 - t0) / 3600000);
    var i = 0;
    for (final MapEntry(key: s, value: list) in series.entries) {
      final p = Paint()..color = _colors[s]!.withValues(alpha: 0.35);
      for (final hr in list) {
        final mm = hr.mm ?? 0;
        if (mm <= 0) continue;
        final bh = mm / mmMax * h * 0.5;
        final bx = x(hr.ts) - hourW / 2 + i * hourW / 2;
        canvas.drawRect(Rect.fromLTWH(bx, h - bh, hourW / 2, bh), p);
      }
      i++;
    }
    for (final MapEntry(key: s, value: list) in series.entries) {
      final pts = [
        for (final hr in list)
          if (hr.t != null) Offset(x(hr.ts), y(hr.t!)),
      ];
      if (pts.length < 2) continue;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _colors[s]!
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    // Godziny co 6 h pod osią.
    final first = all.map((h) => h.ts).reduce((a, b) => a.isBefore(b) ? a : b);
    for (var k = 0; k <= 24; k += 6) {
      final ts = first.add(Duration(hours: k));
      if (ts.millisecondsSinceEpoch > t1) break;
      label(_hh(ts), Offset(x(ts) - 12, h + 4));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.series != series || old.grid != grid;
}

/// Tabela 24 h: godzina, temperatura i opad z obu źródeł.
class _HoursTable extends StatelessWidget {
  const _HoursTable({required this.data});

  final WeatherCompare data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final byTs = <int, Map<String, HourForecast>>{};
    for (final s in weatherSources) {
      for (final h in data.sources[s]?.hourly ?? const <HourForecast>[]) {
        (byTs[h.ts.millisecondsSinceEpoch] ??= {})[s] = h;
      }
    }
    final keys = byTs.keys.toList()..sort();
    return Table(
      key: const Key('compareHours'),
      columnWidths: const {0: FixedColumnWidth(56)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            Text('Godz.', style: t.labelMedium),
            for (final s in weatherSources) Text(_short(s), style: t.labelMedium?.copyWith(color: _colors[s])),
          ],
        ),
        for (final k in keys)
          TableRow(
            children: [
              Text(_hh(DateTime.fromMillisecondsSinceEpoch(k)), style: t.bodySmall),
              for (final s in weatherSources) _hourCell(context, byTs[k]![s]),
            ],
          ),
      ],
    );
  }

  Widget _hourCell(BuildContext context, HourForecast? h) {
    final t = Theme.of(context).textTheme;
    if (h == null) return Text('—', style: t.bodySmall);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(weatherIconAt(h.icon, day: h.ts.hour >= 6 && h.ts.hour < 20), size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              (h.mm ?? 0) > 0 ? '${fmtTemp(h.t)} · ${_mm(h.mm)}' : fmtTemp(h.t),
              style: t.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tabela 7 dni: min / max, opad, szansa opadu i ikona z obu źródeł.
class _DaysTable extends StatelessWidget {
  const _DaysTable({required this.data});

  final WeatherCompare data;

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final byDay = <String, Map<String, DayForecast>>{};
    final dates = <String, DateTime>{};
    for (final s in weatherSources) {
      for (final d in data.sources[s]?.daily ?? const <DayForecast>[]) {
        (byDay[_key(d.date)] ??= {})[s] = d;
        dates[_key(d.date)] = d.date;
      }
    }
    final keys = byDay.keys.toList()..sort((a, b) => dates[a]!.compareTo(dates[b]!));
    return Column(
      key: const Key('compareDays'),
      children: [
        for (final k in keys)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${_dayNames[dates[k]!.weekday - 1]} ${dates[k]!.day}.${dates[k]!.month.toString().padLeft(2, '0')}',
                      style: t.labelMedium,
                    ),
                  ),
                  for (final s in weatherSources) Expanded(child: _dayCell(context, s, byDay[k]![s])),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, String s, DayForecast? d) {
    final t = Theme.of(context).textTheme;
    if (d == null) return Text('—', style: t.bodySmall);
    return Row(
      children: [
        Container(width: 3, height: 32, color: _colors[s]),
        const SizedBox(width: 6),
        Icon(weatherIconAt(d.icon), size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${fmtTemp(d.tMin, decimals: 0)} / ${fmtTemp(d.tMax, decimals: 0)}', style: t.bodySmall),
              Text(
                [_mm(d.mm), if (d.pp != null) '${d.pp} %'].join(' · '),
                style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
