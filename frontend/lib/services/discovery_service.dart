import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/api_credentials.dart';
import '../auth/auth_client.dart';
import '../auth/auth_session.dart';
import '../config.dart';
import '../models/onboarding_preferences.dart';
import '../models/trip_plan.dart';
import 'onboarding_repository.dart';

/// A failed preferences/discovery request with a user-safe message.
class DiscoveryApiException extends OnboardingSaveException {
  /// Null when no response arrived (timeout, offline).
  final int? statusCode;

  /// FastAPI `detail.code`, when object-shaped.
  final String? code;

  const DiscoveryApiException(super.message, {this.statusCode, this.code});

  /// 409 from recommendations when saved preferences changed mid-ranking.
  bool get preferencesChanged =>
      statusCode == 409 && code != 'profile_link_required';
}

/// One `POST /api/v1/me/recommendations` request (#103). Both values are
/// chosen by the user; neither is derived from the profile budget.
class DiscoveryRequest {
  /// One of [kPlannableGroups].
  final String groupType;

  /// Per-person, per-visit venue-cost ceiling as a two-decimal string.
  final String perVisitBudgetMax;
  final int limit;

  const DiscoveryRequest({
    required this.groupType,
    required this.perVisitBudgetMax,
    this.limit = 10,
  });

  Map<String, dynamic> toJson() => {
    'group_type': groupType,
    'per_person_visit_budget_max': perVisitBudgetMax,
    'limit': limit,
  };
}

class DiscoveryPage {
  final List<TripRecommendation> items;

  /// e.g. `no_compatible_locations`; null when [items] is non-empty.
  final String? emptyReason;

  const DiscoveryPage({required this.items, this.emptyReason});

  factory DiscoveryPage.fromJson(Map<String, dynamic> json) => DiscoveryPage(
    items: [
      for (final item in json['items'] as List<dynamic>)
        TripRecommendation.fromJson(item as Map<String, dynamic>),
    ],
    emptyReason: json['empty_reason'] as String?,
  );
}

/// Owner-scoped onboarding preferences (#102) and cold-start
/// recommendations (#103) for the signed-in user. Never retries a write
/// whose outcome is unknown. [S4-04]
class DiscoveryService implements OnboardingRepository {
  final http.Client _client;
  final ApiCredentials _auth;
  String _activeToken = '';

  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _rankTimeout = Duration(seconds: 45);

  DiscoveryService({http.Client? client, String? token, AuthSession? session})
    : _client = client ?? http.Client(),
      _auth = ApiCredentials.resolve(
        token: token,
        session: session,
        demoToken: AppConfig.tripDemoToken,
      );

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_activeToken',
  };

  /// GET /api/v1/me/preferences
  @override
  Future<OnboardingPreferences> load() async {
    final response = await _send(
      () => _client.get(
        Uri.parse(AppConfig.preferencesEndpoint),
        headers: _headers,
      ),
      onTimeout: 'Loading your preferences took too long. Try again.',
    );
    if (response.statusCode == 200) {
      return OnboardingPreferences.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _errorFor(response, unavailable: 'Preferences');
  }

  /// PUT /api/v1/me/preferences (full replacement).
  @override
  Future<OnboardingPreferences> save(OnboardingPreferences preferences) async {
    final response = await _send(
      () => _client.put(
        Uri.parse(AppConfig.preferencesEndpoint),
        headers: _headers,
        body: jsonEncode(preferences.toJson()),
      ),
      // The write may have landed; say so instead of retrying.
      onTimeout:
          'We couldn’t confirm your save. Check your connection, then try '
          'again; saving the same answers twice is safe.',
    );
    if (response.statusCode == 200) {
      return OnboardingPreferences.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 422) {
      throw DiscoveryApiException(
        'Some answers weren’t accepted${_fieldsFor(response.body)}. Review '
        'them and try again.',
        statusCode: 422,
      );
    }
    throw _errorFor(response, unavailable: 'Saving preferences');
  }

  /// POST /api/v1/me/recommendations
  Future<DiscoveryPage> recommend(DiscoveryRequest request) async {
    final response = await _send(
      () => _client.post(
        Uri.parse(AppConfig.meRecommendationsEndpoint),
        headers: _headers,
        body: jsonEncode(request.toJson()),
      ),
      timeout: _rankTimeout,
      onTimeout: 'Finding places took too long. Try again.',
    );
    if (response.statusCode == 200) {
      return DiscoveryPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 409 &&
        apiErrorCode(response.body) != 'profile_link_required') {
      throw DiscoveryApiException(
        'Your preferences changed while we were looking. Reload to see '
        'places for your latest answers.',
        statusCode: 409,
        code: apiErrorCode(response.body),
      );
    }
    if (response.statusCode == 422) {
      throw const DiscoveryApiException(
        'That group or spending limit wasn’t accepted. Adjust it and try '
        'again.',
        statusCode: 422,
      );
    }
    throw _errorFor(response, unavailable: 'Recommendations');
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration timeout = _timeout,
    required String onTimeout,
  }) async {
    // A refresh that can't reach Supabase is not an expired session.
    try {
      return await _sendAuthorized(request, timeout, onTimeout);
    } on AuthUnreachable {
      throw const DiscoveryApiException(
        'Could not reach the Lagaw server. Check your connection and try '
        'again.',
      );
    }
  }

  Future<http.Response> _sendAuthorized(
    Future<http.Response> Function() request,
    Duration timeout,
    String onTimeout,
  ) async {
    final token = await _auth.token();
    if (token == null) {
      throw const DiscoveryApiException(
        AuthMessages.sessionExpired,
        statusCode: 401,
      );
    }
    _activeToken = token;
    final response = await _timed(request, timeout, onTimeout);
    if (response.statusCode != 401 || !_auth.usesSession) return response;
    // A 401 was rejected before anything ran, so one retry is safe.
    if (!await _auth.recover()) return response;
    _activeToken = await _auth.token() ?? '';
    return _timed(request, timeout, onTimeout);
  }

  Future<http.Response> _timed(
    Future<http.Response> Function() request,
    Duration timeout,
    String onTimeout,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw DiscoveryApiException(onTimeout);
    } on http.ClientException {
      throw const DiscoveryApiException(
        'Could not reach the Lagaw server. Check your connection and try '
        'again.',
      );
    }
  }

  DiscoveryApiException _errorFor(
    http.Response response, {
    required String unavailable,
  }) {
    final status = response.statusCode;
    final code = apiErrorCode(response.body);
    return switch (status) {
      401 => const DiscoveryApiException(
        AuthMessages.sessionExpired,
        statusCode: 401,
      ),
      403 => const DiscoveryApiException(
        AuthMessages.emailConfirmation,
        statusCode: 403,
      ),
      404 => const DiscoveryApiException(
        'Your Lagaw profile couldn’t be found. Sign out and back in.',
        statusCode: 404,
      ),
      409 => DiscoveryApiException(
        AuthMessages.profileLink,
        statusCode: 409,
        code: code,
      ),
      503 => DiscoveryApiException(
        '$unavailable temporarily unavailable. Try again in a moment.',
        statusCode: 503,
      ),
      _ => DiscoveryApiException(
        'Something went wrong (HTTP $status). Try again.',
        statusCode: status,
      ),
    };
  }

  /// " (budget_max, travel_style)" from a sanitized FastAPI 422 body.
  String _fieldsFor(String body) {
    try {
      final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
      if (detail is! List) return '';
      final fields = {
        for (final entry in detail.whereType<Map<String, dynamic>>())
          if (entry['loc'] is List && (entry['loc'] as List).length > 1)
            '${(entry['loc'] as List)[1]}',
      };
      return fields.isEmpty ? '' : ' (${fields.join(', ')})';
    } on Object {
      return '';
    }
  }

  void dispose() => _client.close();
}
