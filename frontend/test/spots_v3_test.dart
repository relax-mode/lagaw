import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/screens/spots/spots_view.dart';

LocationItem _loc(String id, String name, String category) =>
    LocationItem.fromJson({
      'id': id,
      'name': name,
      'description': '$name description.',
      'category': category,
      'vibe_tags': ['heritage'],
      'address': '$name St, Bacolod City',
      'estimated_cost_min': null,
      'estimated_cost_max': null,
      'typical_visit_duration': 45,
    });

final _places = [
  _loc('a', 'Capitol Park and Lagoon', 'park'),
  _loc('b', 'Negros Forest Park', 'park'),
  _loc('c', 'Calea Pastries', 'cafe'),
];

/// Floating elements loop forever, so step time instead of settling.
/// Two frames: the first starts size animations, the second ends them.
Future<void> _step(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late List<String> events;

  Future<void> pump(
    WidgetTester tester, {
    List<LocationItem>? places,
    String selected = 'all',
    String query = '',
    bool savedOnly = false,
    Widget? placesState,
    Set<String> saved = const {},
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    events = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.blue,
          body: SpotsView(
            avatarLetter: 'R',
            likedCount: 0,
            onSaved: () => events.add('saved'),
            onAccount: () => events.add('account'),
            places: places ?? _places,
            categories: const ['park', 'cafe', 'museum'],
            selectedCategory: selected,
            query: query,
            onQuery: (q) => events.add('query:$q'),
            onCategory: (id) => events.add('category:$id'),
            savedOnly: savedOnly,
            onExitSaved: () => events.add('exit-saved'),
            isSaved: saved.contains,
            isBusy: (_) => false,
            ratingFor: (_) => null,
            onSave: (p) => events.add('save:${p.id}'),
            onRate: (p) => events.add('rate:${p.id}'),
            placesState: placesState,
          ),
        ),
      ),
    );
    await _step(tester);
  }

  testWidgets('shows the title, real count and chips from the data', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Explore\nBacolod'), findsOneWidget);
    expect(find.text('Showing 3 places'), findsOneWidget);
    for (final label in ['All spots', 'Parks', 'Cafés']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Museums'),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('spots-chips')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Museums'), findsOneWidget);
    expect(find.text('Maayong Aga, Roel!'), findsNothing);
  });

  testWidgets('chips and search report changes', (tester) async {
    await pump(tester, query: 'cal');
    await tester.tap(find.text('Cafés'));
    await tester.enterText(find.byKey(const ValueKey('spots-search')), 'lag');
    await tester.tap(find.byKey(const ValueKey('spots-search-clear')));
    expect(events, ['category:cafe', 'query:lag', 'query:']);
  });

  testWidgets('a card shows name, category and price, then expands', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Capitol Park and Lagoon'), findsOneWidget);
    expect(find.text('Parks · Price unknown'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('spot-details-a')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('spot-toggle-a')));
    await _step(tester);
    expect(find.byKey(const ValueKey('spot-details-a')), findsOneWidget);
    expect(find.text('Capitol Park and Lagoon description.'), findsOneWidget);
    expect(
      find.text('Capitol Park and Lagoon St, Bacolod City'),
      findsOneWidget,
    );
    expect(find.text('45 mins'), findsOneWidget);
    expect(find.text('#heritage'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spot-save-a')));
    await tester.tap(find.byKey(const ValueKey('spot-rate-a')));
    expect(events, ['save:a', 'rate:a']);

    // Opening another card closes the first.
    await tester.tap(find.byKey(const ValueKey('spot-toggle-c')));
    await _step(tester);
    expect(find.byKey(const ValueKey('spot-details-a')), findsNothing);
    expect(find.byKey(const ValueKey('spot-details-c')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spot-less-c')));
    await _step(tester);
    expect(find.byKey(const ValueKey('spot-details-c')), findsNothing);
  });

  testWidgets('the heart saves without expanding', (tester) async {
    await pump(tester, saved: {'b'});
    await tester.tap(find.byKey(const ValueKey('spot-heart-a')));
    await _step(tester);
    expect(events, ['save:a']);
    expect(find.byKey(const ValueKey('spot-details-a')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spot-heart-b')),
        matching: find.byIcon(Icons.favorite_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no matches offers Show all places', (tester) async {
    await pump(tester, places: const [], query: 'zzz');
    expect(find.byKey(const ValueKey('spots-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spots-show-all')));
    expect(events, ['query:', 'category:all']);
  });

  testWidgets('the saved view has its own title and a way back', (
    tester,
  ) async {
    await pump(tester, savedOnly: true, places: [_places.first]);
    expect(find.text('Your picks'), findsOneWidget);
    expect(find.text('1 place you liked or saved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spots-exit-saved')));
    expect(events, ['exit-saved']);
  });

  testWidgets('a places state replaces the cards', (tester) async {
    await pump(tester, placesState: const Text('Loading Bacolod places…'));
    expect(find.text('Loading Bacolod places…'), findsOneWidget);
    expect(find.byKey(const ValueKey('spot-a')), findsNothing);
  });
}
