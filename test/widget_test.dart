import 'package:flutter_test/flutter_test.dart';
import 'package:setlistmanager/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SetlistManagerApp());
    expect(find.text('Setlist Manager'), findsWidgets);
  });
}
