import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/onboarding_preferences.dart';
import 'package:frontend/screens/onboarding/discovery_screen.dart';
import 'package:frontend/screens/onboarding/first_run_gate.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/services/discovery_service.dart';

Map<String, dynamic> _rec(String id, String name, double score) => {
  'location_id': id,
  'recommendation_score': score,
  'recommendation_reason': 'Matches your $name vibe.',
  'location': {
    'id': id,
    'name': name,
    'category': 'heritage',
    'address': '$name St, Bacolod City',
    'estimated_cost_min': 0,
    'estimated_cost_max': 100,
    'typical_visit_duration': 60,
  },
};

const _emptyPrefs = {
  'preferred_tags': <String>[],
  'budget_min': null,
  'budget_max': null,
  'travel_style': null,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Records requests and answers each with the next queued response.
class _Server {
  final List<http.Request> requests = [];
  final List<FutureOr<http.Response> Function()> responses = [];

  DiscoveryService service() => DiscoveryService(
    token: 'test-token',
    client: MockClient((request) async {
      requests.add(request);
      return responses.removeAt(0)();
    }),
  );

  void reply(Object body, [int status = 200]) =>
      responses.add(() => _json(body, status));
}

void main() {
  group('DiscoveryService', () {
    test('loads preferences with the bearer token', () async {
      final server = _Server()
        ..reply({
          'preferred_tags': ['cafe'],
          'budget_min': '0.00',
          'budget_max': '500.00',
          'travel_style': 'slow',
        });
      final prefs = await server.service().load();
      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/me/preferences');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(prefs.preferredTags, ['cafe']);
      expect(prefs.budgetMax, '500.00');
      expect(prefs.isUnset, isFalse);
    });

    test('a new account reads as unset', () async {
      final server = _Server()..reply(_emptyPrefs);
      expect((await server.service().load()).isUnset, isTrue);
    });

    test('saves all four keys with PUT', () async {
      final server = _Server()..reply(_emptyPrefs);
      await server.service().save(
        const OnboardingPreferences(preferredTags: ['food']),
      );
      final request = server.requests.single;
      expect(request.method, 'PUT');
      expect(jsonDecode(request.body), {
        'preferred_tags': ['food'],
        'budget_min': null,
        'budget_max': null,
        'travel_style': null,
      });
    });

    test('422 on save names the rejected fields', () async {
      final server = _Server()
        ..reply({
          'detail': [
            {
              'loc': ['body', 'budget_max'],
              'msg': 'bad',
              'type': 'value_error',
            },
          ],
        }, 422);
      await expectLater(
        server.service().save(OnboardingPreferences.empty),
        throwsA(
          isA<DiscoveryApiException>()
              .having((e) => e.statusCode, 'status', 422)
              .having((e) => e.message, 'message', contains('budget_max')),
        ),
      );
    });

    test('an unconfirmed save is reported once, never retried', () async {
      final server = _Server();
      server.responses.add(
        () => throw http.ClientException('connection reset'),
      );
      await expectLater(
        server.service().save(OnboardingPreferences.empty),
        throwsA(isA<DiscoveryApiException>()),
      );
      expect(server.requests, hasLength(1));
    });

    test('recommend sends the chosen group and per-place limit', () async {
      final server = _Server()
        ..reply({
          'schema_version': '1',
          'mode': 'content_only',
          'budget_scope': 'per_person_per_visit',
          'items': [_rec('loc-1', 'Ruins', 0.82)],
          'empty_reason': null,
        });
      final page = await server.service().recommend(
        const DiscoveryRequest(groupType: 'couple', perVisitBudgetMax: '0.00'),
      );
      final request = server.requests.single;
      expect(request.url.path, '/api/v1/me/recommendations');
      expect(jsonDecode(request.body), {
        'group_type': 'couple',
        'per_person_visit_budget_max': '0.00',
        'limit': 10,
      });
      expect(page.items.single.location.name, 'Ruins');
    });

    test('409 while ranking means preferences changed', () async {
      final server = _Server()
        ..reply({
          'detail': {'code': 'preferences_changed'},
        }, 409);
      await expectLater(
        server.service().recommend(
          const DiscoveryRequest(groupType: 'solo', perVisitBudgetMax: '1.00'),
        ),
        throwsA(
          isA<DiscoveryApiException>().having(
            (e) => e.preferencesChanged,
            'preferencesChanged',
            isTrue,
          ),
        ),
      );
    });

    test('profile-link 409 and 503 get their own messages', () async {
      final server = _Server()
        ..reply({
          'detail': {'code': 'profile_link_required'},
        }, 409)
        ..reply({'detail': 'down'}, 503);
      final service = server.service();
      await expectLater(
        service.recommend(
          const DiscoveryRequest(groupType: 'solo', perVisitBudgetMax: '1.00'),
        ),
        throwsA(
          isA<DiscoveryApiException>().having(
            (e) => e.preferencesChanged,
            'preferencesChanged',
            isFalse,
          ),
        ),
      );
      await expectLater(
        service.load(),
        throwsA(
          isA<DiscoveryApiException>().having(
            (e) => e.message,
            'message',
            contains('temporarily unavailable'),
          ),
        ),
      );
    });
  });

  group('DiscoveryScreen', () {
    Future<_Server> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server();
      await tester.pumpWidget(
        MaterialApp(home: DiscoveryScreen(service: server.service())),
      );
      return server;
    }

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('asks both questions before searching', (tester) async {
      final server = await pump(tester);
      await tap(tester, 'discovery-search');
      expect(server.requests, isEmpty);

      await tap(tester, 'chip-family');
      await tap(tester, 'discovery-search');
      expect(server.requests, isEmpty);

      server.reply({
        'items': [_rec('a', 'Ruins', 0.82), _rec('b', 'Museum', 0.5)],
        'empty_reason': null,
      });
      await tap(tester, 'chip-500.00');
      await tap(tester, 'discovery-search');

      expect(jsonDecode(server.requests.single.body), {
        'group_type': 'family',
        'per_person_visit_budget_max': '500.00',
        'limit': 10,
      });
      expect(find.text('Ruins'), findsOneWidget);
      expect(find.text('82%'), findsOneWidget);
      expect(find.text('Matches your Museum vibe.'), findsOneWidget);
      expect(find.text('Update places'), findsOneWidget);
    });

    testWidgets('custom limit is validated before searching', (tester) async {
      final server = await pump(tester);
      await tap(tester, 'chip-solo');
      await tap(tester, 'chip-custom');
      await tap(tester, 'discovery-search');
      expect(find.text('Enter an amount in pesos.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('discovery-custom-budget')),
        '1.234',
      );
      await tap(tester, 'discovery-search');
      expect(
        find.text('Use a peso amount with up to 2 decimals.'),
        findsOneWidget,
      );
      expect(server.requests, isEmpty);

      server.reply({'items': [], 'empty_reason': 'no_compatible_locations'});
      await tester.enterText(
        find.byKey(const ValueKey('discovery-custom-budget')),
        '750',
      );
      await tap(tester, 'discovery-search');
      expect(
        jsonDecode(server.requests.single.body)['per_person_visit_budget_max'],
        '750.00',
      );
      expect(find.byKey(const ValueKey('discovery-empty')), findsOneWidget);
    });

    testWidgets('409 offers Reload, which searches again', (tester) async {
      final server = await pump(tester);
      server
        ..reply({
          'detail': {'code': 'preferences_changed'},
        }, 409)
        ..reply({
          'items': [_rec('a', 'Ruins', 0.7)],
          'empty_reason': null,
        });
      await tap(tester, 'chip-solo');
      await tap(tester, 'chip-0.00');
      await tap(tester, 'discovery-search');

      expect(find.byKey(const ValueKey('discovery-error')), findsOneWidget);
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Ruins'), findsOneWidget);
      expect(find.byKey(const ValueKey('discovery-error')), findsNothing);
      expect(server.requests, hasLength(2));
    });

    testWidgets('503 keeps earlier results and offers Try again', (
      tester,
    ) async {
      final server = await pump(tester);
      server
        ..reply({
          'items': [_rec('a', 'Ruins', 0.7)],
          'empty_reason': null,
        })
        ..reply({'detail': 'down'}, 503);
      await tap(tester, 'chip-solo');
      await tap(tester, 'chip-200.00');
      await tap(tester, 'discovery-search');
      await tap(tester, 'discovery-search');

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Ruins'), findsOneWidget);
    });
  });

  group('FirstRunGate', () {
    setUp(FirstRunGate.checked.clear);

    // Responses are queued before pumping: the check runs on first frame.
    Future<_Server> pump(
      WidgetTester tester,
      String account, [
      void Function(_Server)? setup,
    ]) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = _Server();
      setup?.call(server);
      await tester.pumpWidget(
        MaterialApp(
          home: FirstRunGate(
            accountKey: account,
            service: server.service,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      );
      return server;
    }

    testWidgets('a first-time account goes to onboarding and can skip', (
      tester,
    ) async {
      await pump(
        tester,
        'a',
        (s) => s
          ..reply(_emptyPrefs) // gate check
          ..reply(_emptyPrefs), // onboarding load
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-start')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a returning account is not interrupted', (tester) async {
      final server = await pump(
        tester,
        'b',
        (s) => s.reply({
          ..._emptyPrefs,
          'preferred_tags': ['cafe'],
        }),
      );
      await tester.pumpAndSettle();
      expect(server.requests, hasLength(1));
      expect(find.byKey(const ValueKey('onboarding-start')), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a failed check opens the app normally', (tester) async {
      final server = await pump(
        tester,
        'c',
        (s) => s.reply({'detail': 'down'}, 503),
      );
      await tester.pumpAndSettle();
      expect(server.requests, hasLength(1));
      expect(server.responses, isEmpty);
      expect(find.text('home'), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-start')), findsNothing);
    });

    testWidgets('each account is checked once per run', (tester) async {
      FirstRunGate.checked.add('d');
      final server = await pump(tester, 'd');
      await tester.pumpAndSettle();
      expect(server.requests, isEmpty);
    });
  });

  testWidgets('saving onboarding continues to picked-for-you', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server()
      ..reply(_emptyPrefs)
      ..reply({
        ..._emptyPrefs,
        'preferred_tags': ['cafe'],
      });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openTravelPreferences(context, service: server.service()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    Future<void> tap(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tap('onboarding-start');
    await tap('chip-cafe');
    await tap('onboarding-next');
    await tap('onboarding-skip-budget');
    await tap('onboarding-next');
    await tap('onboarding-save');

    expect(server.requests.last.method, 'PUT');
    expect(find.text('See places for me'), findsOneWidget);
    await tap('onboarding-finish');
    expect(find.byKey(const ValueKey('discovery-setup')), findsOneWidget);
  });
}
