import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/api_credentials.dart';
import '../auth/auth_session.dart';
import '../config.dart';
import '../models/trip.dart';
import '../models/trip_item.dart';

/// A failed trip request, with a message safe to show to users. [S2-04]
class TripApiException implements Exception {
  /// Null when the request never got a response (timeout, offline).
  final int? statusCode;
  final String message;

  /// 422 messages keyed by field name (e.g. `title`); cross-field errors
  /// such as "end_date must be on or after start_date." use [formErrorKey].
  final Map<String, String> fieldErrors;

  static const String formErrorKey = '_form';

  const TripApiException(
    this.message, {
    this.statusCode,
    this.fieldErrors = const {},
  });

  @override
  String toString() => 'TripApiException($statusCode): $message';
}

class TripService {
  final http.Client _client;
  final ApiCredentials _auth;

  /// Bearer token for the request being sent; set by [_send].
  String _activeToken = '';

  static const Duration _timeout = Duration(seconds: 6);

  /// Uses the signed-in Supabase session ([AuthSession.current]) unless a
  /// fixed [token] is given. [S3-16]
  TripService({http.Client? client, String? token, AuthSession? session})
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

  /// POST /api/v1/trips
  Future<Trip> createTrip(TripDraft draft) async {
    final response = await _send(
      () => _client.post(
        Uri.parse(AppConfig.tripsEndpoint),
        headers: _headers,
        body: jsonEncode(draft.toJson()),
      ),
    );
    if (response.statusCode == 201) {
      return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw _errorFor(response);
  }

  /// GET /api/v1/trips
  Future<TripsPage> listTrips({int limit = 10, int offset = 0}) async {
    final uri = Uri.parse(AppConfig.tripsEndpoint).replace(
      queryParameters: {'limit': limit.toString(), 'offset': offset.toString()},
    );
    final response = await _send(() => _client.get(uri, headers: _headers));
    if (response.statusCode == 200) {
      return TripsPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _errorFor(response);
  }

  /// GET /api/v1/trips/{id}
  Future<Trip> getTrip(String id) async {
    final response = await _send(
      () => _client.get(
        Uri.parse('${AppConfig.tripsEndpoint}/${Uri.encodeComponent(id)}'),
        headers: _headers,
      ),
    );
    if (response.statusCode == 200) {
      return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw _errorFor(response);
  }

  /// PATCH /api/v1/trips/{id}. With [original], only fields that differ
  /// from it are sent, so untouched values are never overwritten; a cleared
  /// transport or group goes out as `null`, cleared tags as `[]`.
  Future<Trip> updateTrip(
    String id,
    TripDraft draft, {
    TripDraft? original,
  }) async {
    final body = draft.toJson();
    if (original != null) {
      final changed = draft.changedFieldsFrom(original);
      body.removeWhere((key, _) => !changed.contains(key));
    }
    final response = await _send(
      () => _client.patch(
        Uri.parse('${AppConfig.tripsEndpoint}/${Uri.encodeComponent(id)}'),
        headers: _headers,
        body: jsonEncode(body),
      ),
    );
    if (response.statusCode == 200) {
      return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw _errorFor(response);
  }

  /// DELETE /api/v1/trips/{id}. Permanent; the backend also removes the
  /// trip's itinerary items. Succeeds on 204.
  Future<void> deleteTrip(String id) async {
    final response = await _send(
      () => _client.delete(
        Uri.parse('${AppConfig.tripsEndpoint}/${Uri.encodeComponent(id)}'),
        headers: _headers,
      ),
    );
    if (response.statusCode == 204) return;
    throw _errorFor(response);
  }

  /// GET /api/v1/trips/{id}/items, following pages until every item is read.
  /// Items arrive ordered by day, then visit order. [S3-34]
  Future<List<TripItem>> listTripItems(String tripId) async {
    const pageSize = 100;
    final items = <TripItem>[];
    for (var offset = 0; ; offset += pageSize) {
      final uri = Uri.parse(_itemsUrl(tripId)).replace(
        queryParameters: {
          'limit': pageSize.toString(),
          'offset': offset.toString(),
        },
      );
      final response = await _send(() => _client.get(uri, headers: _headers));
      if (response.statusCode != 200) throw _itemErrorFor(response);
      final page = TripItemsPage.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      items.addAll(page.items);
      if (page.items.length < pageSize) return items;
    }
  }

  /// POST /api/v1/trips/{id}/items. Adds an existing active location at
  /// [dayNumber]/[visitOrder]; the backend rejects occupied positions (409).
  Future<TripItem> addTripItem(
    String tripId, {
    required String locationId,
    required int dayNumber,
    required int visitOrder,
  }) async {
    final response = await _send(
      () => _client.post(
        Uri.parse(_itemsUrl(tripId)),
        headers: _headers,
        body: jsonEncode({
          'location_id': locationId,
          'day_number': dayNumber,
          'visit_order': visitOrder,
        }),
      ),
    );
    if (response.statusCode == 201) {
      return TripItem.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _itemErrorFor(response);
  }

  /// DELETE /api/v1/trips/{id}/items/{itemId}. The location itself stays in
  /// the catalog. Succeeds on 204.
  Future<void> removeTripItem(String tripId, String itemId) async {
    final response = await _send(
      () => _client.delete(
        Uri.parse('${_itemsUrl(tripId)}/${Uri.encodeComponent(itemId)}'),
        headers: _headers,
      ),
    );
    if (response.statusCode == 204) return;
    throw _itemErrorFor(response);
  }

  String _itemsUrl(String tripId) =>
      '${AppConfig.tripsEndpoint}/${Uri.encodeComponent(tripId)}/items';

  /// Item endpoints share trip errors, but 404/409 mean something more
  /// specific: the backend's 404 detail names the missing trip, location
  /// or item.
  TripApiException _itemErrorFor(http.Response response) {
    final auth = _authErrorFor(response);
    if (auth != null) return auth;
    final status = response.statusCode;
    if (status == 409) {
      return TripApiException(
        'That day and stop number is already taken. Reload and try another.',
        statusCode: status,
      );
    }
    if (status == 404) {
      final detail = _detailText(response.body).toLowerCase();
      if (detail.contains('location')) {
        return TripApiException(
          'That destination is no longer available.',
          statusCode: status,
        );
      }
      if (detail.contains('item')) {
        return TripApiException(
          'That destination was already removed from this trip.',
          statusCode: status,
        );
      }
    }
    return _errorFor(response);
  }

  String _detailText(String body) {
    try {
      final decoded = jsonDecode(body);
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      return detail is String ? detail : '';
    } on FormatException {
      return '';
    }
  }

  /// Sends with the current bearer token. A 401 means authentication failed
  /// before the operation ran, so after one successful session refresh the
  /// request is retried once (the #79 contract); it never loops.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final token = await _auth.token();
    if (token == null) {
      if (_auth.usesSession) {
        throw const TripApiException(
          AuthMessages.sessionExpired,
          statusCode: 401,
        );
      }
      throw const TripApiException(
        'Trips are not set up on this build. Run the app with '
        '--dart-define=TRIP_DEMO_TOKEN=<dev token>.',
      );
    }
    _activeToken = token;
    final response = await _timed(request);
    if (response.statusCode != 401 || !_auth.usesSession) return response;
    if (!await _auth.recover()) return response;
    _activeToken = await _auth.token() ?? '';
    return _timed(request);
  }

  Future<http.Response> _timed(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const TripApiException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const TripApiException(
        'Could not reach the Lagaw server. Check your connection and try again.',
      );
    }
  }

  /// Backend authentication outcomes (#79) shared by every endpoint.
  TripApiException? _authErrorFor(http.Response response) {
    final status = response.statusCode;
    final code = apiErrorCode(response.body);
    if (status == 401) {
      return TripApiException(
        _auth.usesSession
            ? AuthMessages.sessionExpired
            : 'This app is not authorized to manage trips.',
        statusCode: status,
      );
    }
    if (status == 403 && code == 'email_confirmation_required') {
      return TripApiException(
        AuthMessages.emailConfirmation,
        statusCode: status,
      );
    }
    if (status == 409 && code == 'profile_link_required') {
      return TripApiException(AuthMessages.profileLink, statusCode: status);
    }
    return null;
  }

  TripApiException _errorFor(http.Response response) {
    final auth = _authErrorFor(response);
    if (auth != null) return auth;
    final status = response.statusCode;
    switch (status) {
      case 404:
        return TripApiException('Trip not found.', statusCode: status);
      case 409:
        return TripApiException(
          'This trip changed while you were editing. Reload it and try again.',
          statusCode: status,
        );
      case 422:
        final fieldErrors = _parseFieldErrors(response.body);
        return TripApiException(
          'Some trip details need fixing.',
          statusCode: status,
          fieldErrors: fieldErrors,
        );
      case 503:
        return TripApiException(
          'Trips are temporarily unavailable. Please try again later.',
          statusCode: status,
        );
      default:
        return TripApiException(
          'Something went wrong (HTTP $status). Please try again.',
          statusCode: status,
        );
    }
  }

  /// Maps FastAPI `{"detail": [{"loc": ["body", "title"], "msg": ...}]}`.
  Map<String, String> _parseFieldErrors(String body) {
    final errors = <String, String>{};
    try {
      final decoded = jsonDecode(body);
      final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
      if (detail is! List) return errors;
      for (final entry in detail.whereType<Map<String, dynamic>>()) {
        final loc = (entry['loc'] as List<dynamic>? ?? []).map((e) => '$e');
        final field = loc.length > 1 && loc.first == 'body'
            ? loc.elementAt(1)
            : TripApiException.formErrorKey;
        final msg = entry['msg']?.toString().replaceFirst('Value error, ', '');
        if (msg != null) errors.putIfAbsent(field, () => msg);
      }
    } on FormatException {
      // Non-JSON 422 bodies fall back to the generic message.
    }
    return errors;
  }

  void dispose() {
    _client.close();
  }
}
