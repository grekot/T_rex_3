// Wykres na widżecie ekranu telefonu: historia punktu z chmury (pkt 8.1) narysowana do obrazka tym samym kodem co
// kafelek pulpitu, plus ostatnia wartość i zakres tekstem. Odświeżany co 15 min (historia też zapisuje się co 15 min).

import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../controllers/device_hub.dart';
import '../data/history.dart';
import '../models/describe.dart';
import '../models/home_widget.dart';
import '../ui/dashboard_tiles.dart' show fallbackPoint;
import '../ui/tile_charts.dart';

/// Wykres w kratce: obrazek PNG (base64), duża wartość i linia z zakresem.
typedef WidgetChart = ({String png, String value, String subtitle});

/// Punkt wykresu: z `describe` urządzenia (pole `history`), bez opisu - zapasowy (np. `temp` termostatu).
DataPoint chartPoint(DeviceController<Object?, Object?>? c, String key) =>
    c?.cachedDescription?.point(key) ?? fallbackPoint(key);

/// Kolor linii / słupków: nazwany kolor pozycji albo pomarańczowy akcent aplikacji.
Color chartColor(String? name) => name == null ? const Color(0xFFE8590C) : namedColor(name, const ColorScheme.dark());

/// Wykres z historii [data] punktu [p]: linia (wartość = ostatnia próbka, zakres min - max) albo słupki
/// (wartość = bieżący przedział, np. dzisiejszy czas grzania). null = za mało danych.
Future<WidgetChart?> buildWidgetChart(
  List<HistoryPoint> data,
  DataPoint p, {
  String? range,
  bool bars = false,
  String? color,
  DateTime? now,
}) async {
  final hours = rangeHours(range);
  final when = rangeLabel(range ?? '24h');
  if (bars) {
    final agg = defaultAgg(p);
    final list = historyBars(data, hours, agg, now ?? DateTime.now());
    final values = [
      for (final b in list)
        if (b.value != null) b.value!,
    ];
    if (values.isEmpty) return null;
    final top = values.reduce((a, b) => a > b ? a : b), bottom = values.reduce((a, b) => a < b ? a : b);
    final lo = agg == 'on' || bottom >= 0 ? 0.0 : bottom;
    final hi = top - lo < 0.1 ? lo + (agg == 'on' ? 1 : 0.1) : top;
    String fmt(double v) => agg == 'on' ? fmtHours(v) : p.format(v);
    final png = await renderChartPng(
      data,
      hours: hours,
      lo: lo,
      hi: hi,
      color: chartColor(color),
      bars: true,
      agg: agg,
      now: now,
    );
    if (png == null) return null;
    final last = list.last.value;
    return (png: png, value: last == null ? '—' : fmt(last), subtitle: '$when · najwięcej ${fmt(top)}');
  }
  if (data.length < 2) return null;
  final values = [for (final d in data) d.value];
  var lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
  final min = lo, max = hi;
  if (hi - lo < 0.1) {
    lo -= 0.5;
    hi += 0.5;
  }
  final png = await renderChartPng(data, hours: hours, lo: lo, hi: hi, color: chartColor(color));
  if (png == null) return null;
  return (png: png, value: p.format(data.last.value), subtitle: '${p.format(min)} – ${p.format(max)} · $when');
}

/// Wykres pozycji widżetu z historii domu w chmurze; null = bez chmury, bez historii punktu albo za mało danych.
Future<WidgetChart?> loadWidgetChart(DeviceHub hub, HomeWidgetItem item) async {
  final h = hub.home;
  if (h == null || !hub.cloud.available || item.device == null || item.point == null) return null;
  final p = chartPoint(hub.controller(item.device!), item.point!);
  final field = p.history;
  if (field == null) return null;
  final data = await loadHistory(
    hub.cloud.store,
    homeId: h.id,
    deviceId: item.device!,
    field: field,
    hours: rangeHours(item.look.range),
  );
  return buildWidgetChart(data, p, range: item.look.range, bars: item.look.bars ?? false, color: item.look.color);
}
