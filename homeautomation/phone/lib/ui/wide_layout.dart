// Szerokie okno (komputer, tablet poziomo): pulpit w kilku kolumnach sekcji zamiast jednej rozciągniętej siatki,
// ekrany z listami - z ograniczoną szerokością. Telefon (wąsko) wygląda jak dotąd.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/dashboard.dart';
import 'dashboard_tiles.dart';

/// Od tej szerokości pulpit dzieli się na kolumny sekcji.
const wideMinWidth = 900.0;

/// Docelowa szerokość kolumny sekcji (siatka 4 kafelków jak na dużym telefonie).
const wideColumnWidth = 440.0;

/// Ile kolumn sekcji przy szerokości [width]; 1 = jak w telefonie.
int dashSectionColumns(double width) => width < wideMinWidth ? 1 : (width / wideColumnWidth).floor().clamp(2, 4);

/// Przybliżona wysokość sekcji (w wierszach 64 px siatki 4) - do rozłożenia sekcji między kolumny.
double dashSectionHeight(List<DashWidget> widgets, int grid) {
  if (widgets.isEmpty) return 1;
  if (grid == 4) return packGrid4(widgets).map((p) => p.row + p.widget.gridH).reduce(math.max).toDouble() + 1;
  // Siatka 2: pola 1×1 = ćwiartka szerokości dwóch wierszy 64 px.
  final cells = widgets.fold<int>(0, (a, w) => a + w.size.columns * w.size.rows);
  return (cells / 2).ceil() * 2 + 1;
}

/// Rozkład sekcji na [columns] kolumn: po kolei, każda do najniższej kolumny (przy równych - do lewej);
/// kolejność sekcji w kolumnie zostaje.
List<List<int>> spreadSections(List<double> heights, int columns) {
  final out = [for (var i = 0; i < columns; i++) <int>[]];
  final sum = List<double>.filled(columns, 0);
  for (var i = 0; i < heights.length; i++) {
    var best = 0;
    for (var c = 1; c < columns; c++) {
      if (sum[c] < sum[best]) best = c;
    }
    out[best].add(i);
    sum[best] += heights[i];
  }
  return out;
}

/// Treść ekranu wyśrodkowana, najwyżej [maxWidth] szeroka (listy ustawień, edycja pulpitu na komputerze).
class WideLimit extends StatelessWidget {
  const WideLimit({super.key, this.maxWidth = 720, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
