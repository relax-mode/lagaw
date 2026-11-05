import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/onboarding_preferences.dart';
import 'package:frontend/screens/onboarding/onboarding_flow.dart';
import 'package:frontend/services/onboarding_repository.dart';

/// Records what was saved; optionally fails loads.
class _Repo extends MockOnboardingRepository {
  final List<OnboardingPreferences> saves = [];
  int failNextLoads;

  _Repo({super.failNextSaves, this.failNextLoads = 0, super.initial})
    : super(delay: const Duration(milliseconds: 300));

  @override
  Future<OnboardingPreferences> load() async {
    if (failNextLoads > 0) {
      failNextLoads--;
      await Future<void>.delayed(delay);
      throw Exception('offline');
    }
    return super.load();
  }

  @override
  Future<OnboardingPreferences> save(OnboardingPreferences preferences) async {
    final saved = await super.save(preferences);
    saves.add(saved);
    return saved;
  }
}

Future<OnboardingPreferences?> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  OnboardingPreferences? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<OnboardingPreferences>(
                MaterialPageRoute(
                  builder: (_) => OnboardingFlow(repository: repo),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return result;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _toBudget(WidgetTester tester) async {
  await _tapKey(tester, 'onboarding-start');
  await _tapKey(tester, 'chip-cafe');
  await _tapKey(tester, 'chip-heritage');
  await _tapKey(tester, 'onboarding-next');
}

void main() {
  group('budget parsing', () {
    test('normalizes amounts to two decimals', () {
      expect(parseBudgetAmount('1,500').value, '1500.00');
      expect(parseBudgetAmount('0').value, '0.00');
      expect(parseBudgetAmount('250.5').value, '250.50');
      expect(parseBudgetAmount('007').value, '7.00');
      expect(parseBudgetAmount('  ').value, isNull);
    });

    test('rejects negatives, over-precision and huge amounts', () {
      expect(parseBudgetAmount('-1').error, isNotNull);
      expect(parseBudgetAmount('1.234').error, isNotNull);
      expect(parseBudgetAmount('1.2.3').error, isNotNull);
      expect(parseBudgetAmount('10000000000').error, isNotNull);
      expect(parseBudgetAmount('9999999999.99').value, '9999999999.99');
    });

    test('range needs both or neither, with min <= max', () {
      expect(validateBudgetRange('', '').min, isNull);
      expect(validateBudgetRange('', '').minError, isNull);
      expect(validateBudgetRange('500', '').maxError, isNotNull);
      expect(validateBudgetRange('', '500').minError, isNotNull);
      expect(validateBudgetRange('900', '500').maxError, isNotNull);
      final ok = validateBudgetRange('500', '500');
      expect((ok.min, ok.max), ('500.00', '500.00'));
    });

    test('toJson always sends all four contract keys', () {
      expect(OnboardingPreferences.empty.toJson(), {
        'preferred_tags': <String>[],
        'budget_min': null,
        'budget_max': null,
        'travel_style': null,
      });
    });
  });

  testWidgets('shows loading, then completes and saves the full flow', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo);
    expect(find.byKey(const ValueKey('onboarding-loading')), findsOneWidget);
    await tester.pumpAndSettle();

    await _toBudget(tester);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-budget-min')),
      '500',
    );
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-budget-max')),
      '2,000',
    );
    await _tapKey(tester, 'onboarding-next');
    await _tapKey(tester, 'style-slow');
    await _tapKey(tester, 'onboarding-next');

    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(find.text('Café, Heritage'), findsOneWidget);
    expect(find.text('₱500 – ₱2,000'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('onboarding-saving')), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('You’re all set!'), findsOneWidget);
    expect(repo.saves.single.toJson(), {
      'preferred_tags': ['cafe', 'heritage'],
      'budget_min': '500.00',
      'budget_max': '2000.00',
      'travel_style': 'slow',
    });
  });

  testWidgets('requires at least one interest', (tester) async {
    await _pump(tester, _Repo());
    await tester.pumpAndSettle();
    await _tapKey(tester, 'onboarding-start');
    await _tapKey(tester, 'onboarding-next');
    expect(find.text('Choose at least one interest.'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await _tapKey(tester, 'chip-food');
    expect(find.text('Choose at least one interest.'), findsNothing);
    await _tapKey(tester, 'onboarding-next');
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('only approved tags are offered', (tester) async {
    await _pump(tester, _Repo());
    await tester.pumpAndSettle();
    await _tapKey(tester, 'onboarding-start');
    for (final tag in kOnboardingTags) {
      expect(find.byKey(ValueKey('chip-$tag')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('chip-art')), findsNothing);
    expect(find.byKey(const ValueKey('chip-sunset')), findsNothing);
  });

  testWidgets('invalid budgets block Next with visible errors', (tester) async {
    await _pump(tester, _Repo());
    await tester.pumpAndSettle();
    await _toBudget(tester);

    final min = find.byKey(const ValueKey('onboarding-budget-min'));
    final max = find.byKey(const ValueKey('onboarding-budget-max'));

    await tester.enterText(min, '900');
    await tester.enterText(max, '500');
    await _tapKey(tester, 'onboarding-next');
    expect(find.text('Max budget must be at least the min.'), findsOneWidget);
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.enterText(max, '');
    await _tapKey(tester, 'onboarding-next');
    expect(
      find.text('Enter both amounts, or leave both empty.'),
      findsOneWidget,
    );

    await tester.enterText(max, '1.234');
    await _tapKey(tester, 'onboarding-next');
    expect(
      find.text('Use a peso amount with up to 2 decimals.'),
      findsOneWidget,
    );
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('skipping budget and style saves nulls', (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    await _toBudget(tester);
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-budget-min')),
      '900',
    );
    await _tapKey(tester, 'onboarding-skip-budget');
    await _tapKey(tester, 'onboarding-next');

    expect(find.text('No preference'), findsNWidgets(2));
    await _tapKey(tester, 'onboarding-save');
    expect(repo.saves.single.budgetMin, isNull);
    expect(repo.saves.single.budgetMax, isNull);
    expect(repo.saves.single.travelStyle, isNull);
  });

  testWidgets('Edit from review returns to review', (tester) async {
    await _pump(tester, _Repo());
    await tester.pumpAndSettle();
    await _toBudget(tester);
    await _tapKey(tester, 'onboarding-skip-budget');
    await _tapKey(tester, 'onboarding-next');

    await _tapKey(tester, 'review-edit-interests');
    expect(find.text('Step 1 of 4'), findsOneWidget);
    await _tapKey(tester, 'chip-nature');
    await _tapKey(tester, 'onboarding-next');
    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(find.text('Café, Heritage, Nature'), findsOneWidget);

    await _tapKey(tester, 'review-edit-style');
    await _tapKey(tester, 'style-fast');
    await _tapKey(tester, 'onboarding-back');
    expect(find.text('Step 4 of 4'), findsOneWidget);
  });

  testWidgets('Back walks to the previous step', (tester) async {
    await _pump(tester, _Repo());
    await tester.pumpAndSettle();
    await _toBudget(tester);
    await _tapKey(tester, 'onboarding-back');
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Choose at least one interest.'), findsNothing);
  });

  testWidgets('a failed save keeps answers and can be retried', (tester) async {
    final repo = _Repo(failNextSaves: 1);
    await _pump(tester, repo);
    await tester.pumpAndSettle();
    await _toBudget(tester);
    await _tapKey(tester, 'onboarding-skip-budget');
    await _tapKey(tester, 'onboarding-next');

    await _tapKey(tester, 'onboarding-save');
    expect(find.byKey(const ValueKey('onboarding-save-error')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Café, Heritage'), findsOneWidget);
    expect(repo.saves, isEmpty);

    await _tapKey(tester, 'onboarding-save');
    expect(find.text('You’re all set!'), findsOneWidget);
    expect(repo.saves, hasLength(1));
  });

  testWidgets('a failed load offers Retry', (tester) async {
    await _pump(tester, _Repo(failNextLoads: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-load-error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-start')), findsOneWidget);
  });

  testWidgets('saved answers are prefilled and Done returns them', (
    tester,
  ) async {
    final repo = _Repo(
      initial: const OnboardingPreferences(
        preferredTags: ['food', 'art'],
        budgetMin: '100.00',
        budgetMax: '800.00',
        travelStyle: 'moderate',
      ),
    );
    OnboardingPreferences? popped;
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => popped = await Navigator.of(context)
                .push<OnboardingPreferences>(
                  MaterialPageRoute(
                    builder: (_) => OnboardingFlow(repository: repo),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'onboarding-start');
    await _tapKey(tester, 'onboarding-next');
    await _tapKey(tester, 'onboarding-next');
    await _tapKey(tester, 'onboarding-next');

    // "art" is not an approved tag and is dropped.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('₱100 – ₱800'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);

    await _tapKey(tester, 'onboarding-save');
    await _tapKey(tester, 'onboarding-finish');
    expect(popped?.preferredTags, ['food']);
    expect(find.text('open'), findsOneWidget);
  });
}
