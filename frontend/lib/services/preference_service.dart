import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/api_credentials.dart';
import '../auth/auth_session.dart';
import '../config.dart';
import '../models/preference_draft.dart';

/// A failed extraction, with a message safe to show. The trip form stays
/// usable: every failure falls back to manual entry. [S3-06]
class PreferenceApiException implements Exception {
  final String message;

  /// Backend `detail.code` (e.g. `extraction_timeout`) when one was sent.
  final String? code;

  /// Null when the request never got a response (timeout, offline).
  final int? statusCode;

  const PreferenceApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() => 'PreferenceApiException($statusCode, $code): $message';
}

/// Calls only the FastAPI extraction endpoint. The provider key stays on the
/// backend; this client never talks to DeepSeek or the database. [S3-06]
class PreferenceService {
  final http.Client _client;
  final ApiCredentials _auth;

  /// The backend allows the provider up to 30 s; leave room for the hop.
  static const Duration _timeout = Duration(seconds: 40);

  static const int maxPromptLength = 2000;

  /// Uses the signed-in Supabase session ([AuthSession.current]) unless a
  /// fixed [token] is given. [S3-16]
  PreferenceService({http.Client? client, String? token, AuthSession? session})
    : _client = client ?? http.Client(),
      _auth = ApiCredentials.resolve(
        token: token,
        session: session,
        demoToken: AppConfig.tripDemoToken,
      );

  /// POST /api/v1/preferences/extract. Sends only the prompt: suggestions
  /// are reviewed and merged on the client, so explicit form values are
  /// never overridden by the server. Never retried automatically.
  Future<PreferenceDraft> extract(String prompt) async {
    var token = await _auth.token();
    if (token == null) {
      throw PreferenceApiException(
        _auth.usesSession
            ? AuthMessages.sessionExpired
            : 'AI suggestions are not set up on this build.',
        statusCode: _auth.usesSession ? 401 : null,
      );
    }
    Future<http.Response> post(String bearer) => _client
        .post(
          Uri.parse(AppConfig.preferenceExtractEndpoint),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $bearer',
          },
          body: jsonEncode({'prompt': prompt}),
        )
        .timeout(_timeout);
    http.Response response;
    try {
      response = await post(token);
      // A 401 is rejected before any provider call, so one retry after a
      // successful refresh cannot double-charge an extraction.
      if (response.statusCode == 401 &&
          _auth.usesSession &&
          await _auth.recover()) {
        token = await _auth.token();
        if (token != null) response = await post(token);
      }
    } on TimeoutException {
      throw const PreferenceApiException(
        'AI suggestions took too long. Try again, or fill in the form yourself.',
        code: 'client_timeout',
      );
    } on http.ClientException {
      throw const PreferenceApiException(
        'Could not reach the Lagaw server. Check your connection, or fill in '
        'the form yourself.',
        code: 'network',
      );
    }

    if (response.statusCode == 200) {
      try {
        return PreferenceDraft.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } catch (_) {
        throw const PreferenceApiException(
          'AI returned suggestions this app could not read. Fill in the form '
          'yourself.',
          code: 'invalid_extraction_output',
          statusCode: 200,
        );
      }
    }
    throw _errorFor(response);
  }

  PreferenceApiException _errorFor(http.Response response) {
    final status = response.statusCode;
    final code = apiErrorCode(response.body);
    final message = switch ((status, code)) {
      (401, _) =>
        _auth.usesSession
            ? AuthMessages.sessionExpired
            : 'This app is not authorized to use AI suggestions.',
      (403, 'email_confirmation_required') => AuthMessages.emailConfirmation,
      (409, 'profile_link_required') => AuthMessages.profileLink,
      (_, 'invalid_request') =>
        'Describe your trip in 1 to $maxPromptLength characters.',
      (_, 'extraction_timeout') =>
        'AI suggestions took too long. Try again, or fill in the form '
            'yourself.',
      (_, 'extraction_rate_limited') =>
        'AI suggestions are busy right now. Try again in a moment, or fill '
            'in the form yourself.',
      (_, 'invalid_extraction_output' || 'extraction_failed') =>
        'AI could not understand that description. Try rephrasing it, or '
            'fill in the form yourself.',
      (_, 'extraction_unavailable') || (503, _) =>
        'AI suggestions are unavailable right now. You can still fill in the '
            'form yourself.',
      _ =>
        'AI suggestions failed (HTTP $status). You can still fill in the '
            'form yourself.',
    };
    return PreferenceApiException(message, code: code, statusCode: status);
  }

  void dispose() {
    _client.close();
  }
}
