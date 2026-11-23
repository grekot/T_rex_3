import 'package:flutter_test/flutter_test.dart';

import 'package:trening/main.dart';

void main() {
  testWidgets('ekran startowy pokazuje nazwę i zapowiedź wersji 0.1',
      (tester) async {
    await tester.pumpWidget(const TreningApp());

    expect(find.text('Trening'), findsOneWidget);
    expect(find.text('Wersja testowa'), findsOneWidget);
    expect(find.text('W wersji 0.1'), findsOneWidget);
  });
}
