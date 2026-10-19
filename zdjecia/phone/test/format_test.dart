import 'package:flutter_test/flutter_test.dart';
import 'package:zdjecia/bridge/format.dart';

void main() {
  test('rozmiary i czasy', () {
    expect(formatBytes(900), '900 B');
    expect(formatBytes(412 * 1024), '412 KB');
    expect(formatBytes(3 * 1024 * 1024 ~/ 2), '1,5 MB');
    expect(formatDuration(const Duration(milliseconds: 250)), '250 ms');
    expect(formatDuration(const Duration(milliseconds: 1250)), '1,3 s');
    expect(formatDateTime(DateTime(2026, 10, 9, 7, 5)), '09.10.2026 07:05');
    expect(formatClock(DateTime(2026, 1, 1, 9, 8, 7)), '09:08:07');
  });
}
