import 'package:flutter/material.dart';

import '../theme.dart';
import 'auth_session.dart';
import 'sign_in_screen.dart';

/// Shows sign-in until there is a session, then [signedIn]. An expired
/// session keeps the app mounted (forms intact) and shows a banner instead;
/// signing in as a different account rebuilds the app. [S3-16]
class AuthGate extends StatelessWidget {
  final AuthSession session;
  final Widget Function() signedIn;

  const AuthGate({super.key, required this.session, required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isSignedIn && !session.expired) {
          return SignInScreen(session: session);
        }
        return KeyedSubtree(
          key: ValueKey('account-${session.accountEmail}'),
          child: signedIn(),
        );
      },
    );
  }
}

/// Banner over the whole app while a session is expired. Placed with
/// `MaterialApp.builder`, so it opens sign-in on the root navigator.
class SessionExpiredBanner extends StatelessWidget {
  final AuthSession session;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const SessionExpiredBanner({
    super.key,
    required this.session,
    required this.navigatorKey,
    required this.child,
  });

  void _signInAgain() {
    navigatorKey.currentState?.push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => SignInScreen(session: session, reauthenticate: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      child: child,
      builder: (context, child) => Stack(
        children: [
          child!,
          if (session.expired)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: Material(
                  key: const ValueKey('session-expired-banner'),
                  color: const Color(0xFFFFF7ED),
                  elevation: 6,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_clock_rounded,
                          color: Color(0xFFC2410C),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Your session expired. Sign in again to keep '
                            'saving; nothing you typed is lost.',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateDark,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('session-sign-in-again'),
                          onPressed: _signInAgain,
                          child: const Text('Sign in'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Account sheet opened from the header avatar: who is signed in, and
/// sign out.
Future<void> showAccountSheet(BuildContext context, AuthSession session) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Signed in as',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.slateMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              session.accountEmail ?? 'Unknown account',
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppTheme.slateDark,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('sign-out'),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await session.signOut();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
