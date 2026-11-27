import 'package:flutter/material.dart';

import '../screens/onboarding/first_run_gate.dart';
import '../theme.dart';
import 'auth_session.dart';
import 'password_reset_screen.dart';
import 'sign_in_screen.dart';
import 'welcome_flow.dart';

/// Shows sign-in until there is a session, then [signedIn]. An expired
/// session keeps the app mounted (forms intact) and shows a banner instead;
/// signing in as a different account rebuilds the app. Signing out, or
/// switching to another account, also closes every pop-up and page opened
/// over the app, so nothing from the previous account stays on screen.
/// [S3-16, #203]
class AuthGate extends StatefulWidget {
  final AuthSession session;
  final Widget Function() signedIn;

  /// Signed out: the swipe intro and welcome page first (the app), or
  /// straight to log in (tests of the form itself).
  final bool intro;

  const AuthGate({
    super.key,
    required this.session,
    required this.signedIn,
    this.intro = true,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _account;

  @override
  void initState() {
    super.initState();
    _account = _signedInAccount;
    widget.session.addListener(_onSession);
  }

  @override
  void didUpdateWidget(AuthGate old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  /// The account the app is showing; null when signed out. An expired
  /// session still shows its account (the app stays mounted).
  String? get _signedInAccount {
    final session = widget.session;
    if (!session.isSignedIn && !session.expired) return null;
    return session.accountEmail;
  }

  void _onSession() {
    final now = _signedInAccount;
    final previous = _account;
    _account = now;
    // Same account (refresh, or signing in again after expiry): keep
    // everything open. Signed out or another account: close it all.
    if (previous == null || previous == now) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.passwordRecoveryPending) {
          return PasswordResetScreen(session: session);
        }
        if (!session.isSignedIn && !session.expired) {
          return widget.intro
              ? WelcomeFlow(session: session)
              : SignInScreen(session: session);
        }
        return KeyedSubtree(
          key: ValueKey('account-${session.accountEmail}'),
          child: widget.signedIn(),
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

/// Account sheet opened from the header avatar: who is signed in, travel
/// preferences, and sign out.
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
            FilledButton.tonalIcon(
              key: const ValueKey('open-onboarding'),
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Travel preferences'),
              onPressed: () {
                Navigator.of(sheetContext).pop();
                openTravelPreferences(context);
              },
            ),
            const SizedBox(height: 10),
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
