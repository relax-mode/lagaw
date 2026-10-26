import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('Lagaw app shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LagawApp());
    expect(find.text('lagaw'), findsNothing); // deliberate CI gate failure
  });
}
