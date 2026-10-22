/// Trip models matching FastAPI `TripCreate` / `TripResponse` [S2-04]
library;

/// Formats a date as the backend's required `YYYY-MM-DD` calendar date.
String formatApiDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Parses `YYYY-MM-DD` as a local calendar date (no timezone shifting).
DateTime parseApiDate(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

/// Pydantic serializes `Decimal` as a JSON string; accept numbers too.
double _parseMoney(dynamic value) {
  if (value is num) return value.toDouble();
  return double.parse(value.toString());
}

/// Sent as a 2-decimal string so the backend `Decimal` gets an exact value.
String _formatMoney(double value) => value.toStringAsFixed(2);

/// Payload for creating or updating a trip.
class TripDraft {
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final double budgetMin;
  final double budgetMax;
  final String? transportationMode;
  final String? groupType;
  final List<String> preferredTags;

  const TripDraft({
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.budgetMin,
    required this.budgetMax,
    this.transportationMode,
    this.groupType,
    this.preferredTags = const [],
  });

  /// Only the fields `TripCreate` accepts; the backend forbids extras.
  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'start_date': formatApiDate(startDate),
    'end_date': formatApiDate(endDate),
    'budget_min': _formatMoney(budgetMin),
    'budget_max': _formatMoney(budgetMax),
    'transportation_mode': transportationMode,
    'group_type': groupType,
    'preferred_tags': preferredTags,
  };

  /// API field names whose values differ from [original]; empty when
  /// nothing changed. Lets the edit screen skip no-op saves.
  Set<String> changedFieldsFrom(TripDraft original) {
    final before = original.toJson();
    return {
      for (final entry in toJson().entries)
        if ('${entry.value}' != '${before[entry.key]}') entry.key,
    };
  }
}

/// A saved trip returned by the backend.
class Trip extends TripDraft {
  final String id;
  final String userId;
  final String status;
  final double? estimatedTotalCost;

  const Trip({
    required this.id,
    required this.userId,
    required this.status,
    this.estimatedTotalCost,
    required super.title,
    required super.startDate,
    required super.endDate,
    required super.budgetMin,
    required super.budgetMax,
    super.transportationMode,
    super.groupType,
    super.preferredTags,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    final cost = json['estimated_total_cost'];
    return Trip(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      status: json['status']?.toString() ?? 'draft',
      estimatedTotalCost: cost == null ? null : _parseMoney(cost),
      title: json['title'].toString(),
      startDate: parseApiDate(json['start_date'].toString()),
      endDate: parseApiDate(json['end_date'].toString()),
      budgetMin: _parseMoney(json['budget_min']),
      budgetMax: _parseMoney(json['budget_max']),
      transportationMode: json['transportation_mode']?.toString(),
      groupType: json['group_type']?.toString(),
      preferredTags:
          (json['preferred_tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// One page of trips from `GET /api/v1/trips`.
class TripsPage {
  final List<Trip> items;
  final int limit;
  final int offset;

  const TripsPage({
    required this.items,
    required this.limit,
    required this.offset,
  });

  factory TripsPage.fromJson(Map<String, dynamic> json) => TripsPage(
    items: (json['items'] as List<dynamic>? ?? [])
        .map((item) => Trip.fromJson(item as Map<String, dynamic>))
        .toList(),
    limit: json['limit'] as int? ?? 0,
    offset: json['offset'] as int? ?? 0,
  );
}
