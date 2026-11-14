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

/// The auth server could not be reached (offline, DNS, timeout). The
/// session is still valid; callers should report a connection problem,
/// never an expired session. [S4-17]
class AuthUnreachable implements Exception {
  const AuthUnreachable();
}

enum AuthChange { signedIn, refreshed, signedOut, passwordRecovery }

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

  /// Request a recovery email without exposing whether an account exists.
  Future<void> requestPasswordReset(String email);

  /// Set a password only with the authenticated recovery session.
  Future<void> updatePassword(String password);

  /// Refreshes through the SDK; returns false when the server rejected the
  /// session. Throws [AuthUnreachable] when the server could not be reached.
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
          sb.AuthChangeEvent.passwordRecovery => AuthChange.passwordRecovery,
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
  Future<void> requestPasswordReset(String email) => _guard(
    () => _auth.resetPasswordForEmail(email, redirectTo: emailRedirectTo),
  );

  @override
  Future<void> updatePassword(String password) => _guard(() async {
    await _auth.updateUser(sb.UserAttributes(password: password));
  }, updatingPassword: true);

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
    } on sb.AuthRetryableFetchException {
      throw const AuthUnreachable();
    } on sb.AuthException {
      return false;
    } on TimeoutException {
      throw const AuthUnreachable();
    } catch (_) {
      // Anything else (socket, DNS, HTTP client) means no answer arrived.
      throw const AuthUnreachable();
    }
  }

  Future<T> _guard<T>(
    Future<T> Function() action, {
    bool updatingPassword = false,
  }) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on sb.AuthException catch (e) {
      throw updatingPassword
          ? describePasswordUpdateError(e.code, e.statusCode, e.message)
          : describeAuthError(e.code, e.statusCode, e.message);
    } on TimeoutException {
      throw AuthFailure(
        updatingPassword
            ? 'The password update took too long. Check your connection and '
                  'try again.'
            : 'The sign-in service took too long. Please try again.',
      );
    } catch (_) {
      throw AuthFailure(
        updatingPassword
            ? 'Could not reach the password update service. Check your '
                  'connection and try again.'
            : 'Could not reach the sign-in service. Check your connection and '
                  'try again.',
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

/// Maps documented Supabase password-update errors without showing the raw
/// provider message (which can contain account and policy details). Unlike
/// ordinary sign-in, a recovery update has a valid short-lived auth session.
/// Unknown provider *codes* are safe to display only when identifier-shaped;
/// they let us debug failed recovery without exposing tokens or email links.
AuthFailure describePasswordUpdateError(
  String? code,
  String? status,
  String message,
) {
  switch (code) {
    case 'same_password':
      return const AuthFailure(
        'Your new password must be different from your current password.',
      );
    case 'weak_password':
      return const AuthFailure(
        'This password does not meet the account security requirements. '
        'Choose a stronger password and try again.',
      );
    case 'reauthentication_needed':
      return const AuthFailure(
        'Supabase requires additional verification before this password can '
        'be changed. Contact the Lagaw team if this continues.',
      );
    case 'reauthentication_not_valid':
      return const AuthFailure(
        'The additional verification code is invalid or expired. '
        'Request a new verification and try again.',
      );
    case 'session_expired' ||
          'session_not_found' ||
          'refresh_token_not_found' ||
          'bad_jwt' ||
          'otp_expired' ||
          'flow_state_expired' ||
          'flow_state_not_found':
      return const AuthFailure(
        'This recovery session has expired or is no longer valid. '
        'Request a fresh password-reset email and open the newest link.',
      );
    case 'over_request_rate_limit':
      return _requestLimit;
    case 'validation_failed':
      return const AuthFailure(
        'The new password was rejected. Choose a different, stronger '
        'password and try again.',
      );
  }
  if (status == '429') return _requestLimit;
  if (status == '401' || status == '403') {
    return const AuthFailure(
      'Your recovery session is no longer authorized. Request a fresh '
      'password-reset email and open the newest link.',
    );
  }
  if (status != null && status.startsWith('5')) {
    return const AuthFailure(
      'The password update service is unavailable. Please try again later.',
    );
  }
  // The provider's error *code* is public and non-sensitive, but its raw
  // message is not. No email, token, URL or response body is surfaced here.
  final safeCode = code != null && RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(code)
      ? ' (error code: $code)'
      : '';
  return AuthFailure(
    'The password could not be updated$safeCode. Try a different, stronger '
    'password or request a fresh recovery link.',
  );
}
