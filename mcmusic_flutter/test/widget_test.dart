import 'package:flutter_test/flutter_test.dart';
import 'package:mcmusic_flutter/main.dart';

void main() {
  testWidgets('McMusicApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const McMusicApp());
    expect(find.byType(McMusicApp), findsOneWidget);
  });
}
