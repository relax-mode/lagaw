import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/models/onboarding_preferences.dart';
import 'package:frontend/screens/spots/spots_view.dart';
import 'package:frontend/screens/you_tab.dart';
import 'package:frontend/services/onboarding_repository.dart';

LocationItem _loc(String id, String name) => LocationItem.fromJson({
  'id': id,
  'name': name,
  'description': '$name description.',
  'category': 'cafe',
  'vibe_tags': ['cafe'],
  'address': '$name St',
  'estimated_cost_min': null,
  'estimated_cost_max': null,
  'typical_visit_duration': 30,
});

void main() {
  late List<String> events;

  Future<void> pump(
    WidgetTester tester, {
    OnboardingPreferences? prefs,
    List<LocationItem> picks = const [],
  }) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    events = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.blue,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: YouTab(
              session: null,
              likedCount: picks.length,
              onOpenSaved: () => events.add('see-all'),
              picks: picks,
              actions: PlaceActions(
                isSaved: (_) => true,
                isBusy: (_) => false,
                ratingFor: (_) => null,
                onSave: (p) => events.add('save:${p.id}'),
                onRate: (p) => events.add('rate:${p.id}'),
              ),
              preferences: prefs == null
                  ? null
                  : () => MockOnboardingRepository(
                      delay: Duration.zero,
                      initial: prefs,
                    ),
              onExplore: () => events.add('explore'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('display name comes from the email', () {
    expect(displayNameFrom('roel.jr@example.com'), 'Roel');
    expect(displayNameFrom('kyle_23@x.ph'), 'Kyle');
    expect(displayNameFrom(null), 'Guest');
  });

  testWidgets('no preferences yet offers to take them', (tester) async {
    await pump(tester, prefs: OnboardingPreferences.empty);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.byKey(const ValueKey('you-take-preferences')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-preferences-summary')), findsNothing);
    expect(find.byKey(const ValueKey('you-picks-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('you-explore')));
    expect(events, ['explore']);
  });

  testWidgets('saved preferences show in full with Edit', (tester) async {
    await pump(
      tester,
      prefs: const OnboardingPreferences(
        preferredTags: ['cafe', 'heritage'],
        budgetMin: '500.00',
        budgetMax: '2000.00',
        travelStyle: 'slow',
      ),
    );
    expect(
      find.byKey(const ValueKey('you-preferences-summary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('you-preferences')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-take-preferences')), findsNothing);
    // Interests show under the name and in the card.
    expect(find.text('Café'), findsNWidgets(2));
    expect(find.text('₱500 – ₱2,000'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);
  });

  testWidgets('shows two picks as Spots cards and See all', (tester) async {
    await pump(
      tester,
      picks: [_loc('a', 'Calea'), _loc('b', 'Cafetolyo'), _loc('c', 'Arima')],
    );
    expect(find.byKey(const ValueKey('you-pick-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-pick-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('you-pick-c')), findsNothing);
    expect(find.text('See all 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('you-saved')));
    expect(events, ['see-all']);

    // A pick opens the same pop-up as on Spots.
    await tester.tap(find.byKey(const ValueKey('spot-toggle-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('spot-details-a')), findsOneWidget);
  });

  testWidgets('the pencil says photos are coming soon', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('you-edit-photo')));
    await tester.pump();
    expect(find.text('Changing your photo is coming soon.'), findsOneWidget);
  });
}
