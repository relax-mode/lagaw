import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/trip.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = 'test-demo-token-0123456789abcdefghij';

Map<String, dynamic> _tripJson({String id = 'trip-1'}) => {
  'id': id,
  'user_id': 'user-1',
  'status': 'draft',
  'estimated_total_cost': null,
  'title': 'Weekend food crawl',
  'start_date': '2026-11-07',
  'end_date': '2026-11-08',
  'budget_min': '1500.00',
  'budget_max': '3000.50',
  'transportation_mode': 'jeepney',
  'group_type': 'friends',
  'preferred_tags': ['food', 'cafe'],
};

final _draft = TripDraft(
  title: '  Weekend food crawl  ',
  startDate: DateTime(2026, 11, 7),
  endDate: DateTime(2026, 11, 8),
  budgetMin: 1500,
  budgetMax: 3000.5,
  transportationMode: 'jeepney',
  groupType: 'friends',
  preferredTags: const ['food', 'cafe'],
);

TripService _serviceReturning(int status, Object body) => TripService(
  token: _token,
  client: MockClient((_) async => http.Response(jsonEncode(body), status)),
);

void main() {
  group('Trip models', () {
    test('TripDraft.toJson matches the TripCreate contract', () {
      expect(_draft.toJson(), {
        'title': 'Weekend food crawl',
        'start_date': '2026-11-07',
        'end_date': '2026-11-08',
        'budget_min': '1500.00',
        'budget_max': '3000.50',
        'transportation_mode': 'jeepney',
        'group_type': 'friends',
        'preferred_tags': ['food', 'cafe'],
      });
    });

    test('Trip.fromJson parses decimal strings and calendar dates', () {
      final trip = Trip.fromJson(_tripJson());

      expect(trip.id, 'trip-1');
      expect(trip.budgetMin, 1500.0);
      expect(trip.budgetMax, 3000.5);
      expect(trip.startDate, DateTime(2026, 11, 7));
      expect(trip.estimatedTotalCost, isNull);
      expect(trip.preferredTags, ['food', 'cafe']);
    });
  });

  group('TripService', () {
    test('createTrip posts JSON with the bearer token', () async {
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/trips');
          expect(request.headers['Authorization'], 'Bearer $_token');
          expect(
            request.headers['Content-Type'],
            startsWith('application/json'),
          );
          expect(jsonDecode(request.body)['title'], 'Weekend food crawl');
          return http.Response(jsonEncode(_tripJson()), 201);
        }),
      );

      final trip = await service.createTrip(_draft);
      expect(trip.title, 'Weekend food crawl');
    });

    test('listTrips sends paging and parses the page', () async {
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          expect(request.url.queryParameters, {'limit': '20', 'offset': '40'});
          return http.Response(
            jsonEncode({
              'items': [_tripJson(), _tripJson(id: 'trip-2')],
              'limit': 20,
              'offset': 40,
            }),
            200,
          );
        }),
      );

      final page = await service.listTrips(limit: 20, offset: 40);
      expect(page.items.map((t) => t.id), ['trip-1', 'trip-2']);
      expect(page.offset, 40);
    });

    test('getTrip retrieves one trip by id', () async {
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/trips/trip-9');
          return http.Response(jsonEncode(_tripJson(id: 'trip-9')), 200);
        }),
      );

      expect((await service.getTrip('trip-9')).id, 'trip-9');
    });

    test('maps 422 detail to per-field and form errors', () async {
      final service = _serviceReturning(422, {
        'detail': [
          {
            'loc': ['body', 'title'],
            'msg': 'String should have at least 1 character',
            'type': 'string_too_short',
          },
          {
            'loc': ['body'],
            'msg': 'Value error, end_date must be on or after start_date.',
            'type': 'value_error',
          },
        ],
      });

      await expectLater(
        service.createTrip(_draft),
        throwsA(
          isA<TripApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.fieldErrors, 'fieldErrors', {
                'title': 'String should have at least 1 character',
                TripApiException.formErrorKey:
                    'end_date must be on or after start_date.',
              }),
        ),
      );
    });

    for (final (status, message) in [
      (401, 'not authorized'),
      (404, 'not found'),
      (503, 'temporarily unavailable'),
      (500, 'HTTP 500'),
    ]) {
      test('maps HTTP $status to a user-facing message', () async {
        final service = _serviceReturning(status, {'detail': 'x'});

        await expectLater(
          service.getTrip('trip-1'),
          throwsA(
            isA<TripApiException>()
                .having((e) => e.statusCode, 'statusCode', status)
                .having((e) => e.message, 'message', contains(message)),
          ),
        );
      });
    }

    test('maps timeouts to a retry message', () async {
      final service = TripService(
        token: _token,
        client: MockClient((_) async => throw TimeoutException('slow')),
      );

      await expectLater(
        service.listTrips(),
        throwsA(
          isA<TripApiException>()
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having((e) => e.message, 'message', contains('too long')),
        ),
      );
    });

    test('maps connection failures to an offline message', () async {
      final service = TripService(
        token: _token,
        client: MockClient((_) async => throw http.ClientException('down')),
      );

      await expectLater(
        service.listTrips(),
        throwsA(
          isA<TripApiException>().having(
            (e) => e.message,
            'message',
            contains('Could not reach'),
          ),
        ),
      );
    });

    test('updateTrip PATCHes only the changed fields', () async {
      final original = Trip.fromJson(_tripJson());
      final edited = TripDraft(
        title: original.title,
        startDate: original.startDate,
        endDate: original.endDate,
        budgetMin: original.budgetMin,
        budgetMax: 3500,
        transportationMode: original.transportationMode,
        groupType: null,
        preferredTags: const [],
      );
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/trips/trip-1');
          expect(request.headers['Authorization'], 'Bearer $_token');
          expect(jsonDecode(request.body), {
            'budget_max': '3500.00',
            'group_type': null,
            'preferred_tags': <String>[],
          });
          return http.Response(
            jsonEncode({..._tripJson(), 'budget_max': '3500.00'}),
            200,
          );
        }),
      );

      final saved = await service.updateTrip(
        'trip-1',
        edited,
        original: original,
      );
      expect(saved.budgetMax, 3500);
    });

    test('updateTrip without original sends every field', () async {
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          expect((jsonDecode(request.body) as Map).keys, hasLength(8));
          return http.Response(jsonEncode(_tripJson()), 200);
        }),
      );

      await service.updateTrip('trip-1', _draft);
    });

    test('deleteTrip sends DELETE and accepts 204', () async {
      final service = TripService(
        token: _token,
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/trips/trip-1');
          expect(request.headers['Authorization'], 'Bearer $_token');
          return http.Response('', 204);
        }),
      );

      await service.deleteTrip('trip-1');
    });

    test('deleteTrip surfaces 404 for an already deleted trip', () async {
      final service = _serviceReturning(404, {'detail': 'Trip not found.'});

      await expectLater(
        service.deleteTrip('trip-1'),
        throwsA(
          isA<TripApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test('maps HTTP 409 to a reload message', () async {
      final service = _serviceReturning(409, {'detail': 'conflict'});

      await expectLater(
        service.updateTrip('trip-1', _draft),
        throwsA(
          isA<TripApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('Reload')),
        ),
      );
    });
  });
}
