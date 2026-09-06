import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/main.dart';

void main() {
  testWidgets('mobile shell starts without services', (tester) async {
    await tester.pumpWidget(const ShioriApp());

    expect(find.text('Shiori'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
