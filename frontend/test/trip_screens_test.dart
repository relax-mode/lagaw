import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/trip.dart';
import 'package:frontend/screens/trip_create_screen.dart';
import 'package:frontend/screens/trip_edit_screen.dart';
import 'package:frontend/screens/trips_tab.dart';
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

  FakeTripService([List<Trip>? trips])
    : trips = trips ?? [],
      super(token: 'fake');

  void _maybeFail() {
    if (errors.isNotEmpty) throw errors.removeAt(0);
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
    return TripsPage(items: List.of(trips), limit: limit, offset: offset);
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
