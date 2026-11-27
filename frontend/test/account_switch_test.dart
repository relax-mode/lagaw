// Signing out, or signing in as someone else, must not leave anything from
// the previous account on screen or let it act as the new one. [#203]
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/auth/api_credentials.dart';
import 'package:frontend/auth/auth_gate.dart';
import 'package:frontend/auth/auth_session.dart';

import 'auth_test.dart' show FakeAuthClient;

FakeAuthClient _client() => FakeAuthClient()
  ..passwords['a@example.com'] = 'pw-a'
  ..passwords['b@example.com'] = 'pw-b';

void main() {
  group('ApiCredentials', () {
    test(
      'stop giving tokens or retries after another account signs in',
      () async {
        final session = AuthSession(_client());
        await session.signIn('a@example.com', 'pw-a');
        final forA = ApiCredentials.resolve(session: session, demoToken: '');
        expect(await forA.token(), isNotNull);
        expect(await forA.recover(), isTrue);

        await session.signOut();
        await session.signIn('b@example.com', 'pw-b');
        // Left over from A: never a token for B, never a retry as B.
        expect(await forA.token(), isNull);
        expect(await forA.recover(), isFalse);
        // New screens for B work normally.
        final forB = ApiCredentials.resolve(session: session, demoToken: '');
        expect(await forB.token(), isNotNull);
      },
    );

    test('keep working when the same account signs in again', () async {
      final client = _client();
      final session = AuthSession(client);
      await session.signIn('a@example.com', 'pw-a');
      final forA = ApiCredentials.resolve(session: session, demoToken: '');
      client.expireFromServer();
      await Future<void>.delayed(Duration.zero);
      expect(session.expired, isTrue);
      await session.signIn('a@example.com', 'pw-a');
      expect(await forA.token(), isNotNull);
    });
  });

  group('AuthGate', () {
    late FakeAuthClient client;
    late AuthSession session;

    Future<void> pumpSignedInWithPopup(WidgetTester tester) async {
      client = _client();
      session = AuthSession(client);
      await session.signIn('a@example.com', 'pw-a');
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            session: session,
            intro: false,
            signedIn: () => Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    Text('home of ${session.accountEmail}'),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const Scaffold(body: Text('A trip pop-up')),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('A trip pop-up'), findsOneWidget);
    }

    testWidgets('signing out closes pop-ups from the account', (tester) async {
      await pumpSignedInWithPopup(tester);
      await session.signOut();
      await tester.pumpAndSettle();
      expect(find.text('A trip pop-up'), findsNothing);
    });

    testWidgets('another account after expiry starts fresh', (tester) async {
      await pumpSignedInWithPopup(tester);
      client.expireFromServer();
      await tester.pumpAndSettle();
      // Expired: the pop-up stays, so nothing typed is lost.
      expect(find.text('A trip pop-up'), findsOneWidget);

      await session.signIn('b@example.com', 'pw-b');
      await tester.pumpAndSettle();
      expect(find.text('A trip pop-up'), findsNothing);
      expect(find.text('home of b@example.com'), findsOneWidget);
    });

    testWidgets('the same account after expiry keeps its pop-ups', (
      tester,
    ) async {
      await pumpSignedInWithPopup(tester);
      client.expireFromServer();
      await tester.pumpAndSettle();
      await session.signIn('a@example.com', 'pw-a');
      await tester.pumpAndSettle();
      expect(find.text('A trip pop-up'), findsOneWidget);
    });
  });
}
