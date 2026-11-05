/// Profile preferences a new user picks during onboarding. Field names and
/// values follow the #102 `GET/PUT /api/v1/me/preferences` contract
/// (docs/onboarding-preferences-api.md) so #104 can send them unchanged.
/// [S4-01]
class OnboardingPreferences {
  /// Subset of [kOnboardingTags].
  final List<String> preferredTags;

  /// PHP amounts as exact decimal strings (e.g. `"500.00"`); both set or
  /// both null.
  final String? budgetMin;
  final String? budgetMax;

  /// One of [kTravelStyles], or null for no preference.
  final String? travelStyle;

  const OnboardingPreferences({
    this.preferredTags = const [],
    this.budgetMin,
    this.budgetMax,
    this.travelStyle,
  });

  static const empty = OnboardingPreferences();

  bool get hasBudget => budgetMin != null && budgetMax != null;

  /// Nothing saved yet: a first-time user.
  bool get isUnset =>
      preferredTags.isEmpty &&
      budgetMin == null &&
      budgetMax == null &&
      travelStyle == null;

  /// The full-replacement PUT body: all four keys, always.
  Map<String, dynamic> toJson() => {
    'preferred_tags': preferredTags,
    'budget_min': budgetMin,
    'budget_max': budgetMax,
    'travel_style': travelStyle,
  };

  factory OnboardingPreferences.fromJson(Map<String, dynamic> json) =>
      OnboardingPreferences(
        preferredTags: [
          for (final tag in json['preferred_tags'] as List<dynamic>? ?? [])
            tag as String,
        ],
        budgetMin: json['budget_min']?.toString(),
        budgetMax: json['budget_max']?.toString(),
        travelStyle: json['travel_style'] as String?,
      );

  OnboardingPreferences copyWith({
    List<String>? preferredTags,
    String? Function()? budgetMin,
    String? Function()? budgetMax,
    String? Function()? travelStyle,
  }) => OnboardingPreferences(
    preferredTags: preferredTags ?? this.preferredTags,
    budgetMin: budgetMin != null ? budgetMin() : this.budgetMin,
    budgetMax: budgetMax != null ? budgetMax() : this.budgetMax,
    travelStyle: travelStyle != null ? travelStyle() : this.travelStyle,
  );
}

/// Approved interest tags (#102 `TravelTag`).
const List<String> kOnboardingTags = [
  'cafe',
  'food',
  'heritage',
  'photography',
  'nature',
  'relaxing',
];

/// Approved travel styles (#102, reusing the extraction pace vocabulary).
const List<String> kTravelStyles = ['slow', 'moderate', 'fast'];

/// Largest amount `numeric(12,2)` can store.
final BigInt _maxCentavos = BigInt.parse('999999999999');
final RegExp _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

/// Parses a typed PHP amount ("1,500" or "1500.5") into the contract's
/// two-decimal string, or returns an error message.
({String? value, String? error}) parseBudgetAmount(String raw) {
  final text = raw.trim().replaceAll(',', '');
  if (text.isEmpty) return (value: null, error: null);
  if (text.startsWith('-')) {
    return (value: null, error: 'Budget can’t be negative.');
  }
  if (!_amountPattern.hasMatch(text)) {
    return (value: null, error: 'Use a peso amount with up to 2 decimals.');
  }
  final parts = text.split('.');
  final centavos =
      '${parts[0]}${(parts.length > 1 ? parts[1] : '').padRight(2, '0')}';
  if (BigInt.parse(centavos) > _maxCentavos) {
    return (value: null, error: 'That amount is too large.');
  }
  final whole = BigInt.parse(parts[0]).toString();
  return (
    value: '$whole.${centavos.substring(centavos.length - 2)}',
    error: null,
  );
}

/// Validates the min/max pair: both empty (no budget) or both valid with
/// min ≤ max.
({String? min, String? max, String? minError, String? maxError})
validateBudgetRange(String minText, String maxText) {
  final min = parseBudgetAmount(minText);
  final max = parseBudgetAmount(maxText);
  if (min.error != null || max.error != null) {
    return (min: null, max: null, minError: min.error, maxError: max.error);
  }
  if (min.value == null && max.value == null) {
    return (min: null, max: null, minError: null, maxError: null);
  }
  if (min.value == null || max.value == null) {
    const both = 'Enter both amounts, or leave both empty.';
    return (
      min: null,
      max: null,
      minError: min.value == null ? both : null,
      maxError: max.value == null ? both : null,
    );
  }
  if (double.parse(min.value!) > double.parse(max.value!)) {
    return (
      min: null,
      max: null,
      minError: null,
      maxError: 'Max budget must be at least the min.',
    );
  }
  return (min: min.value, max: max.value, minError: null, maxError: null);
}
