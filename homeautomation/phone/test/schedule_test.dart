import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/models/schedule.dart';

void main() {
  group('DayPlan', () {
    test('parsuje plan z kontraktu', () {
      final p = DayPlan.tryParse('06:00-08:00,15:00-22:00')!;
      expect(p.periods, [
        TimePeriod(DayTime.hm(6, 0), DayTime.hm(8, 0)),
        TimePeriod(DayTime.hm(15, 0), DayTime.hm(22, 0)),
      ]);
      expect(p.validate(), isNull);
      expect(p.format(), '06:00-08:00,15:00-22:00');
    });

    test('"-" to cały dzień eko', () {
      expect(DayPlan.tryParse('-')!.periods, isEmpty);
      expect(DayPlan.empty.format(), '-');
    });

    test('24:00 dozwolone jako koniec', () {
      final p = DayPlan.tryParse('20:00-24:00')!;
      expect(p.validate(), isNull);
      expect(p.periods.single.end.minutes, 1440);
      expect(p.format(), '20:00-24:00');
    });

    test('24:00 niedozwolone jako początek', () {
      expect(DayPlan.tryParse('24:00-24:00')!.validate(), isNotNull);
    });

    test('zły format', () {
      for (final s in ['6:00-8:00', '06:00', '06:00-08:60', '25:00-26:00', '06:00-08:00;09:00-10:00', 'abc']) {
        expect(DayPlan.tryParse(s), isNull, reason: s);
      }
    });

    test('najwyżej 4 okresy', () {
      final p = DayPlan.tryParse('01:00-02:00,03:00-04:00,05:00-06:00,07:00-08:00,09:00-10:00')!;
      expect(p.validate(), contains('4'));
      expect(DayPlan.tryParse('01:00-02:00,03:00-04:00,05:00-06:00,07:00-08:00')!.validate(), isNull);
    });

    test('okresy rosnąco i bez nakładania', () {
      expect(DayPlan.tryParse('15:00-22:00,06:00-08:00')!.validate(), isNotNull);
      expect(DayPlan.tryParse('06:00-09:00,08:00-10:00')!.validate(), isNotNull);
      expect(DayPlan.tryParse('06:00-08:00,08:00-10:00')!.validate(), isNull, reason: 'styk jest dozwolony');
    });

    test('koniec po początku', () {
      expect(DayPlan.tryParse('08:00-06:00')!.validate(), isNotNull);
      expect(DayPlan.tryParse('08:00-08:00')!.validate(), isNotNull);
    });
  });

  group('NightPeriod', () {
    test('przez północ', () {
      final p = NightPeriod.parse('23:00-06:00')!;
      expect(p.start, DayTime.hm(23, 0));
      expect(p.end, DayTime.hm(6, 0));
      expect(p.lengthMinutes, 7 * 60);
      expect(NightPeriod.format(p), '23:00-06:00');
    });

    test('"-" = brak', () {
      expect(NightPeriod.parse('-'), isNull);
      expect(NightPeriod.format(null), '-');
    });

    test('zły format', () {
      expect(() => NightPeriod.parse('23-6'), throwsFormatException);
      expect(() => NightPeriod.parse('06:00-06:00'), throwsFormatException);
    });
  });
}
