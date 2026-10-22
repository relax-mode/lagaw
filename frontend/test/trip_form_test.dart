import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/trip.dart';
import 'package:frontend/services/trip_service.dart';
import 'package:frontend/theme.dart';
import 'package:frontend/widgets/trip_form/trip_form.dart';
import 'package:frontend/widgets/trip_form/trip_form_validators.dart';

final _existing = TripDraft(
  title: 'Weekend food crawl',
  startDate: DateTime(2026, 11, 7),
  endDate: DateTime(2026, 11, 8),
  budgetMin: 1500,
  budgetMax: 3000.5,
  transportationMode: 'jeepney',
  groupType: 'friends',
  preferredTags: const ['food', 'cafe'],
);

Future<List<TripDraft>> _pumpForm(
  WidgetTester tester, {
  TripDraft? initial,
  Map<String, String> fieldErrors = const {},
  bool isSubmitting = false,
}) async {
  final submitted = <TripDraft>[];
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TripForm(
            initial: initial,
            fieldErrors: fieldErrors,
            isSubmitting: isSubmitting,
            onSubmit: submitted.add,
          ),
        ),
      ),
    ),
  );
  // The submit spinner never settles, so advance past entrance animations.
  isSubmitting
      ? await tester.pump(const Duration(seconds: 1))
      : await tester.pumpAndSettle();
  return submitted;
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('trip-submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('TripFormValidators', () {
    test('title must be non-blank and at most 200 characters', () {
      expect(TripFormValidators.title('   '), isNotNull);
      expect(TripFormValidators.title('a' * 201), isNotNull);
      expect(TripFormValidators.title(' Food crawl '), isNull);
    });

    test('money accepts commas and up to 2 decimals', () {
      expect(TripFormValidators.parseMoney('1,500'), 1500);
      expect(TripFormValidators.parseMoney('99.5'), 99.5);
      expect(TripFormValidators.parseMoney('1.234'), isNull);
      expect(TripFormValidators.parseMoney('-5'), isNull);
      expect(TripFormValidators.parseMoney('12345678901'), isNull);
    });

    test('max budget must be at least min', () {
      expect(TripFormValidators.budgetMax('100', '500'), contains('at least'));
      expect(TripFormValidators.budgetMax('500', '500'), isNull);
    });

    test('dates are required and end cannot precede start', () {
      expect(TripFormValidators.dates(null, null), isNotNull);
      expect(
        TripFormValidators.dates(DateTime(2026, 11, 8), DateTime(2026, 11, 7)),
        isNotNull,
      );
      expect(
        TripFormValidators.dates(DateTime(2026, 11, 7), DateTime(2026, 11, 7)),
        isNull,
      );
    });
  });

  group('TripForm', () {
    testWidgets('empty submit shows errors and does not submit', (
      tester,
    ) async {
      final submitted = await _pumpForm(tester);

      await _tapSubmit(tester);

      expect(submitted, isEmpty);
      expect(find.text('Give your trip a name.'), findsOneWidget);
      expect(find.text('Pick your travel dates.'), findsOneWidget);
      expect(find.text('Enter an amount.'), findsNWidgets(2));
    });

    testWidgets('edit mode pre-fills every field', (tester) async {
      await _pumpForm(tester, initial: _existing);

      expect(find.text('Weekend food crawl'), findsOneWidget);
      expect(find.text('1500'), findsOneWidget);
      expect(find.text('3000.50'), findsOneWidget);
      expect(find.textContaining('Nov 7, 2026'), findsOneWidget);
      expect(find.text('2 days'), findsOneWidget);
    });

    testWidgets('valid form emits the edited draft', (tester) async {
      final submitted = await _pumpForm(tester, initial: _existing);

      await tester.enterText(
        find.byKey(const ValueKey('trip-title')).last,
        'Cafe hopping',
      );
      await tester.tap(find.byKey(const ValueKey('chip-taxi')));
      await tester.tap(find.byKey(const ValueKey('chip-nature')));
      await tester.pumpAndSettle();
      await _tapSubmit(tester);

      expect(submitted, hasLength(1));
      final draft = submitted.single;
      expect(draft.title, 'Cafe hopping');
      expect(draft.transportationMode, 'taxi');
      expect(draft.groupType, 'friends');
      expect(draft.preferredTags, ['food', 'cafe', 'nature']);
      expect(draft.budgetMax, 3000.5);
    });

    testWidgets('tapping a selected single chip clears it', (tester) async {
      final submitted = await _pumpForm(tester, initial: _existing);

      await tester.tap(find.byKey(const ValueKey('chip-friends')));
      await tester.pumpAndSettle();
      await _tapSubmit(tester);

      expect(submitted.single.groupType, isNull);
    });

    testWidgets('rejects max budget below min', (tester) async {
      final submitted = await _pumpForm(tester, initial: _existing);

      await tester.enterText(
        find.byKey(const ValueKey('trip-budget-max')).last,
        '100',
      );
      await _tapSubmit(tester);

      expect(submitted, isEmpty);
      expect(find.text('Max budget must be at least the min.'), findsOneWidget);
    });

    testWidgets('shows server field errors and form-level banner', (
      tester,
    ) async {
      await _pumpForm(
        tester,
        initial: _existing,
        fieldErrors: {
          'title': 'String should have at most 200 characters',
          'start_date': 'Use a calendar date in YYYY-MM-DD format.',
          TripApiException.formErrorKey:
              'budget_max must be greater than or equal to budget_min.',
        },
      );

      expect(
        find.text('String should have at most 200 characters'),
        findsOneWidget,
      );
      expect(
        find.text('Use a calendar date in YYYY-MM-DD format.'),
        findsOneWidget,
      );
      expect(
        find.text('budget_max must be greater than or equal to budget_min.'),
        findsOneWidget,
      );
    });

    testWidgets('submitting state disables the button', (tester) async {
      final submitted = await _pumpForm(
        tester,
        initial: _existing,
        isSubmitting: true,
      );

      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('trip-submit')));
      await tester.pump();
      expect(submitted, isEmpty);
    });
  });

  testWidgets('Vector3DButton still fires onTap with press animation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: Vector3DButton(
            onTap: () => taps++,
            backgroundColor: Colors.blue,
            shadowColor: Colors.indigo,
            child: const Text('Go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
