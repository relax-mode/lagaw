import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/auth/auth_client.dart';
import 'package:frontend/auth/auth_gate.dart';
import 'package:frontend/auth/auth_session.dart';
import 'package:frontend/main.dart' show isPublicSupabaseKey;
import 'package:frontend/models/trip.dart';
import 'package:frontend/services/preference_service.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory Supabase stand-in: no network, no real credentials.
class FakeAuthClient implements AuthClient {
  final _changes = StreamController<AuthChange>.broadcast();
  final Map<String, String> passwords = {};
  final Set<String> unconfirmed = {};
  bool requireConfirmation = false;
  bool refreshSucceeds = true;
  int refreshCalls = 0;
  int _serial = 0;
  AuthTokens? _current;
  AuthFailure? nextFailure;

  FakeAuthClient([this._current]);

  @override
  AuthTokens? get current => _current;

  @override
  Stream<AuthChange> get changes => _changes.stream;

  AuthTokens _issue(String email, {int lifetime = 3600}) => AuthTokens(
    accessToken: 'access-${++_serial}',
    email: email,
    expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime,
  );

  void _failIfQueued() {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
  }

  @override
  Future<bool> signUp(String email, String password) async {
    _failIfQueued();
    if (passwords.containsKey(email)) {
      throw describeAuthError('user_already_exists', '422', '');
    }
    passwords[email] = password;
    if (requireConfirmation) {
      unconfirmed.add(email);
      return false;
    }
    _current = _issue(email);
    _changes.add(AuthChange.signedIn);
    return true;
  }

  @override
  Future<void> signIn(String email, String password) async {
    _failIfQueued();
    if (passwords[email] != password) {
      throw describeAuthError('invalid_credentials', '400', '');
    }
    if (unconfirmed.contains(email)) {
      throw describeAuthError('email_not_confirmed', '400', '');
    }
    _current = _issue(email);
    _changes.add(AuthChange.signedIn);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _changes.add(AuthChange.signedOut);
  }

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    final email = _current?.email;
    if (!refreshSucceeds || email == null) {
      _current = null;
      _changes.add(AuthChange.signedOut);
      return false;
    }
    _current = _issue(email);
    _changes.add(AuthChange.refreshed);
    return true;
  }

  /// Simulates the SDK dropping a session it could not refresh.
  void expireFromServer() {
    _current = null;
    _changes.add(AuthChange.signedOut);
  }
}

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.signature';
}

Map<String, dynamic> _tripJson() => {
  'id': 'trip-1',
  'user_id': 'profile-1',
  'status': 'draft',
  'estimated_total_cost': null,
  'title': 'Food crawl',
  'start_date': '2026-11-07',
  'end_date': '2026-11-08',
  'budget_min': '500.00',
  'budget_max': '2000.00',
  'transportation_mode': null,
  'group_type': null,
  'preferred_tags': <String>[],
};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status);

void main() {
  group('Public key guard', () {
    test('accepts anon/publishable keys and refuses server keys', () {
      expect(isPublicSupabaseKey(_jwt({'role': 'anon'})), isTrue);
      expect(isPublicSupabaseKey('sb_publishable_abc'), isTrue);
      expect(isPublicSupabaseKey(_jwt({'role': 'service_role'})), isFalse);
      expect(isPublicSupabaseKey('sb_secret_abc'), isFalse);
      expect(isPublicSupabaseKey('not-a-key'), isFalse);
    });
  });

  group('AuthSession', () {
    test('refreshes a token that is about to expire before using it', () async {
      final client = FakeAuthClient(
        AuthTokens(
          accessToken: 'old',
          email: 'a@example.com',
          expiresAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 5,
        ),
      );
      final session = AuthSession(client);

      final token = await session.accessToken();

      expect(token, isNot('old'));
      expect(client.refreshCalls, 1);
    });

    test('a failed refresh marks the session expired, once', () async {
      final client = FakeAuthClient()..passwords['a@example.com'] = 'pw';
      final session = AuthSession(client);
      await session.signIn('a@example.com', 'pw');
      client.refreshSucceeds = false;

      final results = await Future.wait([
        session.recoverFromUnauthorized(),
        session.recoverFromUnauthorized(),
      ]);

      expect(results, [false, false]);
      expect(client.refreshCalls, 1);
      expect(session.expired, isTrue);
      expect(session.accountEmail, 'a@example.com');
    });

    test(
      'an unrequested SDK sign-out means expired; sign-out does not',
      () async {
        final client = FakeAuthClient()..passwords['a@example.com'] = 'pw';
        final session = AuthSession(client);
        await session.signIn('a@example.com', 'pw');

        client.expireFromServer();
        await Future<void>.delayed(Duration.zero);
        expect(session.expired, isTrue);

        await session.signIn('a@example.com', 'pw');
        expect(session.expired, isFalse);
        await session.signOut();
        await Future<void>.delayed(Duration.zero);
        expect(session.expired, isFalse);
        expect(session.isSignedIn, isFalse);
        expect(session.accountEmail, isNull);
      },
    );
  });

  group('Authorized FastAPI requests', () {
    late FakeAuthClient client;
    late AuthSession session;

    setUp(() async {
      client = FakeAuthClient()..passwords['a@example.com'] = 'pw';
      session = AuthSession(client);
      await session.signIn('a@example.com', 'pw');
    });

    test('trip calls send the signed-in access token', () async {
      final seen = <String?>[];
      final service = TripService(
        session: session,
        client: MockClient((request) async {
          seen.add(request.headers['Authorization']);
          return _json(_tripJson(), 200);
        }),
      );

      await service.getTrip('trip-1');

      expect(seen, ['Bearer ${client.current!.accessToken}']);
    });

    test('a 401 refreshes once and retries with the new token', () async {
      final seen = <String?>[];
      final service = TripService(
        session: session,
        client: MockClient((request) async {
          seen.add(request.headers['Authorization']);
          return seen.length == 1
              ? _json({'detail': 'expired'}, 401)
              : _json(_tripJson(), 201);
        }),
      );

      final trip = await service.createTrip(
        TripDraft(
          title: 'Food crawl',
          startDate: DateTime(2026, 11, 7),
          endDate: DateTime(2026, 11, 8),
          budgetMin: 500,
          budgetMax: 2000,
        ),
      );

      expect(trip.id, 'trip-1');
      expect(seen, hasLength(2));
      expect(seen.first, isNot(seen.last));
      expect(client.refreshCalls, 1);
    });

    test('a failed refresh stops, marks expired and never loops', () async {
      client.refreshSucceeds = false;
      var calls = 0;
      final service = TripService(
        session: session,
        client: MockClient((_) async {
          calls++;
          return _json({'detail': 'expired'}, 401);
        }),
      );

      await expectLater(
        service.listTrips(),
        throwsA(
          isA<TripApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.message, 'message', contains('expired')),
        ),
      );
      expect(calls, 1);
      expect(session.expired, isTrue);
    });

    test('without a session no request is sent', () async {
      await session.signOut();
      var calls = 0;
      final service = TripService(
        session: session,
        client: MockClient((_) async {
          calls++;
          return _json({}, 200);
        }),
      );

      await expectLater(service.listTrips(), throwsA(isA<TripApiException>()));
      expect(calls, 0);
    });

    for (final (status, code, expected) in [
      (403, 'email_confirmation_required', 'Confirm your email'),
      (409, 'profile_link_required', 'needs a review'),
    ]) {
      test('maps $status $code', () async {
        final service = TripService(
          session: session,
          client: MockClient(
            (_) async => _json({
              'detail': {'code': code, 'message': 'x'},
            }, status),
          ),
        );

        await expectLater(
          service.listTrips(),
          throwsA(
            isA<TripApiException>().having(
              (e) => e.message,
              'message',
              contains(expected),
            ),
          ),
        );
      });
    }

    test('an ordinary 409 keeps its trip meaning', () async {
      final service = TripService(
        session: session,
        client: MockClient((_) async => _json({'detail': 'conflict'}, 409)),
      );

      await expectLater(
        service.getTrip('trip-1'),
        throwsA(
          isA<TripApiException>().having(
            (e) => e.message,
            'message',
            contains('Reload'),
          ),
        ),
      );
    });

    test('extraction also uses the session and retries once on 401', () async {
      final seen = <String?>[];
      final service = PreferenceService(
        session: session,
        client: MockClient((request) async {
          seen.add(request.headers['Authorization']);
          if (seen.length == 1) return _json({'detail': 'expired'}, 401);
          return _json({
            'schema_version': '1',
            'preferences': {
              'preferred_tags': ['cafe'],
              'budget_level': 'low',
              'budget_min': null,
              'budget_max': null,
              'group_type': null,
              'duration': 'afternoon',
              'pace': 'slow',
            },
            'requires_confirmation': true,
            'missing_fields': <String>[],
          }, 200);
        }),
      );

      final draft = await service.extract('coffee');

      expect(draft.preferredTags, ['cafe']);
      expect(seen, hasLength(2));
      expect(seen.last, 'Bearer ${client.current!.accessToken}');
    });
  });

  group('Sign-in flows', () {
    late FakeAuthClient client;
    late AuthSession session;
    final navigatorKey = GlobalKey<NavigatorState>();

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => SessionExpiredBanner(
            session: session,
            navigatorKey: navigatorKey,
            child: child!,
          ),
          home: AuthGate(
            session: session,
            signedIn: () => Scaffold(
              body: Column(
                children: [
                  const TextField(key: ValueKey('unsaved-field')),
                  Builder(
                    builder: (context) => TextButton(
                      key: const ValueKey('account-button'),
                      onPressed: () => showAccountSheet(context, session),
                      child: const Text('account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String key, String text) =>
        tester.enterText(find.byKey(ValueKey(key)), text);

    Future<void> tap(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    setUp(() {
      client = FakeAuthClient()..passwords['a@example.com'] = 'correct-pw';
      session = AuthSession(client);
    });

    testWidgets('signed out shows sign-in; valid sign-in opens the app', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Welcome to Lagaw'), findsOneWidget);

      await fill(tester, 'auth-email', 'a@example.com');
      await fill(tester, 'auth-password', 'correct-pw');
      await tap(tester, 'auth-submit');

      expect(find.byKey(const ValueKey('unsaved-field')), findsOneWidget);
    });

    testWidgets('validation runs before any request', (tester) async {
      await pumpApp(tester);
      await tap(tester, 'auth-submit');

      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(session.isSignedIn, isFalse);
    });

    testWidgets('wrong password shows a recoverable error', (tester) async {
      await pumpApp(tester);
      await fill(tester, 'auth-email', 'a@example.com');
      await fill(tester, 'auth-password', 'nope');
      await tap(tester, 'auth-submit');

      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      await fill(tester, 'auth-password', 'correct-pw');
      await tap(tester, 'auth-submit');
      expect(find.byKey(const ValueKey('unsaved-field')), findsOneWidget);
    });

    testWidgets('network failure keeps the form for another try', (
      tester,
    ) async {
      client.nextFailure = const AuthFailure(
        'Could not reach the sign-in service. Check your connection and try '
        'again.',
      );
      await pumpApp(tester);
      await fill(tester, 'auth-email', 'a@example.com');
      await fill(tester, 'auth-password', 'correct-pw');
      await tap(tester, 'auth-submit');

      expect(find.textContaining('Could not reach'), findsOneWidget);
      expect(find.text('a@example.com'), findsOneWidget);
    });

    testWidgets('sign-up with email confirmation asks to confirm first', (
      tester,
    ) async {
      client.requireConfirmation = true;
      await pumpApp(tester);
      await tap(tester, 'auth-switch-mode');
      expect(find.text('Create your account'), findsOneWidget);

      await fill(tester, 'auth-email', 'new@example.com');
      await fill(tester, 'auth-password', 'short');
      await fill(tester, 'auth-confirm', 'other');
      await tap(tester, 'auth-submit');
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('Passwords do not match.'), findsOneWidget);

      await fill(tester, 'auth-password', 'long-enough');
      await fill(tester, 'auth-confirm', 'long-enough');
      await tap(tester, 'auth-submit');

      expect(find.textContaining('Check new@example.com'), findsOneWidget);
      expect(find.text('Welcome to Lagaw'), findsOneWidget);
      expect(session.isSignedIn, isFalse);

      // Signing in before confirming explains instead of failing silently.
      await fill(tester, 'auth-password', 'long-enough');
      await tap(tester, 'auth-submit');
      expect(find.textContaining('Confirm your email first'), findsOneWidget);
    });

    testWidgets('sign-up without confirmation signs in directly', (
      tester,
    ) async {
      await pumpApp(tester);
      await tap(tester, 'auth-switch-mode');
      await fill(tester, 'auth-email', 'new@example.com');
      await fill(tester, 'auth-password', 'long-enough');
      await fill(tester, 'auth-confirm', 'long-enough');
      await tap(tester, 'auth-submit');

      expect(find.byKey(const ValueKey('unsaved-field')), findsOneWidget);
    });

    testWidgets('restores an existing session without asking', (tester) async {
      await session.signIn('a@example.com', 'correct-pw');
      await pumpApp(tester);

      expect(find.text('Welcome to Lagaw'), findsNothing);
      expect(find.byKey(const ValueKey('unsaved-field')), findsOneWidget);
    });

    testWidgets('sign out returns to sign-in', (tester) async {
      await session.signIn('a@example.com', 'correct-pw');
      await pumpApp(tester);

      await tap(tester, 'account-button');
      expect(find.text('a@example.com'), findsOneWidget);
      await tap(tester, 'sign-out');

      expect(find.text('Welcome to Lagaw'), findsOneWidget);
      expect(session.isSignedIn, isFalse);
    });

    testWidgets('expiry keeps unsaved input and re-sign-in restores it', (
      tester,
    ) async {
      await session.signIn('a@example.com', 'correct-pw');
      await pumpApp(tester);
      await fill(tester, 'unsaved-field', 'half-written trip');

      client.expireFromServer();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('session-expired-banner')),
        findsOneWidget,
      );
      expect(find.text('half-written trip'), findsOneWidget);

      await tap(tester, 'session-sign-in-again');
      expect(find.text('Sign in again'), findsOneWidget);
      await fill(tester, 'auth-password', 'correct-pw');
      await tap(tester, 'auth-submit');

      expect(
        find.byKey(const ValueKey('session-expired-banner')),
        findsNothing,
      );
      expect(find.text('half-written trip'), findsOneWidget);
    });
  });
}
