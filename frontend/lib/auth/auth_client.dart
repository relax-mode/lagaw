import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// A sign-in/sign-up problem, with a message safe to show. [S3-16]
class AuthFailure implements Exception {
  final String message;

  /// True when the user should confirm their email before signing in.
  final bool needsConfirmation;

  /// Set for rate limits: how long to hold the submit button before retrying.
  final Duration? retryAfter;

  const AuthFailure(
    this.message, {
    this.needsConfirmation = false,
    this.retryAfter,
  });

  @override
  String toString() => 'AuthFailure: $message';
}

/// The current Supabase session, reduced to what the app needs.
class AuthTokens {
  final String accessToken;
  final String? email;

  /// Seconds since epoch; null when unknown.
  final int? expiresAt;

  const AuthTokens({required this.accessToken, this.email, this.expiresAt});

  bool expiresWithin(Duration margin) {
    final at = expiresAt;
    if (at == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return at - now <= margin.inSeconds;
  }
}

enum AuthChange { signedIn, refreshed, signedOut }

/// Email/password auth. The real implementation wraps Supabase; tests use a
/// fake. Only the public project URL and anon key are ever configured.
abstract class AuthClient {
  AuthTokens? get current;
  Stream<AuthChange> get changes;

  /// Returns true when a session was created immediately; false when the
  /// account must confirm its email first.
  Future<bool> signUp(String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();

  /// Refreshes through the SDK; returns false when the session is gone.
  Future<bool> refresh();
}

/// [AuthClient] over `supabase_flutter`, which persists and auto-refreshes
/// the session on Android and Web.
class SupabaseAuthClient implements AuthClient {
  final sb.GoTrueClient _auth;

  /// Where the confirmation email sends the user back (web origin).
  final String? emailRedirectTo;

  SupabaseAuthClient(this._auth, {this.emailRedirectTo});

  @override
  AuthTokens? get current => _tokens(_auth.currentSession);

  AuthTokens? _tokens(sb.Session? session) => session == null
      ? null
      : AuthTokens(
          accessToken: session.accessToken,
          email: session.user.email,
          expiresAt: session.expiresAt,
        );

  @override
  Stream<AuthChange> get changes => _auth.onAuthStateChange
      .map(
        (state) => switch (state.event) {
          sb.AuthChangeEvent.signedOut => AuthChange.signedOut,
          sb.AuthChangeEvent.tokenRefreshed => AuthChange.refreshed,
          _ =>
            state.session == null ? AuthChange.signedOut : AuthChange.signedIn,
        },
      )
      .handleError((_) {});

  @override
  Future<bool> signUp(String email, String password) => _guard(() async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: emailRedirectTo,
    );
    if (response.session == null && _isExistingAccount(response.user)) {
      throw const AuthFailure(_existingAccount);
    }
    return response.session != null;
  });

  /// With confirmation on, Supabase answers a sign-up for an already
  /// confirmed email with an obfuscated user that has no identities, instead
  /// of an error, and sends no email.
  static bool _isExistingAccount(sb.User? user) =>
      user != null && (user.identities?.isEmpty ?? false);

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _auth.signInWithPassword(email: email, password: password));

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // The local session is cleared even when the server call fails.
    }
  }

  @override
  Future<bool> refresh() async {
    if (_auth.currentSession == null) return false;
    try {
      final response = await _auth.refreshSession();
      return response.session != null;
    } catch (_) {
      return false;
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on sb.AuthException catch (e) {
      throw describeAuthError(e.code, e.statusCode, e.message);
    } on TimeoutException {
      throw const AuthFailure(
        'The sign-in service took too long. Please try again.',
      );
    } catch (_) {
      throw const AuthFailure(
        'Could not reach the sign-in service. Check your connection and try '
        'again.',
      );
    }
  }
}

const _existingAccount =
    'An account with this email already exists. Sign in instead.';

const _requestLimit = AuthFailure(
  'Too many attempts from this network. Wait a few minutes, then try again.',
  retryAfter: Duration(minutes: 1),
);

final RegExp _retryAfterSeconds = RegExp(r'after (\d+) seconds?');

/// Supabase reports two different email limits under one code: a per-address
/// cooldown ("...only request this after 42 seconds") and the project's
/// hourly email cap ("email rate limit exceeded").
AuthFailure _emailLimit(String message) {
  final seconds = int.tryParse(
    _retryAfterSeconds.firstMatch(message)?.group(1) ?? '',
  );
  if (seconds != null) {
    return AuthFailure(
      'An email was just sent to this address. Check your inbox (and spam), '
      'or try again in $seconds seconds.',
      retryAfter: Duration(seconds: seconds),
    );
  }
  return const AuthFailure(
    'Lagaw cannot send more confirmation emails right now. If you already '
    'signed up, check your inbox (and spam) for the link, then sign in. '
    'Otherwise try again later.',
    retryAfter: Duration(minutes: 1),
  );
}

/// Where confirmation emails send the user back. Supabase only honors URLs
/// on the project's redirect allow-list and otherwise falls back to its Site
/// URL, which defaults to localhost. An explicit `AUTH_REDIRECT_URL` wins;
/// Web returns to its own origin; Android, which has no deep link, goes to
/// the deployed web app of the same Supabase project.
String? emailRedirectFor({
  required String configured,
  required bool isWeb,
  required Uri base,
  required String supabaseUrl,
}) {
  if (configured.isNotEmpty) return configured;
  if (isWeb) return base.origin;
  return knownWebApps[Uri.tryParse(supabaseUrl)?.host];
}

/// Deployed web app per Supabase project host (docs/flutter-authentication.md).
const knownWebApps = {
  'vnpkyvtbupnquvirzlzp.supabase.co': 'https://staging.lagaw.pages.dev',
  'zjnuqqtbapbpudsjbpif.supabase.co': 'https://lagaw.pages.dev',
};

/// Maps Supabase Auth error codes to user-facing messages.
AuthFailure describeAuthError(String? code, String? status, String message) {
  switch (code) {
    case 'invalid_credentials':
      return const AuthFailure('Email or password is incorrect.');
    case 'email_not_confirmed':
      return const AuthFailure(
        'Confirm your email first. Check your inbox for the link, then sign '
        'in.',
        needsConfirmation: true,
      );
    case 'user_already_exists' || 'email_exists':
      return const AuthFailure(_existingAccount);
    case 'weak_password':
      return const AuthFailure(
        'Choose a stronger password (at least 8 characters).',
      );
    case 'over_email_send_rate_limit':
      return _emailLimit(message);
    case 'over_request_rate_limit' || 'over_sms_send_rate_limit':
      return _requestLimit;
    case 'signup_disabled' || 'email_provider_disabled':
      return const AuthFailure('New sign-ups are turned off right now.');
    case 'validation_failed' || 'email_address_invalid':
      return const AuthFailure('Enter a valid email address.');
  }
  if (status == '429') return _requestLimit;
  if (status != null && status.startsWith('5')) {
    return const AuthFailure(
      'The sign-in service is unavailable right now. Please try again.',
    );
  }
  return const AuthFailure('Sign-in failed. Please try again.');
}
