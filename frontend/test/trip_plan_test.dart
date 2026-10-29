import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/location.dart';
import 'package:frontend/models/trip.dart';
import 'package:frontend/models/trip_item.dart';
import 'package:frontend/models/trip_plan.dart';
import 'package:frontend/screens/trip_planner_screen.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:frontend/widgets/itinerary_section.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = 'test-token-0123456789abcdefghijklmnop';

Map<String, dynamic> _locationJson(String id, String name) => {
  'id': id,
  'name': name,
  'category': 'heritage',
  'address': '$name St, Bacolod City',
  'estimated_cost_min': 0,
  'estimated_cost_max': 100,
  'typical_visit_duration': 60,
};

Map<String, dynamic> _itemJson(String id, {bool generated = true}) => {
  'id': id,
  'trip_id': 'trip-1',
  'location_id': 'loc-1',
  'day_number': 1,
  'visit_order': 1,
  'location': _locationJson('loc-1', 'San Sebastian Cathedral'),
  'arrival_time': generated ? '09:00:00' : null,
  'departure_time': generated ? '10:30:00' : null,
  'estimated_travel_time': generated ? 15 : null,
  'estimated_cost': generated ? '120.00' : null,
  'recommendation_score': generated ? 0.91 : null,
  'recommendation_reason': generated ? 'Matches your heritage vibe.' : null,
};

Map<String, dynamic> _recJson(String id, String name, double score) => {
  'location_id': id,
  'recommendation_score': score,
  'recommendation_reason': '$name fits your trip.',
  'location': _locationJson(id, name),
};

const _options = PlanOptions(partySize: 2, plannedVisits: 3);

TripService _returning(int status, Object body) => TripService(
  token: _token,
  client: MockClient((_) async => http.Response(jsonEncode(body), status)),
);

Trip _trip({
  String? group = 'couple',
  List<String> tags = const ['heritage'],
  String? transport = 'jeepney',
}) => Trip(
  id: 'trip-1',
  userId: 'profile-1',
  status: 'draft',
  title: 'Heritage weekend',
  startDate: DateTime(2026, 11, 7),
  endDate: DateTime(2026, 11, 8),
  budgetMin: 500,
  budgetMax: 3000,
  transportationMode: transport,
  groupType: group,
  preferredTags: tags,
);

LocationItem _loc(String id, String name) =>
    LocationItem.fromJson(_locationJson(id, name));

TripRecommendation _rec(String id, String name, double score) =>
    TripRecommendation(
      locationId: id,
      score: score,
      reason: '$name fits your trip.',
      location: _loc(id, name),
    );

/// Mocked #52/#53/#54 API for the planner screen.
class FakePlanService extends TripService {
  final List<Object> recResponses = [];
  final List<Object> genResponses = [];
  final List<Exception> interactionErrors = [];
  final List<(String, InteractionType, double?)> interactions = [];
  final List<String?> genRevisions = [];
  int recCalls = 0;

  FakePlanService() : super(token: 'fake');

  @override
  Future<RecommendationsPage> recommendTrip(
    String tripId,
    PlanOptions options,
  ) async {
    recCalls++;
    final next = recResponses.length > 1
        ? recResponses.removeAt(0)
        : recResponses.first;
    if (next is Exception) throw next;
    return next as RecommendationsPage;
  }

  @override
  Future<GenerationResult> generateItinerary(
    String tripId,
    PlanOptions options, {
    String? expectedRevision,
  }) async {
    genRevisions.add(expectedRevision);
    final next = genResponses.removeAt(0);
    if (next is Exception) throw next;
    return next as GenerationResult;
  }

  @override
  Future<void> recordInteraction(
    String locationId,
    InteractionType type, {
    double? rating,
  }) async {
    if (interactionErrors.isNotEmpty) throw interactionErrors.removeAt(0);
    interactions.add((locationId, type, rating));
  }

  @override
  Future<List<TripItem>> listTripItems(String tripId) async => [];
}

final _generated = GenerationResult(
  estimatedTotalCost: 360,
  revision: 'a' * 32,
  items: [TripItem.fromJson(_itemJson('item-1'))],
);

void main() {
  group('Plan API client', () {
    test('recommendations post counts and parse reasons/scores', () async {
      late http.Request sent;
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'schema_version': '1',
              'trip_id': 'trip-1',
              'budget': {'budget_max': '500.00'},
              'items': [_recJson('loc-1', 'Cathedral', 0.9)],
              'empty_reason': null,
            }),
            200,
          );
        }),
      );

      final page = await service.recommendTrip('trip-1', _options);

      expect(sent.url.path, '/api/v1/trips/trip-1/recommendations');
      expect(jsonDecode(sent.body), {
        'party_size': 2,
        'planned_visits': 3,
        'limit': 20,
      });
      expect(page.items.single.reason, 'Cathedral fits your trip.');
      expect(page.items.single.score, 0.9);
      expect(page.budgetMax, 500);
    });

    test('empty recommendations keep their reason', () async {
      final page = await _returning(200, {
        'items': <Object>[],
        'empty_reason': 'no_compatible_locations',
      }).recommendTrip('trip-1', _options);

      expect(page.items, isEmpty);
      expect(page.emptyReason, 'no_compatible_locations');
    });

    test('generation sends replace flags only with a revision', () async {
      final bodies = <Map<String, dynamic>>[];
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'schema_version': '1',
              'trip_id': 'trip-1',
              'timezone': 'Asia/Manila',
              'estimated_total_cost': '360.00',
              'revision': 'b' * 32,
              'items': [_itemJson('item-1')],
            }),
            200,
          );
        }),
      );

      final result = await service.generateItinerary('trip-1', _options);
      await service.generateItinerary(
        'trip-1',
        _options,
        expectedRevision: 'c' * 32,
      );

      expect(bodies.first['replace_existing'], false);
      expect(bodies.first.containsKey('expected_revision'), isFalse);
      expect(bodies.first['recommendations']['planned_visits'], 3);
      expect(bodies.first['duration'], 'full_day');
      expect(bodies.last['replace_existing'], true);
      expect(bodies.last['expected_revision'], 'c' * 32);
      expect(result.estimatedTotalCost, 360);
      expect(result.items.single.arrivalTime, '09:00:00');
    });

    test('replacement 409 keeps code and revision', () async {
      await expectLater(
        _returning(409, {
          'detail': {
            'code': 'replacement_confirmation_required',
            'revision': 'd' * 32,
            'message': 'Confirm replacing all existing itinerary items.',
          },
        }).generateItinerary('trip-1', _options),
        throwsA(
          isA<PlanApiException>()
              .having((e) => e.needsReplacementConfirmation, 'confirm', true)
              .having((e) => e.revision, 'revision', 'd' * 32),
        ),
      );
    });

    test('infeasible 409 keeps counts and skipped reasons', () async {
      await expectLater(
        _returning(409, {
          'detail': {
            'code': 'requested_visits_do_not_fit',
            'scheduled_visits': 1,
            'requested_visits': 3,
            'skipped': {'loc-2': 'unknown_or_unsupported_opening_hours'},
            'message': 'No complete feasible itinerary. Saved data preserved.',
          },
        }).generateItinerary('trip-1', _options),
        throwsA(
          isA<PlanApiException>()
              .having((e) => e.isInfeasible, 'infeasible', true)
              .having((e) => e.message, 'message', contains('Only 1 of 3'))
              .having((e) => e.skipped, 'skipped', {
                'loc-2': 'unknown_or_unsupported_opening_hours',
              }),
        ),
      );
    });

    test('string 422 and 503 details are readable', () async {
      await expectLater(
        _returning(422, {
          'detail': 'Use approved saved tags and group type, and supported category constraints.',
        }).recommendTrip('trip-1', _options),
        throwsA(
          isA<PlanApiException>().having(
            (e) => e.message,
            'message',
            contains('approved saved tags'),
          ),
        ),
      );
      await expectLater(
        _returning(503, {
          'detail': 'Recommendations are temporarily unavailable.',
        }).generateItinerary('trip-1', _options),
        throwsA(
          isA<PlanApiException>().having(
            (e) => e.message,
            'message',
            contains('saved plan is unchanged'),
          ),
        ),
      );
    });

    test('interactions post the #52 shape', () async {
      final bodies = <Map<String, dynamic>>[];
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 201);
        }),
      );

      await service.recordInteraction('loc-1', InteractionType.save);
      await service.recordInteraction(
        'loc-1',
        InteractionType.rating,
        rating: 4,
      );

      expect(bodies.first, {
        'location_id': 'loc-1',
        'interaction_type': 'save',
      });
      expect(bodies.last, {
        'location_id': 'loc-1',
        'interaction_type': 'rating',
        'rating_value': 4.0,
      });
    });

    test('a retired location maps to a readable interaction error', () async {
      await expectLater(
        _returning(404, {
          'detail': 'Active location not found.',
        }).recordInteraction('loc-1', InteractionType.rightSwipe),
        throwsA(
          isA<TripApiException>().having(
            (e) => e.message,
            'message',
            contains('no longer available'),
          ),
        ),
      );
    });

    test('items parse generated fields and keep manual nulls', () {
      final generated = TripItem.fromJson(_itemJson('a'));
      final manual = TripItem.fromJson(_itemJson('b', generated: false));

      expect(generated.isScheduled, isTrue);
      expect(generated.estimatedCost, 120);
      expect(generated.estimatedTravelTime, 15);
      expect(manual.isScheduled, isFalse);
      expect(manual.estimatedCost, isNull);
      expect(manual.recommendationReason, isNull);
    });
  });

  group('Plan with AI screen', () {
    late FakePlanService service;

    Future<List<Object?>> pumpPlanner(WidgetTester tester, {Trip? trip}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final popped = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped.add(
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripPlannerScreen(
                        service: service,
                        trip: trip ?? _trip(),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    Future<void> tap(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    setUp(() => service = FakePlanService());

    testWidgets('shows ranked places with score and reason', (tester) async {
      service.recResponses.add(
        RecommendationsPage(
          items: [
            _rec('loc-1', 'San Sebastian Cathedral', 0.92),
            _rec('loc-2', 'The Negros Museum', 0.81),
          ],
        ),
      );
      await pumpPlanner(tester);
      await tap(tester, 'plan-recommend');

      expect(find.text('San Sebastian Cathedral'), findsOneWidget);
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('The Negros Museum fits your trip.'), findsOneWidget);
    });

    testWidgets('no matches shows the empty state', (tester) async {
      service.recResponses.add(
        const RecommendationsPage(
          items: [],
          emptyReason: 'no_compatible_locations',
        ),
      );
      await pumpPlanner(tester);
      await tap(tester, 'plan-recommend');

      expect(find.byKey(const ValueKey('plan-recs-empty')), findsOneWidget);
    });

    testWidgets('like and save are sent once and then shown as done', (
      tester,
    ) async {
      service.recResponses.add(
        RecommendationsPage(items: [_rec('loc-1', 'Cathedral', 0.9)]),
      );
      await pumpPlanner(tester);
      await tap(tester, 'plan-recommend');

      await tap(tester, 'rec-like-loc-1');
      await tap(tester, 'rec-like-loc-1');
      await tap(tester, 'rec-save-loc-1');

      expect(service.interactions.map((e) => e.$2), [
        InteractionType.rightSwipe,
        InteractionType.save,
      ]);
      expect(find.text('Liked'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('dislike confirms, records left swipe and refreshes', (
      tester,
    ) async {
      service.recResponses.addAll([
        RecommendationsPage(
          items: [
            _rec('loc-1', 'Cathedral', 0.9),
            _rec('loc-2', 'Museum', 0.8),
          ],
        ),
        RecommendationsPage(items: [_rec('loc-2', 'Museum', 0.85)]),
      ]);
      await pumpPlanner(tester);
      await tap(tester, 'plan-recommend');

      await tap(tester, 'rec-dislike-loc-1');
      expect(find.text('Not for you?'), findsOneWidget);
      await tap(tester, 'confirm-cancel');
      expect(service.interactions, isEmpty);

      await tap(tester, 'rec-dislike-loc-1');
      await tap(tester, 'confirm-accept');

      expect(service.interactions.single.$2, InteractionType.leftSwipe);
      expect(service.recCalls, 2);
      expect(find.byKey(const ValueKey('rec-loc-1')), findsNothing);
      expect(find.text('85%'), findsOneWidget);
    });

    testWidgets('rating sends the chosen stars and refreshes', (tester) async {
      service.recResponses.add(
        RecommendationsPage(items: [_rec('loc-1', 'Cathedral', 0.9)]),
      );
      await pumpPlanner(tester);
      await tap(tester, 'plan-recommend');

      await tap(tester, 'rec-rate-loc-1');
      await tap(tester, 'rating-star-4');
      await tap(tester, 'rating-submit');

      expect(service.interactions.single.$3, 4);
      expect(service.recCalls, 2);
      expect(find.text('Rated 4'), findsOneWidget);
    });

    testWidgets('a failed interaction shows an error and keeps the list', (
      tester,
    ) async {
      service.recResponses.add(
        RecommendationsPage(items: [_rec('loc-1', 'Cathedral', 0.9)]),
      );
      service.interactionErrors.add(
        const TripApiException('Could not save that right now.'),
      );
      await pumpPlanner(tester);
      await tap(tester, 'plan-recommend');
      await tap(tester, 'rec-save-loc-1');

      expect(find.text('Could not save that right now.'), findsOneWidget);
      expect(find.text('Cathedral'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('generation success returns the saved plan', (tester) async {
      service.genResponses.add(_generated);
      final popped = await pumpPlanner(tester);

      await tap(tester, 'plan-generate');

      expect(popped.single, same(_generated));
      expect(service.genRevisions, [null]);
    });

    testWidgets('replacing asks first; cancel makes no write', (tester) async {
      service.genResponses.add(
        PlanApiException(
          'This trip already has an itinerary.',
          statusCode: 409,
          code: 'replacement_confirmation_required',
          revision: 'e' * 32,
        ),
      );
      final popped = await pumpPlanner(tester);

      await tap(tester, 'plan-generate');
      expect(find.text('Replace this itinerary?'), findsOneWidget);
      await tap(tester, 'confirm-cancel');

      expect(service.genRevisions, [null]);
      expect(popped, isEmpty);
    });

    testWidgets('confirming replacement resends with the revision', (
      tester,
    ) async {
      service.genResponses.addAll([
        PlanApiException(
          'This trip already has an itinerary.',
          statusCode: 409,
          code: 'replacement_confirmation_required',
          revision: 'e' * 32,
        ),
        _generated,
      ]);
      final popped = await pumpPlanner(tester);

      await tap(tester, 'plan-generate');
      await tap(tester, 'confirm-accept');

      expect(service.genRevisions, [null, 'e' * 32]);
      expect(popped.single, same(_generated));
    });

    testWidgets('a stale confirmation asks to try again', (tester) async {
      service.genResponses.addAll([
        const PlanApiException(
          'The itinerary changed since you last loaded it.',
          statusCode: 409,
          code: 'itinerary_changed',
        ),
        _generated,
      ]);
      final popped = await pumpPlanner(tester);

      await tap(tester, 'plan-generate');
      expect(find.textContaining('itinerary changed'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(service.genRevisions, [null, null]);
      expect(popped.single, same(_generated));
    });

    testWidgets('an infeasible plan explains and stays on screen', (
      tester,
    ) async {
      service.genResponses.add(
        const PlanApiException(
          'Only 1 of 3 stops fit the schedule.',
          statusCode: 409,
          code: 'requested_visits_do_not_fit',
          skipped: {
            'loc-2': 'unknown_or_unsupported_opening_hours',
            'loc-3': 'unknown_or_unsupported_opening_hours',
          },
        ),
      );
      final popped = await pumpPlanner(tester);

      await tap(tester, 'plan-generate');

      expect(find.textContaining('Only 1 of 3'), findsOneWidget);
      expect(find.textContaining('2 unknown opening hours'), findsOneWidget);
      expect(popped, isEmpty);
    });

    testWidgets('a network failure keeps the user on the planner', (
      tester,
    ) async {
      service.genResponses.add(
        const TripApiException('The server took too long to respond.'),
      );
      final popped = await pumpPlanner(tester);

      await tap(tester, 'plan-generate');

      expect(find.textContaining('saved plan is unchanged'), findsOneWidget);
      expect(popped, isEmpty);
    });

    testWidgets('unsupported trip choices block calls and offer editing', (
      tester,
    ) async {
      await pumpPlanner(
        tester,
        trip: _trip(group: 'students', tags: ['heritage', 'art']),
      );

      expect(find.byKey(const ValueKey('plan-issues')), findsOneWidget);
      expect(find.textContaining('Students'), findsOneWidget);
      expect(find.textContaining('Art'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-edit-trip')), findsOneWidget);

      await tap(tester, 'plan-recommend');
      await tap(tester, 'plan-generate');
      expect(service.recCalls, 0);
      expect(service.genRevisions, isEmpty);
    });

    testWidgets('options change the request counts', (tester) async {
      service.genResponses.add(_generated);
      PlanOptions? sent;
      final capture = _CapturingService((o) => sent = o);
      service = capture;
      await pumpPlanner(tester);

      await tap(tester, 'plan-party-plus');
      await tap(tester, 'plan-visits-minus');
      await tap(tester, 'plan-generate');

      expect(sent!.partySize, 3);
      expect(sent!.plannedVisits, 3);
    });
  });

  testWidgets('itinerary shows schedule, reason, total and manual stops', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _ItemsService([
      TripItem.fromJson(_itemJson('gen')),
      TripItem.fromJson({
        ..._itemJson('manual', generated: false),
        'visit_order': 2,
      }),
    ]);
    final trip = Trip(
      id: 'trip-1',
      userId: 'profile-1',
      status: 'draft',
      estimatedTotalCost: 360,
      title: 'Heritage weekend',
      startDate: DateTime(2026, 11, 7),
      endDate: DateTime(2026, 11, 8),
      budgetMin: 500,
      budgetMax: 3000,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ItineraryLocationsSection(
              service: service,
              locations: ApiService(),
              trip: trip,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Estimated total: ₱360'), findsOneWidget);
    expect(
      find.text('9:00 AM – 10:30 AM · 15 min travel · ₱120'),
      findsOneWidget,
    );
    expect(find.text('Matches your heritage vibe.'), findsOneWidget);
    expect(find.text('Added by you · not scheduled'), findsOneWidget);

    // The backend clears the total on manual edits; so does the UI.
    await tester.tap(find.byIcon(Icons.remove_circle_outline_rounded).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(service.removed, ['manual']);
    expect(find.byKey(const ValueKey('itinerary-total')), findsNothing);
  });
}

class _CapturingService extends FakePlanService {
  final void Function(PlanOptions) onGenerate;

  _CapturingService(this.onGenerate) {
    genResponses.add(_generated);
  }

  @override
  Future<GenerationResult> generateItinerary(
    String tripId,
    PlanOptions options, {
    String? expectedRevision,
  }) {
    onGenerate(options);
    return super.generateItinerary(
      tripId,
      options,
      expectedRevision: expectedRevision,
    );
  }
}

class _ItemsService extends TripService {
  final List<TripItem> items;

  _ItemsService(this.items) : super(token: 'fake');

  @override
  Future<List<TripItem>> listTripItems(String tripId) async => items;

  final List<String> removed = [];

  @override
  Future<void> removeTripItem(String tripId, String itemId) async {
    removed.add(itemId);
    items.removeWhere((item) => item.id == itemId);
  }
}
