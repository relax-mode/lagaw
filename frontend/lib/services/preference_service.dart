import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
  final String _token;

  /// The backend allows the provider up to 30 s; leave room for the hop.
  static const Duration _timeout = Duration(seconds: 40);

  static const int maxPromptLength = 2000;

  PreferenceService({http.Client? client, String? token})
    : _client = client ?? http.Client(),
      _token = token ?? AppConfig.tripDemoToken;

  /// POST /api/v1/preferences/extract. Sends only the prompt: suggestions
  /// are reviewed and merged on the client, so explicit form values are
  /// never overridden by the server. Never retried automatically.
  Future<PreferenceDraft> extract(String prompt) async {
    if (_token.isEmpty) {
      throw const PreferenceApiException(
        'AI suggestions are not set up on this build.',
      );
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(AppConfig.preferenceExtractEndpoint),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode({'prompt': prompt}),
          )
          .timeout(_timeout);
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
    final code = _detailCode(response.body);
    final message = switch ((status, code)) {
      (401, _) => 'This app is not authorized to use AI suggestions.',
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

  /// `{"detail": {"code": ...}}` for extraction errors; access errors use
  /// a plain string detail and have no code.
  String? _detailCode(String body) {
    try {
      final decoded = jsonDecode(body);
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      return detail is Map<String, dynamic> ? detail['code']?.toString() : null;
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
