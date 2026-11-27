import 'dart:convert';

import 'auth_session.dart';

/// Where a protected FastAPI request gets its bearer token. [S3-16]
///
/// With Supabase configured, this is always the signed-in user's access
/// token; the old demo token is used only by local demo builds that have no
/// Supabase configuration, and never as a fallback for a failed session.
///
/// Credentials are bound to the account that was signed in when they were
/// made. After a switch to another account they give no token and no retry,
/// so a screen left over from the previous account can never send (or
/// resend) a request as someone else. [#203]
class ApiCredentials {
  final String? _fixed;
  final AuthSession? _session;
  String? _account;

  ApiCredentials._(this._fixed, this._session)
    : _account = _session?.accountEmail;

  /// [token] pins a credential (tests, local demo backend). Otherwise the
  /// app-wide [AuthSession.current], else the compiled demo token.
  factory ApiCredentials.resolve({
    String? token,
    AuthSession? session,
    required String demoToken,
  }) {
    if (token != null) return ApiCredentials._(token, null);
    final active = session ?? AuthSession.current;
    if (active != null) return ApiCredentials._(null, active);
    return ApiCredentials._(demoToken, null);
  }

  bool get usesSession => _session != null;

  Future<String?> token() async {
    final session = _session;
    if (session == null) {
      final fixed = _fixed ?? '';
      return fixed.isEmpty ? null : fixed;
    }
    if (!_sameAccount(session)) return null;
    final token = await session.accessToken();
    return _sameAccount(session) ? token : null;
  }

  /// After a 401: true when a refreshed token for the same account is ready
  /// for one retry.
  Future<bool> recover() async {
    final session = _session;
    if (session == null || !_sameAccount(session)) return false;
    final ok = await session.recoverFromUnauthorized();
    return ok && _sameAccount(session);
  }

  bool _sameAccount(AuthSession session) {
    final now = session.accountEmail;
    _account ??= now;
    return now == null || now == _account;
  }
}

/// `detail.code` from FastAPI's `{"detail": {"code": ...}}` envelopes.
String? apiErrorCode(String body) {
  try {
    final decoded = jsonDecode(body);
    final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
    return detail is Map<String, dynamic> ? detail['code']?.toString() : null;
  } on FormatException {
    return null;
  }
}

/// Shared messages for the backend's authentication outcomes.
abstract final class AuthMessages {
  static const sessionExpired =
      'Your session has expired. Sign in again; your unsaved changes are kept.';
  static const signInRequired = 'Sign in to manage your trips.';
  static const emailConfirmation =
      'Confirm your email address first. Check your inbox for the link.';
  static const profileLink =
      'This account needs a review before it can use trips. Please contact '
      'the Lagaw team.';
}
