import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/preference_draft.dart';
import 'package:frontend/models/trip.dart';
import 'package:frontend/services/preference_service.dart';
import 'package:frontend/widgets/trip_form/trip_form.dart';

/// Mocked extraction API: queue drafts or errors; [pending] holds a call open.
class FakePreferenceService extends PreferenceService {
  final List<Object> responses = [];
  final List<String> prompts = [];
  Completer<void>? pending;

  FakePreferenceService() : super(token: 'fake');

  @override
  Future<PreferenceDraft> extract(String prompt) async {
    prompts.add(prompt);
    if (pending != null) await pending!.future;
    final next = responses.removeAt(0);
    if (next is PreferenceApiException) throw next;
    return next as PreferenceDraft;
  }
}

const _suggested = PreferenceDraft(
  preferredTags: ['cafe', 'photography', 'relaxing'],
  budgetLevel: 'low',
  duration: 'afternoon',
  pace: 'slow',
  missingFields: ['budget', 'group_type'],
);

final _existing = TripDraft(
  title: 'Weekend food crawl',
  startDate: DateTime(2026, 11, 7),
  endDate: DateTime(2026, 11, 8),
  budgetMin: 500,
  budgetMax: 2000,
  transportationMode: 'jeepney',
  groupType: 'friends',
  preferredTags: const ['food', 'cafe'],
);

Future<List<TripDraft>> _pumpForm(
  WidgetTester tester,
  FakePreferenceService service, {
  TripDraft? initial,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final submitted = <TripDraft>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TripForm(
            initial: initial,
            preferenceService: service,
            onSubmit: submitted.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return submitted;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _describe(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byKey(const ValueKey('describe-trip-prompt')),
    text,
  );
  await _tap(tester, 'describe-trip-suggest');
}

Future<void> _save(WidgetTester tester) => _tap(tester, 'trip-submit');

void main() {
  testWidgets('success: review, apply only ticked vibes, then save', (
    tester,
  ) async {
    final service = FakePreferenceService()..responses.add(_suggested);
    final submitted = await _pumpForm(tester, service, initial: _existing);

    await _describe(tester, '  A slow afternoon with coffee and photos  ');
    expect(service.prompts, ['A slow afternoon with coffee and photos']);
    expect(find.text('Review suggestions'), findsOneWidget);
    // Already chosen vibes are not offered again.
    expect(find.byKey(const ValueKey('review-tag-cafe')), findsNothing);
    expect(find.text('Already in your trip: Café'), findsOneWidget);
    expect(find.text('Afternoon'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);
    expect(find.textContaining('Not mentioned: Budget'), findsOneWidget);

    await _tap(tester, 'review-tag-relaxing'); // untick
    await _tap(tester, 'review-apply');
    expect(
      find.text('Added 1 vibe. Check the form, then save.'),
      findsOneWidget,
    );

    await _save(tester);
    final saved = submitted.single;
    expect(saved.preferredTags, ['food', 'cafe', 'photography']);
    // Explicit values are untouched.
    expect(saved.title, 'Weekend food crawl');
    expect(saved.budgetMin, 500);
    expect(saved.budgetMax, 2000);
    expect(saved.groupType, 'friends');
    expect(saved.transportationMode, 'jeepney');
    // Review-only fields never reach the Trip API payload.
    expect(saved.toJson().keys, isNot(contains('pace')));
    expect(saved.toJson().keys, isNot(contains('budget_level')));
  });

  testWidgets('extraction never saves by itself', (tester) async {
    final service = FakePreferenceService()..responses.add(_suggested);
    final submitted = await _pumpForm(tester, service, initial: _existing);

    await _describe(tester, 'Coffee and photos');
    await _tap(tester, 'review-apply');

    expect(submitted, isEmpty);
  });

  testWidgets('cancel leaves the form unchanged', (tester) async {
    final service = FakePreferenceService()..responses.add(_suggested);
    final submitted = await _pumpForm(tester, service, initial: _existing);

    await _describe(tester, 'Coffee and photos');
    await _tap(tester, 'review-cancel');
    expect(find.text('Review suggestions'), findsNothing);

    await _save(tester);
    expect(submitted.single.preferredTags, ['food', 'cafe']);
  });

  testWidgets('partial result with no vibes explains and changes nothing', (
    tester,
  ) async {
    final service = FakePreferenceService()
      ..responses.add(
        const PreferenceDraft(
          preferredTags: [],
          budgetLevel: 'unspecified',
          duration: 'unspecified',
          pace: 'unspecified',
          missingFields: ['budget', 'group_type'],
        ),
      );
    final submitted = await _pumpForm(tester, service, initial: _existing);

    await _describe(tester, 'Somewhere nice');
    expect(
      find.text('No vibes were found in your description.'),
      findsOneWidget,
    );
    expect(find.text('Not mentioned'), findsNWidgets(3));
    await _tap(tester, 'review-apply');
    expect(find.text('No changes applied.'), findsOneWidget);

    await _save(tester);
    expect(submitted.single.preferredTags, ['food', 'cafe']);
  });

  for (final error in [
    const PreferenceApiException(
      'AI suggestions took too long. Try again, or fill in the form yourself.',
      code: 'extraction_timeout',
      statusCode: 504,
    ),
    const PreferenceApiException(
      'AI suggestions are unavailable right now. You can still fill in the '
      'form yourself.',
      code: 'extraction_unavailable',
      statusCode: 503,
    ),
    const PreferenceApiException(
      'AI could not understand that description. Try rephrasing it, or fill '
      'in the form yourself.',
      code: 'invalid_extraction_output',
      statusCode: 502,
    ),
    const PreferenceApiException(
      'Could not reach the Lagaw server. Check your connection, or fill in '
      'the form yourself.',
      code: 'network',
    ),
  ]) {
    testWidgets('${error.code}: shows the message and keeps form values', (
      tester,
    ) async {
      final service = FakePreferenceService()..responses.add(error);
      final submitted = await _pumpForm(tester, service, initial: _existing);

      await _describe(tester, 'Coffee and photos');

      expect(find.text(error.message), findsOneWidget);
      expect(find.text('Review suggestions'), findsNothing);
      expect(find.text('Weekend food crawl'), findsOneWidget);
      // Manual saving still works with the untouched values.
      await _save(tester);
      expect(submitted.single.preferredTags, ['food', 'cafe']);
      expect(submitted.single.budgetMax, 2000);
    });
  }

  testWidgets('a retry after a failure can succeed', (tester) async {
    final service = FakePreferenceService()
      ..responses.addAll([
        const PreferenceApiException(
          'AI suggestions took too long.',
          code: 'extraction_timeout',
        ),
        _suggested,
      ]);
    await _pumpForm(tester, service, initial: _existing);

    await _describe(tester, 'Coffee and photos');
    expect(find.text('AI suggestions took too long.'), findsOneWidget);
    await _tap(tester, 'describe-trip-suggest');

    expect(find.text('Review suggestions'), findsOneWidget);
    expect(service.prompts, hasLength(2));
  });

  testWidgets('blank description is rejected without calling the API', (
    tester,
  ) async {
    final service = FakePreferenceService();
    await _pumpForm(tester, service);

    await _describe(tester, '   ');

    expect(find.text('Describe your trip first.'), findsOneWidget);
    expect(service.prompts, isEmpty);
  });

  testWidgets('suggest cannot be sent twice while a request is pending', (
    tester,
  ) async {
    final service = FakePreferenceService()
      ..responses.add(_suggested)
      ..pending = Completer<void>();
    await _pumpForm(tester, service, initial: _existing);

    await tester.enterText(
      find.byKey(const ValueKey('describe-trip-prompt')),
      'Coffee',
    );
    await tester.tap(find.byKey(const ValueKey('describe-trip-suggest')));
    await tester.pump();
    expect(find.text('Reading your description…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('describe-trip-suggest')));
    await tester.pump();
    expect(service.prompts, hasLength(1));

    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Review suggestions'), findsOneWidget);
  });

  testWidgets('new trip: applied vibes are part of the created draft', (
    tester,
  ) async {
    final service = FakePreferenceService()..responses.add(_suggested);
    await _pumpForm(tester, service);

    await _describe(tester, 'Coffee and photos');
    await _tap(tester, 'review-apply');

    expect(
      find.text('Added 3 vibes. Check the form, then save.'),
      findsOneWidget,
    );
    final state = tester.state<TripFormState>(find.byType(TripForm));
    // Title/dates/budget are still required: validation blocks a save.
    expect(state.buildDraft(), isNull);
  });
}
