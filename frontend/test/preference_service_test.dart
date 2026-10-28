import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/preference_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _token = 'test-demo-token-0123456789abcdefghij';

Map<String, dynamic> _success({
  List<String> tags = const ['cafe', 'photography', 'relaxing'],
  String duration = 'afternoon',
  List<String> missing = const ['budget', 'group_type'],
}) => {
  'schema_version': '1',
  'preferences': {
    'preferred_tags': tags,
    'budget_level': 'low',
    'budget_min': null,
    'budget_max': null,
    'budget_scope': 'trip_total',
    'group_type': null,
    'duration': duration,
    'pace': 'slow',
  },
  'requires_confirmation': true,
  'missing_fields': missing,
};

PreferenceService _returning(int status, Object body) => PreferenceService(
  token: _token,
  client: MockClient((_) async => http.Response(jsonEncode(body), status)),
);

Map<String, dynamic> _error(String code) => {
  'detail': {'code': code, 'message': 'x', 'manual_fallback': true},
};

void main() {
  test('posts only the prompt to the FastAPI extraction endpoint', () async {
    late http.Request sent;
    final service = PreferenceService(
      token: _token,
      client: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(_success()), 200);
      }),
    );

    final draft = await service.extract('A slow afternoon with coffee');

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/preferences/extract');
    expect(sent.headers['Authorization'], 'Bearer $_token');
    expect(jsonDecode(sent.body), {'prompt': 'A slow afternoon with coffee'});
    expect(draft.preferredTags, ['cafe', 'photography', 'relaxing']);
    expect(draft.budgetLevel, 'low');
    expect(draft.budgetMin, isNull);
    expect(draft.duration, 'afternoon');
    expect(draft.pace, 'slow');
    expect(draft.missingFields, ['budget', 'group_type']);
  });

  test('parses partial results with unspecified fields', () async {
    final draft = await _returning(
      200,
      _success(tags: const [], duration: 'unspecified'),
    ).extract('Somewhere nice');

    expect(draft.preferredTags, isEmpty);
    expect(draft.duration, 'unspecified');
  });

  for (final (status, code, expected) in [
    (504, 'extraction_timeout', 'took too long'),
    (503, 'extraction_unavailable', 'unavailable'),
    (502, 'invalid_extraction_output', 'could not understand'),
    (502, 'extraction_failed', 'could not understand'),
    (429, 'extraction_rate_limited', 'busy'),
    (422, 'invalid_request', '1 to 2000'),
  ]) {
    test('maps $status $code to a readable fallback message', () async {
      await expectLater(
        _returning(status, _error(code)).extract('trip'),
        throwsA(
          isA<PreferenceApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.statusCode, 'status', status)
              .having((e) => e.message, 'message', contains(expected)),
        ),
      );
    });
  }

  test('handles inherited string details (401 and 503)', () async {
    await expectLater(
      _returning(401, {
        'detail': 'A valid trip demo bearer token is required.',
      }).extract('trip'),
      throwsA(
        isA<PreferenceApiException>().having(
          (e) => e.message,
          'message',
          contains('not authorized'),
        ),
      ),
    );
    await expectLater(
      _returning(503, {
        'detail': 'Trip demo context is not configured.',
      }).extract('trip'),
      throwsA(
        isA<PreferenceApiException>().having(
          (e) => e.message,
          'message',
          contains('unavailable'),
        ),
      ),
    );
  });

  test('a malformed 200 body is reported, not thrown raw', () async {
    await expectLater(
      _returning(200, {'unexpected': true}).extract('trip'),
      throwsA(
        isA<PreferenceApiException>().having(
          (e) => e.code,
          'code',
          'invalid_extraction_output',
        ),
      ),
    );
  });

  test('maps client timeouts and offline errors', () async {
    final slow = PreferenceService(
      token: _token,
      client: MockClient((_) async => throw TimeoutException('slow')),
    );
    await expectLater(
      slow.extract('trip'),
      throwsA(
        isA<PreferenceApiException>()
            .having((e) => e.statusCode, 'status', isNull)
            .having((e) => e.message, 'message', contains('took too long')),
      ),
    );

    final offline = PreferenceService(
      token: _token,
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(
      offline.extract('trip'),
      throwsA(
        isA<PreferenceApiException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach'),
        ),
      ),
    );
  });

  test('refuses to call without a demo token', () async {
    var called = false;
    final service = PreferenceService(
      token: '',
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.extract('trip'),
      throwsA(isA<PreferenceApiException>()),
    );
    expect(called, isFalse);
  });
}
