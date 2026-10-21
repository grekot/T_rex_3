import 'package:flutter_test/flutter_test.dart';
import 'package:powrot/geo.dart';

void main() {
  test('normalize', () {
    expect(normalize(0), 0);
    expect(normalize(360), 0);
    expect(normalize(-90), 270);
    expect(normalize(725), 5);
  });

  test('odległość (haversine)', () {
    expect(distanceMeters(52.0, 21.0, 52.0001, 21.0), closeTo(11.1, 0.2));
    // Warszawa - Kraków ok. 252 km
    expect(distanceMeters(52.2297, 21.0122, 50.0647, 19.945), closeTo(252000, 2000));
    expect(distanceMeters(50, 20, 50, 20), 0);
  });

  test('azymut do celu', () {
    expect(bearing(52, 21, 53, 21), closeTo(0, 0.01)); // na północ
    expect(bearing(52, 21, 51, 21), closeTo(180, 0.01)); // na południe
    expect(bearing(0, 0, 0, 1), closeTo(90, 0.01)); // na wschód
    expect(bearing(0, 1, 0, 0), closeTo(270, 0.01)); // na zachód
    // Warszawa -> Kraków: na południowy zachód, ok. 197°
    expect(bearing(52.2297, 21.0122, 50.0647, 19.945), closeTo(197, 1.5));
  });

  test('kąt strzałki względem telefonu', () {
    expect(relativeAngle(90, 0), 90); // cel na wschodzie, patrzę na północ -> w prawo
    expect(relativeAngle(90, 90), 0); // patrzę na cel -> prosto
    expect(relativeAngle(10, 350), 20);
    expect(relativeAngle(350, 10), 340); // lekko w lewo
  });

  test('wygładzanie po najkrótszym łuku', () {
    expect(smoothAngle(null, 370, 0.2), 10);
    expect(smoothAngle(0, 100, 0.5), 50);
    expect(smoothAngle(359, 1, 0.5), closeTo(0, 1e-9)); // przez północ, nie przez 180°
    expect(smoothAngle(10, 350, 0.5), closeTo(0, 1e-9));
    // po wielu krokach dochodzi do celu
    double? h;
    for (var i = 0; i < 100; i++) {
      h = smoothAngle(h ?? 300, 20, 0.15);
    }
    expect(h, closeTo(20, 0.01));
  });

  test('angleDiff', () {
    expect(angleDiff(350, 10), 20);
    expect(angleDiff(10, 350), -20);
    expect(angleDiff(0, 180).abs(), 180);
  });

  test('strony świata i opis azymutu', () {
    expect(cardinal(0), 'Pn');
    expect(cardinal(359), 'Pn');
    expect(cardinal(47), 'Pn-Wsch');
    expect(cardinal(90), 'Wsch');
    expect(cardinal(140), 'Pd-Wsch');
    expect(cardinal(200), 'Pd');
    expect(cardinal(-45), 'Pn-Zach');
    expect(formatBearing(47.4), 'Pn-Wsch · 47°');
    expect(formatBearing(359.7), 'Pn · 0°');
  });

  test('formatowanie odległości', () {
    expect(formatDistance(7.2), '7 m');
    expect(formatDistance(349.6), '350 m');
    expect(formatDistance(1250), '1,25 km');
    expect(formatDistance(12345), '12,3 km');
    expect(formatDistance(152400), '152 km');
    expect(formatDistance(double.nan), '–');
  });

  group('Na miejscu', () {
    test('wibracja raz przy wejściu w 15 m, ponownie dopiero po oddaleniu na 30 m', () {
      final t = ArrivalTracker();
      expect(t.update(100), isFalse);
      expect(t.here, isFalse);
      expect(t.update(14), isTrue);
      expect(t.here, isTrue);
      expect(t.update(10), isFalse, reason: 'bez ponownej wibracji');
      expect(t.update(22), isFalse, reason: 'drgania GPS przy granicy');
      expect(t.here, isTrue);
      expect(t.update(12), isFalse);
      expect(t.update(31), isFalse);
      expect(t.here, isFalse);
      expect(t.update(20), isFalse);
      expect(t.update(15), isTrue, reason: 'po oddaleniu na 30 m alarm znowu działa');
    });

    test('start na miejscu wibruje od razu', () {
      expect(ArrivalTracker().update(3), isTrue);
    });
  });

  group('deklinacja', () {
    final when = DateTime(2027, 1, 1);

    test('Polska: wschodnia, ok. 5-8°', () {
      expect(declination(52.23, 21.01, when), closeTo(6.9, 0.3)); // Warszawa
      expect(declination(50.06, 19.94, when), closeTo(6.4, 0.3)); // Kraków
      expect(declination(53.43, 14.55, when), closeTo(5.6, 0.3)); // Szczecin
      expect(declination(49.23, 19.98, when), closeTo(6.2, 0.3)); // Tatry
    });

    test('zmiana w czasie', () {
      final now = declination(52.23, 21.01, DateTime(2027, 1, 1))!;
      final later = declination(52.23, 21.01, DateTime(2029, 1, 1))!;
      expect(later - now, closeTo(0.23, 0.05));
      // poza 2024-2032 nie ekstrapolujemy
      expect(declination(52.23, 21.01, DateTime(2050)), declination(52.23, 21.01, DateTime(2032)));
    });

    test('poza obszarem modelu - brak poprawki', () {
      expect(declination(40.4, -3.7, when), isNull); // Madryt
      expect(declination(-33.9, 151.2, when), isNull); // Sydney
      expect(declination(46.0, 11.0, when), isNotNull); // Dolomity - w marginesie
    });

    test('kierunek geograficzny', () {
      expect(trueHeading(355, 7), 2);
      expect(trueHeading(10, 7), 17);
    });
  });

  test('jakość kompasu', () {
    expect(compassQuality(15), CompassQuality.good);
    expect(compassQuality(30), CompassQuality.medium);
    expect(compassQuality(45), CompassQuality.poor);
    expect(compassQuality(null), CompassQuality.unknown);
  });
}
