import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/floating_elements.dart';

void main() {
  Future<void> show(WidgetTester tester, List<ElementPlacement> set) =>
      tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 390,
            height: 800,
            child: FloatingElements(placements: set),
          ),
        ),
      );

  Iterable<String> shown(WidgetTester tester) => tester
      .widgetList<Positioned>(find.byType(Positioned))
      .map((p) => (p.key! as ValueKey<String>).value);

  testWidgets('elements glide between pages and others come and go', (
    tester,
  ) async {
    await show(tester, ElementPlacement.home);
    expect(shown(tester).toSet(), {'masskara', 'inasal', 'piaya', 'carabao'});
    final piayaHome = tester.getTopLeft(find.byKey(const ValueKey('piaya')));

    await show(tester, ElementPlacement.spots);
    await tester.pump(const Duration(milliseconds: 360));
    // Mid-glide: leaving ones still fading out, piaya on its way.
    expect(shown(tester), contains('carabao'));
    final piayaMid = tester.getTopLeft(find.byKey(const ValueKey('piaya')));
    expect(piayaMid, isNot(piayaHome));

    await tester.pump(const Duration(milliseconds: 500));
    expect(shown(tester).toSet(), {'inasal', 'piaya'});

    // No elements: nothing left ticking, so the page can settle.
    await show(tester, const []);
    await tester.pumpAndSettle();
    expect(shown(tester), isEmpty);
  });
}
