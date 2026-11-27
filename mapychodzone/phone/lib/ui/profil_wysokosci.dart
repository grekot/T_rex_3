import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../trasa/trasa.dart';

/// Profil wysokości trasy: wysokość (oś Y) od odległości (oś X).
class ProfilWysokosci extends StatelessWidget {
  const ProfilWysokosci({super.key, required this.trasa, this.wysokosc = 90});

  final Trasa trasa;
  final double wysokosc;

  @override
  Widget build(BuildContext context) {
    final schemat = Theme.of(context).colorScheme;
    return SizedBox(
      height: wysokosc,
      width: double.infinity,
      child: CustomPaint(
        painter: _Malarz(trasa, schemat.primary, schemat.onSurfaceVariant, Theme.of(context).textTheme.labelSmall!),
      ),
    );
  }
}

class _Malarz extends CustomPainter {
  _Malarz(this.trasa, this.kolor, this.kolorOsi, this.styl);

  final Trasa trasa;
  final Color kolor;
  final Color kolorOsi;
  final TextStyle styl;

  @override
  void paint(Canvas canvas, Size size) {
    final punkty = [
      for (final p in trasa.punkty)
        if (p.wysokosc != null) p,
    ];
    if (punkty.length < 2 || trasa.dlugosc <= 0) return;
    final hMin = trasa.najnizej!;
    final hMax = trasa.najwyzej!;
    // co najmniej 50 m zakresu, żeby płaska trasa nie wyglądała jak ściana
    final zakres = math.max(50.0, hMax - hMin);
    const lewy = 40.0;
    final szer = size.width - lewy;
    final wys = size.height - 4;

    Offset xy(PunktTrasy p) => Offset(
          lewy + p.odStartu / trasa.dlugosc * szer,
          2 + wys - (p.wysokosc! - hMin) / zakres * wys,
        );

    final linia = Path()..moveTo(xy(punkty.first).dx, xy(punkty.first).dy);
    for (final p in punkty.skip(1)) {
      final o = xy(p);
      linia.lineTo(o.dx, o.dy);
    }
    final wypelnienie = Path.from(linia)
      ..lineTo(lewy + szer, size.height)
      ..lineTo(lewy, size.height)
      ..close();
    canvas.drawPath(wypelnienie, Paint()..color = kolor.withValues(alpha: 0.18));
    canvas.drawPath(
      linia,
      Paint()
        ..color = kolor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    void napis(String t, double y) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: styl.copyWith(color: kolorOsi)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: lewy - 4);
      tp.paint(canvas, Offset(0, y.clamp(0, size.height - tp.height)));
    }

    napis('${hMax.round()} m', 2 + wys - (hMax - hMin) / zakres * wys - 6);
    napis('${hMin.round()} m', size.height - 12);
  }

  @override
  bool shouldRepaint(_Malarz old) => old.trasa != trasa || old.kolor != kolor;
}
