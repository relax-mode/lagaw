import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/screens/swipe/swipe_deck.dart';

LocationItem _loc(String id, String name) => LocationItem.fromJson({
  'id': id,
  'name': name,
  'description': '$name description.',
  'category': 'heritage',
  'vibe_tags': ['heritage', 'photography', 'history'],
  'address': '$name Street, Bacolod City',
  'estimated_cost_min': null,
  'estimated_cost_max': null,
  'typical_visit_duration': 60,
});

void main() {
  late List<String> events;

  Future<void> pump(
    WidgetTester tester, {
    bool busy = false,
    String? error,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    events = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.blue,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SwipeDeck(
              spot: _loc('a', 'The Ruins'),
              upNext: [_loc('b', 'Museum'), _loc('c', 'Capitol')],
              position: 1,
              total: 3,
              busy: busy,
              rating: null,
              error: error,
              onSwipe: (liked) async => events.add(liked ? 'like' : 'pass'),
              onRate: () => events.add('rate'),
            ),
          ),
        ),
      ),
    );
    // The busy spinner never settles, so step time instead.
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('centered title, count, card panel and the stack behind', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Swipe your vibe'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('The Ruins'), findsOneWidget);
    expect(find.text('The Ruins Street'), findsOneWidget);
    expect(find.text('#heritage'), findsOneWidget);
    // Only two tags, so the panel stays short.
    expect(find.text('#history'), findsNothing);
    expect(find.byKey(const ValueKey('swipe-next-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('swipe-next-c')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons like, pass and rate', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('swipe-like')));
    await tester.tap(find.byKey(const ValueKey('swipe-pass')));
    await tester.tap(find.byKey(const ValueKey('swipe-rate')));
    expect(events, ['like', 'pass', 'rate']);
  });

  testWidgets('a far drag swipes; a short one springs back', (tester) async {
    await pump(tester);
    final card = find.text('The Ruins');
    await tester.drag(card, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(events, isEmpty);

    await tester.drag(card, const Offset(160, 0));
    await tester.pumpAndSettle();
    await tester.drag(card, const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(events, ['like', 'pass']);
  });

  testWidgets('busy blocks swiping and shows progress', (tester) async {
    await pump(tester, busy: true, error: 'Couldn’t save that swipe.');
    expect(find.byKey(const ValueKey('swipe-busy')), findsOneWidget);
    expect(find.byKey(const ValueKey('swipe-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swipe-pass')));
    await tester.drag(find.text('The Ruins'), const Offset(200, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(events, isEmpty);
  });
}
