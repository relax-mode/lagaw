import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/models/trip.dart';
import 'package:frontend/models/trip_item.dart';
import 'package:frontend/screens/trip_create_screen.dart';
import 'package:frontend/screens/trip_detail_screen.dart';
import 'package:frontend/screens/trip_edit_screen.dart';
import 'package:frontend/screens/trips_tab.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/trip_service.dart';

Trip _trip(String id, String title) => Trip(
  id: id,
  userId: 'user-1',
  status: 'draft',
  title: title,
  startDate: DateTime(2026, 11, 7),
  endDate: DateTime(2026, 11, 8),
  budgetMin: 1500,
  budgetMax: 3000,
  transportationMode: 'jeepney',
  groupType: 'friends',
  preferredTags: const ['food'],
);

/// In-memory stand-in for the trip API; queue errors to simulate failures.
class FakeTripService extends TripService {
  final List<Trip> trips;
  final List<Exception> errors = [];
  final List<TripDraft> created = [];
  final List<TripDraft> updated = [];
  final List<String> deleted = [];

  /// Itinerary items keyed by trip id; queue [itemErrors] to fail item calls.
  final Map<String, List<TripItem>> items = {};
  final List<Exception> itemErrors = [];
  final List<String> itemCallTrips = [];
  var _itemSeq = 0;

  FakeTripService([List<Trip>? trips])
    : trips = trips ?? [],
      super(token: 'fake');

  void _maybeFail() {
    if (errors.isNotEmpty) throw errors.removeAt(0);
  }

  void _maybeFailItem(String tripId) {
    itemCallTrips.add(tripId);
    if (itemErrors.isNotEmpty) throw itemErrors.removeAt(0);
  }

  @override
  Future<List<TripItem>> listTripItems(String tripId) async {
    _maybeFailItem(tripId);
    return [...items[tripId] ?? const <TripItem>[]];
  }

  @override
  Future<TripItem> addTripItem(
    String tripId, {
    required String locationId,
    required int dayNumber,
    required int visitOrder,
  }) async {
    _maybeFailItem(tripId);
    final location = _locations.firstWhere((l) => l.id == locationId);
    final item = TripItem(
      id: 'item-${++_itemSeq}',
      tripId: tripId,
      locationId: locationId,
      dayNumber: dayNumber,
      visitOrder: visitOrder,
      location: location,
    );
    items.putIfAbsent(tripId, () => []).add(item);
    return item;
  }

  @override
  Future<void> removeTripItem(String tripId, String itemId) async {
    _maybeFailItem(tripId);
    items[tripId]?.removeWhere((i) => i.id == itemId);
  }

  @override
  Future<Trip> createTrip(TripDraft draft) async {
    _maybeFail();
    created.add(draft);
    final trip = Trip(
      id: 'trip-${trips.length + 1}',
      userId: 'user-1',
      status: 'draft',
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      budgetMin: draft.budgetMin,
      budgetMax: draft.budgetMax,
      transportationMode: draft.transportationMode,
      groupType: draft.groupType,
      preferredTags: draft.preferredTags,
    );
    trips.add(trip);
    return trip;
  }

  @override
  Future<TripsPage> listTrips({int limit = 10, int offset = 0}) async {
    _maybeFail();
    return TripsPage(
      items: trips.skip(offset).take(limit).toList(),
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<void> deleteTrip(String id) async {
    _maybeFail();
    final before = trips.length;
    trips.removeWhere((t) => t.id == id);
    deleted.add(id);
    if (trips.length == before) {
      throw const TripApiException('Trip not found.', statusCode: 404);
    }
  }

  @override
  Future<Trip> getTrip(String id) async {
    _maybeFail();
    return trips.firstWhere(
      (t) => t.id == id,
      orElse: () =>
          throw const TripApiException('Trip not found.', statusCode: 404),
    );
  }

  @override
  Future<Trip> updateTrip(
    String id,
    TripDraft draft, {
    TripDraft? original,
  }) async {
    _maybeFail();
    updated.add(draft);
    final index = trips.indexWhere((t) => t.id == id);
    final current = trips[index];
    final saved = Trip(
      id: current.id,
      userId: current.userId,
      status: current.status,
      title: draft.title,
      startDate: draft.startDate,
      endDate: draft.endDate,
      budgetMin: draft.budgetMin,
      budgetMax: draft.budgetMax,
      transportationMode: draft.transportationMode,
      groupType: draft.groupType,
      preferredTags: draft.preferredTags,
    );
    trips[index] = saved;
    return saved;
  }
}

LocationItem _location(String id, String name, String category) =>
    LocationItem.fromJson({
      'id': id,
      'name': name,
      'category': category,
      'address': '$name Rd, Bacolod City',
      'estimated_cost_min': 0,
      'estimated_cost_max': 0,
      'typical_visit_duration': 45,
    });

final _locations = [
  _location('loc-cathedral', 'San Sebastian Cathedral', 'heritage'),
  _location('loc-museum', 'The Negros Museum', 'museum'),
];

/// Stand-in for `GET /locations`; set [fail] to simulate an outage.
class FakeLocationsService extends ApiService {
  bool fail = false;

  @override
  Future<List<LocationItem>> fetchAllLocations() async {
    if (fail) throw Exception('offline');
    return _locations;
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Widget _tab(FakeTripService service) => Scaffold(
  backgroundColor: Colors.blue,
  body: SingleChildScrollView(child: TripsTab(service: service, isWide: false)),
);

/// Scrolls a keyed widget into view (pages are lazy ListViews), then taps it.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillNewTrip(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('trip-title')).last,
    'Sunset at the Ruins',
  );
  await _tapKey(tester, 'trip-dates');
  await tester.pumpAndSettle();
  // Type the range in the picker's input mode; next year is always valid.
  final year = DateTime.now().year + 1;
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  final count = fields.evaluate().length;
  await tester.enterText(fields.at(count - 2), '11/10/$year');
  await tester.enterText(fields.at(count - 1), '11/11/$year');
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('trip-budget-min')).last,
    '800',
  );
  await tester.enterText(
    find.byKey(const ValueKey('trip-budget-max')).last,
    '1,200',
  );
  await _tapKey(tester, 'chip-couple');
  await tester.pumpAndSettle();
}

void main() {
  group('TripsTab', () {
    testWidgets('shows the empty state with a create button', (tester) async {
      await _pump(tester, _tab(FakeTripService()));

      expect(find.text('No trips yet'), findsOneWidget);
      expect(find.text('0 saved trips'), findsOneWidget);
    });

    testWidgets('lists saved trips', (tester) async {
      await _pump(
        tester,
        _tab(
          FakeTripService([
            _trip('a', 'Food crawl'),
            _trip('b', 'Heritage walk'),
          ]),
        ),
      );

      expect(find.text('Food crawl'), findsOneWidget);
      expect(find.text('Heritage walk'), findsOneWidget);
      expect(find.text('2 saved trips'), findsOneWidget);
      expect(find.textContaining('Nov 7 – 8, 2026'), findsNWidgets(2));
    });

    testWidgets('error state retries', (tester) async {
      final service = FakeTripService([_trip('a', 'Food crawl')])
        ..errors.add(
          const TripApiException('Trips are temporarily unavailable.'),
        );
      await _pump(tester, _tab(service));

      expect(find.text('Trips are temporarily unavailable.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Food crawl'), findsOneWidget);
    });

    testWidgets('create flow saves, shows detail, then lists the trip', (
      tester,
    ) async {
      final service = FakeTripService();
      await _pump(tester, _tab(service));

      await _tapKey(tester, 'trips-create');
      await tester.pumpAndSettle();
      await _fillNewTrip(tester);
      await _tapKey(tester, 'trip-submit');
      await tester.pumpAndSettle();

      expect(service.created.single.title, 'Sunset at the Ruins');
      expect(service.created.single.budgetMax, 1200);
      expect(service.created.single.groupType, 'couple');
      expect(find.textContaining('Trip saved!'), findsOneWidget);

      await _tapKey(tester, 'trip-back');
      await tester.pumpAndSettle();
      expect(find.text('Sunset at the Ruins'), findsOneWidget);
      expect(find.text('1 saved trip'), findsOneWidget);
    });
  });

  group('TripCreateScreen', () {
    testWidgets('shows backend field errors on the fields', (tester) async {
      final service = FakeTripService()
        ..errors.add(
          const TripApiException(
            'Some trip details need fixing.',
            statusCode: 422,
            fieldErrors: {'title': 'Title is already taken'},
          ),
        );
      await _pump(tester, TripCreateScreen(service: service));

      await _fillNewTrip(tester);
      await _tapKey(tester, 'trip-submit');
      await tester.pumpAndSettle();

      expect(find.text('Some trip details need fixing.'), findsOneWidget);
      expect(find.text('Title is already taken'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('server outage offers retry that succeeds', (tester) async {
      final service = FakeTripService()
        ..errors.add(
          const TripApiException('Trips are temporarily unavailable.'),
        );
      await _pump(tester, TripCreateScreen(service: service));

      await _fillNewTrip(tester);
      await _tapKey(tester, 'trip-submit');
      await tester.pumpAndSettle();
      expect(find.text('Trips are temporarily unavailable.'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(service.created, hasLength(1));
      expect(find.textContaining('Trip saved!'), findsOneWidget);
    });
  });

  group('TripEditScreen', () {
    testWidgets('pre-fills, skips no-op saves, then saves and returns', (
      tester,
    ) async {
      final service = FakeTripService([_trip('a', 'Food crawl')]);
      await _pump(tester, _tab(service));

      // List -> detail -> edit, the real navigation path.
      await tester.tap(find.text('Food crawl'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'trip-edit');
      expect(find.text('1500'), findsOneWidget);

      await _tapKey(tester, 'trip-submit');
      expect(find.text('No changes to save yet.'), findsOneWidget);
      expect(service.updated, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('trip-title')).last,
        'Food crawl v2',
      );
      await _tapKey(tester, 'trip-submit');

      expect(service.updated.single.title, 'Food crawl v2');
      expect(find.text('Changes saved.'), findsOneWidget);
      expect(find.text('Food crawl v2'), findsWidgets);

      await _tapKey(tester, 'trip-back');
      expect(find.text('Food crawl v2'), findsOneWidget);
    });

    testWidgets('409 conflict offers reload that resets the form', (
      tester,
    ) async {
      final service = FakeTripService([_trip('a', 'Food crawl')]);
      await _pump(tester, TripEditScreen(service: service, tripId: 'a'));

      await tester.enterText(
        find.byKey(const ValueKey('trip-title')).last,
        'Edited locally',
      );
      service.errors.add(
        const TripApiException(
          'This trip changed. Reload it.',
          statusCode: 409,
        ),
      );
      await _tapKey(tester, 'trip-submit');
      expect(find.text('This trip changed. Reload it.'), findsOneWidget);

      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Edited locally'), findsNothing);
      expect(find.text('Food crawl'), findsWidgets);
    });

    testWidgets('missing trip shows error with retry', (tester) async {
      await _pump(
        tester,
        TripEditScreen(service: FakeTripService(), tripId: 'x'),
      );

      expect(find.text('Trip not found.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  test('changedFieldsFrom reports only differing API fields', () {
    final original = _trip('a', 'Food crawl');
    final edited = TripDraft(
      title: 'Food crawl',
      startDate: original.startDate,
      endDate: original.endDate,
      budgetMin: 1500,
      budgetMax: 3500,
      transportationMode: 'jeepney',
      groupType: null,
      preferredTags: const ['food'],
    );

    expect(original.changedFieldsFrom(original), isEmpty);
    expect(edited.changedFieldsFrom(original), {'budget_max', 'group_type'});
  });

  group('Delete flow [S2-05]', () {
    Future<FakeTripService> openFirstTrip(
      WidgetTester tester,
      List<Trip> trips,
    ) async {
      final service = FakeTripService(trips);
      await _pump(tester, _tab(service));
      await tester.tap(find.text(trips.first.title));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('cancelling the confirmation keeps the trip', (tester) async {
      final service = await openFirstTrip(tester, [_trip('a', 'Food crawl')]);

      await _tapKey(tester, 'trip-delete');
      expect(find.text('Delete this trip?'), findsOneWidget);
      expect(find.textContaining('"Food crawl"'), findsOneWidget);
      await _tapKey(tester, 'confirm-cancel');

      expect(service.deleted, isEmpty);
      expect(find.text('Delete this trip?'), findsNothing);
      expect(find.byKey(const ValueKey('trip-edit')), findsOneWidget);
    });

    testWidgets('confirming deletes and the trip leaves the list', (
      tester,
    ) async {
      final service = await openFirstTrip(tester, [
        _trip('a', 'Food crawl'),
        _trip('b', 'Heritage walk'),
      ]);

      await _tapKey(tester, 'trip-delete');
      await _tapKey(tester, 'confirm-accept');

      expect(service.deleted, ['a']);
      expect(find.text('Trip deleted.'), findsOneWidget);
      expect(find.text('Food crawl'), findsNothing);
      expect(find.text('Heritage walk'), findsOneWidget);
      expect(find.text('1 saved trip'), findsOneWidget);
    });

    testWidgets('a failed delete stays on the trip with the error', (
      tester,
    ) async {
      final service = await openFirstTrip(tester, [_trip('a', 'Food crawl')]);
      service.errors.add(
        const TripApiException('Trips are temporarily unavailable.'),
      );

      await _tapKey(tester, 'trip-delete');
      await _tapKey(tester, 'confirm-accept');

      expect(find.text('Trips are temporarily unavailable.'), findsOneWidget);
      expect(service.trips, hasLength(1));
      expect(find.byKey(const ValueKey('trip-delete')), findsOneWidget);
    });

    testWidgets('deleting a trip already gone elsewhere still returns', (
      tester,
    ) async {
      final service = await openFirstTrip(tester, [_trip('a', 'Food crawl')]);
      service.trips.clear(); // removed on another device

      await _tapKey(tester, 'trip-delete');
      await _tapKey(tester, 'confirm-accept');

      expect(find.text('Trip deleted.'), findsOneWidget);
      expect(find.text('No trips yet'), findsOneWidget);
    });

    testWidgets('opening a trip deleted elsewhere explains and goes back', (
      tester,
    ) async {
      final service = FakeTripService([_trip('a', 'Food crawl')]);
      await _pump(tester, _tab(service));
      service.trips.clear();

      await tester.tap(find.text('Food crawl'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer exists'), findsOneWidget);

      await tester.tap(find.text('Back to My Trips'));
      await tester.pumpAndSettle();
      expect(find.text('No trips yet'), findsOneWidget);
    });

    testWidgets('detail pops the deleted result', (tester) async {
      final service = FakeTripService([_trip('a', 'Food crawl')]);
      Object? result;
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      TripDetailScreen(service: service, tripId: 'a'),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'trip-delete');
      await _tapKey(tester, 'confirm-accept');

      expect(result, TripDetailResult.deleted);
    });
  });

  group('Itinerary locations', () {
    Future<(FakeTripService, FakeLocationsService)> openDetail(
      WidgetTester tester, {
      void Function(FakeTripService)? setup,
    }) async {
      final service = FakeTripService([
        _trip('a', 'Food crawl'),
        _trip('b', 'Heritage walk'),
      ]);
      final locations = FakeLocationsService();
      setup?.call(service);
      await _pump(
        tester,
        TripDetailScreen(service: service, tripId: 'a', locations: locations),
      );
      return (service, locations);
    }

    TripItem item(String id, String tripId, LocationItem loc, int day, int n) =>
        TripItem(
          id: id,
          tripId: tripId,
          locationId: loc.id,
          dayNumber: day,
          visitOrder: n,
          location: loc,
        );

    testWidgets('shows the empty state for a trip without items', (
      tester,
    ) async {
      await openDetail(tester);

      expect(find.text('Itinerary Locations'), findsOneWidget);
      expect(find.byKey(const ValueKey('itinerary-empty')), findsOneWidget);
      expect(find.text('No destinations yet'), findsOneWidget);
    });

    testWidgets('lists saved items grouped by day with location details', (
      tester,
    ) async {
      await openDetail(
        tester,
        setup: (s) => s.items['a'] = [
          item('i1', 'a', _locations[0], 1, 1),
          item('i2', 'a', _locations[1], 2, 1),
        ],
      );

      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);
      expect(find.text('San Sebastian Cathedral'), findsOneWidget);
      expect(find.text('The Negros Museum'), findsOneWidget);
      expect(find.text('Heritage'), findsOneWidget);
      expect(
        find.text('San Sebastian Cathedral Rd, Bacolod City'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('itinerary-empty')), findsNothing);
    });

    testWidgets('a failed load shows the error and Retry recovers', (
      tester,
    ) async {
      final (service, _) = await openDetail(
        tester,
        setup: (s) => s.itemErrors.add(
          const TripApiException('The server took too long to respond.'),
        ),
      );
      expect(find.byKey(const ValueKey('itinerary-error')), findsOneWidget);
      // The trip details themselves still render.
      expect(find.byKey(const ValueKey('trip-edit')), findsOneWidget);

      service.items['a'] = [item('i1', 'a', _locations[0], 1, 1)];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('itinerary-error')), findsNothing);
      expect(find.text('San Sebastian Cathedral'), findsOneWidget);
    });

    testWidgets('adds a picked destination to the chosen day and refreshes', (
      tester,
    ) async {
      final (service, _) = await openDetail(tester);

      await _tapKey(tester, 'itinerary-add');
      expect(find.text('Add a destination'), findsOneWidget);
      await _tapKey(tester, 'picker-day-2');
      await _tapKey(tester, 'destination-loc-museum');
      await _tapKey(tester, 'picker-submit');

      expect(find.text('Add a destination'), findsNothing);
      final saved = service.items['a']!.single;
      expect(saved.locationId, 'loc-museum');
      expect(saved.dayNumber, 2);
      expect(saved.visitOrder, 1);
      expect(find.text('Added The Negros Museum to Day 2.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('itinerary-item-item-1')),
        findsOneWidget,
      );
      // Only the opened trip was touched.
      expect(service.items['b'], isNull);
      expect(service.itemCallTrips.toSet(), {'a'});
    });

    testWidgets('next stop number follows the day\'s last stop', (
      tester,
    ) async {
      final (service, _) = await openDetail(
        tester,
        setup: (s) => s.items['a'] = [item('i1', 'a', _locations[0], 1, 3)],
      );

      await _tapKey(tester, 'itinerary-add');
      expect(find.text('Day · stop #4'), findsOneWidget);
      await _tapKey(tester, 'destination-loc-cathedral');
      await _tapKey(tester, 'picker-submit');

      expect(service.items['a']!.last.visitOrder, 4);
    });

    testWidgets('API errors stay in the picker and keep the selection', (
      tester,
    ) async {
      final (service, _) = await openDetail(tester);
      await _tapKey(tester, 'itinerary-add');
      await _tapKey(tester, 'destination-loc-cathedral');
      service.itemErrors.add(
        const TripApiException(
          'Some trip details need fixing.',
          statusCode: 422,
          fieldErrors: {
            'day_number': "day_number must be within the trip's dates.",
          },
        ),
      );
      await _tapKey(tester, 'picker-submit');

      expect(
        find.text("day_number must be within the trip's dates."),
        findsOneWidget,
      );
      expect(find.text('Add a destination'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(service.items['a'], isNull);

      // A retry from the same sheet succeeds.
      await _tapKey(tester, 'picker-submit');
      expect(service.items['a'], hasLength(1));
    });

    testWidgets('picker shows a retryable error when locations fail', (
      tester,
    ) async {
      final (_, locations) = await openDetail(tester);
      locations.fail = true;
      await _tapKey(tester, 'itinerary-add');
      expect(find.byKey(const ValueKey('picker-load-error')), findsOneWidget);

      locations.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('The Negros Museum'), findsOneWidget);
    });

    testWidgets('cancelling removal keeps the item', (tester) async {
      final (service, _) = await openDetail(
        tester,
        setup: (s) => s.items['a'] = [item('i1', 'a', _locations[0], 1, 1)],
      );

      await _tapKey(tester, 'itinerary-remove-i1');
      expect(find.text('Remove this destination?'), findsOneWidget);
      await _tapKey(tester, 'confirm-cancel');

      expect(service.items['a'], hasLength(1));
      expect(find.text('San Sebastian Cathedral'), findsOneWidget);
    });

    testWidgets('confirming removal deletes only that item', (tester) async {
      final (service, _) = await openDetail(
        tester,
        setup: (s) {
          s.items['a'] = [
            item('i1', 'a', _locations[0], 1, 1),
            item('i2', 'a', _locations[1], 1, 2),
          ];
          s.items['b'] = [item('i3', 'b', _locations[0], 1, 1)];
        },
      );

      await _tapKey(tester, 'itinerary-remove-i1');
      await _tapKey(tester, 'confirm-accept');

      expect(service.items['a']!.map((i) => i.id), ['i2']);
      expect(service.items['b'], hasLength(1));
      expect(find.text('Removed San Sebastian Cathedral.'), findsOneWidget);
      expect(find.byKey(const ValueKey('itinerary-item-i1')), findsNothing);
      expect(find.byKey(const ValueKey('itinerary-item-i2')), findsOneWidget);
    });

    testWidgets('a failed removal shows the error and keeps the list', (
      tester,
    ) async {
      final (service, _) = await openDetail(
        tester,
        setup: (s) => s.items['a'] = [item('i1', 'a', _locations[0], 1, 1)],
      );
      service.itemErrors.add(
        const TripApiException('Trips are temporarily unavailable.'),
      );

      await _tapKey(tester, 'itinerary-remove-i1');
      await _tapKey(tester, 'confirm-accept');

      expect(find.text('Trips are temporarily unavailable.'), findsOneWidget);
      expect(find.byKey(const ValueKey('itinerary-item-i1')), findsOneWidget);
      expect(service.items['a'], hasLength(1));
    });
  });

  testWidgets('My Trips pages past 50 trips with Load more', (tester) async {
    final service = FakeTripService([
      for (var i = 0; i < 55; i++) _trip('t$i', 'Trip $i'),
    ]);
    await _pump(tester, _tab(service));

    expect(find.text('50+ saved trips'), findsOneWidget);
    await _tapKey(tester, 'trips-load-more');

    expect(find.text('55 saved trips'), findsOneWidget);
    expect(find.byKey(const ValueKey('trips-load-more')), findsNothing);
  });

  test('service refuses to call the API without a demo token', () async {
    final service = TripService(token: '');

    await expectLater(
      service.listTrips(),
      throwsA(
        isA<TripApiException>().having(
          (e) => e.message,
          'message',
          contains('TRIP_DEMO_TOKEN'),
        ),
      ),
    );
  });
}
