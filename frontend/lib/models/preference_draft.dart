/// Preferences suggested by `POST /api/v1/preferences/extract`, for the user
/// to review before anything is saved. Schema version "1". [S3-06]
///
/// Only [preferredTags] and [groupType] map onto Trip CRUD fields. The
/// budget level, duration and pace are review context only: Trips has no
/// columns for them, so they are never sent to the Trip API.
class PreferenceDraft {
  final List<String> preferredTags;
  final String budgetLevel;
  final double? budgetMin;
  final double? budgetMax;
  final String? groupType;
  final String duration;
  final String pace;
  final List<String> missingFields;

  const PreferenceDraft({
    required this.preferredTags,
    required this.budgetLevel,
    this.budgetMin,
    this.budgetMax,
    this.groupType,
    required this.duration,
    required this.pace,
    this.missingFields = const [],
  });

  factory PreferenceDraft.fromJson(Map<String, dynamic> json) {
    final prefs = json['preferences'] as Map<String, dynamic>;
    double? money(Object? value) =>
        value == null ? null : double.parse(value.toString());
    return PreferenceDraft(
      preferredTags: [
        for (final tag in prefs['preferred_tags'] as List<dynamic>? ?? [])
          tag.toString(),
      ],
      budgetLevel: prefs['budget_level']?.toString() ?? 'unspecified',
      budgetMin: money(prefs['budget_min']),
      budgetMax: money(prefs['budget_max']),
      groupType: prefs['group_type']?.toString(),
      duration: prefs['duration']?.toString() ?? 'unspecified',
      pace: prefs['pace']?.toString() ?? 'unspecified',
      missingFields: [
        for (final field in json['missing_fields'] as List<dynamic>? ?? [])
          field.toString(),
      ],
    );
  }
}
