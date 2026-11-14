import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/image_credits.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/screens/home/home_view.dart';
import 'package:frontend/screens/you_tab.dart';
import 'package:frontend/widgets/lagaw_nav_bar.dart';

LocationItem _loc(String id, String category, {String? image}) =>
    LocationItem.fromJson({
      'id': id,
      'name': 'Place $id',
      'category': category,
      'image_url': image,
    });

final _places = [
  _loc('p1', 'park'),
  _loc('p2', 'park'),
  _loc('p3', 'park'),
  _loc('c1', 'cafe'),
  _loc('c2', 'cafe'),
  _loc('h1', 'heritage'),
];

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Scaffold(backgroundColor: Colors.blue, body: child),
    ),
  ),
);

Future<void> _size(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('greets by time of day in Hiligaynon', () {
    expect(hiligaynonGreeting(DateTime(2026, 1, 1, 7)), 'Maayong aga,');
    expect(hiligaynonGreeting(DateTime(2026, 1, 1, 12)), 'Maayong udto,');
    expect(hiligaynonGreeting(DateTime(2026, 1, 1, 15)), 'Maayong hapon,');
    expect(hiligaynonGreeting(DateTime(2026, 1, 1, 20)), 'Maayong gab-i,');
    expect(hiligaynonGreeting(DateTime(2026, 1, 1, 2)), 'Maayong gab-i,');
  });

  group('HomeCategory', () {
    test('groups real places, largest first, with honest labels', () {
      final cats = HomeCategory.fromLocations(
        _places,
        credits: ImageCredits(const []),
      );
      expect(cats.map((c) => c.id), ['park', 'cafe', 'heritage']);
      expect(HomeCategory.startPage(cats), 2);
      expect(cats.map((c) => c.count), [3, 2, 1]);
      expect(cats[0].word, 'parks');
      expect(cats[0].seeLabel, 'See 3 parks');
      expect(cats[1].seeLabel, 'See 2 cafés');
      expect(cats[2].seeLabel, 'See 1 heritage spot');
      expect(cats[2].countLabel, '1 spot');
      expect(cats[0].countLabel, '3 spots');
    });

    test('starts on heritage, or the middle card without one', () {
      final noHeritage = HomeCategory.fromLocations(
        _places.where((p) => p.category != 'heritage').toList(),
        credits: ImageCredits(const []),
      );
      expect(HomeCategory.startPage(noHeritage), 1);
    });

    test('prefers a place with an approved photo as the cover', () {
      final sha = 'a' * 64;
      const id = '1a3bca09-5532-5de6-8587-2440c4e5830d';
      final url =
          'https://x.supabase.co/storage/v1/object/public/destination-images/'
          'locations/$id/$sha.jpg';
      final cats = HomeCategory.fromLocations(
        [_loc('other', 'heritage'), _loc(id, 'heritage', image: url)],
        credits: ImageCredits([
          ImageCredit(
            locationId: id,
            sha256: sha,
            primary: true,
            attribution: 'Photo: A',
            photographer: 'A',
            license: 'CC BY 4.0',
          ),
        ]),
      );
      expect(cats.single.cover.id, id);
    });
  });

  group('HomeView', () {
    Future<List<String>> pump(
      WidgetTester tester, {
      List<LocationItem>? places,
      int liked = 0,
      Widget? placesState,
    }) async {
      await _size(tester);
      final seen = <String>[];
      final list = places ?? _places;
      await tester.pumpWidget(
        _app(
          HomeView(
            avatarLetter: 'R',
            spotCount: list.length,
            likedCount: liked,
            categories: HomeCategory.fromLocations(
              list,
              credits: ImageCredits(const []),
            ),
            placesState: placesState,
            clock: () => DateTime(2026, 11, 14, 15),
            onSearch: () => seen.add('search'),
            onSaved: () => seen.add('saved'),
            onAccount: () => seen.add('account'),
            onSeeCategory: (id) => seen.add('see:$id'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return seen;
    }

    testWidgets('shows greeting, headline, real counts and the see pill', (
      tester,
    ) async {
      await pump(tester, liked: 3);
      expect(find.text('Maayong hapon,'), findsOneWidget);
      expect(find.text('Bacolod City'), findsOneWidget);
      expect(find.text('6 spots to explore'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-headline')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // Opens on heritage so neighbors can peek from the side.
      expect(find.text('heritage'), findsOneWidget);
      expect(find.text('See 1 heritage spot'), findsOneWidget);
      expect(find.text('Maayong Aga, Roel!'), findsNothing);
    });

    testWidgets('the see pill and header buttons call back', (tester) async {
      final seen = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('home-see-category')));
      await tester.tap(find.byKey(const ValueKey('home-saved')));
      await tester.tap(find.byKey(const ValueKey('home-search')));
      await tester.tap(find.byKey(const ValueKey('home-account')));
      expect(seen, ['see:heritage', 'saved', 'search', 'account']);
    });

    testWidgets('the see pill follows the carousel', (tester) async {
      await pump(tester);
      await tester.drag(
        find.byKey(const ValueKey('home-carousel')),
        const Offset(260, 0),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('See 2 cafés'), findsOneWidget);
    });

    testWidgets('without places it shows the given state, no carousel', (
      tester,
    ) async {
      await pump(
        tester,
        places: const [],
        placesState: const Text('Loading Bacolod places…'),
      );
      expect(find.text('Loading Bacolod places…'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-carousel')), findsNothing);
      expect(find.text('0 spots to explore'), findsOneWidget);
    });
  });

  group('LagawNavBar and swipe menu', () {
    Future<(List<Object?>, NavDestination?)> pump(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      await _size(tester);
      final events = <Object?>[];
      await tester.pumpWidget(
        _app(
          reduceMotion: reduceMotion,
          Builder(
            builder: (context) => Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: LagawNavBar(
                  active: NavDestination.home,
                  onSelect: events.add,
                  onSwipe: () async =>
                      events.add(await showSwipeMenu(context, bottomInset: 16)),
                ),
              ),
            ),
          ),
        ),
      );
      return (events, NavDestination.home);
    }

    testWidgets('tabs select their destination', (tester) async {
      final (events, _) = await pump(tester);
      for (final d in [NavDestination.spots, NavDestination.trips]) {
        await tester.tap(find.byKey(ValueKey('nav-${d.name}')));
      }
      await tester.tap(find.byKey(const ValueKey('nav-you')));
      expect(events, [
        NavDestination.spots,
        NavDestination.trips,
        NavDestination.you,
      ]);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('the swipe button opens Start matching and Plan a trip', (
      tester,
    ) async {
      final (events, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('nav-swipe')));
      await tester.pumpAndSettle();
      expect(find.text('What do you feel like?'), findsOneWidget);
      expect(find.text('Start matching'), findsOneWidget);
      expect(find.text('Plan a trip'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('swipe-menu-plan')));
      await tester.pumpAndSettle();
      expect(events, [SwipeMenuChoice.planTrip]);
      expect(find.text('Plan a trip'), findsNothing);
    });

    testWidgets('tapping outside or the close button closes with nothing', (
      tester,
    ) async {
      final (events, _) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('nav-swipe')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 120));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('nav-swipe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swipe-menu-close')));
      await tester.pumpAndSettle();
      expect(events, [null, null]);
    });

    testWidgets('reduced motion still opens the menu, with a fade', (
      tester,
    ) async {
      final (events, _) = await pump(tester, reduceMotion: true);
      await tester.tap(find.byKey(const ValueKey('nav-swipe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('swipe-menu-start')));
      await tester.pumpAndSettle();
      expect(events, [SwipeMenuChoice.startMatching]);
    });
  });

  testWidgets('You tab without a session shows no sign out', (tester) async {
    await _size(tester);
    var opened = false;
    await tester.pumpWidget(
      _app(
        YouTab(session: null, likedCount: 2, onOpenSaved: () => opened = true),
      ),
    );
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('2 places'), findsOneWidget);
    expect(find.byKey(const ValueKey('you-sign-out')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('you-saved')));
    expect(opened, isTrue);
  });
}
