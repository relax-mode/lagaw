import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/auth/auth_gate.dart';
import 'package:frontend/auth/auth_session.dart';
import 'package:frontend/auth/welcome_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_test.dart' show FakeAuthClient;

void main() {
  late AuthSession session;

  Future<void> pump(WidgetTester tester, {bool seen = false}) async {
    SharedPreferences.setMockInitialValues({if (seen) introSeenKey: true});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session = AuthSession(
      FakeAuthClient()..passwords['a@example.com'] = 'correct-pw',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          session: session,
          signedIn: () => const Text('signed in'),
        ),
      ),
    );
    await _step(tester);
  }

  testWidgets('the swipe demo shows real photos with their credits', (
    tester,
  ) async {
    await pump(tester);
    bool shows(String name) => tester
        .widgetList<Image>(find.byType(Image))
        .any(
          (i) =>
              i.image is AssetImage &&
              (i.image as AssetImage).assetName == 'assets/intro/$name.webp',
        );
    expect(shows('san-sebastian'), isTrue);
    expect(shows('calea'), isTrue);
    expect(shows('capitol-park'), isTrue);
    expect(find.text('Rauxilian · CC BY-SA 4.0'), findsOneWidget);
  });

  testWidgets('first run walks through the intro to the welcome page', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Swipe your vibe'), findsOneWidget);
    expect(find.byKey(const ValueKey('intro-dots')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro-log-in')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('intro-next')));
    await _step(tester);
    expect(find.text('Find spots around Bacolod'), findsOneWidget);

    // Swiping works too.
    await tester.fling(
      find.byKey(const ValueKey('intro-pages')),
      const Offset(-300, 0),
      1000,
    );
    await _step(tester);
    expect(find.text('Plan a trip in seconds'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intro-skip')));
    await _step(tester);
    expect(find.text('Welcome to Lagaw'), findsOneWidget);
    expect(find.byKey(const ValueKey('intro-create-account')), findsOneWidget);
    expect(find.byKey(const ValueKey('intro-log-in')), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(introSeenKey), isTrue);
  });

  testWidgets('Create account and Log in open the email form, Back returns', (
    tester,
  ) async {
    await pump(tester, seen: true);
    // Seen before: straight to the welcome page.
    expect(find.text('Welcome to Lagaw'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intro-create-account')));
    await _step(tester);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth-back')));
    await _step(tester);
    expect(find.text('Welcome to Lagaw'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('intro-log-in')));
    await _step(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-confirm')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'correct-pw',
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await _step(tester);
    expect(find.text('signed in'), findsOneWidget);
  });
}

/// The intro's little demos loop forever, so step time instead of settling.
Future<void> _step(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}
