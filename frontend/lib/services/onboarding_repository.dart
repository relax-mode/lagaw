import '../models/onboarding_preferences.dart';

/// Where onboarding preferences are read from and saved to. #101 ships a
/// mock; #104 adds the `GET/PUT /api/v1/me/preferences` implementation.
abstract class OnboardingRepository {
  Future<OnboardingPreferences> load();

  /// Full replacement; returns what was stored.
  Future<OnboardingPreferences> save(OnboardingPreferences preferences);
}

class OnboardingSaveException implements Exception {
  final String message;
  const OnboardingSaveException(this.message);

  @override
  String toString() => message;
}

/// In-memory stand-in with a short delay so loading states are visible.
/// Nothing leaves the device. [S4-01]
class MockOnboardingRepository implements OnboardingRepository {
  /// Shared for the running app so a saved mock survives reopening the flow.
  /// Build with `--dart-define=MOCK_ONBOARDING_SAVE_FAILURE=true` to make
  /// the first save fail, for demonstrating the error state.
  static final MockOnboardingRepository shared = MockOnboardingRepository(
    failNextSaves: const bool.fromEnvironment('MOCK_ONBOARDING_SAVE_FAILURE')
        ? 1
        : 0,
  );

  final Duration delay;

  /// The next N saves fail, to exercise the error state.
  int failNextSaves;

  OnboardingPreferences _stored;

  MockOnboardingRepository({
    this.delay = const Duration(milliseconds: 700),
    this.failNextSaves = 0,
    OnboardingPreferences initial = OnboardingPreferences.empty,
  }) : _stored = initial;

  @override
  Future<OnboardingPreferences> load() async {
    await Future<void>.delayed(delay);
    return _stored;
  }

  @override
  Future<OnboardingPreferences> save(OnboardingPreferences preferences) async {
    await Future<void>.delayed(delay);
    if (failNextSaves > 0) {
      failNextSaves--;
      throw const OnboardingSaveException(
        'Couldn’t save your preferences. Check your connection and try again.',
      );
    }
    _stored = preferences;
    return _stored;
  }
}
