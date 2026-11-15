import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/greeting_pill.dart';
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
    test('merges expanded aliases with existing categories and clean labels', () {
      final places = [
        _loc('orange', 'gallery'),
        _loc('artfull', 'art_gallery'),
        _loc('arima', 'restaurant'),
        _loc('quan', 'local_food'),
        _loc('palawud', 'seaside_dining'),
        _loc('bowling', 'evening_bowling'),
        _loc('arcade', 'arcade_recreation'),
        _loc('mall', 'shopping_leisure'),
        _loc('books', 'bookstore_leisure'),
        _loc('pool', 'waterpark'),
      ];
      final cats = HomeCategory.fromLocations(
        places,
        credits: ImageCredits(const []),
      );
      final counts = {for (final cat in cats) cat.id: cat.count};
      expect(counts, {
        'gallery': 2,
        'restaurant': 3,
        'recreation': 2,
        'shopping': 2,
        'resort': 1,
      });
      expect(places[1].id, 'artfull');
      expect(places[1].category, 'gallery');
      expect(HomeCategory.labelFor('art_gallery'), 'Art');
      expect(HomeCategory.labelFor('local_food'), 'Dining');
      expect(HomeCategory.labelFor('recreation'), 'Activities');
      expect(HomeCategory.labelFor('shopping'), 'Shopping');
      expect(HomeCategory.labelFor('resort'), 'Resorts');
      expect(HomeCategory.labelFor('future_local_spot'), 'Future Local Spot');
    });

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
    await tester.pumpWidget(_app(const YouTab(session: null, likedCount: 2)));
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('2 places liked and saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('you-sign-out')), findsNothing);
    // See all expands on You itself.
    await tester.tap(find.byKey(const ValueKey('you-saved')));
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  test('every category reads as words, including new ones', () {
    // Finer catalogue categories group into broad ones (#186).
    expect(HomeCategory.labelFor('local_food'), 'Dining');
    expect(HomeCategory.labelFor('coastal_day_resort'), 'Resorts');
    expect(HomeCategory.labelFor('brand_new_kind'), 'Brand New Kind');
    final cover = LocationItem.fromJson({'id': 'x', 'name': 'X'});
    expect(
      HomeCategory(id: 'garden_farm_tourism', count: 2, cover: cover).seeLabel,
      'See 2 parks',
    );
    expect(
      HomeCategory(id: 'new_thing', count: 1, cover: cover).word,
      'new thing',
    );
  });

  testWidgets('the pill only animates when it folds or unfolds', (
    tester,
  ) async {
    await _size(tester);
    Widget pill(bool collapsed) => MaterialApp(
      home: Scaffold(
        body: GreetingPill(
          avatarLetter: 'R',
          likedCount: 0,
          onSearch: () {},
          onSaved: () {},
          onAccount: () {},
          collapsed: collapsed,
        ),
      ),
    );
    double width() => tester
        .getSize(
          find
              .descendant(
                of: find.byType(GreetingPill),
                matching: find.byType(Container),
              )
              .first,
        )
        .width;

    // A page that opens collapsed shows just the heart at once.
    await tester.pumpWidget(pill(true));
    final folded = width();
    expect(folded, lessThan(80));

    // Staying collapsed (Spots to Trips) never moves.
    await tester.pumpWidget(pill(true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(width(), folded);

    // Going Home unfolds smoothly, then settles full width.
    await tester.pumpWidget(pill(false));
    await tester.pump(const Duration(milliseconds: 300));
    final midway = width();
    expect(midway, greaterThan(folded));
    await tester.pumpAndSettle();
    expect(width(), greaterThan(midway));
  });
}
