import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/trip.dart';

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
  final String _token;

  static const Duration _timeout = Duration(seconds: 6);

  TripService({http.Client? client, String? token})
    : _client = client ?? http.Client(),
      _token = token ?? AppConfig.tripDemoToken;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_token',
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

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    if (_token.isEmpty) {
      throw const TripApiException(
        'Trips are not set up on this build. Run the app with '
        '--dart-define=TRIP_DEMO_TOKEN=<dev token>.',
      );
    }
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

  TripApiException _errorFor(http.Response response) {
    final status = response.statusCode;
    switch (status) {
      case 401:
        return TripApiException(
          'This app is not authorized to manage trips.',
          statusCode: status,
        );
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
