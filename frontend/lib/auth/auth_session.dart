import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_client.dart';

/// App-wide sign-in state shared by every protected FastAPI call. [S3-16]
///
/// When a session can no longer be refreshed, the app is *not* torn down:
/// [expired] is set so open screens (and unsaved forms) stay put while the
/// user signs in again on top of them.
class AuthSession extends ChangeNotifier {
  /// Set at startup when Supabase is configured; null in local demo builds.
  static AuthSession? current;

  final AuthClient client;
  StreamSubscription<AuthChange>? _sub;
  bool _signingOut = false;
  bool _expired = false;
  Future<bool>? _refreshing;

  AuthSession(this.client) {
    _lastEmail = client.current?.email;
    _sub = client.changes.listen(_onChange);
  }

  bool get isSignedIn => client.current != null;

  /// The session ended without the user signing out.
  bool get expired => _expired;

  String? get email => client.current?.email;

  /// The last signed-in account; kept while [expired] so the app knows
  /// whether a re-sign-in is the same person.
  String? get accountEmail => email ?? _lastEmail;
  String? _lastEmail;

  void _onChange(AuthChange change) {
    if (change == AuthChange.signedOut) {
      // An SDK sign-out we did not ask for means the refresh failed.
      if (!_signingOut && !_expired && _lastEmail != null) _expired = true;
    } else {
      _expired = false;
      _lastEmail = email ?? _lastEmail;
    }
    notifyListeners();
  }

  /// Access token for a protected request, refreshed first when it is about
  /// to expire. Null when there is no usable session.
  Future<String?> accessToken() async {
    final tokens = client.current;
    if (tokens == null) return null;
    if (tokens.expiresWithin(const Duration(seconds: 30))) {
      if (!await _refreshOnce()) return null;
    }
    return client.current?.accessToken;
  }

  /// Called after a 401: refresh once (concurrent callers share it). On
  /// failure the session is marked [expired] and false is returned; never
  /// loops and never falls back to another credential.
  Future<bool> recoverFromUnauthorized() => _refreshOnce();

  Future<bool> _refreshOnce() {
    return _refreshing ??= () async {
      try {
        final ok = await client.refresh();
        if (!ok) _markExpired();
        return ok;
      } finally {
        _refreshing = null;
      }
    }();
  }

  void _markExpired() {
    if (_expired) return;
    _expired = true;
    notifyListeners();
  }

  Future<bool> signUp(String email, String password) =>
      client.signUp(email, password);

  Future<void> signIn(String email, String password) async {
    await client.signIn(email, password);
    _expired = false;
    _lastEmail = this.email ?? email;
    notifyListeners();
  }

  Future<void> signOut() async {
    _signingOut = true;
    try {
      await client.signOut();
    } finally {
      _signingOut = false;
      _expired = false;
      _lastEmail = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
