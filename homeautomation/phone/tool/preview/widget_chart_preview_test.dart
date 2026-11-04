// Podgląd obrazków wykresu dla widżetu ekranu telefonu (nie jest częścią `flutter test`): linia temperatury i słupki
// czasu grzania na dzień - te same PNG, które usługa widżetów wysyła do Androida. Uruchomienie:
//   flutter test tool/preview/widget_chart_preview_test.dart
// Obrazki: tool/preview/widzet_wykres_linia.png, widzet_wykres_slupki.png.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/home_widgets/widget_chart.dart';
import 'package:homeautomation/ui/dashboard_tiles.dart' show fallbackPoint;

void main() {
  test('obrazki wykresu widżetu', () async {
    final now = DateTime(2026, 11, 4, 12, 30);
    final temp = [
      for (var m = 0; m <= 24 * 60; m += 15)
        (at: now.subtract(Duration(minutes: 24 * 60 - m)), value: 21.7 + (m < 300 ? 1.2 - m / 250 : (m % 180) / 300)),
    ];
    final line = await buildWidgetChart(temp, fallbackPoint('temp'), now: now);
    File('tool/preview/widzet_wykres_linia.png').writeAsBytesSync(base64Decode(line!.png));
    final heat = [
      for (var m = 0; m < 24 * 60 * 7; m += 15)
        (at: now.subtract(Duration(minutes: 24 * 60 * 7 - m)), value: ((m ~/ 60) % 24) < 3 + (m ~/ 1440) ? 0.8 : 0.0),
    ];
    final bars = await buildWidgetChart(
      heat,
      fallbackPoint('heating'),
      range: '7d',
      bars: true,
      color: 'blue',
      now: now,
    );
    File('tool/preview/widzet_wykres_slupki.png').writeAsBytesSync(base64Decode(bars!.png));
  });
}
