import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/locations_screen.dart';
import 'package:frontend/models/trip_plan.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/discovery_interactions.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _event(String location, String type, {String? rating}) => {
  'id': 'e-$location-$type',
  'location_id': location,
  'interaction_type': type,
  'interaction_value': type == 'left_swipe' ? '-1' : '1',
  'rating_value': rating,
  'created_at': '2026-11-06T00:00:00+00:00',
  'provenance': 'real',
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Fake backend for `/api/v1/interactions` that records every request.
class _Backend {
  final List<Map<String, dynamic>> history;
  final List<http.Request> requests = [];

  /// Status (or `0` for a network failure) for the next POSTs, in order.
  final List<int> postResults = [];
  Completer<void>? holdPosts;

  _Backend([List<Map<String, dynamic>>? history]) : history = history ?? [];

  List<http.Request> get posts =>
      requests.where((r) => r.method == 'POST').toList();

  TripService service() => TripService(
    token: 'test-token',
    client: MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        final limit = int.parse(request.url.queryParameters['limit']!);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return _json({
          'schema_version': '1',
          'items': history.skip(offset).take(limit).toList(),
          'limit': limit,
          'offset': offset,
        });
      }
      await holdPosts?.future;
      final status = postResults.isEmpty ? 201 : postResults.removeAt(0);
      if (status == 0) throw http.ClientException('connection reset');
      if (status != 201) return _json({'detail': 'unavailable'}, status);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json(
        _event(
          body['location_id'] as String,
          body['interaction_type'] as String,
        ),
        201,
      );
    }),
  );
}

/// v3 home: the nav's swipe button opens a menu with Start matching.
/// The home's floating elements loop forever, so step time instead of
/// waiting for it to settle while home is on screen.
Future<void> _openDeck(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-swipe')));
  await tester.pump(const Duration(milliseconds: 400));
  tester.takeException();
  await tester.tap(find.byKey(const ValueKey('swipe-menu-start')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  group('TripService.listInteractions', () {
    test('reads every page and skips unknown event types', () async {
      final backend = _Backend([
        _event('a', 'right_swipe'),
        _event('b', 'save'),
        _event('c', 'rating', rating: '4.00'),
        _event('d', 'future_type'),
        _event('e', 'left_swipe'),
      ]);
      final events = await backend.service().listInteractions(pageSize: 2);

      expect(backend.requests.map((r) => r.url.queryParameters['offset']), [
        '0',
        '2',
        '4',
      ]);
      expect(events.map((e) => e.type), [
        InteractionType.rightSwipe,
        InteractionType.save,
        InteractionType.rating,
        InteractionType.leftSwipe,
      ]);
      expect(events[2].rating, 4.0);
    });
  });

  group('DiscoveryInteractions', () {
    test('restores swiped, saved and rated state from history', () async {
      final backend = _Backend([
        _event('liked', 'right_swipe'),
        _event('passed', 'left_swipe'),
        _event('saved', 'save'),
        _event('rated', 'rating', rating: '2'),
        _event('rated', 'rating', rating: '5'),
        // A left swipe wins over a later save (#52 exclusion policy).
        _event('mixed', 'save'),
        _event('mixed', 'left_swipe'),
      ]);
      final state = DiscoveryInteractions(backend.service());
      await state.load();

      expect(state.loaded, isTrue);
      expect(state.isSwiped('liked'), isTrue);
      expect(state.isSwiped('passed'), isTrue);
      expect(state.isSwiped('saved'), isFalse);
      expect(state.isSaved('saved'), isTrue);
      expect(state.ratingFor('rated'), 5.0);
      expect(state.picks, {'liked', 'saved'});
    });

    test('each action sends exactly one event', () async {
      final backend = _Backend();
      final state = DiscoveryInteractions(backend.service());
      await state.load();

      await state.swipe('a', liked: true);
      await state.swipe('b', liked: false);
      await state.save('c');
      await state.rate('d', 4);

      expect(backend.posts.map((r) => jsonDecode(r.body)), [
        {'location_id': 'a', 'interaction_type': 'right_swipe'},
        {'location_id': 'b', 'interaction_type': 'left_swipe'},
        {'location_id': 'c', 'interaction_type': 'save'},
        {'location_id': 'd', 'interaction_type': 'rating', 'rating_value': 4.0},
      ]);
      expect(state.picks, {'a', 'c'});
      expect(state.ratingFor('d'), 4.0);
    });

    test('a saved place is not saved again', () async {
      final backend = _Backend([_event('a', 'save')]);
      final state = DiscoveryInteractions(backend.service());
      await state.load();
      await state.save('a');
      expect(backend.posts, isEmpty);
    });

    test('a place is locked while its request is in flight', () async {
      final backend = _Backend()..holdPosts = Completer<void>();
      final state = DiscoveryInteractions(backend.service());
      await state.load();

      final first = state.swipe('a', liked: true);
      await Future<void>.delayed(Duration.zero);
      expect(state.isBusy('a'), isTrue);
      await state.swipe('a', liked: true);
      await state.save('a');

      backend.holdPosts!.complete();
      await first;
      expect(backend.posts, hasLength(1));
      expect(state.isBusy('a'), isFalse);
    });

    test('a failed write changes nothing and is not retried', () async {
      final backend = _Backend()..postResults.addAll([503, 0]);
      final state = DiscoveryInteractions(backend.service());
      await state.load();

      await expectLater(
        state.swipe('a', liked: true),
        throwsA(isA<TripApiException>()),
      );
      expect(state.isSwiped('a'), isFalse);

      TripApiException? offline;
      try {
        await state.save('b');
      } on TripApiException catch (e) {
        offline = e;
      }
      expect(state.isSaved('b'), isFalse);
      expect(backend.posts, hasLength(2));
      expect(
        describeInteractionFailure(offline!),
        contains('may still have been recorded'),
      );
    });

    test('a failed load reports an error', () async {
      final state = DiscoveryInteractions(
        TripService(
          token: 'test-token',
          client: MockClient((_) async => _json({'detail': 'down'}, 503)),
        ),
      );
      await state.load();
      expect(state.loaded, isFalse);
      expect(state.loadError, isNotNull);
    });
  });

  group('Swipe deck', () {
    final locations = [
      for (final (id, name) in [
        ('loc-1', 'San Sebastian Cathedral'),
        ('loc-2', 'The Negros Museum'),
        ('loc-3', 'Capitol Park and Lagoon'),
      ])
        {
          'id': id,
          'name': name,
          'description': '$name description',
          'category': 'heritage',
          'vibe_tags': ['heritage'],
          'address': 'Bacolod City',
          'estimated_cost_min': 0,
          'estimated_cost_max': 100,
          'typical_visit_duration': 60,
          'image_url': null,
        },
    ];

    Future<_Backend> pumpDeck(
      WidgetTester tester, {
      List<Map<String, dynamic>>? history,
      bool explained = false,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (explained) 'lagaw.discovery.leftSwipeExplained': true,
      });
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = _Backend(history);
      await tester.pumpWidget(
        MaterialApp(
          home: LocationsScreen(
            tripService: backend.service(),
            apiService: ApiService(
              client: MockClient((_) async => _json({'items': locations})),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      tester.takeException(); // Pre-existing home overflow; see home tests.
      await _openDeck(tester);
      tester.takeException();
      return backend;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      tester.takeException();
    }

    testWidgets('skips places already swiped and resumes the count', (
      tester,
    ) async {
      await pumpDeck(tester, history: [_event('loc-1', 'right_swipe')]);
      expect(find.text('The Negros Museum'), findsWidgets);
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('a like is recorded once and advances after the server', (
      tester,
    ) async {
      final backend = await pumpDeck(tester);
      expect(find.text('1 / 3'), findsOneWidget);
      await tapKey(tester, 'swipe-like');

      expect(jsonDecode(backend.posts.single.body), {
        'location_id': 'loc-1',
        'interaction_type': 'right_swipe',
      });
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('first left swipe explains once, then goes straight through', (
      tester,
    ) async {
      final backend = await pumpDeck(tester);
      await tapKey(tester, 'swipe-pass');
      expect(find.text('Not for you?'), findsOneWidget);
      await tester.tap(find.text('Got it, pass'));
      await tester.pumpAndSettle();
      tester.takeException();
      expect(backend.posts, hasLength(1));

      await tapKey(tester, 'swipe-pass');
      expect(find.text('Not for you?'), findsNothing);
      expect(backend.posts, hasLength(2));
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('cancelling the explainer sends nothing', (tester) async {
      final backend = await pumpDeck(tester);
      await tapKey(tester, 'swipe-pass');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.posts, isEmpty);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('a failed swipe keeps the card and explains', (tester) async {
      final backend = await pumpDeck(tester, explained: true);
      backend.postResults.add(503);
      await tapKey(tester, 'swipe-like');

      expect(find.byKey(const ValueKey('swipe-error')), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(backend.posts, hasLength(1));
    });

    testWidgets('rating sends the chosen stars and shows them', (tester) async {
      final backend = await pumpDeck(tester);
      await tapKey(tester, 'swipe-rate');
      await tapKey(tester, 'rating-star-4');
      await tapKey(tester, 'rating-submit');

      expect(jsonDecode(backend.posts.single.body)['rating_value'], 4.0);
      // The star button now shows the rating.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('swipe-rate')),
          matching: find.text('4'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed history load blocks the deck with Retry', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocationsScreen(
            tripService: TripService(
              token: 'test-token',
              client: MockClient((_) async {
                calls++;
                return calls == 1
                    ? _json({'detail': 'down'}, 503)
                    : _json({'items': []});
              }),
            ),
            apiService: ApiService(
              client: MockClient((_) async => _json({'items': locations})),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();
      await _openDeck(tester);
      tester.takeException();

      expect(find.byKey(const ValueKey('swipe-like')), findsNothing);
      await tapKey(tester, 'swipe-history-retry');
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('failed places load never swipes the offline list', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = _Backend();
      await tester.pumpWidget(
        MaterialApp(
          home: LocationsScreen(
            tripService: backend.service(),
            apiService: ApiService(
              client: MockClient(
                (_) async => throw http.ClientException('offline'),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();
      await _openDeck(tester);
      tester.takeException();

      expect(find.byKey(const ValueKey('swipe-places-state')), findsOneWidget);
      expect(find.byKey(const ValueKey('swipe-like')), findsNothing);
      expect(backend.posts, isEmpty);
    });
  });
}
